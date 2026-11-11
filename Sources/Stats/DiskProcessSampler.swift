import Foundation
import Darwin

/// Tracks per-process disk reads and writes over the same sliding window as the
/// network, from the cumulative counters of `proc_pid_rusage`. Without root, the
/// kernel only answers for the user's own processes (EPERM for the others), so
/// system daemons such as mds_stores or kernel_task are never counted.
@MainActor
final class DiskProcessSampler {

    nonisolated static let window = NetworkProcessSampler.window
    nonisolated static let sampleInterval = NetworkProcessSampler.sampleInterval

    private var counters = ByteCounterWindow(duration: window)
    private var isSampling = false
    /// Executable names by process identity, so paths are only resolved once
    private var names: [String: String] = [:]

    /// Called on the main actor after each sample, with the processes that read
    /// or wrote in the window (bytesIn read, bytesOut written).
    var onUpdate: (([ProcessBytes]) -> Void)?

    func refresh() {
        guard !isSampling else { return }
        isSampling = true
        let known = names

        Task { [weak self] in
            let reading = await Task.detached(priority: .utility) {
                Self.read(knownNames: known)
            }.value
            guard let self else { return }
            self.isSampling = false
            self.names = Dictionary(reading.values.map { ($0.identity, $0.name) }, uniquingKeysWith: { first, _ in first })
            self.counters.record(reading, at: Date())
            self.onUpdate?(self.counters.ranked)
        }
    }

    /// Counters of every process the kernel lets us read.
    nonisolated static func read(knownNames: [String: String]) -> [pid_t: ByteCounterWindow.Counters] {
        var result: [pid_t: ByteCounterWindow.Counters] = [:]
        for pid in allPIDs() {
            guard let usage = diskUsage(pid: pid) else { continue }
            // pid and start time together name one process for its whole life
            let identity = "\(pid)@\(usage.startTime)"
            let name = knownNames[identity] ?? executableName(pid: pid) ?? shortName(pid: pid) ?? "\(pid)"
            result[pid] = .init(name: name, identity: identity, bytesIn: usage.read, bytesOut: usage.written)
        }
        return result
    }

    /// Bytes read from and written to disk since the process started; nil for
    /// processes of other users and root.
    nonisolated static func diskUsage(pid: pid_t) -> (read: UInt64, written: UInt64, startTime: UInt64)? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }
        return (info.ri_diskio_bytesread, info.ri_diskio_byteswritten, info.ri_proc_start_abstime)
    }

    private nonisolated static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).filter { $0 > 0 }
    }

    private nonisolated static func shortName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
