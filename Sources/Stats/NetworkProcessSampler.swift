import Foundation
import Darwin

/// Tracks per-process network traffic over a sliding window using `nettop`,
/// which reports cumulative byte counters per process (system ones included).
/// Sampling must run continuously — not only while the popover is open — so the
/// window really covers the last few minutes.
@MainActor
final class NetworkProcessSampler {

    nonisolated static let window: TimeInterval = 300
    nonisolated static let sampleInterval: TimeInterval = 10

    private var counters = ByteCounterWindow(duration: window)
    private var isSampling = false

    /// Called on the main actor after each successful sample, with the processes
    /// that received or sent data in the window (bytesIn received, bytesOut sent).
    var onUpdate: (([ProcessBytes]) -> Void)?

    func refresh() {
        guard !isSampling else { return }
        isSampling = true

        Task { [weak self] in
            let reading = await Task.detached(priority: .utility) {
                // nettop takes about 5 s to produce its single sample
                runCommand("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"], timeout: 20)
                    .map(Self.parse)
            }.value
            guard let self else { return }
            self.isSampling = false
            guard let reading else { return }
            self.counters.record(reading, at: Date())
            self.onUpdate?(self.counters.ranked)
        }
    }

    /// Parses lines like `Claude Helper.97795,1899084,6241861,`. The identity is
    /// nettop's own (truncated) name, which never varies for a given process.
    nonisolated static func parse(_ output: String) -> [pid_t: ByteCounterWindow.Counters] {
        var result: [pid_t: ByteCounterWindow.Counters] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let dot = fields[0].lastIndex(of: "."),
                  let pid = pid_t(fields[0][fields[0].index(after: dot)...]),
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2])
            else { continue }
            let command = String(fields[0][..<dot])
            let name = executableName(pid: pid) ?? command
            result[pid] = .init(name: name, identity: command, bytesIn: bytesIn, bytesOut: bytesOut)
        }
        return result
    }
}

/// The full name of a process's executable, or nil when its path cannot be read
/// (nettop and proc_name truncate names to 15 characters).
func executableName(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
}
