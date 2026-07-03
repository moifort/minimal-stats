import SwiftUI

struct PopoverView: View {
    var updateAvailable: AutoUpdater.Release?
    var quotaTracker: QuotaTracker?
    var onUpdate: (() -> Void)?
    var onOpenActivityMonitor: (() -> Void)?
    var onQuit: (() -> Void)?
    var onUninstall: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tracker = quotaTracker {
                ClaudeQuotaSection(tracker: tracker)
                Divider().padding(.vertical, 8)
            }
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
        .frame(width: 250)
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

// MARK: - Claude Usage Section

/// Observes the tracker directly so the rows update live while the popover is open.
private struct ClaudeQuotaSection: View {
    @ObservedObject var tracker: QuotaTracker

    var body: some View {
        VStack(spacing: 2) {
            quotaRow(
                systemImage: "sparkle",
                title: "Claude Usage",
                utilization: tracker.lastSnapshot?.fiveHourUtilization,
                detail: Self.resetTimeText(tracker.lastSnapshot?.fiveHourResetsAt)
            )
            quotaRow(
                systemImage: "calendar",
                title: "Weekly",
                utilization: tracker.lastSnapshot?.sevenDayUtilization,
                detail: Self.timeRemainingText(until: tracker.lastSnapshot?.sevenDayResetsAt)
            )
        }
    }

    private func quotaRow(systemImage: String, title: String, utilization: Double?, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text(title)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                if !detail.isEmpty {
                    Text(detail)
                    Text("•")
                }
                Text(Self.percentText(utilization))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tracker.isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .font(.system(size: 13))
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private static func percentText(_ utilization: Double?) -> String {
        guard let utilization else { return "–" }
        return "\(Int(utilization.rounded()))%"
    }

    /// Local clock time of the next reset, e.g. "10:58"
    private static func resetTimeText(_ date: Date?) -> String {
        guard let date, date > Date() else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func timeRemainingText(until date: Date?) -> String {
        guard let date else { return "" }
        let remaining = Int(date.timeIntervalSince(Date()))
        guard remaining > 0 else { return "" }

        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        let minutes = (remaining % 3600) / 60

        if days > 0 {
            return "\(days)d" + (hours > 0 ? "\(hours)h" : "")
        }
        if hours > 0 {
            return "\(hours)h" + (minutes > 0 ? String(format: "%02dm", minutes) : "")
        }
        return "\(minutes)m"
    }
}

// MARK: - Previews

struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView(
            quotaTracker: QuotaTracker(
                initialSnapshot: QuotaSnapshot(
                    fiveHourUtilization: 63,
                    fiveHourResetsAt: Date().addingTimeInterval(3600),
                    sevenDayUtilization: 21,
                    sevenDayResetsAt: Date().addingTimeInterval(2 * 86400),
                    fetchedAt: Date()
                )
            )
        )
    }
}
