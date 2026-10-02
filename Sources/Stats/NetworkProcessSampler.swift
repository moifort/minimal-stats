import Foundation
import Darwin

struct NetworkProcessUsage: Identifiable {
    let pid: pid_t
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64

    var id: pid_t { pid }
    var totalBytes: UInt64 { bytesIn + bytesOut }
}

/// Tracks per-process network traffic over a sliding window using `nettop`,
/// which reports cumulative byte counters per process (system ones included).
/// Sampling must run continuously — not only while the popover is open — so the
/// window really covers the last few minutes.
@MainActor
final class NetworkProcessSampler {

    static let window: TimeInterval = 300
    static let sampleInterval: TimeInterval = 10

    private struct Counters {
        let name: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private struct Sample {
        let date: Date
        let deltas: [pid_t: Counters]
    }

    private var lastCounters: [pid_t: Counters]?
    private var samples: [Sample] = []
    private var isSampling = false

    /// Called on the main actor after each successful sample.
    var onUpdate: (([NetworkProcessUsage]) -> Void)?

    func refresh() {
        guard !isSampling else { return }
        isSampling = true

        Task { [weak self] in
            let counters = await Task.detached(priority: .utility) {
                runCommand("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"])
                    .map(Self.parse)
            }.value
            guard let self else { return }
            self.isSampling = false
            guard let counters else { return }
            self.record(counters, at: Date())
            self.onUpdate?(self.topProcesses())
        }
    }

    /// Processes with traffic in the window, largest total first
    func topProcesses() -> [NetworkProcessUsage] {
        var totals: [pid_t: NetworkProcessUsage] = [:]
        for sample in samples {
            for (pid, delta) in sample.deltas {
                let previous = totals[pid]
                totals[pid] = NetworkProcessUsage(
                    pid: pid,
                    name: delta.name,
                    bytesIn: (previous?.bytesIn ?? 0) + delta.bytesIn,
                    bytesOut: (previous?.bytesOut ?? 0) + delta.bytesOut
                )
            }
        }
        return totals.values
            .filter { $0.totalBytes > 0 }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Private

    private func record(_ counters: [pid_t: Counters], at date: Date) {
        defer { lastCounters = counters }
        // The first reading only seeds the counters: lifetime totals of processes
        // that were already running say nothing about the recent window.
        guard let previous = lastCounters else { return }

        var deltas: [pid_t: Counters] = [:]
        for (pid, current) in counters {
            // A new pid has done all its traffic since the last sample. A counter
            // that went backwards means the pid was reused by another process.
            let base = previous[pid].flatMap { prev in
                current.bytesIn >= prev.bytesIn && current.bytesOut >= prev.bytesOut ? prev : nil
            }
            let delta = Counters(
                name: current.name,
                bytesIn: current.bytesIn - (base?.bytesIn ?? 0),
                bytesOut: current.bytesOut - (base?.bytesOut ?? 0)
            )
            if delta.bytesIn > 0 || delta.bytesOut > 0 {
                deltas[pid] = delta
            }
        }

        samples.append(Sample(date: date, deltas: deltas))
        samples.removeAll { date.timeIntervalSince($0.date) > Self.window }
    }

    /// Parses lines like `Claude Helper.97795,1899084,6241861,`
    private nonisolated static func parse(_ output: String) -> [pid_t: Counters] {
        var result: [pid_t: Counters] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let dot = fields[0].lastIndex(of: "."),
                  let pid = pid_t(fields[0][fields[0].index(after: dot)...]),
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2])
            else { continue }
            let name = executableName(pid: pid) ?? String(fields[0][..<dot])
            result[pid] = Counters(name: name, bytesIn: bytesIn, bytesOut: bytesOut)
        }
        return result
    }

    /// nettop truncates names to 15 characters; the executable path has the full one.
    private nonisolated static func executableName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }
}
