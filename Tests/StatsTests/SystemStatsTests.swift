import XCTest
@testable import Stats

final class SystemStatsTests: XCTestCase {

    private typealias Bytes = SystemStats.InterfaceBytes

    func testSumsPerInterfaceDeltas() {
        let previous = ["en0": Bytes(inBytes: 1_000, outBytes: 500), "en1": Bytes(inBytes: 10, outBytes: 10)]
        let current = ["en0": Bytes(inBytes: 3_000, outBytes: 600), "en1": Bytes(inBytes: 20, outBytes: 15)]
        XCTAssertEqual(SystemStats.networkDelta(current: current, previous: previous), Bytes(inBytes: 2_010, outBytes: 105))
    }

    func testDisappearingInterfaceDoesNotWrapAround() {
        // Wi-Fi turned off: the total drops, which used to wrap to ~1.8e19 B/s
        let previous = ["en0": Bytes(inBytes: 9_000_000_000, outBytes: 1_000_000), "en5": Bytes(inBytes: 100, outBytes: 100)]
        let current = ["en5": Bytes(inBytes: 150, outBytes: 120)]
        XCTAssertEqual(SystemStats.networkDelta(current: current, previous: previous), Bytes(inBytes: 50, outBytes: 20))
    }

    func testAppearingInterfaceDoesNotBringItsLifetimeTotals() {
        let previous = ["en0": Bytes(inBytes: 100, outBytes: 100)]
        let current = ["en0": Bytes(inBytes: 100, outBytes: 100), "en7": Bytes(inBytes: 5_000_000_000, outBytes: 1_000)]
        XCTAssertEqual(SystemStats.networkDelta(current: current, previous: previous), Bytes(inBytes: 0, outBytes: 0))
    }

    func testResetCounterAddsNothing() {
        let previous = ["en0": Bytes(inBytes: 5_000, outBytes: 5_000)]
        let current = ["en0": Bytes(inBytes: 10, outBytes: 6_000)]
        XCTAssertEqual(SystemStats.networkDelta(current: current, previous: previous), Bytes(inBytes: 0, outBytes: 1_000))
    }
}
