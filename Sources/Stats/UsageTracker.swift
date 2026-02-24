import Foundation

enum PlanType: String, CaseIterable {
    case pro = "Pro"
    case max5x = "Max 5x"
    case max20x = "Max 20x"

    var outputTokenLimit: Int {
        switch self {
        case .pro: return 28_000
        case .max5x: return 142_000
        case .max20x: return 565_000
        }
    }
}

struct UsageSnapshot {
    var outputTokens: Int = 0
    var inputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var fraction: Double = 0
    var windowStart: Date = Date()
    var planType: PlanType = .max20x
    var nextReset: Date = Date()
}

final class UsageTracker {
    private let windowDuration: TimeInterval = 5 * 3600 // 5 hours
    // Known reset: 2026-02-24T18:00:00Z (19h Paris)
    private static let referenceReset: TimeInterval = 1_771_956_000
    private let projectsDir: URL

    var planType: PlanType = .max20x

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        projectsDir = home.appendingPathComponent(".claude/projects")
    }

    func refresh() -> UsageSnapshot {
        let now = Date().timeIntervalSince1970
        let elapsed = now - Self.referenceReset
        let windowIndex = floor(elapsed / windowDuration)
        let windowStart = Date(timeIntervalSince1970: Self.referenceReset + windowIndex * windowDuration)
        let nextReset = windowStart.addingTimeInterval(windowDuration)
        var snapshot = UsageSnapshot(windowStart: windowStart, planType: planType, nextReset: nextReset)

        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDir.path) else { return snapshot }

        let jsonlFiles = findJSONLFiles(in: projectsDir, modifiedAfter: windowStart)

        for fileURL in jsonlFiles {
            parseFile(fileURL, windowStart: windowStart, snapshot: &snapshot)
        }

        let limit = Double(planType.outputTokenLimit)
        snapshot.fraction = limit > 0 ? min(Double(snapshot.outputTokens) / limit, 1.0) : 0

        return snapshot
    }

    private func findJSONLFiles(in directory: URL, modifiedAfter cutoff: Date) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate,
                  modDate >= cutoff
            else { continue }

            results.append(fileURL)
        }

        return results
    }

    private func parseFile(_ fileURL: URL, windowStart: Date, snapshot: inout UsageSnapshot) {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8)
        else { return }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Each API call produces multiple JSONL "assistant" entries (one per content
        // block: thinking, text, tool_use…), each carrying the cumulative usage for the
        // whole message.  We must only count the *last* assistant entry in each
        // consecutive run so we don't multiply the real usage by the number of blocks.
        var pendingOutput = 0
        var pendingInput = 0
        var pendingCacheCreation = 0
        var pendingCacheRead = 0
        var hasPending = false

        func flushPending() {
            guard hasPending else { return }
            snapshot.outputTokens += pendingOutput
            snapshot.inputTokens += pendingInput
            snapshot.cacheCreationTokens += pendingCacheCreation
            snapshot.cacheReadTokens += pendingCacheRead
            hasPending = false
        }

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }

            if type != "assistant" {
                flushPending()
                continue
            }

            guard let timestampStr = json["timestamp"] as? String,
                  let timestamp = dateFormatter.date(from: timestampStr),
                  timestamp >= windowStart,
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            // Overwrite (not accumulate) — the last entry wins
            pendingOutput = usage["output_tokens"] as? Int ?? 0
            pendingInput = usage["input_tokens"] as? Int ?? 0
            pendingCacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            pendingCacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            hasPending = true
        }

        flushPending()
    }
}
