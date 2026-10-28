import XCTest
@testable import Stats

final class ProcessGroupTests: XCTestCase {

    private func process(_ pid: pid_t, parent: pid_t, _ name: String, cpu: Double?, memory: UInt64 = 0, uid: uid_t = 501) -> ProcessUsage {
        ProcessUsage(pid: pid, parentPID: parent, name: name, cpuPercent: cpu, memoryBytes: memory, isOwnedByUser: uid == 501)
    }

    func testGroupsDescendantsUnderTheirTopLevelAncestor() {
        let groups = ProcessGroup.make(from: [
            process(1221, parent: 1, "Claude", cpu: 2),
            process(1321, parent: 1221, "Claude Helper", cpu: 3),
            process(1709, parent: 1221, "claude", cpu: 1),
            process(1800, parent: 1709, "swift-frontend", cpu: 12.5, memory: 100),
            process(614, parent: 1, "WindowServer", cpu: 5, uid: 88),
        ])
        let claude = groups.first { $0.rootPID == 1221 }
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(claude?.name, "Claude")
        XCTAssertEqual(claude?.cpuPercent ?? -1, 18.5, accuracy: 0.001)
        XCTAssertEqual(claude?.memoryBytes, 100)
        XCTAssertEqual(claude?.members.first?.name, "swift-frontend")
        XCTAssertEqual(claude?.canQuit, true)
        XCTAssertEqual(groups.first { $0.rootPID == 614 }?.canQuit, false)
    }

    func testSimulatorIsNamedAndCannotBeQuit() {
        let groups = ProcessGroup.make(
            from: [
                process(2883, parent: 1, "launchd_sim", cpu: 0),
                process(2900, parent: 2883, "SpringBoard", cpu: 6),
                process(2921, parent: 2883, "backboardd", cpu: 4),
            ],
            names: [2883: "Simulator · iPhone 17 Pro"]
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "Simulator · iPhone 17 Pro")
        XCTAssertEqual(groups[0].cpuPercent ?? -1, 10, accuracy: 0.001)
        XCTAssertFalse(groups[0].canQuit)
    }

    func testGroupWithoutAnyMeasuredMemberHasNoCPUFigure() {
        let groups = ProcessGroup.make(from: [process(5, parent: 1, "new", cpu: nil)])
        XCTAssertNil(groups[0].cpuPercent)
    }

    func testOrphanWhoseParentIsUnknownIsItsOwnRoot() {
        let groups = ProcessGroup.make(from: [process(9, parent: 4242, "orphan", cpu: 1)])
        XCTAssertEqual(groups.map(\.rootPID), [9])
    }
}
