import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: StatusBarModel
    var updateAvailable: AutoUpdater.Release?
    var onUpdate: (() -> Void)?
    var onOpenActivityMonitor: (() -> Void)?
    var onQuit: (() -> Void)?
    var onQuitProcess: ((pid_t, String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SystemStatsSection(model: model)
            Divider().padding(.vertical, 8)
            TopProcessesSection(model: model, onQuitProcess: onQuitProcess)
            Divider().padding(.vertical, 8)
            if let release = updateAvailable {
                actionButton("Update v\(release.version)", systemImage: "arrow.down.circle.fill") {
                    onUpdate?()
                }
                Divider().padding(.vertical, 8)
            }
            actionsSection
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
        }
        .padding(12)
        .frame(width: 290)
    }

    // MARK: - Action Buttons

    private var actionsSection: some View {
        VStack(spacing: 2) {
            actionButton("Activity Monitor", systemImage: "gauge.with.dots.needle.33percent") {
                onOpenActivityMonitor?()
            }
            actionButton("Quit Stats", systemImage: "xmark") {
                onQuit?()
            }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System Stats Section

private struct SystemStatsSection: View {
    @ObservedObject var model: StatusBarModel

    var body: some View {
        VStack(spacing: 2) {
            StatRow(systemImage: "cpu", title: "CPU") {
                Text(Format.percent(model.cpuHistory.last))
            }
            StatRow(systemImage: "memorychip", title: "Memory") {
                Text("\(Format.memory(model.memoryUsed)) / \(Format.memory(model.memoryTotal, decimals: 0))")
            }
            StatRow(systemImage: "network", title: "Network") {
                Text(Format.inOut(model.netInHistory.last ?? 0, model.netOutHistory.last ?? 0, suffix: "/s"))
            }
            StatRow(systemImage: "internaldrive", title: "Disk") {
                Text("\(Format.bytes(Double(model.diskTotal - model.diskFree))) / \(Format.bytes(Double(model.diskTotal), decimals: 0))")
            }
        }
    }
}

private struct StatRow<Value: View>: View {
    var systemImage: String
    var title: LocalizedStringKey
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text(title)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            value
                .lineLimit(1)
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}

// MARK: - Top Processes Section

private struct TopProcessesSection: View {
    @ObservedObject var model: StatusBarModel
    var onQuitProcess: ((pid_t, String) -> Void)?

    private struct Row {
        let pid: pid_t
        let name: String
        let value: String
        let canQuit: Bool
    }

    private static let rowCount = 5
    private static let quitHitOutset: CGFloat = 3

    var body: some View {
        VStack(spacing: 2) {
            ProcessTabs(selection: $model.processSort, tabs: ProcessSort.available)
            // As wide as the dividers: the four French tabs need 263 points.
            .padding(.bottom, 4)

            // Always render the same number of rows so the panel never resizes
            ForEach(0..<Self.rowCount, id: \.self) { index in
                if index < rows.count {
                    rowView(rows[index])
                } else {
                    rowView(nil)
                }
            }
        }
    }

    private var rows: [Row] {
        switch model.processSort {
        case .cpu:
            // Processes seen only once have no CPU figure yet
            return ProcessGroup.sortedByCPU(model.processGroups)
                .prefix(Self.rowCount)
                .map { Row(pid: $0.group.rootPID, name: Format.processName($0.group.name), value: Format.percent($0.cpuPercent, decimals: 1), canQuit: $0.group.canQuit) }
        case .memory:
            return ProcessGroup.sortedByMemory(model.processGroups)
                .prefix(Self.rowCount)
                .map { Row(pid: $0.rootPID, name: Format.processName($0.name), value: Format.memory($0.memoryBytes), canQuit: $0.canQuit) }
        case .network:
            return GroupTraffic.make(from: model.networkProcesses, groups: model.processGroups)
                .prefix(Self.rowCount)
                .map { Row(pid: $0.rootPID, name: Format.processName($0.name), value: Format.inOut(Double($0.bytesIn), Double($0.bytesOut)), canQuit: $0.canQuit) }
        case .disk:
            return GroupTraffic.make(from: model.diskProcesses, groups: model.processGroups)
                .prefix(Self.rowCount)
                .map { Row(pid: $0.rootPID, name: Format.processName($0.name), value: Format.readWrite(Double($0.bytesIn), Double($0.bytesOut)), canQuit: $0.canQuit) }
        }
    }

    private func rowView(_ row: Row?) -> some View {
        HStack(spacing: 6) {
            Text(row?.name ?? " ")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(row?.value ?? "")
                .lineLimit(1)
                .fixedSize()
                .monospacedDigit()
                .foregroundStyle(.secondary)
            quitButton(for: row)
        }
        .font(.system(size: 12))
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    /// Only the user's own processes can be quit; other rows keep the space so values stay aligned.
    @ViewBuilder
    private func quitButton(for row: Row?) -> some View {
        if let row, row.canQuit {
            Button {
                onQuitProcess?(row.pid, row.name)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    // A 22 pt target around the 16 pt icon; the negative padding
                    // below keeps the 16 pt layout, so values stay aligned.
                    .padding(Self.quitHitOutset)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-Self.quitHitOutset)
            .help(String(localized: "Quit \(row.name)"))
            .accessibilityLabel(String(localized: "Quit \(row.name)"))
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}

// MARK: - Tabs

/// The tab bar: the same AppKit segmented control a segmented `Picker` draws,
/// but always exactly as wide as SwiftUI offers. The `Picker` sometimes
/// re-measured itself on a refresh, asked for its ideal width (segments of
/// equal width, wider than the popover in French) and pushed the whole
/// popover sideways for a frame.
private struct ProcessTabs: NSViewRepresentable {
    @Binding var selection: ProcessSort
    let tabs: [ProcessSort]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: tabs.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fillProportionally
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for (index, tab) in tabs.enumerated() {
            control.setToolTip(tab.help, forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        let index = tabs.firstIndex(of: selection) ?? 0
        if control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    /// The width offered, never the control's own idea of it.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? control.intrinsicContentSize.width, height: control.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: ProcessTabs
        init(parent: ProcessTabs) { self.parent = parent }

        @objc func changed(_ control: NSSegmentedControl) {
            guard parent.tabs.indices.contains(control.selectedSegment) else { return }
            parent.selection = parent.tabs[control.selectedSegment]
        }
    }
}

// MARK: - Formatting

enum Format {
    /// Figures follow the interface's language, not the region: a French
    /// interface writes 1,2Go, an English one 1.2GB.
    static var french = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true

    static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "–" }
        return decimal(String(format: "%.\(decimals)f%%", value))
    }

    /// Decimal units (1 KB = 1000 B), matching Finder and network tools
    static func bytes(_ value: Double, decimals: Int? = nil) -> String {
        scaled(value, base: 1000, decimals: decimals)
    }

    /// Binary units (1 GB = 1024³ B), matching Activity Monitor's memory figures
    static func memory(_ value: UInt64, decimals: Int? = nil) -> String {
        scaled(Double(value), base: 1024, decimals: decimals)
    }

    /// "com.apple.DriverKit-AppleBCMWLAN" reads as "DriverKit-AppleBCMWLAN": the
    /// prefix is shared by hundreds of system processes and says nothing.
    static func processName(_ name: String) -> String {
        let prefix = "com.apple."
        guard name.hasPrefix(prefix), name.count > prefix.count else { return name }
        return String(name.dropFirst(prefix.count))
    }

    static func inOut(_ bytesIn: Double, _ bytesOut: Double, suffix: String = "") -> String {
        "↓ \(bytes(bytesIn))\(suffix)  ↑ \(bytes(bytesOut))\(suffix)"
    }

    /// R for read and W for written: arrows already mean received and sent
    static func readWrite(_ bytesRead: Double, _ bytesWritten: Double) -> String {
        french ? "L \(bytes(bytesRead))  É \(bytes(bytesWritten))" : "R \(bytes(bytesRead))  W \(bytes(bytesWritten))"
    }

    private static func scaled(_ value: Double, base: Double, decimals: Int?) -> String {
        let units = french ? ["o", "Ko", "Mo", "Go", "To"] : ["B", "KB", "MB", "GB", "TB"]
        var scaled = max(value, 0)
        var unit = 0
        while scaled >= base, unit < units.count - 1 {
            scaled /= base
            unit += 1
        }
        // One decimal below 100 keeps small values readable without jitter on large ones
        let digits = decimals ?? (unit == 0 || scaled >= 100 ? 0 : 1)
        return decimal(String(format: "%.\(digits)f%@", scaled, units[unit]))
    }

    /// The decimal comma of a French interface; `String(format:)` always writes a point.
    private static func decimal(_ text: String) -> String {
        french ? text.replacingOccurrences(of: ".", with: ",") : text
    }
}

// MARK: - Previews

struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView(model: StatusBarModel())
    }
}
