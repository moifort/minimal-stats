import XCTest
@testable import Stats

final class AutoUpdaterTests: XCTestCase {

    private func runShell(_ arguments: [String]) throws -> (output: String, duration: TimeInterval) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        let start = Date()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), Date().timeIntervalSince(start))
    }

    func testRelaunchPassesHostilePathVerbatim() throws {
        let path = #"/Applications/My "Stats" $(touch /tmp/pwned) `id`.app"#
        // A pid that cannot exist: no waiting
        let result = try runShell(AutoUpdater.relaunchArguments(pid: 99_999_999, appPath: path, opener: "/bin/echo"))
        XCTAssertEqual(result.output, path + "\n")
    }

    func testRelaunchWaitsForTheOldProcessToExit() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["0.5"]
        try sleeper.run()
        let result = try runShell(AutoUpdater.relaunchArguments(pid: sleeper.processIdentifier, appPath: "/x.app", opener: "/bin/echo"))
        sleeper.waitUntilExit()
        XCTAssertEqual(result.output, "/x.app\n")
        XCTAssertGreaterThanOrEqual(result.duration, 0.4)
    }

    // MARK: - Versions

    func testComparesVersionsNumericallyWithMissingComponentsAsZero() {
        XCTAssertTrue(AutoUpdater.isVersion("1.10.0", newerThan: "1.9.9"))
        XCTAssertTrue(AutoUpdater.isVersion("2", newerThan: "1.99"))
        XCTAssertFalse(AutoUpdater.isVersion("1.2", newerThan: "1.2.0"))
        XCTAssertFalse(AutoUpdater.isVersion("1.2.0", newerThan: "1.2"))
        XCTAssertEqual(AutoUpdater.compareVersions("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(AutoUpdater.compareVersions("1.2.0", "1.2.1"), .orderedAscending)
    }

    func testNonNumericVersionsAreRejectedRatherThanShifted() {
        // compactMap used to turn 1.x.3 into [1, 3], i.e. version 1.3
        XCTAssertNil(AutoUpdater.versionComponents("1.x.3"))
        XCTAssertNil(AutoUpdater.versionComponents("1.2-beta"))
        XCTAssertNil(AutoUpdater.versionComponents("1..2"))
        XCTAssertNil(AutoUpdater.compareVersions("1.x.3", "1.0"))
        XCTAssertFalse(AutoUpdater.isVersion("1.x.3", newerThan: "1.0"))
        XCTAssertEqual(AutoUpdater.versionComponents("1.11.0"), [1, 11, 0])
    }

    func testNewerReleasesAreSortedOldestFirst() {
        let url = URL(string: "https://github.com/a/b/releases/download/v/Stats.app.zip")!
        let releases = ["1.12.0", "1.10.0", "1.11.1", "1.11", "1.12"].map {
            AutoUpdater.Release(version: $0, downloadURL: url, body: "")
        }
        let newer = AutoUpdater.newerReleases(releases, than: "1.11.0")
        XCTAssertEqual(newer.map(\.version).first, "1.11.1")
        XCTAssertEqual(Set(newer.map(\.version).suffix(2)), ["1.12.0", "1.12"])
        XCTAssertEqual(newer.count, 3)
    }

    // MARK: - Releases payload

    private func release(tag: String, body: Any? = "notes", url: String = "https://github.com/moifort/minimal-stats/releases/download/v1/Stats.app.zip", prerelease: Bool = false) -> [String: Any] {
        var dict: [String: Any] = [
            "tag_name": tag,
            "prerelease": prerelease,
            "draft": false,
            "assets": [["name": "Stats.app.zip", "browser_download_url": url]],
        ]
        dict["body"] = body ?? NSNull()
        return dict
    }

    func testParsesReleasesAndTreatsNullBodyAsEmpty() {
        let releases = AutoUpdater.parseReleases([
            release(tag: "v1.12.0"),
            release(tag: "v1.13.0", body: nil),
        ])
        XCTAssertEqual(releases.map(\.version), ["1.12.0", "1.13.0"])
        XCTAssertEqual(releases.map(\.body), ["notes", ""])
    }

    func testSkipsPrereleasesUnparsableTagsAndUntrustedURLs() {
        let releases = AutoUpdater.parseReleases([
            release(tag: "v2.0.0", prerelease: true),
            release(tag: "v1.x.3"),
            release(tag: "v3.0.0", url: "http://github.com/moifort/minimal-stats/releases/download/v3/Stats.app.zip"),
            release(tag: "v3.0.1", url: "https://evil.example.com/Stats.app.zip"),
            release(tag: "v3.0.2", url: "https://github.com.evil.example/Stats.app.zip"),
        ])
        XCTAssertTrue(releases.isEmpty)
    }

    func testTrustsGitHubAssetHostsOverHTTPSOnly() {
        XCTAssertTrue(AutoUpdater.isTrustedDownloadURL(URL(string: "https://github.com/a/b/releases/download/v1/x.zip")!))
        XCTAssertTrue(AutoUpdater.isTrustedDownloadURL(URL(string: "https://release-assets.githubusercontent.com/x")!))
        XCTAssertTrue(AutoUpdater.isTrustedDownloadURL(URL(string: "https://objects.githubusercontent.com/x")!))
        XCTAssertFalse(AutoUpdater.isTrustedDownloadURL(URL(string: "http://github.com/x")!))
        XCTAssertFalse(AutoUpdater.isTrustedDownloadURL(URL(string: "https://notgithub.com/x")!))
    }

    // MARK: - Downloaded bundle

    func testValidatesDownloadedBundle() {
        let id = "com.stats.menubar"
        XCTAssertNoThrow(try AutoUpdater.validate(
            newBundleInfo: ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.12.0"],
            bundleIdentifier: id, currentVersion: "1.11.0"))
        XCTAssertThrowsError(try AutoUpdater.validate(
            newBundleInfo: ["CFBundleIdentifier": "com.other", "CFBundleShortVersionString": "9.0.0"],
            bundleIdentifier: id, currentVersion: "1.11.0")) {
            XCTAssertEqual($0 as? AutoUpdater.UpdateError, .wrongBundleIdentifier)
        }
        XCTAssertThrowsError(try AutoUpdater.validate(
            newBundleInfo: ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.11"],
            bundleIdentifier: id, currentVersion: "1.11.0")) {
            XCTAssertEqual($0 as? AutoUpdater.UpdateError, .notNewer)
        }
    }
}
