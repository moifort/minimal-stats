import AppKit
import SwiftUI
import Charts
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let stats = SystemStats()
    private var timer: Timer?

    private var hostingView: NSHostingView<StatusBarView>?
    private var statusBarView = StatusBarView(cpuHistory: [], diskUsedFraction: 0, netInHistory: [], netOutHistory: [])

    private var autoUpdater: AutoUpdater?
    private var updateInfo: AutoUpdater.UpdateInfo?
    private var panel: NSPanel?
    private var updatePanel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: – Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let barWidth: CGFloat = 113

        statusItem = NSStatusBar.system.statusItem(withLength: barWidth)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            let view = NSHostingView(rootView: statusBarView)
            view.frame = NSRect(x: 0, y: 0, width: barWidth, height: 22)
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(view)
            button.frame.size = view.frame.size
            hostingView = view
        }

        // Register as login item
        try? SMAppService.mainApp.register()

        // Seed the delta-based CPU metric with an initial reading
        _ = stats.refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.tick()
        }

        let updater = AutoUpdater()
        updater.onUpdateAvailable = { [weak self] info in
            self?.updateInfo = info
        }
        updater.startPeriodicChecks()
        autoUpdater = updater
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: – Panel

    @objc private func togglePopover() {
        if panel != nil {
            closePanel()
            return
        }

        let contentView = PopoverView(
            updateAvailable: updateInfo?.latestRelease,
            onUpdate: { [weak self] in
                guard let self, let info = self.updateInfo else { return }
                self.closePanel()
                self.showUpdatePanel(info: info)
            },
            onOpenActivityMonitor: { [weak self] in
                self?.closePanel()
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
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
        p.title = "Update to v\(info.latestRelease.version)"
        p.isFloatingPanel = true
        p.level = .floating
        p.contentView = NSHostingView(rootView: contentView)

        p.center()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        updatePanel = p
    }

    private func tick() {
        _ = stats.refresh()
        statusBarView.cpuHistory = stats.cpuHistory
        if stats.diskTotal > 0 {
            statusBarView.diskUsedFraction = Double(stats.diskUsed) / Double(stats.diskTotal)
        }
        statusBarView.netInHistory = stats.netInHistory
        statusBarView.netOutHistory = stats.netOutHistory
        hostingView?.rootView = statusBarView
    }
}

// MARK: – Combined Status Bar View

struct StatusBarView: View {
    var cpuHistory: [Double]
    var diskUsedFraction: Double
    var netInHistory: [Double]
    var netOutHistory: [Double]

    var body: some View {
        HStack(spacing: 10) {
            CPULineChartView(history: cpuHistory)
            NetworkChartView(inHistory: netInHistory, outHistory: netOutHistory)
            DiskPieChartView(usedFraction: diskUsedFraction)
        }
    }
}

// MARK: – CPU Chart View

struct CPULineChartView: View {
    var history: [Double]

    private var dataPoints: [(index: Int, value: Double)] {
        let offset = 149 - history.count + 1
        return history.enumerated().map { (index: $0.offset + offset, value: $0.element) }
    }

    var body: some View {
        Chart(dataPoints, id: \.index) { point in
            AreaMark(
                x: .value("Time", point.index),
                y: .value("CPU", point.value)
            )
            .foregroundStyle(Color.primary)
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", point.index),
                y: .value("CPU", point.value)
            )
            .lineStyle(StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Color.primary)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .chartXScale(domain: 0...149)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .frame(width: 35, height: 18)
    }
}

// MARK: – Network Chart View

struct NetworkChartView: View {
    var inHistory: [Double]
    var outHistory: [Double]

    private var maxSpeed: Double {
        max(inHistory.max() ?? 1, outHistory.max() ?? 1, 1)
    }

    private func dataPoints(_ history: [Double]) -> [(index: Int, value: Double)] {
        let scale = maxSpeed
        let offset = 149 - history.count + 1
        return history.enumerated().map { (index: $0.offset + offset, value: $0.element / scale * 100) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Upload — grows from bottom of top half (flipped)
            Chart(dataPoints(outHistory), id: \.index) { point in
                AreaMark(
                    x: .value("Time", point.index),
                    y: .value("Out", point.value)
                )
                .foregroundStyle(Color.primary)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.index),
                    y: .value("Out", point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...149)
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.background(.clear)
            }
            .frame(width: 35, height: 9)
            .scaleEffect(y: -1)

            // Download — grows from top of bottom half (normal)
            Chart(dataPoints(inHistory), id: \.index) { point in
                AreaMark(
                    x: .value("Time", point.index),
                    y: .value("In", point.value)
                )
                .foregroundStyle(Color.primary)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.index),
                    y: .value("In", point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...149)
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.background(.clear)
            }
            .frame(width: 35, height: 9)
        }
    }
}

// MARK: – Disk Pie Chart View

struct DiskPieChartView: View {
    var usedFraction: Double

    var body: some View {
        Chart {
            SectorMark(angle: .value("Used", usedFraction), innerRadius: .ratio(0))
                .foregroundStyle(Color.primary)
            SectorMark(angle: .value("Free", 1 - usedFraction), innerRadius: .ratio(0))
                .foregroundStyle(Color.primary.opacity(0.2))
        }
        .chartLegend(.hidden)
        .frame(width: 18, height: 18)
    }
}

// MARK: – NSImage Rounded Rect Mask

extension NSImage {
    static func roundedRect(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: radius, left: radius, bottom: radius, right: radius
        )
        image.resizingMode = .stretch
        return image
    }
}
