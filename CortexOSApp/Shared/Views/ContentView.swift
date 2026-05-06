//
//  ContentView.swift
//  CortexOS
//
//  Root navigation — calm, focused, minimal.
//  iOS: Focus / Capture. Open → Understand → Capture → Close.
//  macOS: Focus / Notes / Insights / Decisions / Memory / Weekly Review.
//  Quiet workbench.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = CortexEngine()
    @AppStorage("simplixio_onboarding_completed") private var onboardingCompleted = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            #if os(iOS)
            iOSRoot
            #else
            macOSRoot
            #endif
        }
        .sheet(isPresented: $showOnboarding) {
            SimpliXioOnboardingView(
                showOnboarding: $showOnboarding,
                onboardingCompleted: $onboardingCompleted
            )
            .environmentObject(engine)
        }
        .task {
            if !onboardingCompleted {
                showOnboarding = true
            }
        }
    }

    // MARK: - iOS (Focus / Capture)

    #if os(iOS)
    @State private var showSettings = false
    @State private var showReview = false
    @State private var selectedTab: IOSTab = .focus
    @StateObject private var routeCenter = SimpliXioRouteCenter.shared

    private var iOSRoot: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DailyFocusView(onRequestCapture: {
                    selectedTab = .capture
                })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showReview = true } label: {
                                Image(systemName: "clock")
                                    .foregroundStyle(CortexColor.textTertiary)
                            }
                            .accessibilityLabel("Review history")
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                selectedTab = .capture
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .foregroundStyle(CortexColor.accent)
                            }
                            .accessibilityLabel("Capture")

                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(CortexColor.textTertiary)
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
            }
            .tag(IOSTab.focus)
            .tabItem { Label("Focus", systemImage: "target") }

            NavigationStack { QuickCaptureView() }
                .tag(IOSTab.capture)
                .tabItem { Label("Capture", systemImage: "square.and.pencil") }
        }
        .tint(CortexColor.accent)
        .environmentObject(engine)
        .task {
            await engine.sync()
        }
        .onOpenURL { url in
            routeCenter.handle(url: url)
        }
        .onReceive(routeCenter.$pendingRoute.compactMap { $0 }) { route in
            switch route {
            case .focus:
                selectedTab = .focus
            case .capture:
                selectedTab = .capture
            }
            routeCenter.pendingRoute = nil
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(engine)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                }
            }
        }
        .sheet(isPresented: $showReview) {
            NavigationStack {
                HistoryView()
                    .environmentObject(engine)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showReview = false }
                        }
                    }
            }
        }
    }

    enum IOSTab: Hashable {
        case focus
        case capture
    }
    #endif

    // MARK: - macOS (Focus / Notes / Insights / Decisions / Memory / Weekly Review)

    #if os(macOS)
    @State private var selection: MacSection? = .focus
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var macOSRoot: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                sidebarGroup("Now", items: MacSection.coreSidebar)
                sidebarGroup("Review", items: MacSection.reviewSidebar)
                sidebarGroup("Create", items: MacSection.publishSidebar)
                sidebarGroup("Control", items: MacSection.systemSidebar)
            }
            .navigationTitle("SimpliXio")
            .listStyle(.sidebar)
            .foregroundStyle(CortexColor.textPrimary)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            switch selection {
            case .focus:       DailyFocusView()
            case .capture:     QuickCaptureView()
            case .notes:       KnowledgeListView()
            case .insights:    InsightFeedView()
            case .decisions:   DecisionHistoryView()
            case .memory:      MemoryExplorerView()
            case .weeklyReview: WeeklyReviewView()
            case .decisionReplay: DecisionReplayView()
            case .signalQueues: SignalWorkbenchView()
            case .recurringPatterns: SignalWorkbenchView(focus: .recurringPatterns)
            case .unresolvedTensions: SignalWorkbenchView(focus: .unresolvedTensions)
            case .contentCandidates: SignalWorkbenchView(focus: .contentCandidates)
            case .newsletter: NewsletterWorkbenchView()
            case .settings:    SettingsView()
            case nil:          DailyFocusView()
            }
        }
        .onChange(of: selection) { _, _ in
            // Keep the workbench navigation stable when switching sections.
            columnVisibility = .all
        }
        .onAppear {
            if selection == nil {
                selection = .focus
            }
            columnVisibility = .all
        }
        .environmentObject(engine)
        .frame(minWidth: 800, minHeight: 500)
        .task {
            await engine.sync()
        }
    }

    @ViewBuilder
    private func sidebarGroup(_ title: String, items: [MacSection]) -> some View {
        Text(title.uppercased())
            .font(CortexFont.captionMedium)
            .foregroundStyle(CortexColor.textTertiary)
            .padding(.top, CortexSpacing.xs)
            .padding(.bottom, CortexSpacing.xxs)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 2, trailing: 10))
            .listRowSeparator(.hidden)

        ForEach(items, id: \.self) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
                .accessibilityLabel(section.title)
                .accessibilityIdentifier("sidebar.\(section.accessibilityID)")
        }
    }

    enum MacSection: Hashable, CaseIterable {
        case focus, capture, notes, insights, decisions, memory, weeklyReview, decisionReplay, signalQueues, recurringPatterns, unresolvedTensions, contentCandidates, newsletter, settings

        static let coreSidebar: [MacSection] = [
            .focus,
            .capture,
            .notes,
            .insights,
            .decisions,
            .memory,
        ]

        static let reviewSidebar: [MacSection] = [
            .weeklyReview,
            .decisionReplay,
            .signalQueues,
            .recurringPatterns,
            .unresolvedTensions,
            .contentCandidates,
        ]

        static let publishSidebar: [MacSection] = [
            .newsletter,
        ]

        static let systemSidebar: [MacSection] = [
            .settings,
        ]

        var title: String {
            switch self {
            case .focus: "Focus"
            case .capture: "Capture"
            case .notes: "Notes"
            case .insights: "Insights"
            case .decisions: "Decisions"
            case .memory: "Memory"
            case .weeklyReview: "Weekly Review"
            case .decisionReplay: "Decision Replay"
            case .signalQueues: "Review Queue"
            case .recurringPatterns: "Recurring Patterns"
            case .unresolvedTensions: "Unresolved Tensions"
            case .contentCandidates: "Content Candidates"
            case .newsletter: "Newsletter"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .focus: "target"
            case .capture: "square.and.pencil"
            case .notes: "doc.text"
            case .insights: "lightbulb"
            case .decisions: "checkmark.seal"
            case .memory: "brain.head.profile"
            case .weeklyReview: "calendar.badge.clock"
            case .decisionReplay: "arrow.triangle.branch"
            case .signalQueues: "list.bullet.rectangle"
            case .recurringPatterns: "waveform.path.ecg"
            case .unresolvedTensions: "exclamationmark.triangle"
            case .contentCandidates: "doc.text"
            case .newsletter: "newspaper"
            case .settings: "gearshape"
            }
        }

        var accessibilityID: String {
            switch self {
            case .focus: "focus"
            case .capture: "capture"
            case .notes: "notes"
            case .insights: "insights"
            case .decisions: "decisions"
            case .memory: "memory"
            case .weeklyReview: "weeklyReview"
            case .decisionReplay: "decisionReplay"
            case .signalQueues: "reviewQueue"
            case .recurringPatterns: "recurringPatterns"
            case .unresolvedTensions: "unresolvedTensions"
            case .contentCandidates: "contentCandidates"
            case .newsletter: "newsletter"
            case .settings: "settings"
            }
        }
    }
    #endif
}

