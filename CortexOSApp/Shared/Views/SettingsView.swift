//
//  SettingsView.swift
//  CortexOS
//
//  Minimal settings. Connection, identity, about.
//  No dashboard metrics. No developer tools exposed.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: CortexEngine
    @State private var serverURL: String = ""
    @State private var connectionFeedback: ConnectionFeedback?
    @State private var isTesting = false
    @State private var isPreparingDemo = false
    @State private var isRetryingQueue = false
    @State private var showQueueSheet = false

    @AppStorage("cortex_system_name") private var systemName: String = "SimpliXio"
    @AppStorage("cortex_demo_mode_enabled") private var demoModeEnabled: Bool = true

    private let projectURL = URL(string: "https://github.com/SimplixioMindSystem/Thinking-Engine")!
    private let orgURL = URL(string: "https://github.com/SimplixioMindSystem")!
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
            serverURL = engine.api.baseURL
            await engine.checkConnection()
            await engine.refreshPendingSyncActions()
            demoModeEnabled = engine.demoModeEnabled
        }
        .sheet(isPresented: $showQueueSheet) { queueSheet }
    }

    // MARK: - iOS layout

    private var iOSSettingsBody: some View {
        Form {
            connectionSection
            trustSection
            identitySection
            aboutSection
            demoSection
            projectSection
            authorSection
        }
    }

    // MARK: - macOS layout

    private var macSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                settingsCard("Sync") { connectionSectionBody }
                settingsCard("Privacy & Trust") { trustSectionBody }
                settingsCard("Identity") { identitySectionBody }
                settingsCard("About") { aboutSectionBody }
                settingsCard("Sample Data") { demoSectionBody }
                settingsCard("Project") { projectSectionBody }
                settingsCard("Author") { authorSectionBody }
            }
            .padding(CortexSpacing.xl)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CortexColor.bgPrimary)
    }

    // MARK: - Shared sections

    private var connectionSection: some View {
        Section { connectionSectionBody } header: { Text("Sync") }
    }

    @ViewBuilder
    private var connectionSectionBody: some View {
        HStack(spacing: CortexSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(CortexFont.body)
                .foregroundStyle(CortexColor.textPrimary)
            Spacer()
        }

        DisclosureGroup("Server endpoint") {
            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                Text("Server URL")
                    .cortexFieldLabel()
                TextField("https://api.example.com", text: $serverURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .textFieldStyle(.plain)
                    .cortexInputSurface()
                    .onChange(of: serverURL) { _, newValue in
                        engine.api.baseURL = newValue
                    }
            }

            Text("Leave empty to run locally. Captures stay on-device and can sync after you add a server.")
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textTertiary)

            connectionActions
        }

        if engine.pendingSyncActions > 0 {
            Button {
                showQueueSheet = true
            } label: {
                HStack {
                    Label("Waiting to sync", systemImage: "tray.and.arrow.up")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textSecondary)
                    Spacer()
                    Text("\(engine.pendingSyncActions)")
                        .font(CortexFont.captionMedium)
                        .foregroundStyle(CortexColor.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(CortexColor.textTertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var identitySection: some View {
        Section {
            identitySectionBody
        } header: {
            Text("Identity")
        }
    }

    @ViewBuilder
    private var identitySectionBody: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            Text("Display Name")
                .cortexFieldLabel()
            TextField("Name", text: $systemName)
                .textFieldStyle(.plain)
                .cortexInputSurface()
        }
    }

    private var demoSection: some View {
        Section {
            demoSectionBody
        } header: {
            Text("Sample Data")
        }
    }

    @ViewBuilder
    private var demoSectionBody: some View {
        Toggle("Show sample content", isOn: $demoModeEnabled)
            .font(CortexFont.bodyMedium)
            .onChange(of: demoModeEnabled) { _, enabled in
                Task {
                    isPreparingDemo = true
                    await engine.setDemoMode(enabled: enabled)
                    isPreparingDemo = false
                }
            }

        Button {
            Task {
                isPreparingDemo = true
                await engine.populateDemoContent()
                isPreparingDemo = false
            }
        } label: {
            HStack(spacing: CortexSpacing.xs) {
                Text("Load sample priorities")
                if isPreparingDemo {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(CortexSecondaryButtonStyle())
        .disabled(isPreparingDemo)

        Text("Use sample content to understand the product before your own captures build up.")
            .font(CortexFont.caption)
            .foregroundStyle(CortexColor.textTertiary)

        if let status = engine.lastSyncStatus, !status.isEmpty {
            Text(status)
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.accent)
        }
    }

    private var aboutSection: some View {
        Section("About") { aboutSectionBody }
    }

    @ViewBuilder
    private var aboutSectionBody: some View {
        LabeledContent("App", value: "SimpliXio")
        LabeledContent("Purpose", value: "Turn noise into 3 priorities and one next action.")
        LabeledContent("Version", value: appVersionDisplay)
    }

    private var projectSection: some View {
        Section("Project") { projectSectionBody }
    }

    @ViewBuilder
    private var projectSectionBody: some View {
        ShareLink(item: projectURL) {
            HStack(spacing: CortexSpacing.sm) {
                Image(systemName: "square.and.arrow.up.fill")
                    .imageScale(.medium)
                    .foregroundStyle(CortexColor.accentForeground)
                Text("Share Project")
                    .font(CortexFont.bodyMedium.weight(.semibold))
                    .foregroundStyle(CortexColor.accentForeground)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))

        Link(destination: projectURL) {
            settingsLinkRow(icon: "shippingbox.fill", title: "Repository", value: "Thinking-Engine")
        }

        Link(destination: orgURL) {
            settingsLinkRow(icon: "building.2.fill", title: "Organization", value: "SimplixioMindSystem")
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

        Link(destination: URL(string: "https://pierrehenry.dev")!) {
            settingsLinkRow(icon: "globe", title: "Website", value: "pierrehenry.dev")
        }

        Link(destination: orgURL) {
            settingsLinkRow(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub", value: "SimplixioMindSystem")
        }
    }

    private var trustSection: some View {
        Section("Privacy & Trust") { trustSectionBody }
    }

    @ViewBuilder
    private var trustSectionBody: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            trustRow("Private by default.")
            trustRow("Public content is redacted before export.")
            trustRow("No autopublish for sensitive content.")
            trustRow("Private outreach requires approval.")
            trustRow("You stay in control of final decisions.")
        }
        .padding(.vertical, CortexSpacing.xxs)
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

    private func testConnection() async {
        isTesting = true
        connectionFeedback = nil
        defer { isTesting = false }

        await engine.checkConnection()
        if engine.api.isOffline {
            connectionFeedback = .local
        } else {
            connectionFeedback = engine.isConnected ? .success : .failure
        }
    }

    private var statusLabel: String {
        if engine.api.isOffline { return "Local Offline Mode" }
        return engine.isConnected ? "Connected" : "Offline"
    }

    private var statusColor: Color {
        if engine.api.isOffline { return CortexColor.neutral }
        return engine.isConnected ? CortexColor.success : CortexColor.error
    }

    private var queueSheet: some View {
        NavigationStack {
            List {
                Section("Waiting to sync") {
                    LabeledContent("Notes", value: "\(engine.pendingNotes)")
                    LabeledContent("Decisions", value: "\(engine.pendingDecisions)")
                    LabeledContent("Feedback", value: "\(engine.pendingFeedback)")
                    LabeledContent("Total", value: "\(engine.pendingSyncActions)")
                }

                Section("Captured offline") {
                    if engine.queuedActions.isEmpty {
                        Text("Everything is synced.")
                            .font(CortexFont.caption)
                            .foregroundStyle(CortexColor.textTertiary)
                    } else {
                        ForEach(engine.queuedActions) { item in
                            VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                                HStack {
                                    Text(item.kind)
                                        .font(CortexFont.captionMedium)
                                        .foregroundStyle(CortexColor.accent)
                                    Spacer()
                                    Text(item.capturedAt, style: .relative)
                                        .font(CortexFont.caption)
                                        .foregroundStyle(CortexColor.textTertiary)
                                }
                                Text(item.title)
                                    .font(CortexFont.caption)
                                    .foregroundStyle(CortexColor.textPrimary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, CortexSpacing.xxs)
                        }
                    }
                }
            }
            .navigationTitle("Offline Captures")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showQueueSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isRetryingQueue = true
                            await engine.retryPendingSyncActions()
                            isRetryingQueue = false
                        }
                    } label: {
                        if isRetryingQueue {
                            ProgressView()
                        } else {
                            Text("Sync now")
                        }
                    }
                    .buttonStyle(CortexPrimaryButtonStyle())
                    .disabled(isRetryingQueue)
                }
            }
            .task {
                await engine.refreshPendingSyncActions()
            }
        }
    }

    @ViewBuilder
    private var connectionActions: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: CortexSpacing.sm) {
            Button {
                Task { await testConnection() }
            } label: {
                HStack(spacing: CortexSpacing.xs) {
                    Text("Test connection")
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
            .disabled(isTesting)

            Button {
                Task { await engine.sync() }
            } label: {
                HStack(spacing: CortexSpacing.xs) {
                    if engine.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(engine.isSyncing ? "Syncing…" : "Sync now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
            .disabled(engine.isSyncing)
            .onChange(of: engine.isSyncing) { _, syncing in
                if syncing {
                    connectionFeedback = .syncing
                } else if engine.api.isOffline {
                    connectionFeedback = .local
                } else {
                    connectionFeedback = engine.isConnected ? .success : .failure
                }
            }

            if let feedback = connectionFeedback {
                Text(feedback.message)
                    .font(CortexFont.caption)
                    .foregroundStyle(feedback.color)
            }
        }
        #else
        HStack {
            Button {
                Task { await testConnection() }
            } label: {
                HStack(spacing: CortexSpacing.xs) {
                    Text("Test")
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .buttonStyle(CortexSecondaryButtonStyle())
            .disabled(isTesting)

            Button {
                Task { await engine.sync() }
            } label: {
                if engine.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Sync now")
                }
            }
            .buttonStyle(CortexPrimaryButtonStyle())
            .disabled(engine.isSyncing)
            .onChange(of: engine.isSyncing) { _, syncing in
                if syncing {
                    connectionFeedback = .syncing
                } else if engine.api.isOffline {
                    connectionFeedback = .local
                } else {
                    connectionFeedback = engine.isConnected ? .success : .failure
                }
            }

            Spacer()

            if let feedback = connectionFeedback {
                Text(feedback.message)
                    .font(CortexFont.caption)
                    .foregroundStyle(feedback.color)
            }
        }
        #endif
    }
}

// MARK: - Supporting Types

private enum ConnectionFeedback {
    case success, failure, local, syncing

    var message: String {
        switch self {
        case .success: "Connected"
        case .failure: "Unable to connect"
        case .local: "Local mode active"
        case .syncing: "Sync started…"
        }
    }

    var color: Color {
        switch self {
        case .success: CortexColor.success
        case .failure: CortexColor.error
        case .local: CortexColor.neutral
        case .syncing: CortexColor.textSecondary
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
