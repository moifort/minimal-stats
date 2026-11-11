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

    // MARK: - Stable order

    private let idleGroups: [ProcessUsage] = [
        ProcessUsage(pid: 30, parentPID: 1, name: "b", cpuPercent: 0, memoryBytes: 10, isOwnedByUser: true),
        ProcessUsage(pid: 20, parentPID: 1, name: "a", cpuPercent: 0, memoryBytes: 10, isOwnedByUser: true),
        ProcessUsage(pid: 10, parentPID: 1, name: "b", cpuPercent: 0, memoryBytes: 10, isOwnedByUser: true),
        ProcessUsage(pid: 40, parentPID: 1, name: "busy", cpuPercent: 5, memoryBytes: 99, isOwnedByUser: true),
    ]

    func testGroupsComeOutInAStableOrder() {
        let groups = ProcessGroup.make(from: idleGroups)
        XCTAssertEqual(groups.map(\.rootPID), [20, 10, 30, 40])
        XCTAssertEqual(ProcessGroup.make(from: idleGroups.reversed()).map(\.rootPID), [20, 10, 30, 40])
    }

    func testEqualValuesAreOrderedByNameThenPID() {
        let groups = ProcessGroup.make(from: idleGroups.shuffled())
        XCTAssertEqual(ProcessGroup.sortedByCPU(groups).map(\.group.rootPID), [40, 20, 10, 30])
        XCTAssertEqual(ProcessGroup.sortedByMemory(groups).map(\.rootPID), [40, 20, 10, 30])
    }

    func testMembersWithEqualCPUAreOrderedByNameThenPID() {
        let groups = ProcessGroup.make(from: [
            process(100, parent: 1, "root", cpu: 0),
            process(5, parent: 100, "z", cpu: 0),
            process(4, parent: 100, "a", cpu: 0),
            process(3, parent: 100, "a", cpu: 0),
        ].shuffled())
        XCTAssertEqual(groups[0].members.map(\.pid), [3, 4, 100, 5])
    }

    // MARK: - Simulator device folder

    func testFindsDeviceFolderInPathsWithSpaces() {
        let arguments = [
            "/Library/Developer/CoreSimulator/Volumes/iOS_23A/Profiles/Runtimes/iOS 27.2.simruntime/Contents/Resources/RuntimeRoot/sbin/launchd_sim",
            "/Users/Jane Doe/Library/Developer/CoreSimulator/Devices/17C55769-48DC-444C-8E31-7C005B062908/data/var/run/launchd_bootstrap.plist",
        ]
        XCTAssertEqual(
            ProcessGroup.simulatorDeviceFolder(arguments: arguments),
            "/Users/Jane Doe/Library/Developer/CoreSimulator/Devices/17C55769-48DC-444C-8E31-7C005B062908/"
        )
        XCTAssertNil(ProcessGroup.simulatorDeviceFolder(arguments: ["launchd_sim", "--help"]))
    }

    func testReadsOwnProcessArguments() {
        let arguments = ProcessGroup.processArguments(pid: getpid())
        XCTAssertEqual(arguments, CommandLine.arguments)
    }

    // MARK: - Network tab

    private func traffic(_ pid: pid_t, _ name: String, _ bytesIn: UInt64, _ bytesOut: UInt64) -> NetworkProcessUsage {
        NetworkProcessUsage(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut)
    }

    private lazy var groups = ProcessGroup.make(
        from: [
            process(1221, parent: 1, "Claude", cpu: 0),
            process(1321, parent: 1221, "Claude Helper (Renderer)", cpu: 0),
            process(1709, parent: 1221, "claude", cpu: 0),
            process(2883, parent: 1, "launchd_sim", cpu: 0),
            process(2950, parent: 2883, "nsurlsessiond", cpu: 0),
            process(614, parent: 1, "WindowServer", cpu: 0, uid: 88),
        ],
        names: [2883: "Simulator · iPhone 17 Pro"]
    )

    func testTrafficIsSummedByApplication() {
        let rows = GroupTraffic.make(from: [
            traffic(1321, "Claude Helper (Renderer)", 40, 4),
            traffic(1709, "claude", 10, 1),
            traffic(1221, "Claude", 2, 0),
            traffic(614, "WindowServer", 3, 0),
        ], groups: groups)
        XCTAssertEqual(rows, [
            GroupTraffic(rootPID: 1221, name: "Claude", bytesIn: 52, bytesOut: 5, canQuit: true),
            GroupTraffic(rootPID: 614, name: "WindowServer", bytesIn: 3, bytesOut: 0, canQuit: false),
        ])
    }

    func testSimulatorTrafficCannotBeQuit() {
        let rows = GroupTraffic.make(from: [traffic(2950, "nsurlsessiond", 7, 7)], groups: groups)
        XCTAssertEqual(rows.map(\.name), ["Simulator · iPhone 17 Pro"])
        XCTAssertEqual(rows.map(\.canQuit), [false])
    }

    func testProcessMissingFromTheListKeepsItsOwnRowWithoutQuit() {
        let rows = GroupTraffic.make(from: [traffic(4242, "curl", 9, 1)], groups: groups)
        XCTAssertEqual(rows, [GroupTraffic(rootPID: 4242, name: "curl", bytesIn: 9, bytesOut: 1, canQuit: false)])
        XCTAssertEqual(GroupTraffic.make(from: [traffic(4242, "curl", 9, 1)], groups: []).count, 1)
    }

    func testEqualTrafficIsOrderedByNameThenPID() {
        let rows = GroupTraffic.make(from: [
            traffic(30, "b", 5, 0), traffic(20, "a", 5, 0), traffic(10, "b", 5, 0), traffic(40, "idle", 0, 0),
        ], groups: [])
        XCTAssertEqual(rows.map(\.rootPID), [20, 10, 30])
    }
}
