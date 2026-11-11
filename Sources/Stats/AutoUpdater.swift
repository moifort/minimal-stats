import AppKit
import os

final class AutoUpdater {

    struct Release {
        let version: String
        let downloadURL: URL
        let body: String
    }

    struct UpdateInfo {
        let latestRelease: Release
        let changelog: String
    }

    enum UpdateError: LocalizedError, Equatable {
        case extractionFailed
        case appBundleNotFound
        case badResponse(Int)
        case untrustedURL
        case wrongBundleIdentifier
        case notNewer

        var errorDescription: String? {
            switch self {
            case .extractionFailed: return String(localized: "The downloaded archive could not be extracted.")
            case .appBundleNotFound: return String(localized: "No app bundle was found in the downloaded archive.")
            case .badResponse(let status): return String(localized: "The server answered with HTTP status \(status).")
            case .untrustedURL: return String(localized: "The download did not come from GitHub over HTTPS.")
            case .wrongBundleIdentifier: return String(localized: "The downloaded app is not Stats.")
            case .notNewer: return String(localized: "The downloaded app is not newer than the installed one.")
            }
        }
    }

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "AutoUpdater")

    private let repo = "moifort/minimal-stats"
    private var timer: Timer?
    /// Main thread only. Set while an update downloads and installs, so a second
    /// click on Update cannot start another one.
    private var isUpdating = false
    var onUpdateAvailable: ((UpdateInfo) -> Void)?

    // MARK: - Public

    func startPeriodicChecks() {
        checkForUpdates()
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func checkForUpdates() {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard let data, error == nil else {
                Self.log.error("Update check failed: \(error?.localizedDescription ?? "no data")")
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                Self.log.error("Update check failed: HTTP status \(status)")
                return
            }
            guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                Self.log.error("Update check failed: unexpected response payload")
                return
            }

            let newer = Self.newerReleases(Self.parseReleases(releases), than: Self.currentVersion)

            guard let latest = newer.last else { return }

            let changelog = newer.map { "## v\($0.version)\n\n\($0.body)" }.joined(separator: "\n\n---\n\n")
            let info = UpdateInfo(latestRelease: latest, changelog: changelog)

            DispatchQueue.main.async {
                self.onUpdateAvailable?(info)
            }
        }.resume()
    }

    func performUpdate(release: Release) {
        guard !isUpdating else { return }
        isUpdating = true

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipPath = tempDir.appendingPathComponent("Stats.app.zip")

        guard Self.isTrustedDownloadURL(release.downloadURL) else {
            reportFailure(UpdateError.untrustedURL)
            return
        }

        URLSession.shared.downloadTask(with: release.downloadURL) { [weak self] localURL, response, error in
            guard let self else { return }
            guard let localURL, error == nil else {
                self.reportFailure(error ?? URLError(.unknown))
                return
            }

            do {
                // GitHub redirects to its asset storage: check where the bytes really came from
                guard let finalURL = response?.url, Self.isTrustedDownloadURL(finalURL) else {
                    throw UpdateError.untrustedURL
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw UpdateError.badResponse(status) }

                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: localURL, to: zipPath)

                let extractDir = tempDir.appendingPathComponent("extracted")
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", zipPath.path, extractDir.path]
                try ditto.run()
                ditto.waitUntilExit()

                guard ditto.terminationStatus == 0 else { throw UpdateError.extractionFailed }

                let extracted = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
                guard let newApp = extracted.first(where: { $0.pathExtension == "app" }) else {
                    throw UpdateError.appBundleNotFound
                }
                let newInfo = Bundle(url: newApp)?.infoDictionary ?? [:]
                try Self.validate(
                    newBundleInfo: newInfo,
                    bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
                    currentVersion: Self.currentVersion
                )

                let currentApp = Bundle.main.bundleURL
                let backupPath = currentApp.deletingLastPathComponent().appendingPathComponent("Stats.app.bak")

                try? FileManager.default.removeItem(at: backupPath)
                try FileManager.default.moveItem(at: currentApp, to: backupPath)
                do {
                    try FileManager.default.moveItem(at: newApp, to: currentApp)
                } catch {
                    // Roll back so the user still has a working app
                    try? FileManager.default.moveItem(at: backupPath, to: currentApp)
                    throw error
                }
                try? FileManager.default.removeItem(at: backupPath)
                try? FileManager.default.removeItem(at: tempDir)

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/sh")
                proc.arguments = Self.relaunchArguments(pid: getpid(), appPath: currentApp.path)
                try proc.run()

                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                self.reportFailure(error)
            }
        }.resume()
    }

    // MARK: - Private

    private func reportFailure(_ error: Error) {
        Self.log.error("Update failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isUpdating = false
            let alert = NSAlert()
            alert.messageText = String(localized: "Update Failed")
            alert.informativeText = String(localized: "The update could not be installed: \(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Published releases with a zip asset. A missing or null body reads as empty.
    static func parseReleases(_ releases: [[String: Any]]) -> [Release] {
        releases.compactMap { dict -> Release? in
            guard (dict["prerelease"] as? Bool) != true,
                  (dict["draft"] as? Bool) != true,
                  let tagName = dict["tag_name"] as? String,
                  let assets = dict["assets"] as? [[String: Any]],
                  let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let downloadURLStr = zipAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLStr),
                  isTrustedDownloadURL(downloadURL)
            else { return nil }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            guard versionComponents(version) != nil else { return nil }
            return Release(version: version, downloadURL: downloadURL, body: dict["body"] as? String ?? "")
        }
    }

    /// Releases newer than `current`, oldest first.
    static func newerReleases(_ releases: [Release], than current: String) -> [Release] {
        releases
            .filter { isVersion($0.version, newerThan: current) }
            .sorted { compareVersions($0.version, $1.version) == .orderedAscending }
    }

    /// HTTPS on github.com or GitHub's asset storage hosts.
    static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    /// The extracted bundle must be Stats, and strictly newer than what runs now.
    /// A copy still running as `com.stats.menubar` accepts `com.polyforms.stats`
    /// (`AppIdentity.acceptsUpdate`).
    static func validate(newBundleInfo info: [String: Any], bundleIdentifier: String, currentVersion: String) throws {
        guard let downloaded = info["CFBundleIdentifier"] as? String,
              AppIdentity.acceptsUpdate(from: bundleIdentifier, to: downloaded)
        else {
            throw UpdateError.wrongBundleIdentifier
        }
        guard let version = info["CFBundleShortVersionString"] as? String,
              isVersion(version, newerThan: currentVersion)
        else { throw UpdateError.notNewer }
    }

    /// `sh` arguments that wait for `pid` to exit (10 s at most), then open the app.
    /// The pid and path are positional parameters, never interpolated into the script,
    /// so quotes, `$` or backticks in the path are harmless. Opening while the old
    /// instance still runs would only reactivate it.
    static func relaunchArguments(pid: pid_t, appPath: String, opener: String = "/usr/bin/open") -> [String] {
        let script = #"i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; exec "$3" "$2""#
        return ["-c", script, "sh", String(pid), appPath, opener]
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        compareVersions(a, b) == .orderedDescending
    }

    /// Compares dotted numeric versions, missing components counting as 0
    /// (`1.2` == `1.2.0`). Nil when either version is not purely numeric.
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult? {
        guard let ac = versionComponents(a), let bc = versionComponents(b) else { return nil }
        for i in 0..<max(ac.count, bc.count) {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// `1.11.0` → [1, 11, 0]; nil if any component is not a number (`1.x.3`, `1.2-beta`).
    static func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        return components
    }
}
