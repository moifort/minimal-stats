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
}
