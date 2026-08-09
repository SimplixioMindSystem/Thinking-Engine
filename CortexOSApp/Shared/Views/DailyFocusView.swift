//
//  DailyFocusView.swift
//  CortexOS
//
//  The only screen that really matters.
//  Open → Understand → Act → Close.
//  Top 3 priorities. Why they matter. One next action. What to ignore.
//

import SwiftUI

struct DailyFocusView: View {
    @EnvironmentObject private var engine: CortexEngine
    var onRequestCapture: (() -> Void)? = nil
    var onRequestDecisionReplay: (() -> Void)? = nil

    /// Priorities the user has swiped away this session (not persisted — resets on next sync)
    @State private var dismissedTitles: Set<String> = []
    @State private var selectedPriority: SyncPriority?
    @State private var showDecisionReplay = false

    var body: some View {
        Group {
            if let brief = engine.snapshot?.priorities {
                focusContent(brief)
            } else {
                VStack(spacing: CortexSpacing.xl) {
                    EmptyStateView(
                        icon: "target",
                        title: "No priorities yet",
                        message: "Capture what is taking mental space. SimpliXio will filter it into what matters now.",
                        actionTitle: onRequestCapture == nil ? "Refresh" : "Capture a thought",
                        action: {
                            if let onRequestCapture {
                                onRequestCapture()
                            } else {
                                Task { await engine.sync() }
                            }
                        },
                        isActionLoading: engine.isSyncing
                    )

                    if let snapshot = engine.snapshot {
                        quickContextCard(snapshot)
                    }
                }
            }
        }
        .background(CortexColor.bgPrimary)
        .accessibilityIdentifier("focus.screen")
        .navigationTitle("Focus")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let shareText = todayShareText {
                    ShareLink(item: shareText) {
                        Label("Share SimpliXio Today", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .help("Share SimpliXio Today")
                }

                if engine.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Syncing…")
                } else {
                    Button(action: triggerSync) {
                        Label("Sync now", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .help("Sync now")
                }
            }
        }
        #endif
        .refreshable { await engine.sync() }
        .sheet(item: $selectedPriority) { priority in
            PriorityDetailSheet(
                priority: priority,
                onFeedback: { useful, acted in
                    Task {
                        await engine.sendFeedback(item: priority.title, useful: useful, acted: acted)
                    }
                },
                onIgnore: { dismiss(priority) }
            )
        }
        #if os(iOS)
        .sheet(isPresented: $showDecisionReplay) {
            NavigationStack {
                DecisionReplayView(compactMode: true)
                    .environmentObject(engine)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showDecisionReplay = false }
                        }
                    }
            }
        }
        #endif
    }

    // MARK: - Quick context when empty

    @ViewBuilder
    private func quickContextCard(_ snapshot: SyncSnapshot) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            if let project = snapshot.activeProject {
                HStack(spacing: CortexSpacing.xs) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(CortexColor.accent)
                    Text(project.projectName)
                        .font(CortexFont.captionMedium)
                        .foregroundStyle(CortexColor.textPrimary)
                }
            }

            if !snapshot.profile.goals.isEmpty {
                VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                    Text("Your goals")
                        .font(CortexFont.mono)
                        .foregroundStyle(CortexColor.textTertiary)
                    ForEach(snapshot.profile.goals.prefix(3), id: \.self) { goal in
                        Text("→ \(goal)")
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cortexSurfaceCard()
        .padding(.horizontal, CortexSpacing.xl)
    }

    // MARK: - Focus content

    @ViewBuilder
    private func focusContent(_ brief: PriorityBrief) -> some View {
        ScrollView {
            focusBody(brief)
                .padding(.bottom, CortexSpacing.xxl)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private func focusBody(_ brief: PriorityBrief) -> some View {
        let visible = brief.priorities.filter { !dismissedTitles.contains($0.title) }

        VStack(alignment: .leading, spacing: CortexSpacing.lg) {
            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                Text("Today’s 3 priorities")
                    .font(CortexFont.title)
                    .foregroundStyle(CortexColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Why they matter. One next action. Everything else stays quiet.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            focusStatusStrip

            // #1 Priority — hero card
            if let top = visible.first {
                HeroPriorityCard(priority: top, onFeedback: { useful in
                    Task { await engine.sendFeedback(item: top.title, useful: useful) }
                }, onOpen: {
                    selectedPriority = top
                }, onDismiss: {
                    dismiss(top)
                })
            }

            // Remaining priorities
            ForEach(Array(visible.dropFirst().prefix(2).enumerated()), id: \.element.title) { index, priority in
                FocusPriorityCard(priority: priority, position: index + 2, onFeedback: { useful in
                    Task { await engine.sendFeedback(item: priority.title, useful: useful) }
                }, onOpen: {
                    selectedPriority = priority
                }, onDismiss: {
                    dismiss(priority)
                })
            }

            // Dismissed priorities (session only)
            let sessionDismissed = brief.priorities.filter { dismissedTitles.contains($0.title) }
            let allIgnored = brief.ignored + sessionDismissed.map(\.title)

            if !allIgnored.isEmpty {
                VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                    Text("Ignored today (\(allIgnored.count))")
                        .font(CortexFont.captionMedium)
                        .foregroundStyle(CortexColor.textTertiary)

                    ForEach(allIgnored, id: \.self) { item in
                        HStack(spacing: CortexSpacing.xs) {
                            Image(systemName: "minus.circle")
                                .font(.caption2)
                                .foregroundStyle(CortexColor.textTertiary)
                            Text(item)
                                .font(CortexFont.caption)
                                .foregroundStyle(CortexColor.textTertiary)
                        }
                    }
                }
                .padding(.top, CortexSpacing.sm)
            }

            // Emerging signals — macOS only, compact
            #if os(macOS)
            if !brief.emergingSignals.isEmpty {
                FlowTags(items: brief.emergingSignals)
                    .padding(.top, CortexSpacing.xs)
            }
            #endif

            if let replay = engine.snapshot?.decisionReplay {
                decisionReplaySummaryCard(replay)
            }

            #if os(macOS)
            if let newsletter = engine.snapshot?.newsletter {
                newsletterSummaryCard(newsletter)
            }
            #endif

            if let resurfaced = engine.snapshot?.resurfacedNow, !resurfaced.isEmpty {
                resurfacedSummaryCard(resurfaced)
            }
        }
        .padding(CortexSpacing.xl)
    }

    @ViewBuilder
    private var focusStatusStrip: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            if let status = engine.lastSyncStatus {
                Label(status, systemImage: focusSyncIcon)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updated = lastUpdatedLabel {
                Text(updated)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var focusSyncIcon: String {
        switch engine.iCloudSyncState {
        case .synced: "checkmark.icloud"
        case .disabled: "internaldrive"
        case .localOnly: "icloud.slash"
        case .waitingForKey: "key.icloud"
        case .storageFull: "externaldrive.badge.exclamationmark"
        case .failed: "exclamationmark.icloud"
        }
    }

    private func dismiss(_ priority: SyncPriority) {
        _ = withAnimation(.easeOut(duration: 0.25)) {
            dismissedTitles.insert(priority.title)
        }
        // Send "not useful" feedback — best-effort, never blocks
        Task { await engine.sendFeedback(item: priority.title, useful: false) }
    }

    #if os(macOS)
    private func triggerSync() {
        Task { await engine.sync() }
    }

    private var todayShareText: String? {
        guard let shareText = engine.snapshot?.today?.shareText else { return nil }
        let trimmed = shareText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    #endif

    private var lastUpdatedLabel: String? {
        guard let raw = engine.snapshot?.syncedAt,
              let date = ISO8601DateFormatter().date(from: raw) else { return nil }

        if abs(date.timeIntervalSinceNow) < 60 {
            return "Updated just now"
        }

        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return "Updated \(rel.localizedString(for: date, relativeTo: Date()))"
    }

    @ViewBuilder
    private func decisionReplaySummaryCard(_ replay: SyncDecisionReplay) -> some View {
        Button {
            openDecisionReplay()
        } label: {
            HStack(alignment: .top, spacing: CortexSpacing.md) {
                VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                    Text("Decision Replay")
                        .font(CortexFont.captionMedium)
                        .foregroundStyle(CortexColor.textPrimary)
                    Text("\(replay.signalsReviewed) reviewed • \(replay.signalsIgnored) ignored • \(replay.finalPriorities.count) selected")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(CortexColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cortexSurfaceCard(padding: CortexSpacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Decision Replay")
    }

    private func openDecisionReplay() {
        #if os(iOS)
        showDecisionReplay = true
        #else
        onRequestDecisionReplay?()
        #endif
    }

    @ViewBuilder
    private func newsletterSummaryCard(_ newsletter: SyncNewsletter) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Draft")
                    .font(CortexFont.captionMedium)
                    .foregroundStyle(CortexColor.textPrimary)
                Spacer()
                Text(newsletter.safeToPublish ? "Checks passed" : "Needs review")
                    .font(CortexFont.caption)
                    .foregroundStyle(newsletter.safeToPublish ? CortexColor.success : CortexColor.warning)
            }

            Text(newsletter.title.isEmpty ? "Newsletter draft ready" : newsletter.title)
                .font(CortexFont.bodyMedium)
                .foregroundStyle(CortexColor.textPrimary)

            if !newsletter.preview.isEmpty {
                Text(newsletter.preview)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
                    .lineLimit(3)
            }

            if !engine.demoModeEnabled,
               newsletter.isApprovedForSharing,
               let share = newsletterShareText(newsletter) {
                ShareLink(item: share) {
                    Label("Share approved draft", systemImage: "square.and.arrow.up")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cortexSurfaceCard(padding: CortexSpacing.md)
    }

    private func newsletterShareText(_ newsletter: SyncNewsletter) -> String? {
        let lines = [newsletter.title, newsletter.subtitle, newsletter.preview]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.isEmpty {
            return nil
        }
        return lines.joined(separator: "\n\n")
    }

    @ViewBuilder
    private func resurfacedSummaryCard(_ items: [SyncRankedSignal]) -> some View {
        if let item = items.first {
            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                Text("Resurfaced")
                    .font(CortexFont.captionMedium)
                    .foregroundStyle(CortexColor.textTertiary)

                Text(item.title)
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)

                Text(item.resurfacingExplanation ?? item.explainability.whyItSurfaced)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
                    .lineLimit(2)

                Text("Next: \(item.nextAction)")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.accent)

                HStack(spacing: CortexSpacing.sm) {
                    Button("Act now") {
                        Task { await engine.applyResurfacingAction(signalID: item.signalID, actionType: "acted_on") }
                    }
                    .buttonStyle(CortexPrimaryButtonStyle())

                    Button("Snooze") {
                        Task { await engine.applyResurfacingAction(signalID: item.signalID, actionType: "snoozed") }
                    }
                    .buttonStyle(CortexSecondaryButtonStyle())

                    Button("Dismiss") {
                        Task { await engine.applyResurfacingAction(signalID: item.signalID, actionType: "dismissed") }
                    }
                    .buttonStyle(CortexSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cortexSurfaceCard(padding: CortexSpacing.md)
        }
    }
}

// MARK: - Hero Priority Card (#1 — visually elevated, calm)

private struct HeroPriorityCard: View {
    let priority: SyncPriority
    let onFeedback: (Bool) -> Void
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            // Rank indicator — calm, not branded
            Text("#1")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CortexColor.accentText)

            // Priority title — large, clear
            Text(priority.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CortexColor.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)

            // Why
            if !priority.whyItMatters.isEmpty {
                Text(priority.whyItMatters)
                    .font(CortexFont.body)
                    .foregroundStyle(CortexColor.textSecondary)
                    .lineLimit(3)
            }

            // Next step
            if !priority.nextStep.isEmpty {
                VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                    Text("Next action")
                        .font(CortexFont.captionMedium)
                        .foregroundStyle(CortexColor.textTertiary)
                    HStack(alignment: .top, spacing: CortexSpacing.sm) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(CortexColor.accentText)
                            .padding(.top, 2)
                        Text(priority.nextStep)
                            .font(CortexFont.bodyMedium)
                            .foregroundStyle(CortexColor.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, CortexSpacing.xxs)
            }

            // Feedback — one-tap on both iOS and macOS
            FeedbackRow(onFeedback: onFeedback)
        }
        .padding(CortexSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                .fill(CortexColor.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                        .strokeBorder(CortexColor.accent.opacity(0.12), lineWidth: 1)
                )
        )
        .cortexShadow()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        #if os(iOS)
        .contextMenu {
            Button(role: .destructive) { onDismiss() } label: {
                Label("Ignore today", systemImage: "eye.slash")
            }
        }
        #endif
    }
}

// MARK: - Focus Priority Card (#2+)

private struct FocusPriorityCard: View {
    let priority: SyncPriority
    let position: Int
    let onFeedback: (Bool) -> Void
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            HStack(alignment: .top, spacing: CortexSpacing.md) {
                Text("\(position)")
                    .font(CortexFont.captionMedium)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(CortexColor.rank(position))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                    Text(priority.title)
                        .font(CortexFont.bodyMedium)
                        .foregroundStyle(CortexColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(2)

                    if !priority.whyItMatters.isEmpty {
                        Text(priority.whyItMatters)
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !priority.nextStep.isEmpty {
                        Label {
                            Text(priority.nextStep)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.accentText)
                    }
                }

                Spacer(minLength: 0)
            }

            // Feedback — one-tap on both iOS and macOS
            FeedbackRow(onFeedback: onFeedback)
        }
        .cortexSurfaceCard(padding: CortexSpacing.md)
        .onTapGesture(perform: onOpen)
        #if os(iOS)
        .contextMenu {
            Button(role: .destructive) { onDismiss() } label: {
                Label("Ignore today", systemImage: "eye.slash")
            }
        }
        #endif
    }
}

// MARK: - Shared feedback row (macOS research flow)

private struct FeedbackRow: View {
    let onFeedback: (Bool) -> Void

    @State private var feedbackGiven: Bool? = nil

    var body: some View {
        Group {
            if feedbackGiven == nil {
                HStack(spacing: CortexSpacing.md) {
                    Spacer()
                    feedbackButton(title: "Useful", icon: "hand.thumbsup", value: true)
                    feedbackButton(title: "Not useful", icon: "hand.thumbsdown", value: false)
                }
            } else {
                HStack {
                    Spacer()
                    Label("Noted", systemImage: "checkmark")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .padding(.top, CortexSpacing.xs)
    }

    @ViewBuilder
    private func feedbackButton(title: String, icon: String, value: Bool) -> some View {
        Button { submit(value) } label: {
            Label(title, systemImage: icon)
                .font(CortexFont.captionMedium)
        }
        .buttonStyle(CortexChipButtonStyle(prominent: value))
    }

    private func submit(_ useful: Bool) {
        withAnimation(.easeOut(duration: 0.2)) {
            feedbackGiven = useful
        }
        onFeedback(useful)
    }
}

// MARK: - Priority detail

private struct PriorityDetailSheet: View {
    let priority: SyncPriority
    let onFeedback: (Bool, Bool?) -> Void
    let onIgnore: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                    Text(priority.title)
                        .font(CortexFont.title)
                        .foregroundStyle(CortexColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !priority.whyItMatters.isEmpty {
                        detailBlock(
                            label: "Why this matters",
                            value: priority.whyItMatters
                        )
                    }

                    if !priority.nextStep.isEmpty {
                        detailBlock(
                            label: "Next action",
                            value: priority.nextStep
                        )
                    }

                    if !priority.source.isEmpty {
                        detailBlock(
                            label: "Source",
                            value: priority.source
                        )
                    }

                    if !priority.tags.isEmpty {
                        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                            Text("Context")
                                .font(CortexFont.captionMedium)
                                .foregroundStyle(CortexColor.textTertiary)
                            FlowTags(items: priority.tags)
                        }
                    }

                    VStack(spacing: CortexSpacing.sm) {
                        Button {
                            onFeedback(true, true)
                            dismiss()
                        } label: {
                            Label("Mark as acted", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))

                        Button {
                            onFeedback(false, false)
                            dismiss()
                        } label: {
                            Label("Mark not useful", systemImage: "hand.thumbsdown")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))

                        Button(role: .destructive) {
                            onIgnore()
                            dismiss()
                        } label: {
                            Label("Ignore today", systemImage: "eye.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
                    }
                    .padding(.top, CortexSpacing.sm)
                }
                .padding(CortexSpacing.xl)
            }
            .background(CortexColor.bgPrimary)
            .navigationTitle("Priority")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func detailBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            Text(label)
                .font(CortexFont.captionMedium)
                .foregroundStyle(CortexColor.textTertiary)
            Text(value)
                .font(CortexFont.body)
                .foregroundStyle(CortexColor.textPrimary)
        }
    }
}

// MARK: - Flow tags

struct FlowTags: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CortexSpacing.xs) {
                ForEach(items, id: \.self) { item in
                    ContextTag(text: item)
                }
            }
        }
    }
}
