//
//  CaptureQueue.swift
//  CortexOS
//
//  Offline-first capture queue. Notes, decisions, and feedback
//  are saved locally first, then flushed when connectivity returns.
//
//  "Capture must always work." — offline or not.
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

    struct QueuedNote: Codable, Identifiable {
        let id: UUID
        let title: String
        let insight: String
        let implication: String
        let action: String
        let sourceURL: String
        let tags: [String]
        let capturedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            insight: String = "",
            implication: String = "",
            action: String = "",
            sourceURL: String = "",
            tags: [String] = [],
            capturedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.insight = insight
            self.implication = implication
            self.action = action
            self.sourceURL = sourceURL
            self.tags = tags
            self.capturedAt = capturedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, title, insight, implication, action, tags, capturedAt
            case sourceURL = "source_url"
            case legacySourceURL = "sourceURL"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            insight = try container.decodeIfPresent(String.self, forKey: .insight) ?? ""
            implication = try container.decodeIfPresent(String.self, forKey: .implication) ?? ""
            action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
            sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
                ?? container.decodeIfPresent(String.self, forKey: .legacySourceURL)
                ?? ""
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(insight, forKey: .insight)
            try container.encode(implication, forKey: .implication)
            try container.encode(action, forKey: .action)
            try container.encode(sourceURL, forKey: .sourceURL)
            try container.encode(tags, forKey: .tags)
            try container.encode(capturedAt, forKey: .capturedAt)
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
    private var decisions: [QueuedDecision] = []
    private var feedback: [QueuedFeedback] = []

    private let notesURL: URL
    private let decisionsURL: URL
    private let feedbackURL: URL

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CortexOS", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )

        notesURL = support.appendingPathComponent("capture_queue_notes.json")
        decisionsURL = support.appendingPathComponent("capture_queue_decisions.json")
        feedbackURL = support.appendingPathComponent("capture_queue_feedback.json")

        // Load persisted queues
        if let data = try? Data(contentsOf: notesURL),
           let saved = try? JSONDecoder().decode([QueuedNote].self, from: data) {
            notes = saved
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
        title: String,
        insight: String = "",
        implication: String = "",
        action: String = "",
        sourceURL: String = "",
        tags: [String] = []
    ) {
        let item = QueuedNote(
            title: title,
            insight: insight,
            implication: implication,
            action: action,
            sourceURL: sourceURL,
            tags: tags
        )
        notes.append(item)
        persistNotes()
    }

    func enqueueDecision(
        decision: String,
        reason: String = "",
        project: String = "",
        assumptions: [String] = []
    ) {
        let item = QueuedDecision(
            id: UUID(),
            decision: decision,
            reason: reason,
            project: project,
            assumptions: assumptions,
            capturedAt: Date()
        )
        decisions.append(item)
        persistDecisions()
    }

    func enqueueFeedback(item: String, useful: Bool, acted: Bool? = nil) {
        let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let queued = QueuedFeedback(
            id: UUID(),
            item: cleaned,
            useful: useful,
            acted: acted,
            capturedAt: Date()
        )
        feedback.append(queued)
        persistFeedback()
    }

    // MARK: - Flush (send to server)

    @MainActor
    func flushNotes(using api: APIService) async -> Int {
        let queued = await getQueuedNotes()
        guard !queued.isEmpty else { return 0 }

        var remaining: [QueuedNote] = []
        var flushed = 0

        for item in queued {
            let request = NoteCreateRequest(
                title: item.title,
                insight: item.insight,
                implication: item.implication,
                action: item.action,
                sourceURL: item.sourceURL,
                tags: item.tags
            )

            do {
                _ = try await api.createNoteRemote(request)
                await OfflineStore.shared.removeMirroredNote(
                    title: item.title,
                    sourceURL: item.sourceURL
                )
                flushed += 1
            } catch {
                remaining.append(item)
            }
        }

        await setQueuedNotes(remaining)
        return flushed
    }

    @MainActor
    func flushDecisions(using api: APIService) async -> Int {
        let queued = await getQueuedDecisions()
        guard !queued.isEmpty else { return 0 }

        var remaining: [QueuedDecision] = []
        var flushed = 0

        for item in queued {
            let request = DecisionCreateRequest(
                decision: item.decision,
                reason: item.reason,
                project: item.project,
                assumptions: item.assumptions
            )

            do {
                _ = try await api.recordDecisionRemote(request)
                await OfflineStore.shared.removeMirroredDecision(
                    decision: item.decision,
                    reason: item.reason,
                    project: item.project
                )
                flushed += 1
            } catch {
                remaining.append(item)
            }
        }

        await setQueuedDecisions(remaining)
        return flushed
    }

    @MainActor
    func flushFeedback(using api: APIService) async -> Int {
        let queued = await getQueuedFeedback()
        guard !queued.isEmpty else { return 0 }

        var remaining: [QueuedFeedback] = []
        var flushed = 0

        for item in queued {
            do {
                try await api.sendFeedbackRemote(
                    FeedbackRequest(item: item.item, useful: item.useful, acted: item.acted)
                )
                flushed += 1
            } catch {
                remaining.append(item)
            }
        }

        await setQueuedFeedback(remaining)
        return flushed
    }

    // MARK: - Counts

    var pendingNoteCount: Int { notes.count }
    var pendingDecisionCount: Int { decisions.count }
    var pendingFeedbackCount: Int { feedback.count }
    var totalPending: Int { notes.count + decisions.count + feedback.count }

    func pendingCounts() -> PendingQueueCounts {
        PendingQueueCounts(
            notes: notes.count,
            decisions: decisions.count,
            feedback: feedback.count,
            total: notes.count + decisions.count + feedback.count
        )
    }

    func pendingActions(limit: Int = 30) -> [PendingAction] {
        let noteActions = notes.map {
            PendingAction(
                id: "note-\($0.id.uuidString)",
                kind: "Note",
                title: $0.title,
                capturedAt: $0.capturedAt
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

        return (noteActions + decisionActions + feedbackActions)
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(max(1, limit))
            .map { $0 }
    }

    // MARK: - Actor-isolated helpers

    private func getQueuedNotes() -> [QueuedNote] { notes }
    private func getQueuedDecisions() -> [QueuedDecision] { decisions }
    private func getQueuedFeedback() -> [QueuedFeedback] { feedback }

    private func setQueuedNotes(_ value: [QueuedNote]) {
        notes = value
        persistNotes()
    }

    private func setQueuedDecisions(_ value: [QueuedDecision]) {
        decisions = value
        persistDecisions()
    }

    private func setQueuedFeedback(_ value: [QueuedFeedback]) {
        feedback = value
        persistFeedback()
    }

    // MARK: - Persistence

    private func persistNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: notesURL, options: .atomic)
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
