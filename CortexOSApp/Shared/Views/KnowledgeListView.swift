//
//  KnowledgeListView.swift
//  CortexOS
//
//  Browse, search, and manage knowledge notes.
//  The macOS "Notes" hub. Create, search, import.
//

import SwiftUI

struct KnowledgeListView: View {
    @EnvironmentObject private var engine: CortexEngine
    @State private var searchText: String
    @State private var showingCreateSheet = false
    @State private var showingImportSheet = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let flag = "-UITestSearchQuery"
        let query: String
        if arguments.contains("-UITests"),
           let flagIndex = arguments.firstIndex(of: flag),
           arguments.indices.contains(flagIndex + 1) {
            query = arguments[flagIndex + 1]
        } else {
            query = ""
        }
        _searchText = State(initialValue: query)
    }

    var body: some View {
        List {
            if engine.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if engine.notes.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "doc.text",
                    description: Text("Capture a thought or import a summary to get started.")
                )
            } else {
                ForEach(engine.notes) { note in
                    NavigationLink(value: note) {
                        NoteRowView(note: note)
                    }
                }
                .onDelete(perform: deleteNotes)
            }
        }
        .navigationTitle("Notes")
        .navigationDestination(for: KnowledgeNote.self) { note in
            NoteDetailView(note: note)
        }
        .searchable(text: $searchText, prompt: "Search notes…")
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                await engine.fetchNotes()
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                await engine.searchNotes(query: query)
            } catch {
                // A newer keystroke cancelled this query.
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingImportSheet = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import summary")

                Button { showingCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
                .help("New note")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateNoteView()
        }
        .sheet(isPresented: $showingImportSheet) {
            NavigationStack {
                SummaryIngestView()
                    .environmentObject(engine)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingImportSheet = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
        }
        .refreshable {
            await engine.fetchNotes()
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = engine.notes[index]
            Task { await engine.deleteNote(note.id) }
        }
    }
}

// MARK: - Note Row

struct NoteRowView: View {
    let note: KnowledgeNote

    var body: some View {
        VStack(alignment: .leading, spacing: CortexSpacing.xxs) {
            Text(note.title)
                .font(CortexFont.bodyMedium)
                .foregroundStyle(CortexColor.textPrimary)
                .lineLimit(2)

            HStack(spacing: CortexSpacing.sm) {
                if !note.tags.isEmpty {
                    Text(note.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                        .font(CortexFont.mono)
                        .foregroundStyle(CortexColor.accent)
                }

                Text(note.createdAt.prefix(10))
                    .font(CortexFont.mono)
                    .foregroundStyle(CortexColor.textTertiary)
            }
        }
        .padding(.vertical, CortexSpacing.xxs)
    }
}

// MARK: - Note Detail

struct NoteDetailView: View {
    let note: KnowledgeNote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CortexSpacing.lg) {
                // Title
                Text(note.title)
                    .font(CortexFont.title)
                    .foregroundStyle(CortexColor.textPrimary)

                // Tags
                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: CortexSpacing.xs) {
                            ForEach(note.tags, id: \.self) { tag in
                                ContextTag(text: tag)
                            }
                        }
                    }
                }

                Divider()

                // Sections
                NoteSection(title: "Insight", icon: "lightbulb.fill", text: note.insight)
                NoteSection(title: "Implication", icon: "arrow.right.circle.fill", text: note.implication)
                NoteSection(title: "Action", icon: "checkmark.circle.fill", text: note.action)

                if !note.sourceURL.isEmpty {
                    NoteSection(title: "Source", icon: "link", text: note.sourceURL)
                }

                // Metadata
                Divider()
                HStack {
                    Label(note.createdAt.prefix(10).description, systemImage: "calendar")
                }
                .font(CortexFont.mono)
                .foregroundStyle(CortexColor.textTertiary)
            }
            .padding(CortexSpacing.xl)
        }
        .background(CortexColor.bgPrimary)
        .navigationTitle("Note")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct NoteSection: View {
    let title: String
    let icon: String
    let text: String

    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: CortexSpacing.xs) {
                Label(title, systemImage: icon)
                    .font(CortexFont.captionMedium)
                    .foregroundStyle(CortexColor.textTertiary)
                Text(text)
                    .font(CortexFont.body)
                    .foregroundStyle(CortexColor.textSecondary)
            }
        }
    }
}

// MARK: - Create Note

struct CreateNoteView: View {
    @EnvironmentObject private var engine: CortexEngine
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var insight = ""
    @State private var implication = ""
    @State private var action = ""
    @State private var sourceURL = ""
    @State private var tagsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Note title", text: $title)
                        .textFieldStyle(.plain)
                        .cortexInputSurface()
                }
                Section("Insight") {
                    TextEditor(text: $insight)
                        .scrollContentBackground(.hidden)
                        .cortexInputSurface(minHeight: CortexInput.multiLineMinHeight)
                }
                Section("Implication") {
                    TextEditor(text: $implication)
                        .scrollContentBackground(.hidden)
                        .cortexInputSurface(minHeight: CortexInput.multiLineMinHeight)
                }
                Section("Action") {
                    TextField("Next action", text: $action)
                        .textFieldStyle(.plain)
                        .cortexInputSurface()
                }
                Section("Source URL") {
                    TextField("https://…", text: $sourceURL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textFieldStyle(.plain)
                        .cortexInputSurface()
                }
                Section("Tags (comma-separated)") {
                    TextField("priority, tension, product", text: $tagsText)
                        .textFieldStyle(.plain)
                        .cortexInputSurface()
                }
            }
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func save() async {
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let request = NoteCreateRequest(
            title: title,
            insight: insight,
            implication: implication,
            action: action,
            sourceURL: sourceURL,
            tags: tags
        )
        if await engine.createNote(request) {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        KnowledgeListView()
            .environmentObject(CortexEngine())
    }
}
