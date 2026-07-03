import Foundation
import Combine

struct QuotaSnapshot {
    var fiveHourUtilization: Double?
    var fiveHourResetsAt: Date?
    var sevenDayUtilization: Double?
    var sevenDayResetsAt: Date?
    var fetchedAt: Date
}

@MainActor
final class QuotaTracker: ObservableObject {

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?
        }
        let fiveHour: Window?
        let sevenDay: Window?
    }

    private struct KeychainCredentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth
    }

    private nonisolated static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private nonisolated static let keychainService = "Claude Code-credentials"
    private nonisolated static let staleAfter: TimeInterval = 600
    private nonisolated static let minFetchInterval: TimeInterval = 30

    @Published private(set) var lastSnapshot: QuotaSnapshot?
    @Published private(set) var isFetching = false
    private var lastFetchAttempt: Date?

    /// Called on the main actor after every refresh attempt, success or failure.
    var onRefreshCompleted: (() -> Void)?

    init(initialSnapshot: QuotaSnapshot? = nil) {
        lastSnapshot = initialSnapshot
    }

    var isStale: Bool {
        guard let snapshot = lastSnapshot else { return true }
        return Date().timeIntervalSince(snapshot.fetchedAt) > Self.staleAfter
    }

    nonisolated static func isClaudeCodeInstalled() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude").path
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Public

    func refresh(force: Bool = false) {
        if isFetching { return }
        if !force, let last = lastFetchAttempt,
           Date().timeIntervalSince(last) < Self.minFetchInterval { return }

        isFetching = true
        lastFetchAttempt = Date()

        Task { [weak self] in
            let snapshot = await Self.fetchSnapshot()
            guard let self else { return }
            if let snapshot { self.lastSnapshot = snapshot }
            self.isFetching = false
            self.onRefreshCompleted?()
        }
    }

    // MARK: - Private

    private nonisolated static func fetchSnapshot() async -> QuotaSnapshot? {
        // The keychain read spawns a blocking subprocess (and may show a consent
        // dialog) — keep it off the cooperative thread pool's fast paths.
        let token = await Task.detached(priority: .utility) { readAccessToken() }.value
        guard let token else { return nil }

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let usage = try decoder.decode(UsageResponse.self, from: data)

            return QuotaSnapshot(
                fiveHourUtilization: usage.fiveHour?.utilization,
                fiveHourResetsAt: parseDate(usage.fiveHour?.resetsAt),
                sevenDayUtilization: usage.sevenDay?.utilization,
                sevenDayResetsAt: parseDate(usage.sevenDay?.resetsAt),
                fetchedAt: Date()
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func readAccessToken() -> String? {
        var payload = readKeychainPayload()
        if payload == nil {
            let fallback = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/.credentials.json")
            payload = try? Data(contentsOf: fallback)
        }
        guard let payload,
              let credentials = try? JSONDecoder().decode(KeychainCredentials.self, from: payload)
        else { return nil }

        if let expiresAt = credentials.claudeAiOauth.expiresAt,
           expiresAt / 1000 < Date().timeIntervalSince1970 {
            return nil
        }
        return credentials.claudeAiOauth.accessToken
    }

    private nonisolated static func readKeychainPayload() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
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

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty
        else { return nil }
        return Data(output.utf8)
    }

    private nonisolated static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
