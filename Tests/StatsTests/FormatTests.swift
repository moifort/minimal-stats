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
