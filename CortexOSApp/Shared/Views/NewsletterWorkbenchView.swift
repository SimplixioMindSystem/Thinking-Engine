import SwiftUI

struct NewsletterWorkbenchView: View {
    @EnvironmentObject private var engine: CortexEngine

    @State private var selectedSource: SourcePreset = .last7Days
    @State private var selectedMode: DraftMode = .weeklyLessons
    @State private var isGeneratingDraft = false
    @State private var isUpdatingApproval = false
    @State private var draftMarkdown = ""
    @State private var hasReviewedDraft = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                header
                statusStrip
                sourceControls
                safetyCard
                sourceQualityCard
                previewCard
                reviewCard
                actions
            }
            .padding(CortexSpacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(CortexColor.bgPrimary)
        .navigationTitle("Newsletter")
        .task(id: engine.snapshot?.newsletter?.generatedAt) {
            loadDraftForReview()
            hasReviewedDraft = false
        }
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
        if engine.demoModeEnabled {
            statusPill(
                label: "Preview content",
                systemImage: "eye",
                color: CortexColor.warning
            )
        }
        statusPill(
            label: "Private by default",
            systemImage: "lock.fill",
            color: CortexColor.textSecondary
        )
        statusPill(
            label: "On-device redaction",
            systemImage: "shield.lefthalf.filled",
            color: CortexColor.accent
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

            Label("Drafting and safety checks run on this device.", systemImage: "cpu")
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

            if engine.snapshot?.newsletter == nil {
                Text("Source counts appear after local redaction and safety checks run.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
            } else {
                HStack(spacing: CortexSpacing.lg) {
                    metric("Sources", "\(total)")
                    metric("Usable", "\(usable)")
                    metric("Quality", "\(Int(quality * 100))%")
                }
            }
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private var previewCard: some View {
        if let newsletter = engine.snapshot?.newsletter {
            VStack(alignment: .leading, spacing: CortexSpacing.sm) {
                Text(previewTitle(newsletter))
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
                }

                HStack(spacing: CortexSpacing.sm) {
                    Text(displayStatus(newsletter.status))
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                    if !newsletter.generatedAt.isEmpty {
                        Text("• \(formattedUpdate(newsletter.generatedAt))")
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
                let automatedSafetyPassed = newsletter.safetyReport?.safeToPublish == true
                Text(automatedSafetyPassed ? "Automated safety check passed" : "Needs safety review")
                    .font(CortexFont.caption)
                    .foregroundStyle(automatedSafetyPassed ? CortexColor.success : CortexColor.warning)

                Text(approvalSummary(newsletter))
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)

                if let notes = newsletter.safetyReport?.remainingConcerns, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                        Text(automatedSafetyPassed ? "Safety actions" : "Remaining concerns")
                            .font(CortexFont.captionMedium)
                            .foregroundStyle(CortexColor.textSecondary)
                        ForEach(notes, id: \.self) { note in
                            Label(note, systemImage: automatedSafetyPassed ? "checkmark" : "exclamationmark.triangle")
                                .font(CortexFont.caption)
                                .foregroundStyle(automatedSafetyPassed ? CortexColor.textSecondary : CortexColor.warning)
                        }
                    }
                }

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
                Text("Private by default. SimpliXio redacts locally, then leaves every draft for your approval.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
            }
        }
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private var reviewCard: some View {
        if let newsletter = engine.snapshot?.newsletter {
            VStack(alignment: .leading, spacing: CortexSpacing.md) {
                Label("Review draft", systemImage: "doc.text.magnifyingglass")
                    .font(CortexFont.headline)
                    .foregroundStyle(CortexColor.textPrimary)

                if draftMarkdown.isEmpty {
                    Text("The local Markdown draft could not be opened. Generate it again before approval.")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.warning)
                } else {
                    Text(draftMarkdown)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Full newsletter draft")

                    if engine.demoModeEnabled {
                        Label("Preview drafts stay private on this device", systemImage: "lock.fill")
                            .font(CortexFont.captionMedium)
                            .foregroundStyle(CortexColor.textSecondary)
                    } else if newsletter.status == "approved" {
                        Label("Approved by you", systemImage: "checkmark.seal.fill")
                            .font(CortexFont.captionMedium)
                            .foregroundStyle(CortexColor.success)
                    } else if newsletter.status == "rejected" {
                        Label("Rejected by you. Nothing was shared.", systemImage: "xmark.circle.fill")
                            .font(CortexFont.captionMedium)
                            .foregroundStyle(CortexColor.warning)
                    } else if newsletter.status == "needs_review" {
                        Toggle("I reviewed the full draft", isOn: $hasReviewedDraft)
                            .font(CortexFont.bodyMedium)
                    }
                }
            }
            .cortexSurfaceCard()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            VStack(spacing: CortexSpacing.sm) {
                approvalButton
                shareButton
                draftButton
                rejectionButton
            }
            .frame(maxWidth: 420)

            if let status = engine.newsletterStatus, !status.isEmpty {
                Text(status)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textTertiary)
            } else if !hasPotentialSourceMaterial {
                Text("Add a recent capture or decision to create a draft.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var draftButton: some View {
        if shouldEmphasizeDraftGeneration {
            generateDraftButton
                .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
        } else {
            generateDraftButton
                .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
        }
    }

    private var generateDraftButton: some View {
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
                Text(primaryDraftButtonTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!canGenerate || isGeneratingDraft)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let newsletter = engine.snapshot?.newsletter,
           newsletter.isApprovedForSharing,
           !engine.demoModeEnabled {
            let url = URL(fileURLWithPath: newsletter.markdownPath)
            ShareLink(item: url) {
                Label("Share Markdown", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
        } else if engine.demoModeEnabled, engine.snapshot?.newsletter != nil {
            Label("Preview drafts stay on this device", systemImage: "lock.fill")
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textSecondary)
        }
    }

    @ViewBuilder
    private var approvalButton: some View {
        if let newsletter = engine.snapshot?.newsletter,
           newsletter.status == "needs_review",
           !engine.demoModeEnabled {
            Button {
                Task {
                    isUpdatingApproval = true
                    defer { isUpdatingApproval = false }
                    _ = await engine.approveNewsletterDraft()
                }
            } label: {
                HStack(spacing: CortexSpacing.xs) {
                    if isUpdatingApproval {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label("Approve after review", systemImage: "checkmark.seal")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
            .disabled(!canApprove || isUpdatingApproval)
        }
    }

    @ViewBuilder
    private var rejectionButton: some View {
        if let newsletter = engine.snapshot?.newsletter,
           newsletter.status == "needs_review",
           !engine.demoModeEnabled {
            Button {
                Task {
                    isUpdatingApproval = true
                    defer { isUpdatingApproval = false }
                    await engine.rejectNewsletterDraft()
                }
            } label: {
                Label("Reject draft", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
            .disabled(isUpdatingApproval)
        }
    }

    private func previewTitle(_ newsletter: SyncNewsletter) -> String {
        let title = newsletter.title.isEmpty ? "Latest draft" : newsletter.title
        return engine.demoModeEnabled ? "Preview: \(title)" : title
    }

    private func displayStatus(_ status: String) -> String {
        switch status {
        case "needs_review": "Needs review"
        case "approved": "Approved"
        case "rejected": "Rejected"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func formattedUpdate(_ rawValue: String) -> String {
        let parser = ISO8601DateFormatter()
        var date = parser.date(from: rawValue)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = parser.date(from: rawValue)
        }
        guard let date else { return "Updated recently" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private var canGenerate: Bool {
        !engine.isSyncing && !isGeneratingDraft && !isUpdatingApproval && hasPotentialSourceMaterial
    }

    private var canApprove: Bool {
        guard let newsletter = engine.snapshot?.newsletter else { return false }
        return !draftMarkdown.isEmpty &&
            hasReviewedDraft &&
            newsletter.isEligibleForApproval
    }

    private var shouldEmphasizeDraftGeneration: Bool {
        guard let newsletter = engine.snapshot?.newsletter else { return true }
        return engine.demoModeEnabled || newsletter.status == "rejected"
    }

    private var hasPotentialSourceMaterial: Bool {
        let days = selectedSource == .last30Days ? 30 : 7
        let start = Calendar.current.date(
            byAdding: .day,
            value: -(days - 1),
            to: Calendar.current.startOfDay(for: Date())
        ) ?? .distantPast

        let hasRecentNote = engine.notes.contains { note in
            !note.archived &&
                (engine.demoModeEnabled || !note.id.hasPrefix("demo-note-")) &&
                sourceDate(note.updatedAt, fallback: note.createdAt) >= start
        }
        let hasRecentDecision = engine.snapshot?.recentDecisions.contains { decision in
            (engine.demoModeEnabled || !decision.id.hasPrefix("demo-decision-")) &&
                sourceDate(decision.createdAt) >= start
        } ?? false

        return hasRecentNote || hasRecentDecision
    }

    private func sourceDate(_ primary: String, fallback: String = "") -> Date {
        parseISODate(primary) ?? parseISODate(fallback) ?? .distantPast
    }

    private func parseISODate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private var primaryDraftButtonTitle: String {
        if isGeneratingDraft {
            return "Generating..."
        }
        return engine.snapshot?.newsletter == nil ? "Create private draft" : "Regenerate private draft"
    }

    private func approvalSummary(_ newsletter: SyncNewsletter) -> String {
        switch newsletter.status {
        case "approved":
            return "Approved by you. Sharing is still a separate manual action."
        case "rejected":
            return "Rejected by you. Nothing was shared."
        default:
            return "Review the full draft and approve it before sharing."
        }
    }

    private func loadDraftForReview() {
        guard let path = engine.snapshot?.newsletter?.markdownPath,
              !path.isEmpty,
              let markdown = try? String(contentsOfFile: path, encoding: .utf8) else {
            draftMarkdown = ""
            return
        }
        draftMarkdown = markdown
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
