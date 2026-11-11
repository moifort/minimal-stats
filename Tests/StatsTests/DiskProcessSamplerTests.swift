import XCTest
@testable import Stats

final class DiskProcessSamplerTests: XCTestCase {

    func testOwnProcessHasDiskCounters() {
        XCTAssertNotNil(DiskProcessSampler.diskUsage(pid: getpid()))
    }

    func testRootProcessesAreNotReadable() throws {
        try XCTSkipIf(getuid() == 0, "root reads every process")
        // launchd runs as root: without privileges the kernel refuses (EPERM)
        XCTAssertNil(DiskProcessSampler.diskUsage(pid: 1))
    }

    func testReadingNamesOwnProcessesByExecutable() {
        let reading = DiskProcessSampler.read(knownNames: [:])
        let own = reading[getpid()]
        XCTAssertNotNil(own)
        XCTAssertEqual(own?.name, executableName(pid: getpid()))
        XCTAssertNil(reading[1])
    }

    func testKnownNamesAreReused() {
        let identity = DiskProcessSampler.read(knownNames: [:])[getpid()]!.identity
        XCTAssertEqual(DiskProcessSampler.read(knownNames: [identity: "cached"])[getpid()]?.name, "cached")
    }
}

final class ByteCounterWindowTests: XCTestCase {

    private func counters(_ bytesIn: UInt64, _ bytesOut: UInt64, identity: String = "a") -> ByteCounterWindow.Counters {
        .init(name: "app", identity: identity, bytesIn: bytesIn, bytesOut: bytesOut)
    }

    func testFirstReadingOnlySeeds() {
        var window = ByteCounterWindow(duration: 300)
        window.record([7: counters(1_000, 1_000)], at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(window.ranked, [])
    }

    func testSumsReadingsAndForgetsThoseOutsideTheWindow() {
        var window = ByteCounterWindow(duration: 300)
        let start = Date(timeIntervalSince1970: 0)
        window.record([7: counters(1_000, 0)], at: start)
        window.record([7: counters(1_500, 10)], at: start.addingTimeInterval(10))
        window.record([7: counters(1_600, 10)], at: start.addingTimeInterval(20))
        XCTAssertEqual(window.ranked, [ProcessBytes(pid: 7, name: "app", bytesIn: 600, bytesOut: 10)])

        window.record([7: counters(1_600, 10)], at: start.addingTimeInterval(315))
        XCTAssertEqual(window.ranked, [ProcessBytes(pid: 7, name: "app", bytesIn: 100, bytesOut: 0)])
        window.record([7: counters(1_600, 10)], at: start.addingTimeInterval(321))
        XCTAssertEqual(window.ranked, [])
    }

    func testReusedPIDStartsFromZero() {
        var window = ByteCounterWindow(duration: 300)
        window.record([7: counters(9_000, 9_000, identity: "7@1")], at: Date(timeIntervalSince1970: 0))
        window.record([7: counters(40, 2, identity: "7@2")], at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(window.ranked.map(\.totalBytes), [42])
    }
}
