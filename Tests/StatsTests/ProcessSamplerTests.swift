import XCTest
@testable import Stats

final class ProcessSamplerTests: XCTestCase {

    func testParsesCPUTimeFormats() {
        XCTAssertEqual(ProcessSampler.cpuSeconds("0:00.00"), 0)
        XCTAssertEqual(ProcessSampler.cpuSeconds("0:01.50"), 1.5)
        XCTAssertEqual(ProcessSampler.cpuSeconds("2086:20.12") ?? -1, 125_180.12, accuracy: 0.001)
        XCTAssertEqual(ProcessSampler.cpuSeconds("1-02:03:04.05") ?? -1, 93_784.05, accuracy: 0.001)
        XCTAssertNil(ProcessSampler.cpuSeconds("garbage"))
    }

    func testParsesPSOutputKeepingNamesWithSpaces() {
        let output = """
          472     1 2086:20.12 123456 88 WindowServer
         1234  1221    0:03.00   2048 501 Claude Helper (Renderer)
        """
        let snapshot = ProcessSampler.parse(output, ownPID: 999)
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[1234]?.name, "Claude Helper (Renderer)")
        XCTAssertEqual(snapshot[1234]?.parentPID, 1221)
        XCTAssertEqual(snapshot[1234]?.cpuSeconds, 3)
        XCTAssertEqual(snapshot[1234]?.memoryBytes, 2048 * 1024)
        XCTAssertEqual(snapshot[1234]?.uid, 501)
        XCTAssertEqual(snapshot[472]?.uid, 88)
    }

    func testExcludesOwnProcess() {
        let snapshot = ProcessSampler.parse("  999 1 0:01.00 100 501 Stats\n", ownPID: 999)
        XCTAssertTrue(snapshot.isEmpty)
    }

    func testCPUPercentIsDeltaOverIntervalAsShareOfMachine() {
        // One full core busy for 2 seconds on an 8-core machine = 12.5% of the machine
        let previous: [pid_t: ProcessSampler.Snapshot] = [
            1: .init(name: "busy", parentPID: 1, cpuSeconds: 10, memoryBytes: 0, uid: 501),
        ]
        let current: [pid_t: ProcessSampler.Snapshot] = [
            1: .init(name: "busy", parentPID: 1, cpuSeconds: 12, memoryBytes: 0, uid: 501),
        ]
        let usage = ProcessSampler.usage(current: current, previous: previous, elapsed: 2, coreCount: 8, currentUID: 501)
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage[0].cpuPercent ?? -1, 12.5, accuracy: 0.001)
        XCTAssertTrue(usage[0].isOwnedByUser)
    }

    func testProcessesWithoutPreviousSampleHaveNoCPUFigure() {
        let current: [pid_t: ProcessSampler.Snapshot] = [
            7: .init(name: "new", parentPID: 1, cpuSeconds: 5, memoryBytes: 4096, uid: 0),
        ]
        let usage = ProcessSampler.usage(current: current, previous: [:], elapsed: 2, coreCount: 8, currentUID: 501)
        XCTAssertEqual(usage.count, 1)
        XCTAssertNil(usage[0].cpuPercent)
        XCTAssertEqual(usage[0].memoryBytes, 4096)
        XCTAssertFalse(usage[0].isOwnedByUser)
    }

    func testReusedPIDWithLowerCPUTimeHasNoCPUFigure() {
        let previous: [pid_t: ProcessSampler.Snapshot] = [
            3: .init(name: "old", parentPID: 1, cpuSeconds: 50, memoryBytes: 0, uid: 501),
        ]
        let current: [pid_t: ProcessSampler.Snapshot] = [
            3: .init(name: "reborn", parentPID: 1, cpuSeconds: 1, memoryBytes: 0, uid: 501),
        ]
        let usage = ProcessSampler.usage(current: current, previous: previous, elapsed: 2, coreCount: 8, currentUID: 501)
        XCTAssertNil(usage[0].cpuPercent)
    }
}
