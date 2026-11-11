import XCTest
@testable import Stats

final class DistributionTests: XCTestCase {

    func testDeveloperIDBuildKeepsEverything() {
        // `swift test` builds without the APP_STORE flag
        XCTAssertFalse(Distribution.isAppStore)
        XCTAssertTrue(Distribution.measuresProcesses)
        XCTAssertTrue(Distribution.canQuitProcesses)
        XCTAssertTrue(Distribution.hasUninstaller)
        XCTAssertEqual(ProcessSort.available, ProcessSort.allCases)
    }

    func testRecognizesBuildFolders() {
        XCTAssertTrue(Distribution.isBuildProduct(path: "/Users/me/minimal-stats/.build/arm64-apple-macosx/debug/Stats.app"))
        XCTAssertTrue(Distribution.isBuildProduct(path: "/Users/me/minimal-stats/build/app-store/Stats.app"))
        XCTAssertTrue(Distribution.isBuildProduct(path: "/Users/me/Library/Developer/Xcode/DerivedData/Stats-abc/Build/Products/Release/Stats.app"))
        XCTAssertFalse(Distribution.isBuildProduct(path: "/Applications/Stats.app"))
        XCTAssertFalse(Distribution.isBuildProduct(path: "/Users/me/Applications/Stats.app"))
    }

    /// What the App Store build lists instead of running /bin/ps.
    func testListsProcessesWithParentsButNoFigures() throws {
        let processes = try XCTUnwrap(ProcessSampler.listWithoutFigures())
        XCTAssertGreaterThan(processes.count, 10)
        XCTAssertFalse(processes.contains { $0.pid == getpid() })
        let launchd = try XCTUnwrap(processes.first { $0.pid == 1 })
        XCTAssertEqual(launchd.name, "launchd")
        XCTAssertFalse(launchd.isOwnedByUser)
        XCTAssertTrue(processes.allSatisfy { $0.cpuPercent == nil && $0.memoryBytes == 0 })
        // The test runner's parent is listed with the right parent pid
        let parent = try XCTUnwrap(processes.first { $0.pid == getppid() })
        XCTAssertTrue(parent.isOwnedByUser)
        XCTAssertFalse(parent.name.isEmpty)
    }
}
