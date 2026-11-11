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
        let id = "com.polyforms.stats"
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

    func testCopyUnderTheLegacyIdentifierAcceptsTheNewOne() {
        XCTAssertNoThrow(try AutoUpdater.validate(
            newBundleInfo: ["CFBundleIdentifier": "com.polyforms.stats", "CFBundleShortVersionString": "1.12.0"],
            bundleIdentifier: "com.stats.menubar", currentVersion: "1.11.0"))
        XCTAssertNoThrow(try AutoUpdater.validate(
            newBundleInfo: ["CFBundleIdentifier": "com.stats.menubar", "CFBundleShortVersionString": "1.12.0"],
            bundleIdentifier: "com.stats.menubar", currentVersion: "1.11.0"))
    }

    func testNeverMovesBackToTheLegacyIdentifierNorToAnotherApp() {
        for (running, downloaded) in [
            ("com.polyforms.stats", "com.stats.menubar"),
            ("com.other", "com.polyforms.stats"),
            ("", "com.polyforms.stats"),
        ] {
            XCTAssertThrowsError(try AutoUpdater.validate(
                newBundleInfo: ["CFBundleIdentifier": downloaded, "CFBundleShortVersionString": "9.0.0"],
                bundleIdentifier: running, currentVersion: "1.11.0"), "\(running) → \(downloaded)") {
                XCTAssertEqual($0 as? AutoUpdater.UpdateError, .wrongBundleIdentifier)
            }
        }
    }

    func testInfoPlistCarriesTheReleaseIdentifier() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Stats/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, AppIdentity.bundleIdentifier)
    }
}

final class UpdateSignatureTests: XCTestCase {

    private let team = AutoUpdater.Signature(isValid: true, teamIdentifier: "46C337T7YN")

    func testSignedCopyTakesAnUpdateFromItsOwnTeamOnly() {
        XCTAssertNoThrow(try AutoUpdater.validateSignature(downloaded: team, running: team))
        XCTAssertThrowsError(try AutoUpdater.validateSignature(
            downloaded: .init(isValid: true, teamIdentifier: "OTHERTEAM1"), running: team)) {
            XCTAssertEqual($0 as? AutoUpdater.UpdateError, .otherDeveloper)
        }
        XCTAssertThrowsError(try AutoUpdater.validateSignature(
            downloaded: .init(isValid: true, teamIdentifier: nil), running: team)) {
            XCTAssertEqual($0 as? AutoUpdater.UpdateError, .otherDeveloper)
        }
    }

    func testAdHocCopyMovesToTheDeveloperIDBuild() {
        let adHoc = AutoUpdater.Signature(isValid: true, teamIdentifier: nil)
        XCTAssertNoThrow(try AutoUpdater.validateSignature(downloaded: team, running: adHoc))
    }

    func testBrokenSignatureIsAlwaysRefused() {
        for running in [team, AutoUpdater.Signature(isValid: true, teamIdentifier: nil)] {
            XCTAssertThrowsError(try AutoUpdater.validateSignature(
                downloaded: .init(isValid: false, teamIdentifier: "46C337T7YN"), running: running)) {
                XCTAssertEqual($0 as? AutoUpdater.UpdateError, .invalidSignature)
            }
        }
    }

    /// A bundle signed then modified fails the check, as a tampered download would.
    func testReadsSignaturesFromDisk() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/Probe.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        try FileManager.default.copyItem(atPath: "/bin/echo", toPath: macOS.appendingPathComponent("Probe").path)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.polyforms.stats.probe", "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))

        XCTAssertFalse(AutoUpdater.signature(of: app).isValid, "not signed yet")
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", app.path]
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(AutoUpdater.signature(of: app), .init(isValid: true, teamIdentifier: nil))

        try Data("tampered".utf8).write(to: app.appendingPathComponent("Contents/Resources.txt"))
        XCTAssertFalse(AutoUpdater.signature(of: app).isValid, "a file added after signing")
    }
}
