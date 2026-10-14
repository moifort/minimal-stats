import AppKit
import Darwin

struct ProcessUsage: Identifiable {
    let pid: pid_t
    let name: String
    /// Share of the whole machine's CPU, 0–100 (not per-core like Activity Monitor),
    /// measured over the interval since the previous sample. Nil until a process has
    /// been seen in two consecutive samples.
    let cpuPercent: Double?
    let memoryBytes: UInt64
    let isOwnedByUser: Bool

    var id: pid_t { pid }
}

/// Lists running processes through `/bin/ps`, which is setuid root and therefore
/// sees system processes (WindowServer, mds_stores…) that libproc hides from us.
///
/// `ps`'s own `%cpu` column is a decaying average since the process started, so a
/// 13-day-old WindowServer looks idle during a spike. Like `top`, we instead read the
/// cumulative CPU time and divide the increase by the wall time between two samples.
@MainActor
final class ProcessSampler {

    struct Snapshot {
        let name: String
        let cpuSeconds: Double
        let memoryBytes: UInt64
        let uid: uid_t
    }

    /// A previous snapshot older than this no longer describes "current" activity.
    static let maxInterval: TimeInterval = 10

    private var previous: (date: Date, processes: [pid_t: Snapshot])?

    /// Returns nil when this call only seeded the deltas (first call, or the
    /// previous snapshot was too old); call again shortly for actual figures.
    func sample() async -> [ProcessUsage]? {
        let now = Date()
        let ownPID = getpid()
        let current = await Task.detached(priority: .utility) {
            runCommand("/bin/ps", ["-Aceo", "pid=,cputime=,rss=,uid=,comm="]).map { Self.parse($0, ownPID: ownPID) }
        }.value
        guard let current, !current.isEmpty else { return nil }

        let last = previous
        previous = (now, current)
        guard let last else { return nil }
        let elapsed = now.timeIntervalSince(last.date)
        guard elapsed > 0, elapsed <= Self.maxInterval else { return nil }

        return Self.usage(
            current: current,
            previous: last.processes,
            elapsed: elapsed,
            coreCount: ProcessInfo.processInfo.activeProcessorCount,
            currentUID: getuid()
        )
    }

    nonisolated static func parse(_ output: String, ownPID: pid_t) -> [pid_t: Snapshot] {
        var result: [pid_t: Snapshot] = [:]
        for line in output.split(separator: "\n") {
            // comm may contain spaces ("Claude Helper (Renderer)"), so it takes the remainder
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5,
                  let pid = pid_t(fields[0]),
                  let cpuSeconds = cpuSeconds(String(fields[1])),
                  let rssKB = UInt64(fields[2]),
                  let uid = uid_t(fields[3]),
                  pid != ownPID
            else { continue }
            result[pid] = Snapshot(name: String(fields[4]), cpuSeconds: cpuSeconds, memoryBytes: rssKB * 1024, uid: uid)
        }
        return result
    }

    /// Parses ps's cputime column: `[days-][hours:]minutes:seconds.centiseconds`.
    nonisolated static func cpuSeconds(_ text: String) -> Double? {
        var rest = Substring(text)
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[..<dash]) else { return nil }
            days = d
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return days * 86400 + seconds
    }

    nonisolated static func usage(
        current: [pid_t: Snapshot],
        previous: [pid_t: Snapshot],
        elapsed: TimeInterval,
        coreCount: Int,
        currentUID: uid_t
    ) -> [ProcessUsage] {
        let capacity = elapsed * Double(coreCount)
        return current.map { pid, now in
            var cpuPercent: Double?
            // A lower CPU time means the pid was recycled by a new process
            if let before = previous[pid], now.cpuSeconds >= before.cpuSeconds {
                cpuPercent = min((now.cpuSeconds - before.cpuSeconds) / capacity * 100, 100)
            }
            return ProcessUsage(
                pid: pid,
                name: now.name,
                cpuPercent: cpuPercent,
                memoryBytes: now.memoryBytes,
                isOwnedByUser: now.uid == currentUID
            )
        }
    }

    /// Asks the process to quit: apps get a regular Quit (so they can save), others SIGTERM.
    nonisolated static func terminate(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        } else {
            kill(pid, SIGTERM)
        }
    }
}

/// Runs a command synchronously and returns its stdout, or nil on failure.
func runCommand(_ path: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}
