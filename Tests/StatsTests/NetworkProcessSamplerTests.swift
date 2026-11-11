import XCTest
@testable import Stats

final class NetworkProcessSamplerTests: XCTestCase {

    private func counters(_ command: String, _ bytesIn: UInt64, _ bytesOut: UInt64) -> ByteCounterWindow.Counters {
        .init(name: command, identity: command, bytesIn: bytesIn, bytesOut: bytesOut)
    }

    func testClosedConnectionDoesNotCountTheWholeCounterAgain() {
        // Measured with nettop: the inbound sum dropped as a flow closed while outbound grew
        let previous = [pid_t(1377): counters("Claude Helper", 10_938_220, 2_630_242)]
        let current = [pid_t(1377): counters("Claude Helper", 10_930_900, 2_672_785)]
        let deltas = ByteCounterWindow.deltas(current: current, previous: previous)
        XCTAssertEqual(deltas[1377]?.bytesIn, 0)
        XCTAssertEqual(deltas[1377]?.bytesOut, 42_543)
    }

    func testCountersThatOnlyWentDownYieldNoTraffic() {
        let previous = [pid_t(560): counters("remoted", 41_426, 3_000)]
        let current = [pid_t(560): counters("remoted", 25_336, 2_998)]
        XCTAssertTrue(ByteCounterWindow.deltas(current: current, previous: previous).isEmpty)
    }

    func testNewPIDCountsAllItsTraffic() {
        let deltas = ByteCounterWindow.deltas(current: [pid_t(42): counters("curl", 500, 20)], previous: [:])
        XCTAssertEqual(deltas[42], counters("curl", 500, 20))
    }

    func testReusedPIDRunningAnotherExecutableCountsAllItsTraffic() {
        let previous = [pid_t(42): counters("curl", 9_000, 9_000)]
        let current = [pid_t(42): counters("wget", 500, 20)]
        XCTAssertEqual(ByteCounterWindow.deltas(current: current, previous: previous)[42], counters("wget", 500, 20))
    }

    func testParsesNettopCSV() {
        let output = """
        ,bytes_in,bytes_out,
        Notion Helper.99991,21206427,1200,
        garbage line
        syslogd.99992,0,111,
        """
        let parsed = NetworkProcessSampler.parse(output)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[99991]?.identity, "Notion Helper")
        XCTAssertEqual(parsed[99991]?.bytesIn, 21_206_427)
        XCTAssertEqual(parsed[99992]?.bytesOut, 111)
    }

    func testRankingSumsSamplesAndBreaksTiesByNameThenPID() {
        let samples: [[pid_t: ByteCounterWindow.Counters]] = [
            [3: counters("b", 10, 0), 2: counters("a", 10, 0), 1: counters("b", 10, 0)],
            [4: counters("big", 100, 0), 2: counters("a", 0, 0)],
        ]
        let ranked = ByteCounterWindow.ranked(samples)
        XCTAssertEqual(ranked.map(\.pid), [4, 2, 1, 3])
        XCTAssertEqual(ranked.first?.totalBytes, 100)
    }
}
