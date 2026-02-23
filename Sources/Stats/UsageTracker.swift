import Foundation

enum PlanType: String, CaseIterable {
    case pro = "Pro"
    case max5x = "Max 5x"
    case max20x = "Max 20x"

    var outputTokenLimit: Int {
        switch self {
        case .pro: return 19_000
        case .max5x: return 88_000
        case .max20x: return 220_000
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
    var oldestMessageInWindow: Date?
}

final class UsageTracker {
    private let windowDuration: TimeInterval = 5 * 3600 // 5 hours
    private let projectsDir: URL

    var planType: PlanType = .max20x

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        projectsDir = home.appendingPathComponent(".claude/projects")
    }

    func refresh() -> UsageSnapshot {
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowDuration)
        var snapshot = UsageSnapshot(windowStart: windowStart, planType: planType)

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

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let timestampStr = json["timestamp"] as? String,
                  let timestamp = dateFormatter.date(from: timestampStr),
                  timestamp >= windowStart,
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let output = usage["output_tokens"] as? Int ?? 0
            let input = usage["input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

            snapshot.outputTokens += output
            snapshot.inputTokens += input
            snapshot.cacheCreationTokens += cacheCreation
            snapshot.cacheReadTokens += cacheRead

            if snapshot.oldestMessageInWindow == nil || timestamp < snapshot.oldestMessageInWindow! {
                snapshot.oldestMessageInWindow = timestamp
            }
        }
    }
}
