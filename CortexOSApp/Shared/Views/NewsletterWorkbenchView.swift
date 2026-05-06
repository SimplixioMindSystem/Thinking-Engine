import SwiftUI

struct NewsletterWorkbenchView: View {
    @EnvironmentObject private var engine: CortexEngine

    @State private var selectedSource: SourcePreset = .last7Days
    @State private var selectedMode: DraftMode = .weeklyLessons
    @State private var isGeneratingDraft = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                header
                statusStrip
                sourceControls
                safetyCard
                sourceQualityCard
                previewCard
                actions
            }
            .padding(CortexSpacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(CortexColor.bgPrimary)
        .navigationTitle("Newsletter")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            Text("Public-safe draft")
                .font(CortexFont.title)
                .foregroundStyle(CortexColor.textPrimary)

            Text("Turn selected, redacted material into a draft. Nothing publishes automatically.")
                .font(CortexFont.body)
                .foregroundStyle(CortexColor.textSecondary)
        }
    }

    @ViewBuilder
    private var statusStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CortexSpacing.sm) {
                newsletterTrustPills
            }

            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                newsletterTrustPills
            }
        }
    }

    @ViewBuilder
    private var newsletterTrustPills: some View {
        statusPill(
            label: "Private by default",
            systemImage: "lock.fill",
            color: CortexColor.textSecondary
        )
        statusPill(
            label: "Redaction required",
            systemImage: "shield.lefthalf.filled",
            color: CortexColor.warning
        )
        statusPill(
            label: "Manual publish only",
            systemImage: "hand.raised.fill",
            color: CortexColor.accent
        )
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                Text("Source")
                    .cortexFieldLabel()
                Picker("Source", selection: $selectedSource) {
                    ForEach(SourcePreset.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                Text("Mode")
                    .cortexFieldLabel()
                Picker("Mode", selection: $selectedMode) {
                    ForEach(DraftMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Label("Strict safety enabled. Human approval required before publishing.", systemImage: "checkmark.shield")
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textSecondary)
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private var sourceQualityCard: some View {
        let total = engine.snapshot?.newsletter?.sourceCountTotal ?? 0
        let usable = engine.snapshot?.newsletter?.sourceCountUsable ?? 0
        let quality = total > 0 ? Double(usable) / Double(total) : 0

        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            Label("Draft inputs", systemImage: "line.3.horizontal.decrease.circle")
                .font(CortexFont.headline)
                .foregroundStyle(CortexColor.textPrimary)

            HStack(spacing: CortexSpacing.lg) {
                metric("Sources", "\(total)")
                metric("Usable", "\(usable)")
                metric("Quality", "\(Int(quality * 100))%")
            }
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private var previewCard: some View {
        if let newsletter = engine.snapshot?.newsletter {
            VStack(alignment: .leading, spacing: CortexSpacing.sm) {
                Text(newsletter.title.isEmpty ? "Latest draft" : newsletter.title)
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)

                if !newsletter.subtitle.isEmpty {
                    Text(newsletter.subtitle)
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textSecondary)
                }

                if !newsletter.preview.isEmpty {
                    Text(newsletter.preview)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textSecondary)
                        .lineLimit(8)
                }

                HStack(spacing: CortexSpacing.sm) {
                    Text("Status: \(newsletter.status)")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                    if !newsletter.generatedAt.isEmpty {
                        Text("• Updated \(newsletter.generatedAt)")
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.textTertiary)
                    }
                }
            }
            .cortexSurfaceCard()
        } else {
            VStack(alignment: .leading, spacing: CortexSpacing.md) {
                Text("Not enough public-safe material yet")
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)
                Text("Capture thoughts and decisions first. SimpliXio will only draft from material that passes safety checks.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)

                VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                    suggestionRow("Capture a thought", systemImage: "square.and.pencil")
                    suggestionRow("Record a decision", systemImage: "checkmark.seal")
                    suggestionRow("Run Weekly Review", systemImage: "calendar.badge.clock")
                }
            }
            .cortexSurfaceCard()
        }
    }

    @ViewBuilder
    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            Label("Trust", systemImage: "checkmark.shield")
                .font(CortexFont.headline)
                .foregroundStyle(CortexColor.textPrimary)

            if let newsletter = engine.snapshot?.newsletter {
                Text(newsletter.safeToPublish ? "Safe to publish: yes" : "Safe to publish: no")
                    .font(CortexFont.caption)
                    .foregroundStyle(newsletter.safeToPublish ? CortexColor.success : CortexColor.warning)

                if let reasons = newsletter.tasteGate?.reasons, !reasons.isEmpty {
                    Text("Taste gate: \(reasons.joined(separator: ", "))")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
                }

                if let recommendation = newsletter.safetyReport?.recommendation, !recommendation.isEmpty {
                    Text(recommendation)
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textSecondary)
                }
            } else {
                Text("Private by default. Public drafts require redaction, safety checks, and manual approval.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
            }
        }
        .cortexSurfaceCard()
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            #if os(iOS)
            VStack(spacing: CortexSpacing.sm) {
                primaryDraftButton
                shareButton
            }
            #else
            HStack(spacing: CortexSpacing.sm) {
                primaryDraftButton
                shareButton
            }
            #endif

            if let status = engine.newsletterStatus, !status.isEmpty {
                Text("Status: \(status)")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var primaryDraftButton: some View {
        Button {
            Task {
                isGeneratingDraft = true
                defer { isGeneratingDraft = false }
                _ = await engine.generateNewsletterDraft(
                    period: selectedSource.periodValue,
                    mode: selectedMode.modeValue
                )
            }
        } label: {
            HStack(spacing: CortexSpacing.xs) {
                if isGeneratingDraft {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isGeneratingDraft ? "Generating…" : "Draft from safe material")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
        .disabled(!canGenerate || isGeneratingDraft)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let newsletter = engine.snapshot?.newsletter,
           !newsletter.markdownPath.isEmpty {
            let url = URL(fileURLWithPath: newsletter.markdownPath)
            ShareLink(item: url) {
                Label("Share Markdown", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
        }
    }

    private var canGenerate: Bool {
        if engine.isSyncing || isGeneratingDraft {
            return false
        }
        if let count = engine.snapshot?.newsletter?.sourceCountTotal {
            return count > 0
        }
        return true
    }

    @ViewBuilder
    private func statusPill(label: String, systemImage: String, color: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(CortexFont.caption)
            .foregroundStyle(color)
            .padding(.horizontal, CortexSpacing.sm)
            .padding(.vertical, CortexSpacing.xs)
            .background(CortexColor.bgSecondary)
            .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
            Text(label)
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textTertiary)
            Text(value)
                .font(CortexFont.bodyMedium)
                .foregroundStyle(CortexColor.textPrimary)
        }
    }

    @ViewBuilder
    private func suggestionRow(_ label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(CortexFont.caption)
            .foregroundStyle(CortexColor.textSecondary)
    }
}

private extension NewsletterWorkbenchView {
    enum SourcePreset: String, CaseIterable, Identifiable {
        case last7Days
        case last30Days

        var id: String { rawValue }

        var label: String {
            switch self {
            case .last7Days: "Last 7 Days"
            case .last30Days: "Last 30 Days"
            }
        }

        var periodValue: String {
            switch self {
            case .last7Days: "weekly"
            case .last30Days: "monthly"
            }
        }
    }

    enum DraftMode: String, CaseIterable, Identifiable {
        case personalReflection
        case productBuilderNotes
        case weeklyLessons
        case technicalEssay

        var id: String { rawValue }

        var label: String {
            switch self {
            case .personalReflection: "Personal Reflection"
            case .productBuilderNotes: "Product Builder Notes"
            case .weeklyLessons: "Weekly Lessons"
            case .technicalEssay: "Technical Essay"
            }
        }

        var modeValue: String {
            switch self {
            case .personalReflection: "personal-reflection"
            case .productBuilderNotes: "product-builder-notes"
            case .weeklyLessons: "weekly-lessons"
            case .technicalEssay: "technical-essay"
            }
        }
    }
}
