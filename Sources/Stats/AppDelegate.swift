import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let stats = SystemStats()
    private let statusBarModel = StatusBarModel()
    private var timer: Timer?
    private var networkProcessTimer: Timer?
    private let networkProcessSampler = NetworkProcessSampler()
    private let diskProcessSampler = DiskProcessSampler()
    private let processSampler = ProcessSampler()
    private var simulatorNameCache: [pid_t: String] = [:]
    private var isSamplingProcesses = false

    private var autoUpdater: AutoUpdater?
    private var updateInfo: AutoUpdater.UpdateInfo?
    private var panel: NSPanel?
    private var updatePanel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var popoverHotKey: GlobalHotKey?
    /// Held only while the popover is open
    private var escapeHotKey: GlobalHotKey?

    // MARK: – Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarModel.memoryTotal = stats.memoryTotal
        // Seed the delta-based CPU/network metrics with an initial reading
        stats.refresh()
        applyStats()

        let view = ClickThroughHostingView(rootView: StatusBarView(model: statusBarModel))
        let barWidth = view.fittingSize.width
        view.frame = NSRect(x: 0, y: 0, width: barWidth, height: 22)

        statusItem = NSStatusBar.system.statusItem(withLength: barWidth)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(view)
            button.frame.size = view.frame.size
            // VoiceOver reads the button, not the charts drawn inside it
            button.setAccessibilityLabel("Stats")
            button.setAccessibilityValue(statusBarModel.accessibilitySummary)
        }

        if Distribution.registersLoginItemAtFirstLaunch {
            registerLoginItemOnFirstLaunch()
        }

        // Unavailable when another app already owns the shortcut; clicks still work
        popoverHotKey = GlobalHotKey(GlobalHotKey.togglePopover) { [weak self] in
            self?.togglePopover()
        }

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

        // Per-process network and disk bytes are sampled continuously so the popover
        // can show who used them over the whole window, not just since opening.
        networkProcessSampler.onUpdate = { [weak self] usage in
            self?.statusBarModel.networkProcesses = usage
        }
        diskProcessSampler.onUpdate = { [weak self] usage in
            self?.statusBarModel.diskProcesses = usage
        }
        let netTimer = Timer(
            timeInterval: NetworkProcessSampler.sampleInterval,
            target: self,
            selector: #selector(refreshByteCounters),
            userInfo: nil,
            repeats: true
        )
        netTimer.tolerance = 1
        RunLoop.main.add(netTimer, forMode: .common)
        networkProcessTimer = netTimer
        refreshByteCounters()

        if Distribution.hasUpdater {
            let updater = AutoUpdater()
            updater.onUpdateAvailable = { [weak self] info in
                self?.updateInfo = info
            }
            updater.startPeriodicChecks()
            autoUpdater = updater
        }
    }

    // MARK: – Login item

    private static let loginItemRegisteredKey = "didRegisterLoginItem"

    /// Opens at login from the first launch on, but only once: an item the user
    /// later removes from System Settings (status back to notRegistered) stays removed.
    private func registerLoginItemOnFirstLaunch() {
        let defaults = UserDefaults.standard
        let service = SMAppService.mainApp
        switch Self.loginItemAction(status: service.status, registeredBefore: defaults.bool(forKey: Self.loginItemRegisteredKey)) {
        case .none:
            break
        case .markRegistered:
            defaults.set(true, forKey: Self.loginItemRegisteredKey)
        case .register:
            // A failure (unsigned build, app outside /Applications…) is retried next launch
            if (try? service.register()) != nil {
                defaults.set(true, forKey: Self.loginItemRegisteredKey)
            }
        }
    }

    enum LoginItemAction: Equatable {
        case none, markRegistered, register
    }

    /// Already enabled, or disabled by the user (requiresApproval): only remember it,
    /// which also covers installs registered by versions without the flag.
    nonisolated static func loginItemAction(status: SMAppService.Status, registeredBefore: Bool) -> LoginItemAction {
        if registeredBefore { return .none }
        switch status {
        case .enabled, .requiresApproval: return .markRegistered
        case .notRegistered, .notFound: return .register
        @unknown default: return .none
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: – Status item menu

    /// Left click opens the popover; right click (or control-click) opens a menu
    /// that only holds the rarely used actions.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        closePanel()
        let menu = NSMenu()
        if Distribution.offersOpenAtLogin {
            let openAtLogin = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
            openAtLogin.target = self
            openAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(openAtLogin)
        }
        if Distribution.hasUninstaller {
            let uninstall = NSMenuItem(title: "Uninstall\u{2026}", action: #selector(uninstallFromMenu), keyEquivalent: "")
            uninstall.target = self
            menu.addItem(uninstall)
        }
        let quit = NSMenuItem(title: "Quit Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        // A menu set on the item opens at the standard place under it; removing it
        // afterwards keeps the left click on the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func uninstallFromMenu() {
        performUninstall()
    }

    /// The App Store build opens at login only once the user asks (guideline 2.4.5).
    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Open at Login Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: – Panel

    @objc private func togglePopover() {
        if panel != nil {
            closePanel()
            return
        }

        refreshProcesses()

        let contentView = PopoverView(
            model: statusBarModel,
            updateAvailable: updateInfo?.latestRelease,
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
            onQuitProcess: { [weak self] pid, name in
                self?.closePanel()
                self?.confirmQuitProcess(pid: pid, name: name)
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

        // The panel never becomes key (a key window would tint the selected tab
        // with the accent colour), so Escape is taken as a hot key while it is open.
        escapeHotKey = GlobalHotKey(GlobalHotKey.escape) { [weak self] in
            self?.closePanel()
        }

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
        escapeHotKey = nil
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func confirmQuitProcess(pid: pid_t, name: String) {
        let alert = NSAlert()
        alert.messageText = "Quit \(name)?"
        alert.informativeText = "Unsaved changes in this process may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ProcessSampler.terminate(pid: pid)
    }

    private func performUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Stats?"
        alert.informativeText = "This will remove the login item and move the app to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        // An LSUIElement app is not active: without this the alert can open behind other windows
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let wasLoginItem = SMAppService.mainApp.status == .enabled
        try? SMAppService.mainApp.unregister()

        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([appURL]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let error else {
                    // A reinstall should open at login again
                    UserDefaults.standard.removeObject(forKey: Self.loginItemRegisteredKey)
                    NSApplication.shared.terminate(nil)
                    return
                }
                // The app is still installed: keep it running, and opening at login if it did
                if wasLoginItem {
                    try? SMAppService.mainApp.register()
                }
                self?.showUninstallFailure(error)
            }
        }
    }

    private func showUninstallFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Uninstall Failed"
        alert.informativeText = "Stats could not be moved to the Trash: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
        applyStats()

        // The process list is only needed while the popover is visible
        if panel != nil {
            refreshProcesses()
        }
    }

    private func applyStats() {
        statusBarModel.cpuHistory = stats.cpuHistory
        statusBarModel.netInHistory = stats.netInHistory
        statusBarModel.netOutHistory = stats.netOutHistory
        statusBarModel.diskFree = stats.diskFree
        statusBarModel.diskTotal = stats.diskTotal
        statusBarModel.memoryUsed = stats.memoryUsed
        statusItem?.button?.setAccessibilityValue(statusBarModel.accessibilitySummary)
    }

    private func refreshProcesses() {
        guard !isSamplingProcesses else { return }
        isSamplingProcesses = true
        Task { [weak self] in
            let processes = await self?.processSampler.sample()
            guard let self else { return }
            if let processes {
                let names = await self.simulatorNames(in: processes)
                self.isSamplingProcesses = false
                self.statusBarModel.processGroups = ProcessGroup.make(from: processes, names: names)
                return
            }
            self.isSamplingProcesses = false
            if self.panel != nil {
                // Only the interval was seeded: take a second sample soon rather
                // than leaving the list empty until the next regular tick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.panel != nil else { return }
                    self.refreshProcesses()
                }
            }
        }
    }

    /// Device names of running simulators, looked up once per launchd_sim pid.
    /// The lookup reads files and process arguments, so it happens off the main thread.
    private func simulatorNames(in processes: [ProcessUsage]) async -> [pid_t: String] {
        let simulators = Set(processes.filter { $0.name == ProcessGroup.simulatorRootName }.map(\.pid))
        let unknown = simulators.filter { simulatorNameCache[$0] == nil }
        if !unknown.isEmpty {
            let found = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: unknown.map { pid in
                    (pid, ProcessGroup.simulatorName(pid: pid).map { "Simulator · \($0)" } ?? "Simulator")
                })
            }.value
            simulatorNameCache.merge(found) { _, new in new }
        }
        simulatorNameCache = simulatorNameCache.filter { simulators.contains($0.key) }
        return simulatorNameCache
    }

    @objc private func refreshByteCounters() {
        networkProcessSampler.refresh()
        diskProcessSampler.refresh()
    }
}

/// The widgets drawn inside the status item button. Clicks go straight to the
/// button, so it sees left and right clicks alike, and so does accessibility.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { nil }
}

