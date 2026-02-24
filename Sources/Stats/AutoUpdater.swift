import AppKit

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
            guard let self, let data, error == nil else { return }
            guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

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

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        URLSession.shared.downloadTask(with: release.downloadURL) { localURL, _, error in
            guard let localURL, error == nil else { return }

            do {
                try FileManager.default.moveItem(at: localURL, to: zipPath)

                let extractDir = tempDir.appendingPathComponent("extracted")
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", zipPath.path, extractDir.path]
                try ditto.run()
                ditto.waitUntilExit()

                guard ditto.terminationStatus == 0 else { return }

                let newApp = extractDir.appendingPathComponent("Stats.app")
                let currentApp = Bundle.main.bundleURL
                let backupPath = currentApp.deletingLastPathComponent().appendingPathComponent("Stats.app.bak")

                try? FileManager.default.removeItem(at: backupPath)
                try FileManager.default.moveItem(at: currentApp, to: backupPath)
                try FileManager.default.moveItem(at: newApp, to: currentApp)
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
            }
        }.resume()
    }

    // MARK: - Private

    private func parseReleases(_ releases: [[String: Any]]) -> [Release] {
        releases.compactMap { dict -> Release? in
            guard let tagName = dict["tag_name"] as? String,
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
