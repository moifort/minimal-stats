import Foundation

/// The identifier Stats ships under, and the ones it used to. The one place
/// they are written: everything else derives from here.
///
/// The identifier names the defaults domain and the login item. Nothing is
/// brought over from `com.stats.menubar` on purpose: its one setting,
/// `didRegisterLoginItem`, says the login item of the old identifier was
/// registered, and copying it would keep the new one from ever registering.
/// So the first launch under `com.polyforms.stats` is a first launch: it
/// registers the login item once (or only remembers it, when macOS already
/// reports it enabled).
enum AppIdentity {
    /// Both builds, Developer ID (GitHub, Homebrew) and Mac App Store, under
    /// the Polyforms name, like Dictate's App Store build.
    static let bundleIdentifier = "com.polyforms.stats"
    /// What Stats was called up to 1.11: an installed copy still runs as this
    /// until its first update.
    static let legacyBundleIdentifiers = ["com.stats.menubar"]
    /// Every identifier a release of Stats has carried.
    static let releases = [bundleIdentifier] + legacyBundleIdentifiers

    /// The running copy's: the test host has none of its own.
    static var current: String { Bundle.main.bundleIdentifier ?? bundleIdentifier }

    /// The `Logger` subsystem, so `log stream --predicate 'subsystem == "com.polyforms.stats"'`
    /// finds every message of the app.
    static let logSubsystem = bundleIdentifier

    /// An update may move a copy from any release identifier to the current
    /// one, never to another app's, and never back to a legacy identifier.
    static func acceptsUpdate(from running: String, to downloaded: String) -> Bool {
        guard !running.isEmpty else { return false }
        if downloaded == running { return true }
        return releases.contains(running) && downloaded == bundleIdentifier
    }
}
