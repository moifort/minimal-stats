import AppKit
import SwiftUI
import Charts
import Combine

// MARK: – Status Bar Model

final class StatusBarModel: ObservableObject {
    @Published var cpuHistory: [Double] = []
    @Published var diskUsedFraction: Double = 0
    @Published var netInHistory: [Double] = []
    @Published var netOutHistory: [Double] = []
}

// MARK: – Combined Status Bar View

struct StatusBarView: View {
    @ObservedObject var model: StatusBarModel

    var body: some View {
        HStack(spacing: 10) {
            SparklineChart(history: model.cpuHistory)
            NetworkChartView(inHistory: model.netInHistory, outHistory: model.netOutHistory)
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

    private var maxSpeed: Double {
        max(inHistory.max() ?? 1, outHistory.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Upload — grows from bottom of top half (flipped)
            SparklineChart(history: outHistory, maxValue: maxSpeed, height: 9)
                .scaleEffect(y: -1)

            // Download — grows from top of bottom half (normal)
            SparklineChart(history: inHistory, maxValue: maxSpeed, height: 9)
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
