import AppKit
import SwiftUI
import Charts
import Combine

// MARK: – Status Bar Model

/// Live metrics shared by the menu bar widgets and the popover.
final class StatusBarModel: ObservableObject {
    @Published var cpuHistory: [Double] = []
    @Published var netInHistory: [Double] = []   // bytes/sec
    @Published var netOutHistory: [Double] = []  // bytes/sec
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    /// Only refreshed while the popover is open
    @Published var processGroups: [ProcessGroup] = []
    /// Sampled all the time, like the per-process disk figures
    @Published var networkProcesses: [ProcessBytes] = []
    @Published var diskProcesses: [ProcessBytes] = []
    /// Kept here rather than in view state so the chosen tab survives reopening the popover
    @Published var processSort: ProcessSort = ProcessSort.available[0]

    var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }

    var memoryUsedFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }

    /// The four widgets in words, for VoiceOver
    var accessibilitySummary: String {
        [
            String(localized: "CPU \(Format.percent(cpuHistory.last))"),
            String(localized: "memory \(Format.memory(memoryUsed)) of \(Format.memory(memoryTotal, decimals: 0))"),
            String(localized: "download \(Format.bytes(netInHistory.last ?? 0))/s, upload \(Format.bytes(netOutHistory.last ?? 0))/s"),
            String(localized: "disk \(Format.bytes(Double(diskTotal - diskFree))) of \(Format.bytes(Double(diskTotal), decimals: 0)) used"),
        ].joined(separator: ", ")
    }
}

enum ProcessSort: String, CaseIterable {
    case cpu = "CPU", memory = "Memory", network = "Network", disk = "Disk"

    /// The tab's name, in the interface's language
    var title: String {
        switch self {
        case .cpu: return String(localized: "CPU")
        case .memory: return String(localized: "Memory")
        case .network: return String(localized: "Network")
        case .disk: return String(localized: "Disk")
        }
    }

    /// CPU and Memory are instantaneous; a cumulated tab says over which period.
    var help: String? {
        switch self {
        case .cpu, .memory: return nil
        case .network: return String(localized: "Data received and sent over the last \(Self.windowText(NetworkProcessSampler.window))")
        case .disk:
            return String(localized: "Data read and written over the last \(Self.windowText(DiskProcessSampler.window)), by your own apps only: macOS does not report it for system processes")
        }
    }

    private static func windowText(_ window: TimeInterval) -> String {
        let minutes = Int(window / 60)
        return minutes == 1 ? String(localized: "minute") : String(localized: "\(minutes) minutes")
    }
}

// MARK: – Combined Status Bar View

struct StatusBarView: View {
    @ObservedObject var model: StatusBarModel

    var body: some View {
        HStack(spacing: 10) {
            SparklineChart(history: model.cpuHistory)
            NetworkChartView(inHistory: model.netInHistory, outHistory: model.netOutHistory)
            MemoryGaugeView(usedFraction: model.memoryUsedFraction)
            DiskPieChartView(usedFraction: model.diskUsedFraction)
        }
        .padding(.horizontal, 5)
    }
}

// MARK: – Sparkline Chart

struct SparklineChart: View {
    var history: [Double]
    var maxValue: Double = 100
    var height: CGFloat = 18

    private var dataPoints: [(index: Int, value: Double)] {
        // Right-align the newest sample at the end of the x domain
        let offset = ChartMetrics.sampleCount - history.count
        return history.enumerated().map { (index: $0.offset + offset, value: $0.element) }
    }

    var body: some View {
        Chart(dataPoints, id: \.index) { point in
            AreaMark(
                x: .value("Time", point.index),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.primary)
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", point.index),
                y: .value("Value", point.value)
            )
            .lineStyle(StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Color.primary)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...maxValue)
        .chartXScale(domain: 0...(ChartMetrics.sampleCount - 1))
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .frame(width: 35, height: height)
    }
}

// MARK: – Network Chart View

struct NetworkChartView: View {
    var inHistory: [Double]
    var outHistory: [Double]

    var body: some View {
        let scaled = Self.scaled(inHistory: inHistory, outHistory: outHistory)
        VStack(spacing: 0) {
            // Upload — grows from bottom of top half (flipped)
            SparklineChart(history: scaled.outHistory, maxValue: scaled.maxValue, height: 9)
                .scaleEffect(y: -1)

            // Download — grows from top of bottom half (normal)
            SparklineChart(history: scaled.inHistory, maxValue: scaled.maxValue, height: 9)
        }
    }

    /// Square-root scale, shared by both halves: after a 40 MB/s burst, 20 KB/s
    /// still fills 2% of the height instead of 0.05%, and the order of the
    /// samples is kept.
    static func scaled(inHistory: [Double], outHistory: [Double]) -> (inHistory: [Double], outHistory: [Double], maxValue: Double) {
        let root = { (speed: Double) in max(speed, 0).squareRoot() }
        let peak = max(inHistory.max() ?? 1, outHistory.max() ?? 1, 1)
        return (inHistory.map(root), outHistory.map(root), root(peak))
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

// MARK: – Memory Gauge View

/// Vertical bar filled to the used share of RAM, styled like the disk pie.
struct MemoryGaugeView: View {
    var usedFraction: Double

    private static let size = CGSize(width: 6, height: 18)

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.2))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary)
                .frame(height: Self.size.height * min(max(usedFraction, 0), 1))
        }
        .frame(width: Self.size.width, height: Self.size.height)
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
