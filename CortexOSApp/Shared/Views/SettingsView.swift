import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: CortexEngine
    @State private var isPreparingPreview = false

    @AppStorage("cortex_demo_mode_enabled") private var demoModeEnabled = false

    private let projectURL = URL(string: "https://github.com/SimplixioMindSystem/Thinking-Engine")
    private let orgURL = URL(string: "https://github.com/SimplixioMindSystem")
    private let authorWebsiteURL = URL(string: "https://pierrehenry.dev")
    private let authorGitHubURL = URL(string: "https://github.com/pH-7")
    private let authorLinkedInURL = URL(string: "https://www.linkedin.com/in/ph7enry/")
    private var appVersionDisplay: String { Bundle.main.versionWithBuild }

    var body: some View {
        Group {
            #if os(macOS)
            macSettingsBody
            #else
            iOSSettingsBody
            #endif
        }
        .navigationTitle("Settings")
        .task {
            engine.resumeSemanticIndexing()
            await engine.refreshSemanticIndexStatus()
            demoModeEnabled = engine.demoModeEnabled
        }
        .accessibilityIdentifier("settings.screen")
    }

    private var iOSSettingsBody: some View {
        Form {
            syncSection
            trustSection
            semanticMemorySection
            aboutSection
            previewSection
            projectSection
            authorSection
        }
    }

    private var macSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                settingsCard("Private iCloud Sync") { syncSectionBody }
                settingsCard("Privacy & Trust") { trustSectionBody }
                settingsCard("On-device Search") { semanticMemorySectionBody }
                settingsCard("About") { aboutSectionBody }
                settingsCard("Preview Content") { previewSectionBody }
                settingsCard("Project") { projectSectionBody }
                settingsCard("Author") { authorSectionBody }
            }
            .padding(CortexSpacing.xl)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CortexColor.bgPrimary)
    }

    private var syncSection: some View {
        Section("Private iCloud Sync") { syncSectionBody }
    }

    @ViewBuilder
    private var syncSectionBody: some View {
        if !engine.demoModeEnabled {
            Toggle(
                "Sync across Apple devices",
                isOn: Binding(
                    get: { engine.iCloudSyncEnabled },
                    set: { enabled in
                        Task { await engine.setICloudSync(enabled: enabled) }
                    }
                )
            )
            .font(CortexFont.bodyMedium)
        }

        HStack(alignment: .top, spacing: CortexSpacing.sm) {
            Image(systemName: syncStatusIcon)
                .foregroundStyle(syncStatusColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                Text(syncStatusTitle)
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)
                Text(syncStatusDetail)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if engine.isSyncing {
                ProgressView().controlSize(.small)
            }
        }

        if !engine.demoModeEnabled {
            Button {
                Task { await engine.sync() }
            } label: {
                Label(engine.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
            .disabled(engine.isSyncing || !engine.iCloudSyncEnabled)
        }

        Text(syncExplanation)
            .font(CortexFont.caption)
            .foregroundStyle(CortexColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trustSection: some View {
        Section("Privacy & Trust") { trustSectionBody }
    }

    @ViewBuilder
    private var trustSectionBody: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            trustRow("Captures, priorities, reviews, and search are processed on-device.")
            trustRow("Private sync encrypts captures before iCloud; no SimpliXio or third-party app server receives readable content.")
            trustRow("Newsletter drafts are redacted locally and never published automatically.")
            trustRow("Every priority shows why it surfaced and the next action it suggests.")
            trustRow("Your useful, skipped, and done feedback improves future ranking.")
            trustRow("You stay in control of every decision and public export.")
        }
        .padding(.vertical, CortexSpacing.xxs)
    }

    private var semanticMemorySection: some View {
        Section("On-device Search") { semanticMemorySectionBody }
    }

    @ViewBuilder
    private var semanticMemorySectionBody: some View {
        HStack(spacing: CortexSpacing.sm) {
            Image(systemName: semanticStatusIcon)
                .foregroundStyle(semanticStatusColor)
            VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                Text("Private semantic search")
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)
                Text(semanticIndexLabel)
                    .font(CortexFont.caption)
                    .foregroundStyle(semanticStatusColor)
            }
            Spacer()
            if engine.isRebuildingSemanticIndex || semanticIndexIsPreparing {
                ProgressView().controlSize(.small)
            }
        }

        Button {
            Task { await engine.rebuildSemanticIndex() }
        } label: {
            Label("Refresh private search", systemImage: "sparkle.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
        .disabled(engine.isRebuildingSemanticIndex || engine.semanticIndexStatus?.isAvailable != true)

        Text("The search index stays on this device. Search never sends note text to an external model.")
            .font(CortexFont.caption)
            .foregroundStyle(CortexColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var aboutSection: some View {
        Section("About") { aboutSectionBody }
    }

    @ViewBuilder
    private var aboutSectionBody: some View {
        LabeledContent("App", value: "SimpliXio")
        LabeledContent("Promise", value: "3 priorities. Why. Action.")
        LabeledContent("Version", value: appVersionDisplay)
    }

    private var previewSection: some View {
        Section("Preview Content") { previewSectionBody }
    }

    @ViewBuilder
    private var previewSectionBody: some View {
        Toggle("Show clearly marked preview content", isOn: $demoModeEnabled)
            .font(CortexFont.bodyMedium)
            .disabled(isPreparingPreview)
            .onChange(of: demoModeEnabled) { _, enabled in
                Task {
                    isPreparingPreview = true
                    await engine.setDemoMode(enabled: enabled)
                    isPreparingPreview = false
                }
            }

        if isPreparingPreview {
            ProgressView("Preparing preview…")
                .controlSize(.small)
        }

        Text("Preview content is optional, stays on this device, and never replaces your own captures.")
            .font(CortexFont.caption)
            .foregroundStyle(CortexColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var projectSection: some View {
        Section("Project") { projectSectionBody }
    }

    @ViewBuilder
    private var projectSectionBody: some View {
        if let projectURL {
            ShareLink(item: projectURL) {
                Label("Share Project", systemImage: "square.and.arrow.up.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))

            Link(destination: projectURL) {
                settingsLinkRow(icon: "shippingbox.fill", title: "Repository", value: "SimpliXio")
            }
        }
        if let orgURL {
            Link(destination: orgURL) {
                settingsLinkRow(icon: "building.2.fill", title: "Organization", value: "SimplixioMindSystem")
            }
        }
    }

    private var authorSection: some View {
        Section("Author") { authorSectionBody }
    }

    @ViewBuilder
    private var authorSectionBody: some View {
        HStack(alignment: .top, spacing: CortexSpacing.md) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(CortexColor.accent)
            VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                Text("Pierre-Henry Soria")
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)
                Text("I build calm tools that turn noise into clearer decisions and action.")
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let authorWebsiteURL {
            Link(destination: authorWebsiteURL) {
                settingsLinkRow(icon: "globe", title: "Website", value: "pierrehenry.dev")
            }
        }
        if let authorGitHubURL {
            Link(destination: authorGitHubURL) {
                settingsLinkRow(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub", value: "pH-7")
            }
        }
        if let authorLinkedInURL {
            Link(destination: authorLinkedInURL) {
                settingsLinkRow(icon: "person.crop.square", title: "LinkedIn", value: "ph7enry")
            }
        }
    }

    private var syncStatusTitle: String {
        if engine.demoModeEnabled { return "Preview stays on this device" }
        switch engine.iCloudSyncState {
        case .disabled: return "On this device only"
        case .synced: return "Private iCloud sync active"
        case .localOnly: return "Saved locally"
        case .waitingForKey: return "Waiting for private sync key"
        case .storageFull: return "iCloud sync storage is full"
        case .failed: return "iCloud is temporarily unavailable"
        }
    }

    private var syncStatusDetail: String {
        if engine.demoModeEnabled {
            return "Sample content never enters private iCloud sync. Turn off Preview Content to use your own synced captures."
        }
        if let status = engine.lastSyncStatus, !status.isEmpty { return status }
        return engine.iCloudSyncEnabled
            ? "Your private state syncs between iPhone, Mac, and Apple Watch."
            : "Your captures remain available on this device."
    }

    private var syncStatusIcon: String {
        if engine.demoModeEnabled { return "eye" }
        switch engine.iCloudSyncState {
        case .disabled: return "internaldrive"
        case .synced: return "checkmark.icloud.fill"
        case .localOnly: return "icloud.slash"
        case .waitingForKey: return "key.icloud"
        case .storageFull: return "externaldrive.badge.exclamationmark"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        if engine.demoModeEnabled { return CortexColor.textSecondary }
        switch engine.iCloudSyncState {
        case .synced: return CortexColor.success
        case .storageFull, .failed: return CortexColor.warning
        case .disabled, .localOnly, .waitingForKey: return CortexColor.textSecondary
        }
    }

    private var syncExplanation: String {
        if engine.demoModeEnabled {
            return "Preview content is isolated from private iCloud sync. Your own captures can sync after Preview Content is turned off."
        }
        return "Changes save on this device first. If iCloud is unavailable, nothing is lost and sync retries later."
    }

    private var semanticIndexIsPreparing: Bool {
        guard let status = engine.semanticIndexStatus else { return true }
        return status.isAvailable && status.indexedNotes < status.totalNotes
    }

    private var semanticIndexLabel: String {
        guard let status = engine.semanticIndexStatus else { return "Preparing private search…" }
        guard status.isAvailable else { return "Unavailable on this device" }
        guard status.isPersistent else { return "Ready for this session" }
        if status.indexedNotes < status.totalNotes {
            return "Updating \(status.indexedNotes) of \(status.totalNotes) captures"
        }
        return status.totalNotes == 1 ? "Ready for 1 capture" : "Ready for \(status.totalNotes) captures"
    }

    private var semanticStatusIcon: String {
        guard let status = engine.semanticIndexStatus else { return "magnifyingglass.circle" }
        return status.isReady ? "checkmark.circle.fill" : "magnifyingglass.circle"
    }

    private var semanticStatusColor: Color {
        guard let status = engine.semanticIndexStatus else { return CortexColor.neutral }
        if status.isReady { return CortexColor.success }
        if !status.isAvailable || !status.isPersistent { return CortexColor.warning }
        return CortexColor.accent
    }

    @ViewBuilder
    private func trustRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: CortexSpacing.xs) {
            Image(systemName: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(CortexColor.accent)
                .padding(.top, 2)
            Text(text)
                .font(CortexFont.captionMedium)
                .foregroundStyle(CortexColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CortexSpacing.md) {
            Text(title)
                .font(CortexFont.headline)
                .foregroundStyle(CortexColor.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cortexSurfaceCard()
    }

    @ViewBuilder
    private func settingsLinkRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(CortexColor.textPrimary)
            Spacer()
            Text(value)
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textTertiary)
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Bundle {
    var versionWithBuild: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(CortexEngine())
    }
}
