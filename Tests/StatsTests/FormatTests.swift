import XCTest
@testable import Stats

final class FormatTests: XCTestCase {

    func testProcessNameDropsTheAppleBundlePrefix() {
        XCTAssertEqual(Format.processName("com.apple.DriverKit-AppleBCMWLAN"), "DriverKit-AppleBCMWLAN")
        XCTAssertEqual(Format.processName("com.apple.WebKit.Networking"), "WebKit.Networking")
    }

    func testProcessNameKeepsOtherNames() {
        XCTAssertEqual(Format.processName("Claude Helper (Renderer)"), "Claude Helper (Renderer)")
        XCTAssertEqual(Format.processName("com.google.Chrome"), "com.google.Chrome")
        XCTAssertEqual(Format.processName("xcom.apple.thing"), "xcom.apple.thing")
        // Nothing would be left to show
        XCTAssertEqual(Format.processName("com.apple."), "com.apple.")
    }
}

final class ProcessSortTests: XCTestCase {

    func testOnlyCumulatedTabsExplainTheirPeriod() {
        XCTAssertNil(ProcessSort.cpu.help)
        XCTAssertNil(ProcessSort.memory.help)
        XCTAssertEqual(ProcessSort.network.help, "Data received and sent over the last 5 minutes")
    }
}

final class StatusBarModelTests: XCTestCase {

    func testAccessibilitySummaryReadsTheFourWidgets() {
        let model = StatusBarModel()
        model.cpuHistory = [10, 12.4]
        model.memoryUsed = 11 * 1024 * 1024 * 1024
        model.memoryTotal = 16 * 1024 * 1024 * 1024
        model.netInHistory = [1_200_000]
        model.netOutHistory = [30_000]
        model.diskTotal = 494_000_000_000
        model.diskFree = 300_000_000_000
        XCTAssertEqual(
            model.accessibilitySummary,
            "CPU 12%, memory 11.0GB of 16GB, download 1.2MB/s, upload 30.0KB/s, disk 194GB of 494GB used"
        )
    }

    func testAccessibilitySummaryBeforeTheFirstSample() {
        XCTAssertEqual(
            StatusBarModel().accessibilitySummary,
            "CPU –, memory 0B of 0B, download 0B/s, upload 0B/s, disk 0B of 0B used"
        )
    }
}