#Preview {
    ContentView()
}

private struct SimpliXioOnboardingView: View {
    @EnvironmentObject private var engine: CortexEngine
    @Binding var showOnboarding: Bool
    @Binding var onboardingCompleted: Bool
    @State private var isPreparingDemo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                    VStack(alignment: .leading, spacing: CortexSpacing.sm) {
                        Text("SimpliXio")
                            .font(CortexFont.largeTitle)
                            .foregroundStyle(CortexColor.textPrimary)

                        Text("Turn scattered thoughts, project noise, and open loops into 3 priorities and one next action.")
                            .font(CortexFont.title)
                            .foregroundStyle(CortexColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: CortexSpacing.md) {
                        onboardingRow(
                            icon: "square.and.pencil",
                            title: "Capture messy input",
                            message: "Save thoughts, links, decisions, questions, and tensions in seconds. Sort later."
                        )
                        onboardingRow(
                            icon: "target",
                            title: "Get 3 priorities",
                            message: "SimpliXio filters scattered thoughts and project noise into what matters now."
                        )
                        onboardingRow(
                            icon: "lightbulb",
                            title: "Understand why",
                            message: "Each priority explains why it matters before you act."
                        )
                        onboardingRow(
                            icon: "arrow.right.circle",
                            title: "Take one action",
                            message: "Move on one concrete next step instead of juggling everything."
                        )
                        onboardingRow(
                            icon: "checkmark.seal",
                            title: "Improve with feedback",
                            message: "Mark what was useful, skipped, or done so future priorities get sharper."
                        )
                    }

                    Text("You can stay fully offline, or connect a server later in Settings.")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                    Text("Private by default. Public output is redacted, and you stay in control.")
                        .font(CortexFont.caption)
                        .foregroundStyle(CortexColor.textTertiary)
                }
                .padding(CortexSpacing.xl)
            }
            .background(CortexColor.bgPrimary)
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: CortexSpacing.sm) {
                    Button {
                        finish()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .imageScale(.medium)
                            Text("Start")
                                .font(CortexFont.bodyMedium.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
                    .accessibilityHint("Continue with your own data")

                    Button {
                        Task {
                            isPreparingDemo = true
                            await engine.populateDemoContent()
                            isPreparingDemo = false
                            finish()
                        }
                    } label: {
                        HStack {
                            if isPreparingDemo {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(CortexColor.accent)
                            }
                            Image(systemName: "sparkles")
                                .imageScale(.medium)
                            Text("Preview 3 priorities")
                                .font(CortexFont.bodyMedium.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(CortexSecondaryButtonStyle(fullWidth: true))
                    .disabled(isPreparingDemo)
                    .opacity(isPreparingDemo ? 0.7 : 1.0)
                    .accessibilityHint("Preview SimpliXio with example priorities and notes")
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, CortexSpacing.xl)
                .padding(.vertical, CortexSpacing.sm)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func onboardingRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: CortexSpacing.md) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(CortexColor.accent)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
                Text(title)
                    .font(CortexFont.bodyMedium)
                    .foregroundStyle(CortexColor.textPrimary)
                Text(message)
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.textSecondary)
            }
        }
    }

    private func finish() {
        onboardingCompleted = true
        showOnboarding = false
    }
}
