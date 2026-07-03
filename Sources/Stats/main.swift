import AppKit

// Top-level code in main.swift is not implicitly main-actor-isolated,
// but it does run on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
