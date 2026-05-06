import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchDecisionModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow

                    if let priority = model.topPriority {
                        priorityCard(priority)
                        feedbackCard(priority)
                    } else {
                        emptyStateCard
                    }

                    captureCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .navigationTitle("Next")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.sync() }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isLocalMode ? CortexColor.neutral : (model.isOffline ? CortexColor.warning : CortexColor.success))
                .frame(width: 6, height: 6)
            Text(model.updatedStatus)
                .font(.caption2)
                .foregroundStyle(CortexColor.textSecondary)
            Spacer()
            if model.pendingCount > 0 {
                Text(queuedLabel)
                    .font(.caption2)
                    .foregroundStyle(CortexColor.accent)
            }
        }
    }

    private var queuedLabel: String {
        model.pendingCount == 1 ? "1 queued" : "\(model.pendingCount) queued"
    }

    @ViewBuilder
    private func priorityCard(_ priority: SyncTodayPriority) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What matters now")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(priority.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !priority.action.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next action")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label(priority.action, systemImage: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(CortexColor.accent)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CortexColor.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CortexColor.strokeSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func feedbackCard(_ priority: SyncTodayPriority) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Feedback")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                feedbackButton("Done", icon: "checkmark.circle.fill") {
                    Task { await model.sendQuickFeedback(for: priority, useful: true, acted: true) }
                }
                feedbackButton("Useful", icon: "hand.thumbsup.fill") {
                    Task { await model.sendQuickFeedback(for: priority, useful: true, acted: nil) }
                }
            }

            HStack(spacing: 5) {
                feedbackButton("Snooze", icon: "clock.fill") {
                    Task { await model.sendQuickFeedback(for: priority, useful: true, acted: false) }
                }
                feedbackButton("Skip", icon: "hand.thumbsdown.fill") {
                    Task { await model.sendQuickFeedback(for: priority, useful: false, acted: nil) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CortexColor.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CortexColor.strokeSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func feedbackButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("Thought or tension", text: $model.captureText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(8)
                .background(CortexColor.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CortexColor.strokeSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Task { await model.captureByVoice() }
            } label: {
                Label("Capture", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .disabled(model.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)

            Text(model.captureStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CortexColor.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CortexColor.strokeSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No next action yet")
                .font(.headline)
            Text(model.isLocalMode ? "Capture one thought. It stays private here." : "Sync to pull what matters now.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                Task { await model.sync() }
            } label: {
                Label(model.isSyncing ? "Syncing..." : (model.isLocalMode ? "Refresh" : "Sync"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .disabled(model.isSyncing)
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CortexColor.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CortexColor.strokeSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
