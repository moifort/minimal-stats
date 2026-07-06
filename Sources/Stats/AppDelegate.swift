import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let stats = SystemStats()
    private let statusBarModel = StatusBarModel()
    private var timer: Timer?
    private var quotaTimer: Timer?

    private var autoUpdater: AutoUpdater?
    private var quotaTracker: QuotaTracker?
    private var updateInfo: AutoUpdater.UpdateInfo?
    private var panel: NSPanel?
    private var updatePanel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: – Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let claudeExists = QuotaTracker.isClaudeCodeInstalled()
        if claudeExists {
            statusBarModel.claudeQuota = .stale
        }

        let view = NSHostingView(rootView: StatusBarView(model: statusBarModel))
        let barWidth = view.fittingSize.width
        view.frame = NSRect(x: 0, y: 0, width: barWidth, height: 22)

        statusItem = NSStatusBar.system.statusItem(withLength: barWidth)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(view)
            button.frame.size = view.frame.size
        }

        // Register as login item
        try? SMAppService.mainApp.register()

        // Seed the delta-based CPU/network metrics with an initial reading
        stats.refresh()

        // .common mode keeps the charts ticking during event tracking
        let statsTimer = Timer(
            timeInterval: ChartMetrics.refreshInterval,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(statsTimer, forMode: .common)
        timer = statsTimer

        if claudeExists {
            let tracker = QuotaTracker()
            tracker.onRefreshCompleted = { [weak self] in
                self?.applyQuota()
            }
            quotaTracker = tracker

            let qTimer = Timer(
                timeInterval: 120.0,
                target: self,
                selector: #selector(refreshQuota),
                userInfo: nil,
                repeats: true
            )
            qTimer.tolerance = 10
            RunLoop.main.add(qTimer, forMode: .common)
            quotaTimer = qTimer
            tracker.refresh()
        }

        let updater = AutoUpdater()
        updater.onUpdateAvailable = { [weak self] info in
            self?.updateInfo = info
        }
        updater.startPeriodicChecks()
        autoUpdater = updater
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: – Panel

    @objc private func togglePopover() {
        if panel != nil {
            closePanel()
            return
        }

        quotaTracker?.refresh(force: true)

        let contentView = PopoverView(
            updateAvailable: updateInfo?.latestRelease,
            quotaTracker: quotaTracker,
            onUpdate: { [weak self] in
                guard let self, let info = self.updateInfo else { return }
                self.closePanel()
                self.showUpdatePanel(info: info)
            },
            onOpenActivityMonitor: { [weak self] in
                self?.closePanel()
                self?.openActivityMonitor()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            },
            onUninstall: { [weak self] in
                self?.closePanel()
                self?.performUninstall()
            }
        )

        let controller = NSHostingController(rootView: contentView)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = .clear
        let contentSize = controller.view.fittingSize

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true

        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.maskImage = .roundedRect(size: contentSize, radius: 10)

        controller.view.frame = visualEffect.bounds
        controller.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(controller.view)
        p.contentView = visualEffect

        // Position flush below the status bar button, right-aligned
        if let button = statusItem.button,
           let buttonWindow = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(rectInWindow)
            let x = screenRect.maxX - contentSize.width
            let y = screenRect.minY - contentSize.height
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.makeKeyAndOrderFront(nil)
        panel = p

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self = self, event.window != self.panel,
               event.window != self.statusItem.button?.window {
                self.closePanel()
            }
            return event
        }
    }

    private func closePanel() {
        panel?.close()
        panel = nil
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func performUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Stats?"
        alert.informativeText = "This will remove the login item and move the app to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? SMAppService.mainApp.unregister()

        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([appURL]) { _, _ in
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: – Auto Update Panel

    private func showUpdatePanel(info: AutoUpdater.UpdateInfo) {
        updatePanel?.close()

        let contentView = UpdateView(
            version: info.latestRelease.version,
            changelog: info.changelog,
            onInstall: { [weak self] in
                self?.updatePanel?.close()
                self?.updatePanel = nil
                self?.autoUpdater?.performUpdate(release: info.latestRelease)
            },
            onLater: { [weak self] in
                self?.updatePanel?.close()
                self?.updatePanel = nil
            }
        )

        let size = NSSize(width: 400, height: 350)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.title = "Update to v\(info.latestRelease.version)"
        p.isFloatingPanel = true
        p.level = .floating
        p.contentView = NSHostingView(rootView: contentView)

        p.center()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        updatePanel = p
    }

    // MARK: – Refresh

    @objc private func tick() {
        stats.refresh()
        statusBarModel.cpuHistory = stats.cpuHistory
        if stats.diskTotal > 0 {
            statusBarModel.diskUsedFraction = Double(stats.diskUsed) / Double(stats.diskTotal)
        }
        statusBarModel.netInHistory = stats.netInHistory
        statusBarModel.netOutHistory = stats.netOutHistory
        // Re-evaluate the Claude light every tick so it flips to green the moment
        // the reset time is crossed, without waiting for the next quota fetch.
        if quotaTracker != nil {
            applyQuota()
        }
    }

    @objc private func refreshQuota() {
        quotaTracker?.refresh()
    }

    private func applyQuota() {
        guard let tracker = quotaTracker else { return }
        // Keep showing the last known level even when the snapshot goes stale:
        // usage only changes at the reset boundary, so a stale value is still
        // accurate until then. We only dim to `.stale` when we have no snapshot
        // at all (nothing fetched yet).
        guard let snapshot = tracker.lastSnapshot,
              let utilization = snapshot.fiveHourUtilization else {
            statusBarModel.claudeQuota = .stale
            return
        }
        // Once the five-hour window's reset time has passed, usage is back to
        // zero — turn the light green right away instead of waiting for the
        // next fetch to confirm it.
        if let resetsAt = snapshot.fiveHourResetsAt, Date() >= resetsAt {
            statusBarModel.claudeQuota = .level(0)
            return
        }
        statusBarModel.claudeQuota = .level(utilization)
    }
}
