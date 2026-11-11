import Foundation
import Darwin

/// An application and everything it spawned: Claude with its helpers and the shells,
/// compilers and tools its sessions run, or a simulator with its dozens of daemons.
/// A busy machine is rarely one process at 100%; it is one app spread over many
/// processes at a few percent each, which a per-process list hides.
struct ProcessGroup: Identifiable {
    /// The top-level process, a direct child of launchd
    let rootPID: pid_t
    let name: String
    /// Sum of the members' figures; nil while none of them has one yet
    let cpuPercent: Double?
    let memoryBytes: UInt64
    /// Busiest first
    let members: [ProcessUsage]
    let canQuit: Bool

    var id: pid_t { rootPID }

    /// Groups processes under their ancestor whose parent is launchd (or that has no
    /// known parent). `names` overrides a root's displayed name, e.g. for simulators.
    static func make(from processes: [ProcessUsage], names: [pid_t: String] = [:]) -> [ProcessGroup] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func root(of process: ProcessUsage) -> ProcessUsage { ancestors(of: process, in: byPID).last ?? process }

        var members: [pid_t: [ProcessUsage]] = [:]
        var roots: [pid_t: ProcessUsage] = [:]
        for process in processes {
            let top = root(of: process)
            roots[top.pid] = top
            members[top.pid, default: []].append(process)
        }

        let groups = members.map { rootPID, members in
            let root = roots[rootPID]!
            let measured = members.compactMap(\.cpuPercent)
            let isSimulator = root.name == simulatorRootName
            return ProcessGroup(
                rootPID: rootPID,
                name: names[rootPID] ?? (isSimulator ? "Simulator" : root.name),
                cpuPercent: measured.isEmpty ? nil : min(measured.reduce(0, +), 100),
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                members: members.sorted {
                    let a = $0.cpuPercent ?? -1, b = $1.cpuPercent ?? -1
                    return a != b ? a > b : isOrdered($0.name, $0.pid, before: $1.name, $1.pid)
                },
                // SIGTERM on launchd_sim would leave the simulator in a broken state
                canQuit: root.isOwnedByUser && !isSimulator
            )
        }
        // Dictionary order changes from one sample to the next
        return groups.sorted { isOrdered($0.name, $0.rootPID, before: $1.name, $1.rootPID) }
    }

    /// Busiest first; groups without a CPU figure yet are left out.
    static func sortedByCPU(_ groups: [ProcessGroup]) -> [(group: ProcessGroup, cpuPercent: Double)] {
        groups
            .compactMap { group in group.cpuPercent.map { (group: group, cpuPercent: $0) } }
            .sorted {
                $0.cpuPercent != $1.cpuPercent
                    ? $0.cpuPercent > $1.cpuPercent
                    : isOrdered($0.group.name, $0.group.rootPID, before: $1.group.name, $1.group.rootPID)
            }
    }

    /// Largest first.
    static func sortedByMemory(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        groups.sorted {
            $0.memoryBytes != $1.memoryBytes
                ? $0.memoryBytes > $1.memoryBytes
                : isOrdered($0.name, $0.rootPID, before: $1.name, $1.rootPID)
        }
    }

    /// Tie-break for equal values, so rows keep their place between refreshes.
    static func isOrdered(_ name: String, _ pid: pid_t, before otherName: String, _ otherPID: pid_t) -> Bool {
        name != otherName ? name < otherName : pid < otherPID
    }

    static let simulatorRootName = "launchd_sim"

    /// The process itself, then its parent, and so on up to the child of launchd
    /// (or the last ancestor that is still in the list).
    private static func ancestors(of process: ProcessUsage, in byPID: [pid_t: ProcessUsage]) -> [ProcessUsage] {
        var chain = [process]
        var visited: Set<pid_t> = [process.pid]
        while let current = chain.last,
              current.parentPID > 1,
              let parent = byPID[current.parentPID],
              visited.insert(parent.pid).inserted {
            chain.append(parent)
        }
        return chain
    }

    /// "iPhone 17 Pro" for a launchd_sim pid, read from the device folder in its arguments.
    static func simulatorName(pid: pid_t) -> String? {
        guard let arguments = processArguments(pid: pid),
              let deviceFolder = simulatorDeviceFolder(arguments: arguments)
        else { return nil }
        let plist = URL(fileURLWithPath: deviceFolder).appendingPathComponent("device.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = info["name"] as? String
        else { return nil }
        return name
    }

    /// The `…/Devices/<UDID>/` folder named in one of the arguments. Each argument
    /// is matched on its own, so spaces in the path (or in the runtime path that
    /// precedes it) do not matter.
    static func simulatorDeviceFolder(arguments: [String]) -> String? {
        for argument in arguments {
            if let range = argument.range(of: #"^.*?/Devices/[0-9A-F-]+/"#, options: .regularExpression) {
                return String(argument[range])
            }
        }
        return nil
    }

    /// A process's argv, read with sysctl(KERN_PROCARGS2): argc, the executable
    /// path, NUL padding, then the NUL-terminated arguments.
    static func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and the padding after it
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}

/// What an app and everything it spawned sent and received, or read and wrote,
/// like a `ProcessGroup` for the Network and Disk tabs.
struct GroupTraffic: Identifiable, Equatable {
    /// The group's root, or the process itself when it belongs to no known group
    let rootPID: pid_t
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    let canQuit: Bool

    var id: pid_t { rootPID }
    var totalBytes: UInt64 { bytesIn + bytesOut }

    /// Sums per-process bytes by group, largest total first, then by name and pid.
    /// Bytes are sampled all the time but the process list only while the popover
    /// is open: a pid found in no group (it exited, or started since) stays on its
    /// own row, which cannot be quit since nothing says who owns it now.
    static func make(from usage: [ProcessBytes], groups: [ProcessGroup]) -> [GroupTraffic] {
        var groupOf: [pid_t: ProcessGroup] = [:]
        for group in groups {
            for member in group.members { groupOf[member.pid] = group }
        }

        var totals: [pid_t: GroupTraffic] = [:]
        for process in usage {
            let group = groupOf[process.pid]
            let key = group?.rootPID ?? process.pid
            let previous = totals[key]
            totals[key] = GroupTraffic(
                rootPID: key,
                name: group?.name ?? process.name,
                bytesIn: (previous?.bytesIn ?? 0) + process.bytesIn,
                bytesOut: (previous?.bytesOut ?? 0) + process.bytesOut,
                canQuit: group?.canQuit ?? false
            )
        }
        return totals.values
            .filter { $0.totalBytes > 0 }
            .sorted {
                $0.totalBytes != $1.totalBytes
                    ? $0.totalBytes > $1.totalBytes
                    : ProcessGroup.isOrdered($0.name, $0.rootPID, before: $1.name, $1.rootPID)
            }
    }
}
