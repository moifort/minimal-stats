import SwiftUI

struct PopoverView: View {
    let snapshot: UsageSnapshot?
    var updateAvailable: AutoUpdater.Release?
    var onPlanChange: ((PlanType) -> Void)?
    var onUpdate: (() -> Void)?
    var onOpenActivityMonitor: (() -> Void)?
    var onQuit: (() -> Void)?
    var onUninstall: (() -> Void)?

    @State private var selectedPlan: PlanType

    init(
        snapshot: UsageSnapshot? = nil,
        updateAvailable: AutoUpdater.Release? = nil,
        onPlanChange: ((PlanType) -> Void)? = nil,
        onUpdate: (() -> Void)? = nil,
        onOpenActivityMonitor: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        onUninstall: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.updateAvailable = updateAvailable
        self.onPlanChange = onPlanChange
        self.onUpdate = onUpdate
        self.onOpenActivityMonitor = onOpenActivityMonitor
        self.onQuit = onQuit
        self.onUninstall = onUninstall
        self._selectedPlan = State(initialValue: snapshot?.planType ?? .max20x)
    }

    private var fraction: Double {
        guard let snapshot = snapshot else { return 0 }
        let limit = Double(selectedPlan.outputTokenLimit)
        return limit > 0 ? min(Double(snapshot.outputTokens) / limit, 1.0) : 0
    }

    private var percentText: String {
        "\(Int(fraction * 100))%"
    }

    private var timeRemainingText: String {
        guard let snapshot = snapshot else { return "" }
        let remaining = snapshot.nextReset.timeIntervalSince(Date())

        if remaining <= 0 {
            return ""
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h\(minutes > 0 ? String(format: "%02dm", minutes) : "")"
        }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if snapshot != nil {
                claudeSection
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
        .frame(width: 220)
    }

    // MARK: - Claude Usage Section

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Plan picker
            Picker("", selection: $selectedPlan) {
                ForEach(PlanType.allCases, id: \.self) { plan in
                    Text(plan.rawValue).tag(plan)
                }
            }.labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .onChange(of: selectedPlan) { _, newValue in
                onPlanChange?(newValue)
            }
            // Title + percentage
            HStack(spacing: 4) {
                Text("Claude Usage")
                Spacer()
                if (!timeRemainingText.isEmpty) {
                    Text(timeRemainingText)
                    Text("•")
                }
                Text(percentText)
            }.font(.body)
        }
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
// MARK: - Previews

struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView(
            snapshot: UsageSnapshot(
                outputTokens: 165_000,
                inputTokens: 50_000,
                cacheCreationTokens: 10_000,
                cacheReadTokens: 5_000,
                fraction: 0.75,
                windowStart: Date().addingTimeInterval(-3 * 3600),
                planType: .max20x,
                nextReset: Date().addingTimeInterval(2 * 3600)
            )
        )
    }
}


