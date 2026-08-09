import SwiftUI

struct SignalWorkbenchView: View {
    enum Focus {
        case overview
        case recurringPatterns
        case unresolvedTensions
        case contentCandidates
    }

    @EnvironmentObject private var engine: CortexEngine
    let focus: Focus

    init(focus: Focus = .overview) {
        self.focus = focus
    }

    var body: some View {
        Group {
            if let snapshot = engine.snapshot {
                content(snapshot)
            } else {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "Preparing your review",
                    message: "Capture a few thoughts, then refresh to see private on-device queues.",
                    actionTitle: "Refresh",
                    action: { Task { await engine.sync() } },
                    isActionLoading: engine.isSyncing
                )
            }
        }
        .navigationTitle(screenTitle)
        .background(CortexColor.bgPrimary)
        .refreshable { await engine.sync() }
    }

    private var screenTitle: String {
        switch focus {
        case .overview: "Queues"
        case .recurringPatterns: "Recurring Patterns"
        case .unresolvedTensions: "Unresolved Tensions"
        case .contentCandidates: "Content Candidates"
        }
    }

    @ViewBuilder
    private func content(_ snapshot: SyncSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                metrics(snapshot.signalMatchingCounts)

                switch focus {
                case .overview:
                    queueCard(
                        title: "What matters now",
                        icon: "target",
                        items: snapshot.whatMattersNow ?? [],
                        emptyText: "No immediate items right now.",
                        maxVisible: 3
                    )

                    queueCard(
                        title: "Decision Queue",
                        icon: "checkmark.seal",
                        items: snapshot.decisionQueue ?? [],
                        emptyText: "No decision-ready items yet.",
                        maxVisible: 5
                    )

                    queueCard(
                        title: "Action-Ready Queue",
                        icon: "bolt.fill",
                        items: snapshot.actionReadyQueue ?? [],
                        emptyText: "No action-ready items yet.",
                        maxVisible: 5
                    )

                    queueCard(
                        title: "Unresolved Tensions",
                        icon: "exclamationmark.triangle",
                        items: snapshot.unresolvedTensions ?? [],
                        emptyText: "No unresolved tensions detected.",
                        maxVisible: 5
                    )

                    queueCard(
                        title: "Content Candidates",
                        icon: "doc.text",
                        items: snapshot.contentCandidates ?? [],
                        emptyText: "No safe content candidates right now.",
                        maxVisible: 5
                    )

                    recurringPatternsCard(snapshot.recurringPatterns ?? [], maxVisible: 5)

                case .recurringPatterns:
                    recurringPatternsCard(snapshot.recurringPatterns ?? [], maxVisible: 5)

                case .unresolvedTensions:
                    queueCard(
                        title: "Unresolved Tensions",
                        icon: "exclamationmark.triangle",
                        items: snapshot.unresolvedTensions ?? [],
                        emptyText: "No unresolved tensions detected.",
                        maxVisible: 5
                    )
                case .contentCandidates:
                    queueCard(
                        title: "Content Candidates",
                        icon: "doc.text",
                        items: snapshot.contentCandidates ?? [],
                        emptyText: "No safe content candidates right now.",
                        maxVisible: 5
                    )
                }
            }
            .padding(CortexSpacing.xl)
        }
    }

    @ViewBuilder
    private func metrics(_ counts: SyncSignalMatchingCounts?) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            Text("Current filter")
                .font(CortexFont.captionMedium)
                .foregroundStyle(CortexColor.textTertiary)

            HStack(spacing: CortexSpacing.lg) {
                metric("Captured", "\(counts?.signalsTotal ?? 0)")
                metric("Active", "\(counts?.signalsActive ?? 0)")
                metric("Filtered out", "\(counts?.ignored ?? 0)")
            }
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private func queueCard(
        title: String,
        icon: String,
        items: [SyncRankedSignal],
        emptyText: String,
        maxVisible: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            Label(title, systemImage: icon)
                .font(CortexFont.headline)
                .foregroundStyle(CortexColor.textPrimary)

            if items.isEmpty {
                Text(emptyText)
                    .font(CortexFont.body)
                    .foregroundStyle(CortexColor.textTertiary)
            } else {
                ForEach(items.prefix(maxVisible)) { item in
                    VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                        Text(item.title)
                            .font(CortexFont.bodyMedium)
                            .foregroundStyle(CortexColor.textPrimary)

                        Text(item.explainability.whyItSurfaced)
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.textSecondary)

                        Text("Next: \(item.nextAction)")
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.accent)

                        HStack(spacing: CortexSpacing.xs) {
                            queuePill(item.horizon.capitalized)
                            queuePill(item.signalType.replacingOccurrences(of: "_", with: " ").capitalized)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CortexSpacing.xs)

                    if item.signalID != items.prefix(maxVisible).last?.signalID {
                        Divider()
                            .opacity(0.3)
                    }
                }

                if items.count > maxVisible {
                    Text("Showing \(maxVisible) of \(items.count). Open the focused section for deeper review.")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                }
            }
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private func recurringPatternsCard(_ patterns: [SyncRecurringPattern], maxVisible: Int) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            Label("Recurring Patterns", systemImage: "waveform.path.ecg")
                .font(CortexFont.headline)
                .foregroundStyle(CortexColor.textPrimary)

            if patterns.isEmpty {
                Text("No recurring patterns detected yet.")
                    .font(CortexFont.body)
                    .foregroundStyle(CortexColor.textTertiary)
            } else {
                ForEach(patterns.prefix(maxVisible)) { pattern in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                            Text(pattern.topic.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(CortexFont.bodyMedium)
                                .foregroundStyle(CortexColor.textPrimary)
                            Text("\(pattern.count)x • unresolved \(pattern.unresolvedCount)")
                                .font(CortexFont.caption)
                                .foregroundStyle(CortexColor.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(pattern.avgImportance))")
                            .font(CortexFont.captionMedium)
                            .foregroundStyle(CortexColor.accent)
                    }
                }
            }
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
            Text(label)
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textTertiary)
            Text(value)
                .font(CortexFont.captionMedium)
                .foregroundStyle(CortexColor.textPrimary)
        }
    }

    @ViewBuilder
    private func queuePill(_ text: String) -> some View {
        Text(text)
            .font(CortexFont.mono)
            .foregroundStyle(CortexColor.textTertiary)
            .padding(.horizontal, CortexSpacing.sm)
            .padding(.vertical, CortexSpacing.xxs)
            .background(CortexColor.bgSecondary)
            .clipShape(Capsule(style: .continuous))
    }
}
