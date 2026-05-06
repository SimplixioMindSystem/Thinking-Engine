//
//  QuickCaptureView.swift
//  CortexOS
//
//  Capture a thought or decision in seconds.
//  Built for fast input, large writing surfaces, and reliable offline flow.
//

import SwiftUI

struct QuickCaptureView: View {
    @EnvironmentObject private var engine: CortexEngine

    @State private var text = ""
    @State private var mode: CaptureMode = .thought
    @State private var reason = ""
    @State private var saved = false

    @FocusState private var focusedField: FocusField?

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Auto-detect URL in the text.
    private var detectedURL: String? {
        text.split(separator: " ").map(String.init)
            .first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    private var capturedStatusText: String {
        if engine.api.isOffline { return "Captured locally" }
        return engine.isConnected ? "Captured" : "Captured offline"
    }

    private var capturedStatusIcon: String {
        if engine.api.isOffline { return "checkmark.circle.fill" }
        return engine.isConnected ? "checkmark.circle.fill" : "arrow.clockwise.circle"
    }

    private var captureSyncText: String {
        if engine.api.isOffline {
            return "Stored on this device. Add a server later to sync."
        }
        return engine.isConnected ? "Capture syncs automatically." : "Offline capture is queued safely."
    }

    private var captureSyncIcon: String {
        if engine.api.isOffline { return "internaldrive" }
        return engine.isConnected ? "arrow.triangle.2.circlepath" : "tray.and.arrow.up"
    }

    private func captureTitle(from value: String) -> String {
        let compact = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard compact.count > 90 else { return compact }

        let prefix = compact.prefix(87).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                    Text("Capture without sorting first")
                        .font(CortexFont.title)
                        .foregroundStyle(CortexColor.textPrimary)
                    Text("Drop the messy input here. SimpliXio filters it later into priorities, why, and action.")
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                    Text("Kind")
                        .cortexFieldLabel()
                    Picker("Kind", selection: $mode) {
                        ForEach(CaptureMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.menu)
                    #else
                    .pickerStyle(.segmented)
                    #endif
                }

                CaptureEditorCard(
                    title: mode.editorTitle,
                    placeholder: mode.placeholder,
                    text: $text,
                    minHeight: 190,
                    focused: _focusedField,
                    field: .text
                )

                if mode == .decision {
                    CaptureEditorCard(
                        title: "Why",
                        placeholder: "Why this decision?",
                        text: $reason,
                        minHeight: 130,
                        focused: _focusedField,
                        field: .reason
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let url = detectedURL {
                    HStack(spacing: CortexSpacing.xs) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(url)
                            .font(CortexFont.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(CortexColor.accent)
                }

                if saved {
                    Label(
                        capturedStatusText,
                        systemImage: capturedStatusIcon
                    )
                    .font(CortexFont.caption)
                    .foregroundStyle(CortexColor.success)
                    .transition(.opacity)
                }

                Label(
                    captureSyncText,
                    systemImage: captureSyncIcon
                )
                .font(CortexFont.caption)
                .foregroundStyle(CortexColor.textTertiary)
            }
            .padding(CortexSpacing.xl)
        }
        .background(CortexColor.bgPrimary)
        .navigationTitle("Capture")
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: CortexSpacing.md) {
                if focusedField != nil {
                    Button {
                        focusedField = nil
                    } label: {
                        Label("Done", systemImage: "keyboard.chevron.compact.down")
                            .font(CortexFont.captionMedium)
                    }
                    .buttonStyle(CortexSecondaryButtonStyle())
                } else if canSave {
                    Button {
                        text = ""
                        reason = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(CortexFont.captionMedium)
                    }
                    .buttonStyle(CortexSecondaryButtonStyle())
                }

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Capture")
                            .font(CortexFont.bodyMedium)
                        Spacer()
                    }
                }
                .buttonStyle(CortexPrimaryButtonStyle(fullWidth: true))
                .disabled(!canSave)
            }
            .padding(.horizontal, CortexSpacing.xl)
            .padding(.vertical, CortexSpacing.sm)
            .background(.ultraThinMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if focusedField != nil {
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .animation(.easeInOut(duration: 0.2), value: saved)
        .onTapGesture {
            focusedField = nil
        }
    }

    private func save() async {
        focusedField = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let success: Bool

        switch mode {
        case .decision:
            let request = DecisionCreateRequest(
                decision: trimmed,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            success = await engine.recordDecision(request)

        default:
            let note = NoteCreateRequest(
                title: captureTitle(from: trimmed),
                insight: trimmed,
                sourceURL: detectedURL ?? "",
                tags: [mode.noteTag]
            )
            success = await engine.createNote(note)
        }

        guard success else { return }

        withAnimation {
            saved = true
            text = ""
            reason = ""
        }

        try? await Task.sleep(for: .seconds(2))
        withAnimation { saved = false }
    }
}

private struct CaptureEditorCard: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat
    @FocusState var focused: FocusField?
    let field: FocusField

    var body: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xs) {
            Text(title)
                .cortexFieldLabel()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(CortexFont.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(CortexSpacing.sm)
                    .focused($focused, equals: field)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(CortexFont.body)
                        .foregroundStyle(CortexColor.textTertiary)
                        .padding(.top, CortexSpacing.md)
                        .padding(.leading, CortexSpacing.md)
                        .allowsHitTesting(false)
                }
            }
            .background(CortexColor.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CortexRadius.large, style: .continuous))
            .cortexShadow()
        }
    }
}

private enum CaptureMode: String, CaseIterable, Identifiable {
    case thought
    case question
    case tension
    case link
    case reflection
    case decision

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thought: "Thought"
        case .question: "Question"
        case .tension: "Tension"
        case .link: "Link"
        case .reflection: "Reflection"
        case .decision: "Decision"
        }
    }

    var editorTitle: String {
        switch self {
        case .thought: "Thought"
        case .question: "Question"
        case .tension: "Tension"
        case .link: "Link"
        case .reflection: "Reflection"
        case .decision: "Decision"
        }
    }

    var placeholder: String {
        switch self {
        case .thought: "What is taking mental space?"
        case .question: "What question keeps coming back?"
        case .tension: "What feels unresolved or blocked?"
        case .link: "Paste the link and why it matters."
        case .reflection: "What did you notice?"
        case .decision: "What did you decide?"
        }
    }

    var systemImage: String {
        switch self {
        case .thought: "text.bubble"
        case .question: "questionmark.circle"
        case .tension: "exclamationmark.triangle"
        case .link: "link"
        case .reflection: "sparkle.magnifyingglass"
        case .decision: "checkmark.seal"
        }
    }

    var noteTag: String {
        switch self {
        case .thought: "thought"
        case .question: "question"
        case .tension: "tension"
        case .link: "link"
        case .reflection: "reflection"
        case .decision: "decision"
        }
    }
}

private enum FocusField: Hashable {
    case text
    case reason
}
