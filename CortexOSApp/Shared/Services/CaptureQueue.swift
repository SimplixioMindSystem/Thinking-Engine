//
//  CaptureQueue.swift
//  CortexOS
//
//  Offline-first note mutations. Captures, edits, and removals are persisted
//  locally before any network request, then delivered in their original order.
//

import Foundation

actor CaptureQueue {
    static let shared = CaptureQueue()

    // MARK: - Types

    struct PendingQueueCounts {
        let notes: Int
        let decisions: Int
        let feedback: Int
        let total: Int
    }

    struct PendingAction: Identifiable {
        let id: String
        let kind: String
        let title: String
        let capturedAt: Date
    }

    struct QueuedNote: Codable, Identifiable, Equatable {
        let id: UUID
        let localNoteID: String?
        var title: String
        var insight: String
        var implication: String
        var action: String
        var sourceURL: String
        var tags: [String]
        var archived: Bool
        let capturedAt: Date

        init(
            id: UUID = UUID(),
            localNoteID: String? = nil,
            title: String,
            insight: String = "",
            implication: String = "",
            action: String = "",
            sourceURL: String = "",
            tags: [String] = [],
            archived: Bool = false,
            capturedAt: Date = Date()
        ) {
            self.id = id
            self.localNoteID = localNoteID
            self.title = title
            self.insight = insight
            self.implication = implication
            self.action = action
            self.sourceURL = sourceURL
            self.tags = tags
            self.archived = archived
            self.capturedAt = capturedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, localNoteID, title, insight, implication, action, tags, archived, capturedAt
            case sourceURL = "source_url"
            case legacySourceURL = "sourceURL"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            localNoteID = try container.decodeIfPresent(String.self, forKey: .localNoteID)
            title = try container.decode(String.self, forKey: .title)
            insight = try container.decodeIfPresent(String.self, forKey: .insight) ?? ""
            implication = try container.decodeIfPresent(String.self, forKey: .implication) ?? ""
            action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
            sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
                ?? container.decodeIfPresent(String.self, forKey: .legacySourceURL)
                ?? ""
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
            capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(localNoteID, forKey: .localNoteID)
            try container.encode(title, forKey: .title)
            try container.encode(insight, forKey: .insight)
            try container.encode(implication, forKey: .implication)
            try container.encode(action, forKey: .action)
            try container.encode(sourceURL, forKey: .sourceURL)
            try container.encode(tags, forKey: .tags)
            try container.encode(archived, forKey: .archived)
            try container.encode(capturedAt, forKey: .capturedAt)
        }

        mutating func apply(_ update: NoteUpdateRequest) {
            title = update.title ?? title
            insight = update.insight ?? insight
            implication = update.implication ?? implication
            action = update.action ?? action
            sourceURL = update.sourceURL ?? sourceURL
            tags = update.tags ?? tags
            archived = update.archived ?? archived
        }

        var createRequest: NoteCreateRequest {
            NoteCreateRequest(
                title: title,
                insight: insight,
                implication: implication,
                action: action,
                sourceURL: sourceURL,
                tags: tags
            )
        }

        func updateRequired(afterCreate serverNote: KnowledgeNote) -> NoteUpdateRequest? {
            let update = NoteUpdateRequest(
                title: title == serverNote.title ? nil : title,
                insight: insight == serverNote.insight ? nil : insight,
                implication: implication == serverNote.implication ? nil : implication,
                action: action == serverNote.action ? nil : action,
                sourceURL: sourceURL == serverNote.sourceURL ? nil : sourceURL,
                tags: tags == serverNote.tags ? nil : tags,
                archived: archived == serverNote.archived ? nil : archived
            )
            return update.isEmpty ? nil : update
        }
    }

    enum NoteMutationOperation: String, Codable, Equatable {
        case update
        case delete
    }

    struct QueuedNoteMutation: Codable, Identifiable, Equatable {
        let id: UUID
        let noteID: String
        let title: String
        let operation: NoteMutationOperation
        var update: NoteUpdateRequest?
        let capturedAt: Date

        init(
            id: UUID = UUID(),
            noteID: String,
            title: String,
            operation: NoteMutationOperation,
            update: NoteUpdateRequest? = nil,
            capturedAt: Date = Date()
        ) {
            self.id = id
            self.noteID = noteID
            self.title = title
            self.operation = operation
            self.update = update
            self.capturedAt = capturedAt
        }
    }

    struct QueuedDecision: Codable, Identifiable {
        let id: UUID
        let decision: String
        let reason: String
        let project: String
        let assumptions: [String]
        let capturedAt: Date
    }

    struct QueuedFeedback: Codable, Identifiable {
        let id: UUID
        let item: String
        let useful: Bool
        let acted: Bool?
        let capturedAt: Date
    }

    // MARK: - State

    private var notes: [QueuedNote] = []
    private var noteMutations: [QueuedNoteMutation] = []
    private var decisions: [QueuedDecision] = []
    private var feedback: [QueuedFeedback] = []

    private let notesURL: URL
    private let noteMutationsURL: URL
    private let decisionsURL: URL
    private let feedbackURL: URL

    init(storageDirectory: URL? = nil) {
        let support = storageDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CortexOS", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )

        notesURL = support.appendingPathComponent("capture_queue_notes.json")
        noteMutationsURL = support.appendingPathComponent("capture_queue_note_mutations.json")
        decisionsURL = support.appendingPathComponent("capture_queue_decisions.json")
        feedbackURL = support.appendingPathComponent("capture_queue_feedback.json")

        if let data = try? Data(contentsOf: notesURL),
           let saved = try? JSONDecoder().decode([QueuedNote].self, from: data) {
            notes = saved
        }
        if let data = try? Data(contentsOf: noteMutationsURL),
           let saved = try? JSONDecoder().decode([QueuedNoteMutation].self, from: data) {
            noteMutations = saved
        }
        if let data = try? Data(contentsOf: decisionsURL),
           let saved = try? JSONDecoder().decode([QueuedDecision].self, from: data) {
            decisions = saved
        }
        if let data = try? Data(contentsOf: feedbackURL),
           let saved = try? JSONDecoder().decode([QueuedFeedback].self, from: data) {
            feedback = saved
        }
    }

    // MARK: - Enqueue

    func enqueueNote(
        localNoteID: String? = nil,
        title: String,
        insight: String = "",
        implication: String = "",
        action: String = "",
        sourceURL: String = "",
        tags: [String] = []
    ) {
        notes.append(
            QueuedNote(
                localNoteID: localNoteID,
                title: title,
                insight: insight,
                implication: implication,
                action: action,
                sourceURL: sourceURL,
                tags: tags
            )
        )
        persistNotes()
    }

    /// Absorbs changes into a pending create instead of sending a patch for an
    /// ID the server has not issued yet.
    func updatePendingNote(localNoteID: String, with update: NoteUpdateRequest) -> Bool {
        guard let index = notes.lastIndex(where: { $0.localNoteID == localNoteID }) else {
            return false
        }
        notes[index].apply(update)
        persistNotes()
        return true
    }

    /// A locally created note can be removed before it ever reaches the
    /// server, so no deletion request is necessary.
    func cancelPendingNote(localNoteID: String) -> Bool {
        let originalCount = notes.count
        notes.removeAll { $0.localNoteID == localNoteID }
        guard notes.count != originalCount else { return false }
        persistNotes()
        return true
    }

    func enqueueNoteUpdate(
        noteID: String,
        title: String,
        with update: NoteUpdateRequest
    ) {
        guard !update.isEmpty else { return }
        guard !noteMutations.contains(where: {
            $0.noteID == noteID && $0.operation == .delete
        }) else {
            return
        }

        if let index = noteMutations.lastIndex(where: {
            $0.noteID == noteID && $0.operation == .update
        }) {
            noteMutations[index].update = merged(
                noteMutations[index].update,
                with: update
            )
        } else {
            noteMutations.append(
                QueuedNoteMutation(
                    noteID: noteID,
                    title: title,
                    operation: .update,
                    update: update
                )
            )
        }
        persistNoteMutations()
    }

    func enqueueNoteDeletion(noteID: String, title: String) {
        noteMutations.removeAll {
            $0.noteID == noteID && $0.operation == .update
        }
        guard !noteMutations.contains(where: {
            $0.noteID == noteID && $0.operation == .delete
        }) else {
            persistNoteMutations()
            return
        }
        noteMutations.append(
            QueuedNoteMutation(noteID: noteID, title: title, operation: .delete)
        )
        persistNoteMutations()
    }

    func enqueueDecision(
        decision: String,
        reason: String = "",
        project: String = "",
        assumptions: [String] = []
    ) {
        decisions.append(
            QueuedDecision(
                id: UUID(),
                decision: decision,
                reason: reason,
                project: project,
                assumptions: assumptions,
                capturedAt: Date()
            )
        )
        persistDecisions()
    }

    func enqueueFeedback(item: String, useful: Bool, acted: Bool? = nil) {
        let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        feedback.append(
            QueuedFeedback(
                id: UUID(),
                item: cleaned,
                useful: useful,
                acted: acted,
                capturedAt: Date()
            )
        )
        persistFeedback()
    }

    // MARK: - Flush

    @MainActor
    func flushNotes(using api: APIService) async -> Int {
        let queued = await queuedNotes()
        var flushed = 0

        for item in queued {
            do {
                let serverNote = try await api.createNoteRemote(item.createRequest)
                guard let current = await completeQueuedCreate(item) else {
                    // The local note was deleted while its create was in flight.
                    await OfflineStore.shared.deleteNote(id: serverNote.id)
                    await enqueueNoteDeletion(noteID: serverNote.id, title: serverNote.title)
                    continue
                }

                let followUp = current.updateRequired(afterCreate: serverNote)
                if current.localNoteID == nil {
                    // Queues written by older versions did not record local IDs.
                    await OfflineStore.shared.removeMirroredNote(
                        title: current.title,
                        sourceURL: current.sourceURL
                    )
                } else {
                    await OfflineStore.shared.reconcileQueuedNoteUpload(
                        localNoteID: current.localNoteID,
                        serverNote: serverNote,
                        preserveLocalEdits: followUp != nil
                    )
                }
                if let followUp {
                    await enqueueNoteUpdate(
                        noteID: serverNote.id,
                        title: current.title,
                        with: followUp
                    )
                }
                flushed += 1
            } catch {
                // Keep the persisted item unchanged so the next explicit sync
                // attempt can retry it without losing local work.
            }
        }

        let flushedMutations = await flushNoteMutations(using: api)
        return flushed + flushedMutations
    }

    @MainActor
    private func flushNoteMutations(using api: APIService) async -> Int {
        let queued = await queuedNoteMutations()
        var flushed = 0

        for item in queued {
            do {
                switch item.operation {
                case .update:
                    guard let update = item.update else { continue }
                    _ = try await api.updateNoteRemote(id: item.noteID, update)
                case .delete:
                    try await api.deleteNoteRemote(id: item.noteID)
                }
                if await completeNoteMutation(item) {
                    flushed += 1
                }
            } catch {
                // The operation remains in order for a later retry.
            }
        }
        return flushed
    }

    @MainActor
    func flushDecisions(using api: APIService) async -> Int {
        let queued = await queuedDecisions()
        var flushed = 0

        for item in queued {
            do {
                _ = try await api.recordDecisionRemote(
                    DecisionCreateRequest(
                        decision: item.decision,
                        reason: item.reason,
                        project: item.project,
                        assumptions: item.assumptions
                    )
                )
                if await completeDecision(item) {
                    await OfflineStore.shared.removeMirroredDecision(
                        decision: item.decision,
                        reason: item.reason,
                        project: item.project
                    )
                    flushed += 1
                }
            } catch {
                // Keep the persisted item for a later retry.
            }
        }
        return flushed
    }

    @MainActor
    func flushFeedback(using api: APIService) async -> Int {
        let queued = await queuedFeedback()
        var flushed = 0

        for item in queued {
            do {
                try await api.sendFeedbackRemote(
                    FeedbackRequest(item: item.item, useful: item.useful, acted: item.acted)
                )
                if await completeFeedback(item) {
                    flushed += 1
                }
            } catch {
                // Keep the persisted item for a later retry.
            }
        }
        return flushed
    }

    // MARK: - Counts

    var pendingNoteCount: Int { notes.count + noteMutations.count }
    var pendingDecisionCount: Int { decisions.count }
    var pendingFeedbackCount: Int { feedback.count }
    var totalPending: Int { pendingNoteCount + decisions.count + feedback.count }

    func pendingCounts() -> PendingQueueCounts {
        PendingQueueCounts(
            notes: pendingNoteCount,
            decisions: decisions.count,
            feedback: feedback.count,
            total: totalPending
        )
    }

    func pendingActions(limit: Int = 30) -> [PendingAction] {
        let noteActions = notes.map {
            PendingAction(
                id: "note-\($0.id.uuidString)",
                kind: "Capture",
                title: $0.title,
                capturedAt: $0.capturedAt
            )
        }
        let mutationActions = noteMutations.map { mutation in
            PendingAction(
                id: "note-mutation-\(mutation.id.uuidString)",
                kind: mutation.operation == .delete ? "Note removal" : "Note update",
                title: mutation.title,
                capturedAt: mutation.capturedAt
            )
        }
        let decisionActions = decisions.map {
            PendingAction(
                id: "decision-\($0.id.uuidString)",
                kind: "Decision",
                title: $0.decision,
                capturedAt: $0.capturedAt
            )
        }
        let feedbackActions = feedback.map {
            PendingAction(
                id: "feedback-\($0.id.uuidString)",
                kind: "Feedback",
                title: $0.item,
                capturedAt: $0.capturedAt
            )
        }

        return (noteActions + mutationActions + decisionActions + feedbackActions)
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(max(1, limit))
            .map { $0 }
    }

    // MARK: - Actor-isolated helpers

    private func queuedNotes() -> [QueuedNote] { notes }
    private func queuedNoteMutations() -> [QueuedNoteMutation] { noteMutations }
    private func queuedDecisions() -> [QueuedDecision] { decisions }
    private func queuedFeedback() -> [QueuedFeedback] { feedback }

    private func completeQueuedCreate(_ sent: QueuedNote) -> QueuedNote? {
        guard let index = notes.firstIndex(where: { $0.id == sent.id }) else {
            return nil
        }
        let current = notes.remove(at: index)
        persistNotes()
        return current
    }

    private func completeNoteMutation(_ sent: QueuedNoteMutation) -> Bool {
        guard let index = noteMutations.firstIndex(where: { $0.id == sent.id }),
              noteMutations[index] == sent else {
            return false
        }
        noteMutations.remove(at: index)
        persistNoteMutations()
        return true
    }

    private func completeDecision(_ sent: QueuedDecision) -> Bool {
        guard let index = decisions.firstIndex(where: { $0.id == sent.id }) else {
            return false
        }
        decisions.remove(at: index)
        persistDecisions()
        return true
    }

    private func completeFeedback(_ sent: QueuedFeedback) -> Bool {
        guard let index = feedback.firstIndex(where: { $0.id == sent.id }) else {
            return false
        }
        feedback.remove(at: index)
        persistFeedback()
        return true
    }

    private func merged(
        _ existing: NoteUpdateRequest?,
        with newer: NoteUpdateRequest
    ) -> NoteUpdateRequest {
        NoteUpdateRequest(
            title: newer.title ?? existing?.title,
            insight: newer.insight ?? existing?.insight,
            implication: newer.implication ?? existing?.implication,
            action: newer.action ?? existing?.action,
            sourceURL: newer.sourceURL ?? existing?.sourceURL,
            tags: newer.tags ?? existing?.tags,
            archived: newer.archived ?? existing?.archived
        )
    }

    // MARK: - Persistence

    private func persistNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: notesURL, options: .atomic)
    }

    private func persistNoteMutations() {
        guard let data = try? JSONEncoder().encode(noteMutations) else { return }
        try? data.write(to: noteMutationsURL, options: .atomic)
    }

    private func persistDecisions() {
        guard let data = try? JSONEncoder().encode(decisions) else { return }
        try? data.write(to: decisionsURL, options: .atomic)
    }

    private func persistFeedback() {
        guard let data = try? JSONEncoder().encode(feedback) else { return }
        try? data.write(to: feedbackURL, options: .atomic)
    }
}

private extension NoteUpdateRequest {
    var isEmpty: Bool {
        title == nil &&
            insight == nil &&
            implication == nil &&
            action == nil &&
            sourceURL == nil &&
            tags == nil &&
            archived == nil
    }
}
