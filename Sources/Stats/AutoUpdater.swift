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

    enum UpdateError: LocalizedError {
        case extractionFailed
        case appBundleNotFound

        var errorDescription: String? {
            switch self {
            case .extractionFailed: return "The downloaded archive could not be extracted."
            case .appBundleNotFound: return "No app bundle was found in the downloaded archive."
            }
        }
    }

    private static let log = Logger(subsystem: "com.stats.menubar", category: "AutoUpdater")

    private let repo = "moifort/minimal-stats"
    private var timer: Timer?
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

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, error == nil else {
                Self.log.error("Update check failed: \(error?.localizedDescription ?? "no data")")
                return
            }
            guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                Self.log.error("Update check failed: unexpected response payload")
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let parsed = self.parseReleases(releases)
            let newer = parsed
                .filter { Self.isVersion($0.version, newerThan: currentVersion) }
                .sorted { Self.versionComponents($0.version).lexicographicallyPrecedes(Self.versionComponents($1.version)) }

            guard let latest = newer.last else { return }

            let changelog = newer.map { "## v\($0.version)\n\n\($0.body)" }.joined(separator: "\n\n---\n\n")
            let info = UpdateInfo(latestRelease: latest, changelog: changelog)

            DispatchQueue.main.async {
                self.onUpdateAvailable?(info)
            }
        }.resume()
    }

    func performUpdate(release: Release) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipPath = tempDir.appendingPathComponent("Stats.app.zip")

        URLSession.shared.downloadTask(with: release.downloadURL) { [weak self] localURL, _, error in
            guard let self else { return }
            guard let localURL, error == nil else {
                self.reportFailure(error ?? URLError(.unknown))
                return
            }

            do {
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

                let appPath = currentApp.path
                let script = "sleep 1 && open \"\(appPath)\""
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/sh")
                proc.arguments = ["-c", script]
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
            let alert = NSAlert()
            alert.messageText = "Update Failed"
            alert.informativeText = "The update could not be installed: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func parseReleases(_ releases: [[String: Any]]) -> [Release] {
        releases.compactMap { dict -> Release? in
            guard (dict["prerelease"] as? Bool) != true,
                  (dict["draft"] as? Bool) != true,
                  let tagName = dict["tag_name"] as? String,
                  let body = dict["body"] as? String,
                  let assets = dict["assets"] as? [[String: Any]],
                  let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let downloadURLStr = zipAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLStr)
            else { return nil }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            return Release(version: version, downloadURL: downloadURL, body: body)
        }
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let ac = versionComponents(a)
        let bc = versionComponents(b)
        let count = max(ac.count, bc.count)
        for i in 0..<count {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }

    static func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}
