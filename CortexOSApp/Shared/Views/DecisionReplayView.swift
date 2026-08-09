//
//  DecisionReplayView.swift
//  CortexOS
//
//  Shows how SimpliXio reduced noisy signals into clear priorities.
//  Value proof: reviewed -> ignored -> kept -> final priorities.
//

import SwiftUI

struct DecisionReplayView: View {
    @EnvironmentObject private var engine: CortexEngine
    var compactMode: Bool = false

    var body: some View {
        Group {
            if let replay = engine.snapshot?.decisionReplay {
                replayContent(replay)
            } else {
                EmptyStateView(
                    icon: "arrow.triangle.branch",
                    title: "Your Decision Replay will appear here",
                    message: "Capture a few signals first. SimpliXio will show what it kept, what it ignored, and why.",
                    actionTitle: "Refresh",
                    action: { Task { await engine.sync() } },
                    isActionLoading: engine.isSyncing
                )
            }
        }
        .background(CortexColor.bgPrimary)
        .navigationTitle("Decision Replay")
        .refreshable { await engine.sync() }
    }

    @ViewBuilder
    private func replayContent(_ replay: SyncDecisionReplay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                sectionCard("Summary", systemImage: "arrow.triangle.branch") {
                    Text(replay.date)
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                    Text(replay.summary)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textPrimary)
                }

                sectionCard("Metrics", systemImage: "number") {
                    HStack(spacing: CortexSpacing.lg) {
                        metric("Reviewed", "\(replay.signalsReviewed)")
                        metric("Kept", "\(replay.signalsKept)")
                        metric("Ignored", "\(replay.signalsIgnored)")
                        metric("Priorities", "\(replay.finalPriorities.count)")
                    }
                }

                sectionCard("Final Priorities", systemImage: "target") {
                    if replay.finalPriorities.isEmpty {
                        Text("No final priorities captured yet.")
                            .font(CortexFont.body)
                            .foregroundStyle(CortexColor.textTertiary)
                    } else {
                        ForEach(Array(replay.finalPriorities.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                                Text("\(index + 1). \(item.title)")
                                    .font(CortexFont.bodyMedium)
                                    .foregroundStyle(CortexColor.textPrimary)
                                if !item.why.isEmpty {
                                    Text("Why: \(item.why)")
                                        .font(CortexFont.caption)
                                        .foregroundStyle(CortexColor.textSecondary)
                                }
                                if !item.action.isEmpty {
                                    Text("Action: \(item.action)")
                                        .font(CortexFont.caption)
                                        .foregroundStyle(CortexColor.textSecondary)
                                }
                            }
                        }
                    }
                }

                if compactMode {
                    detailDisclosure(title: "Kept Signals", systemImage: "checkmark.circle", items: replay.keptSignals)
                    detailDisclosure(title: "Ignored Noise", systemImage: "minus.circle", items: replay.ignoredSignals)
                } else {
                    sectionCard("Kept Signals", systemImage: "checkmark.circle") {
                        signalList(replay.keptSignals, emptyText: "No kept signals captured.")
                    }
                    sectionCard("Ignored Noise", systemImage: "minus.circle") {
                        signalList(replay.ignoredSignals, emptyText: "No ignored signals captured.")
                    }
                }
            }
            .padding(CortexSpacing.xl)
        }
    }

    @ViewBuilder
    private func detailDisclosure(title: String, systemImage: String, items: [SyncDecisionReplaySignal]) -> some View {
        sectionCard(title, systemImage: systemImage) {
            DisclosureGroup("Show details (\(items.count))") {
                signalList(items, emptyText: "No items.")
                    .padding(.top, CortexSpacing.xs)
            }
            .font(CortexFont.caption)
            .foregroundStyle(CortexColor.textSecondary)
        }
    }

    @ViewBuilder
    private func signalList(_ items: [SyncDecisionReplaySignal], emptyText: String) -> some View {
        if items.isEmpty {
            Text(emptyText)
                .font(CortexFont.body)
                .foregroundStyle(CortexColor.textTertiary)
        } else {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                    Text(item.title)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textPrimary)
                    Text(item.reason)
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            Label(title, systemImage: systemImage)
                .font(CortexFont.headline)
                .foregroundStyle(CortexColor.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
