import Foundation

/// Bytes a process moved in two directions over a period: received and sent for
/// the network, read and written for the disk.
struct ProcessBytes: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64

    var id: pid_t { pid }
    var totalBytes: UInt64 { bytesIn + bytesOut }
}

/// Turns readings of cumulative per-process byte counters into what each process
/// moved over a sliding window. Readings must be taken all the time, not only
/// while the popover is open, for the window to really cover its duration.
struct ByteCounterWindow {

    struct Counters: Equatable {
        /// Display name
        let name: String
        /// Never varies for a given process and changes when its pid is reused
        let identity: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    let duration: TimeInterval
    private var lastCounters: [pid_t: Counters]?
    private var samples: [(date: Date, deltas: [pid_t: Counters])] = []

    init(duration: TimeInterval) {
        self.duration = duration
    }

    mutating func record(_ counters: [pid_t: Counters], at date: Date) {
        defer { lastCounters = counters }
        // The first reading only seeds the counters: lifetime totals of processes
        // that were already running say nothing about the recent window.
        guard let previous = lastCounters else { return }

        samples.append((date, Self.deltas(current: counters, previous: previous)))
        samples.removeAll { date.timeIntervalSince($0.date) > duration }
    }

    /// Processes that moved bytes in the window, largest total first
    var ranked: [ProcessBytes] {
        Self.ranked(samples.map(\.deltas))
    }

    /// Bytes per pid since the previous reading. A counter can go down (nettop's
    /// are the sum of the open flows, which drops when a connection closes): each
    /// direction only counts what it gained, never a negative. A pid that is new,
    /// or now belongs to another process (pid reuse), moved all its bytes since.
    static func deltas(current: [pid_t: Counters], previous: [pid_t: Counters]) -> [pid_t: Counters] {
        var deltas: [pid_t: Counters] = [:]
        for (pid, now) in current {
            let base = previous[pid].flatMap { $0.identity == now.identity ? $0 : nil }
            let delta = Counters(
                name: now.name,
                identity: now.identity,
                bytesIn: now.bytesIn - min(base?.bytesIn ?? 0, now.bytesIn),
                bytesOut: now.bytesOut - min(base?.bytesOut ?? 0, now.bytesOut)
            )
            if delta.bytesIn > 0 || delta.bytesOut > 0 {
                deltas[pid] = delta
            }
        }
        return deltas
    }

    /// Sums per-pid bytes over the samples; largest total first, then by name and pid.
    static func ranked(_ samples: [[pid_t: Counters]]) -> [ProcessBytes] {
        var totals: [pid_t: ProcessBytes] = [:]
        for deltas in samples {
            for (pid, delta) in deltas {
                let previous = totals[pid]
                totals[pid] = ProcessBytes(
                    pid: pid,
                    name: delta.name,
                    bytesIn: (previous?.bytesIn ?? 0) + delta.bytesIn,
                    bytesOut: (previous?.bytesOut ?? 0) + delta.bytesOut
                )
            }
        }
        return totals.values
            .filter { $0.totalBytes > 0 }
            .sorted {
                $0.totalBytes != $1.totalBytes
                    ? $0.totalBytes > $1.totalBytes
                    : ProcessGroup.isOrdered($0.name, $0.pid, before: $1.name, $1.pid)
            }
    }
}
