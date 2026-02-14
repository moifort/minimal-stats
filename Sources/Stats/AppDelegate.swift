import AppKit
import SwiftUI
import Charts

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let stats = SystemStats()
    private var timer: Timer?

    private var hostingView: NSHostingView<StatusBarView>?
    private var statusBarView = StatusBarView(cpuHistory: [], diskUsedFraction: 0)

    // MARK: – Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 64)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(openActivityMonitor)
            let view = NSHostingView(rootView: statusBarView)
            view.frame = NSRect(x: 0, y: 0, width: 64, height: 22)
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(view)
            button.frame = view.frame
            hostingView = view
        }

        // Seed the delta-based CPU metric with an initial reading
        _ = stats.refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.tick()
        }
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.launchApplication("Activity Monitor")
    }

    // MARK: – Update

    private func tick() {
        _ = stats.refresh()
        statusBarView.cpuHistory = stats.cpuHistory
        if stats.diskTotal > 0 {
            statusBarView.diskUsedFraction = Double(stats.diskUsed) / Double(stats.diskTotal)
        }
        hostingView?.rootView = statusBarView
    }
}

// MARK: – Combined Status Bar View

struct StatusBarView: View {
    var cpuHistory: [Double]
    var diskUsedFraction: Double

    var body: some View {
        HStack(spacing: 10) {
            CPULineChartView(history: cpuHistory)
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
        .frame(width: 14, height: 14)
    }
}
