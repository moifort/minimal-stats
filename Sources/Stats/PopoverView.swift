import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: StatusBarModel
    var updateAvailable: AutoUpdater.Release?
    var onUpdate: (() -> Void)?
    var onOpenActivityMonitor: (() -> Void)?
    var onQuit: (() -> Void)?
    var onUninstall: (() -> Void)?
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
            actionButton("Quit", systemImage: "xmark") {
                onQuit?()
            }
            actionButton("Uninstall\u{2026}", systemImage: "trash") {
                onUninstall?()
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
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
    var title: String
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

    var body: some View {
        VStack(spacing: 2) {
            Picker("", selection: $model.processSort) {
                ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 4)
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
            return model.processes
                .sorted { $0.cpuPercent > $1.cpuPercent }
                .prefix(Self.rowCount)
                .map { Row(pid: $0.pid, name: $0.name, value: Format.percent($0.cpuPercent, decimals: 1), canQuit: $0.isOwnedByUser) }
        case .memory:
            return model.processes
                .sorted { $0.memoryBytes > $1.memoryBytes }
                .prefix(Self.rowCount)
                .map { Row(pid: $0.pid, name: $0.name, value: Format.memory($0.memoryBytes), canQuit: $0.isOwnedByUser) }
        case .network:
            let owned = Set(model.processes.filter(\.isOwnedByUser).map(\.pid))
            return model.networkProcesses
                .prefix(Self.rowCount)
                .map { Row(pid: $0.pid, name: $0.name, value: Format.inOut(Double($0.bytesIn), Double($0.bytesOut)), canQuit: owned.contains($0.pid)) }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row?) -> some View {
        let content = HStack(spacing: 6) {
            Text(row?.name ?? " ")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(row?.value ?? "")
                .lineLimit(1)
                .fixedSize()
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .padding(.horizontal, 4)

        if let row, row.canQuit {
            Button {
                onQuitProcess?(row.pid, row.name)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .help("Quit \(row.name)")
        } else {
            content
        }
    }
}

// MARK: - Formatting

enum Format {
    static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "–" }
        return String(format: "%.\(decimals)f%%", value)
    }

    /// Decimal units (1 KB = 1000 B), matching Finder and network tools
    static func bytes(_ value: Double, decimals: Int? = nil) -> String {
        scaled(value, base: 1000, decimals: decimals)
    }

    /// Binary units (1 GB = 1024³ B), matching Activity Monitor's memory figures
    static func memory(_ value: UInt64, decimals: Int? = nil) -> String {
        scaled(Double(value), base: 1024, decimals: decimals)
    }

    static func inOut(_ bytesIn: Double, _ bytesOut: Double, suffix: String = "") -> String {
        "↓ \(bytes(bytesIn))\(suffix)  ↑ \(bytes(bytesOut))\(suffix)"
    }

    private static func scaled(_ value: Double, base: Double, decimals: Int?) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = max(value, 0)
        var unit = 0
        while scaled >= base, unit < units.count - 1 {
            scaled /= base
            unit += 1
        }
        // One decimal below 100 keeps small values readable without jitter on large ones
        let digits = decimals ?? (unit == 0 || scaled >= 100 ? 0 : 1)
        return String(format: "%.\(digits)f %@", scaled, units[unit])
    }
}

// MARK: - Previews

struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView(model: StatusBarModel())
    }
}
