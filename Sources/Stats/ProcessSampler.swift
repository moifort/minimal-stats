import AppKit
import Darwin

struct ProcessUsage: Identifiable {
    let pid: pid_t
    let name: String
    /// Share of the whole machine's CPU, 0–100 (not per-core like Activity Monitor)
    let cpuPercent: Double
    let memoryBytes: UInt64
    let isOwnedByUser: Bool

    var id: pid_t { pid }
}

/// Lists running processes through `/bin/ps`, which is setuid root and therefore
/// sees system processes (WindowServer, mds_stores…) that libproc hides from us.
enum ProcessSampler {

    static func sample() async -> [ProcessUsage] {
        await Task.detached(priority: .utility) {
            guard let output = runCommand("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,uid=,comm="]) else { return [] }
            return parse(output)
        }.value
    }

    static func parse(_ output: String) -> [ProcessUsage] {
        let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)
        let currentUID = getuid()
        let ownPID = getpid()

        return output.split(separator: "\n").compactMap { line in
            // comm may contain spaces ("Claude Helper (Renderer)"), so it takes the remainder
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5,
                  let pid = pid_t(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = UInt64(fields[2]),
                  let uid = uid_t(fields[3]),
                  pid != ownPID
            else { return nil }
            return ProcessUsage(
                pid: pid,
                name: String(fields[4]),
                cpuPercent: cpu / coreCount,
                memoryBytes: rssKB * 1024,
                isOwnedByUser: uid == currentUID
            )
        }
    }

    /// Asks the process to quit: apps get a regular Quit (so they can save), others SIGTERM.
    static func terminate(pid: pid_t) {
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
