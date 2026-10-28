import Foundation

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

        func root(of process: ProcessUsage) -> ProcessUsage {
            var current = process
            var visited: Set<pid_t> = [current.pid]
            while current.parentPID > 1,
                  let parent = byPID[current.parentPID],
                  visited.insert(parent.pid).inserted {
                current = parent
            }
            return current
        }

        var members: [pid_t: [ProcessUsage]] = [:]
        var roots: [pid_t: ProcessUsage] = [:]
        for process in processes {
            let top = root(of: process)
            roots[top.pid] = top
            members[top.pid, default: []].append(process)
        }

        return members.map { rootPID, members in
            let root = roots[rootPID]!
            let measured = members.compactMap(\.cpuPercent)
            let isSimulator = root.name == simulatorRootName
            return ProcessGroup(
                rootPID: rootPID,
                name: names[rootPID] ?? (isSimulator ? "Simulator" : root.name),
                cpuPercent: measured.isEmpty ? nil : min(measured.reduce(0, +), 100),
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                members: members.sorted { ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1) },
                // SIGTERM on launchd_sim would leave the simulator in a broken state
                canQuit: root.isOwnedByUser && !isSimulator
            )
        }
    }

    static let simulatorRootName = "launchd_sim"

    /// "iPhone 17 Pro" for a launchd_sim pid, read from the device folder in its arguments.
    static func simulatorName(pid: pid_t) -> String? {
        guard let args = runCommand("/bin/ps", ["-o", "args=", "-p", String(pid)]),
              let range = args.range(of: #"/Devices/[0-9A-F-]+/"#, options: .regularExpression)
        else { return nil }
        let deviceFolder = args[..<range.upperBound].split(separator: " ").last.map(String.init) ?? ""
        let plist = URL(fileURLWithPath: deviceFolder).appendingPathComponent("device.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = info["name"] as? String
        else { return nil }
        return name
    }
}
