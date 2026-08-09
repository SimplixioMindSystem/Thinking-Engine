//
//  WeeklyReviewView.swift
//  CortexOS
//
//  Weekly decision loop for the macOS workbench.
//  Compact summary of repeated priorities, repeated signals,
//  ignored noise, and recommended next adjustments.
//

import SwiftUI

struct WeeklyReviewView: View {
    @EnvironmentObject private var engine: CortexEngine

    var body: some View {
        Group {
            if let review = engine.snapshot?.weeklyReview {
                reviewContent(review)
            } else {
                EmptyStateView(
                    icon: "calendar.badge.clock",
                    title: "Your weekly review will appear here",
                    message: "Capture a few thoughts or decisions during the week. SimpliXio will summarize what repeated and what deserves focus next.",
                    actionTitle: "Refresh",
                    action: { Task { await engine.sync() } },
                    isActionLoading: engine.isSyncing
                )
            }
        }
        .background(CortexColor.bgPrimary)
        .navigationTitle("Weekly Review")
        .refreshable { await engine.sync() }
    }

    @ViewBuilder
    private func reviewContent(_ review: SyncWeeklyReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                sectionCard("Summary", systemImage: "text.alignleft") {
                    if let periodLabel = review.periodLabel, !periodLabel.isEmpty {
                        Text(periodLabel)
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.textTertiary)
                    }

                    if review.quality == "insufficient_history" {
                        HStack(spacing: CortexSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(CortexColor.warning)
                            Text("Limited history (\(review.daysCovered)/7 days). Treat trends as directional.")
                                .font(CortexFont.caption)
                                .foregroundStyle(CortexColor.textTertiary)
                        }
                    }

                    Text(review.summary)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textPrimary)

                    HStack(spacing: CortexSpacing.lg) {
                        metric("Week", review.periodLabel ?? "\(review.weekStart) → \(review.weekEnd)")
                        metric("Days", "\(review.daysCovered)")
                        metric("Ignored", "\(review.totalIgnoredSignals)")
                    }
                    .padding(.top, CortexSpacing.xs)
                }

                sectionCard("Top Repeated Priorities", systemImage: "target") {
                    countList(review.topPriorities, emptyText: "No repeated priorities yet.")
                }

                sectionCard("Top Repeated Signals", systemImage: "waveform.path.ecg") {
                    countList(review.topSignals, emptyText: "No repeated signals yet.")
                }

                sectionCard("Recommendations", systemImage: "lightbulb") {
                    if review.recommendations.isEmpty {
                        Text("No recommendations available yet.")
                            .font(CortexFont.body)
                            .foregroundStyle(CortexColor.textTertiary)
                    } else {
                        ForEach(Array(review.recommendations.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: CortexSpacing.sm) {
                                Text("\(index + 1).")
                                    .font(CortexFont.captionMedium)
                                    .foregroundStyle(CortexColor.accent)
                                Text(item)
                                    .font(CortexFont.body)
                                    .foregroundStyle(CortexColor.textPrimary)
                            }
                        }
                    }
                }
            }
            .padding(CortexSpacing.xl)
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

    @ViewBuilder
    private func countList(_ items: [SyncWeeklyReviewCountItem], emptyText: String) -> some View {
        if items.isEmpty {
            Text(emptyText)
                .font(CortexFont.body)
                .foregroundStyle(CortexColor.textTertiary)
        } else {
            ForEach(items) { item in
                HStack {
                    Text(item.title)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Text("\(item.count)x")
                        .font(CortexFont.captionMedium)
                        .foregroundStyle(CortexColor.accent)
                }
            }
        }
    }
}
