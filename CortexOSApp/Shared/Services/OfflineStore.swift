import Foundation

actor OfflineStore {
    static let shared = OfflineStore()

    private struct ServerNoteCacheMetadata: Codable {
        var sourceIdentifier = ""
        var noteIDs: Set<String> = []
        var hasCompleteSnapshot = false
    }

    private struct PrivateSyncMetadata: Codable {
        var deletedNoteIDs: [String: String] = [:]
        var profileUpdatedAt = ""
        var decisionUpdatedAt: [String: String] = [:]
    }

    private let notesURL: URL
    private let serverNotesMetadataURL: URL
    private let profileURL: URL
    private let decisionsURL: URL
    private let insightsURL: URL
    private let feedbackURL: URL
    private let privateSyncMetadataURL: URL
    private let newsletterURL: URL
    private let newsletterMarkdownURL: URL

    private var notes: [KnowledgeNote] = []
    private var serverNotesMetadata = ServerNoteCacheMetadata()
    private var profile: UserProfile = .empty
    private var decisions: [SyncDecision] = []
    private var insights: [SyncInsight] = []
    private var feedback: [LocalFeedbackEvent] = []
    private var privateSyncMetadata = PrivateSyncMetadata()
    private var latestNewsletter: SyncNewsletter?

    #if !os(watchOS)
    /// Serializes derived-index mutations so a delayed update can never
    /// resurrect a vector after a newer delete or server reconciliation.
    private var semanticMaintenanceTask: Task<Void, Never>?
    #endif

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let iso = ISO8601DateFormatter()

    private let demoModeKey = "cortex_demo_mode_enabled"
    private let demoModeMigrationKey = "simplixio_preview_mode_opt_in_v1"

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CortexOS", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )

        notesURL = support.appendingPathComponent("offline_notes.json")
        serverNotesMetadataURL = support.appendingPathComponent("server_notes_cache.json")
        profileURL = support.appendingPathComponent("offline_profile.json")
        decisionsURL = support.appendingPathComponent("offline_decisions.json")
        insightsURL = support.appendingPathComponent("offline_insights.json")
        feedbackURL = support.appendingPathComponent("offline_feedback.json")
        privateSyncMetadataURL = support.appendingPathComponent("private_sync_metadata.json")
        newsletterURL = support.appendingPathComponent("offline_newsletter.json")
        newsletterMarkdownURL = support.appendingPathComponent("SimpliXio-Newsletter.md")

        if let data = try? Data(contentsOf: notesURL),
           let value = try? decoder.decode([KnowledgeNote].self, from: data) {
            notes = value
        }

        if let data = try? Data(contentsOf: serverNotesMetadataURL),
           let value = try? decoder.decode(ServerNoteCacheMetadata.self, from: data) {
            serverNotesMetadata = value
        }

        if let data = try? Data(contentsOf: profileURL),
           let value = try? decoder.decode(UserProfile.self, from: data) {
            profile = value
        }

        if let data = try? Data(contentsOf: decisionsURL),
           let value = try? decoder.decode([SyncDecision].self, from: data) {
            decisions = value
        }

        if let data = try? Data(contentsOf: insightsURL),
           let value = try? decoder.decode([SyncInsight].self, from: data) {
            insights = value
        }

        if let data = try? Data(contentsOf: feedbackURL),
           let value = try? decoder.decode([LocalFeedbackEvent].self, from: data) {
            feedback = value
        }

        if let data = try? Data(contentsOf: privateSyncMetadataURL),
           let value = try? decoder.decode(PrivateSyncMetadata.self, from: data) {
            privateSyncMetadata = value
        }

        if let data = try? Data(contentsOf: newsletterURL),
           let value = try? decoder.decode(SyncNewsletter.self, from: data) {
            latestNewsletter = value
        }
    }

    func serverHealth() -> ServerHealth {
        ServerHealth(status: "local", timestamp: iso.string(from: Date()))
    }

    func listNotes(includeArchived: Bool = false) -> [KnowledgeNote] {
        _ = ensureDemoContentIfNeeded()
        return orderedNotes().filter { includeArchived || !$0.archived }
    }

    func getNote(id: String) -> KnowledgeNote? {
        notes.first(where: { $0.id == id })
    }

    /// Reconciles a complete server response into the offline cache while
    /// preserving captures that have not reached the server yet.
    func cacheServerSnapshot(_ serverNotes: [KnowledgeNote], sourceIdentifier: String) {
        notes = Self.mergedServerSnapshot(
            serverNotes: serverNotes,
            existingNotes: notes,
            cachedServerIDs: serverNotesMetadata.noteIDs
        )
        serverNotesMetadata = ServerNoteCacheMetadata(
            sourceIdentifier: sourceIdentifier,
            noteIDs: Set(serverNotes.map(\.id)),
            hasCompleteSnapshot: true
        )
        persistNotes()
        persistServerNotesMetadata()
        scheduleSemanticSynchronization()
    }

    func cacheServerNote(_ note: KnowledgeNote, sourceIdentifier: String) {
        let sourceChanged = prepareServerCache(for: sourceIdentifier)
        notes.removeAll { $0.id == note.id }
        notes.insert(note, at: 0)
        privateSyncMetadata.deletedNoteIDs.removeValue(forKey: note.id)
        serverNotesMetadata.noteIDs.insert(note.id)
        persistNotes()
        persistPrivateSyncMetadata()
        persistServerNotesMetadata()
        if sourceChanged {
            scheduleSemanticSynchronization()
        } else {
            scheduleSemanticIndex(note)
        }
    }

    func removeCachedServerNote(id: String, sourceIdentifier: String) {
        let sourceChanged = prepareServerCache(for: sourceIdentifier)
        notes.removeAll { $0.id == id }
        serverNotesMetadata.noteIDs.remove(id)
        persistNotes()
        persistServerNotesMetadata()
        if sourceChanged {
            scheduleSemanticSynchronization()
        } else {
            scheduleSemanticRemoval(id: id)
        }
    }

    func hasCompleteServerSnapshot(sourceIdentifier: String) -> Bool {
        serverNotesMetadata.sourceIdentifier == sourceIdentifier &&
            serverNotesMetadata.hasCompleteSnapshot
    }

    func createNote(_ body: NoteCreateRequest) -> KnowledgeNote {
        let now = iso.string(from: Date())
        let note = KnowledgeNote(
            id: UUID().uuidString,
            title: body.title,
            insight: body.insight,
            implication: body.implication,
            action: body.action,
            sourceURL: body.sourceURL,
            tags: body.tags,
            createdAt: now,
            updatedAt: now,
            archived: false
        )
        privateSyncMetadata.deletedNoteIDs.removeValue(forKey: note.id)
        notes.insert(note, at: 0)
        persistNotes()
        persistPrivateSyncMetadata()
        scheduleSemanticIndex(note)
        return note
    }

    func updateNote(id: String, with body: NoteUpdateRequest) -> KnowledgeNote? {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return nil }
        notes[idx].title = body.title ?? notes[idx].title
        notes[idx].insight = body.insight ?? notes[idx].insight
        notes[idx].implication = body.implication ?? notes[idx].implication
        notes[idx].action = body.action ?? notes[idx].action
        notes[idx].sourceURL = body.sourceURL ?? notes[idx].sourceURL
        notes[idx].tags = body.tags ?? notes[idx].tags
        notes[idx].archived = body.archived ?? notes[idx].archived
        notes[idx].updatedAt = iso.string(from: Date())
        privateSyncMetadata.deletedNoteIDs.removeValue(forKey: id)
        persistNotes()
        persistPrivateSyncMetadata()
        let updated = notes[idx]
        scheduleSemanticIndex(updated)
        return updated
    }

    func deleteNote(id: String) {
        notes.removeAll { $0.id == id }
        privateSyncMetadata.deletedNoteIDs[id] = iso.string(from: Date())
        persistNotes()
        persistPrivateSyncMetadata()
        scheduleSemanticRemoval(id: id)
    }

    func removeMirroredNote(title: String, sourceURL: String) {
        let matchesMirror: (KnowledgeNote) -> Bool = {
            $0.title == title && $0.sourceURL == sourceURL
        }
        // A successful queued upload can temporarily leave both the local
        // capture and the server-issued record in this cache. Remove the local
        // mirror first so the newly authoritative server record survives.
        let idx = notes.firstIndex {
            matchesMirror($0) && !serverNotesMetadata.noteIDs.contains($0.id)
        } ?? notes.firstIndex(where: matchesMirror)
        if let idx {
            let id = notes[idx].id
            notes.remove(at: idx)
            persistNotes()
            scheduleSemanticRemoval(id: id)
        }
    }

    /// Resolves a locally created note after its queued create reaches the
    /// server. If it changed while uploading, preserve the local version under
    /// the server-issued ID so a following queued update stays visible.
    func reconcileQueuedNoteUpload(
        localNoteID: String?,
        serverNote: KnowledgeNote,
        preserveLocalEdits: Bool
    ) {
        guard let localNoteID,
              let localIndex = notes.firstIndex(where: { $0.id == localNoteID }) else {
            return
        }

        let localNote = notes.remove(at: localIndex)
        // The note now has a server-issued ID. Remove the old local record so
        // semantic search cannot retain an orphaned vector after reconciliation.
        scheduleSemanticRemoval(id: localNoteID)
        if preserveLocalEdits {
            var reconciled = serverNote
            reconciled.title = localNote.title
            reconciled.insight = localNote.insight
            reconciled.implication = localNote.implication
            reconciled.action = localNote.action
            reconciled.sourceURL = localNote.sourceURL
            reconciled.tags = localNote.tags
            reconciled.archived = localNote.archived
            reconciled.updatedAt = localNote.updatedAt
            notes.removeAll { $0.id == serverNote.id }
            notes.insert(reconciled, at: 0)
            scheduleSemanticIndex(reconciled)
        }
        persistNotes()
    }

    func searchNotes(query: String) async -> [KnowledgeNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return listNotes() }

        let ordered = listNotes()
        let lexicalIDs = lexicalRankedIDs(query: q, notes: ordered)

        #if os(watchOS)
        let lookup = Dictionary(
            ordered.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return lexicalIDs.compactMap { lookup[$0] }
        #else
        let semanticHits = await SemanticMemoryStore.shared.search(
            query: query,
            limit: min(50, ordered.count)
        )
        return fuseSearchResults(
            ordered: ordered,
            lexicalIDs: lexicalIDs,
            semanticHits: semanticHits
        )
        #endif
    }

    func prepareSemanticIndex() async {
        #if !os(watchOS)
        semanticMaintenanceTask?.cancel()
        let snapshot = listNotes()
        let task = enqueueSemanticMaintenance {
            await SemanticMemoryStore.shared.synchronize(notes: snapshot)
        }
        await task.value
        #endif
    }

    func semanticIndexStatus() async -> SemanticIndexStatus {
        #if os(watchOS)
        return SemanticIndexStatus(
            indexedNotes: 0,
            totalNotes: listNotes().count,
            dimension: 0,
            modelIdentifier: nil,
            isAvailable: false,
            isPersistent: false,
            storageBytes: 0,
            errorDescription: nil
        )
        #else
        let totalNotes = listNotes().count
        let statistics = await SemanticMemoryStore.shared.statistics()
        return SemanticIndexStatus(
            indexedNotes: statistics.compatibleRecordCount,
            totalNotes: totalNotes,
            dimension: statistics.dimension,
            modelIdentifier: statistics.modelIdentifier,
            isAvailable: statistics.isAvailable,
            isPersistent: statistics.isPersistent,
            storageBytes: statistics.storageBytes,
            errorDescription: statistics.errorDescription
        )
        #endif
    }

    func rebuildSemanticIndex() async {
        #if !os(watchOS)
        semanticMaintenanceTask?.cancel()
        let snapshot = listNotes()
        let task = enqueueSemanticMaintenance {
            await SemanticMemoryStore.shared.rebuild(notes: snapshot)
        }
        await task.value
        #endif
    }

    private func lexicalRankedIDs(query: String, notes: [KnowledgeNote]) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
            "how", "in", "is", "it", "of", "on", "or", "that", "the", "this",
            "to", "was", "what", "when", "where", "which", "with",
        ]
        let meaningfulTokens = query
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        let tokens = meaningfulTokens.isEmpty ? [query] : meaningfulTokens
        return notes.enumerated()
            .compactMap { offset, note -> (id: String, score: Int, offset: Int)? in
                let text = note.lexicalSearchText.lowercased()
                let title = note.title.lowercased()
                let matchedTokens = tokens.reduce(into: 0) { count, token in
                    if text.contains(token) { count += 1 }
                }
                guard text.contains(query) || matchedTokens > 0 else { return nil }

                var score = matchedTokens * 100 / max(tokens.count, 1)
                if text.contains(query) { score += 1_000 }
                if title.contains(query) { score += 500 }
                return (note.id, score, offset)
            }
            .sorted {
                if $0.score == $1.score { return $0.offset < $1.offset }
                return $0.score > $1.score
            }
            .map { $0.id }
    }

    #if !os(watchOS)
    private func fuseSearchResults(
        ordered: [KnowledgeNote],
        lexicalIDs: [String],
        semanticHits: [SemanticSearchHit]
    ) -> [KnowledgeNote] {
        var scores: [String: Double] = [:]
        let rankConstant = 60.0

        for (rank, id) in lexicalIDs.enumerated() {
            scores[id, default: 0] += 1.25 / (rankConstant + Double(rank + 1))
        }

        if let topScore = semanticHits.first?.score {
            let scoreFloor = max(0.15, topScore - 0.25)
            for (rank, hit) in semanticHits.filter({ $0.score >= scoreFloor }).enumerated() {
                scores[hit.id, default: 0] += 1.0 / (rankConstant + Double(rank + 1))
            }
        }

        let lookup = Dictionary(
            ordered.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let recencyRank = Dictionary(
            ordered.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: min
        )
        return scores.keys
            .compactMap { lookup[$0] }
            .sorted {
                let lhs = scores[$0.id, default: 0]
                let rhs = scores[$1.id, default: 0]
                if lhs == rhs {
                    return recencyRank[$0.id, default: .max] < recencyRank[$1.id, default: .max]
                }
                return lhs > rhs
            }
            .prefix(50)
            .map { $0 }
    }
    #endif

    private func scheduleSemanticIndex(_ note: KnowledgeNote) {
        #if !os(watchOS)
        _ = enqueueSemanticMaintenance {
            await SemanticMemoryStore.shared.index(note: note)
        }
        #endif
    }

    private func scheduleSemanticRemoval(id: String) {
        #if !os(watchOS)
        _ = enqueueSemanticMaintenance {
            await SemanticMemoryStore.shared.remove(id: id)
        }
        #endif
    }

    @discardableResult
    private func prepareServerCache(for sourceIdentifier: String) -> Bool {
        guard serverNotesMetadata.sourceIdentifier != sourceIdentifier else { return false }
        let previousServerIDs = serverNotesMetadata.noteIDs
        notes.removeAll { previousServerIDs.contains($0.id) }
        serverNotesMetadata = ServerNoteCacheMetadata(sourceIdentifier: sourceIdentifier)
        return true
    }

    private func scheduleSemanticSynchronization() {
        #if !os(watchOS)
        let snapshot = notes
        _ = enqueueSemanticMaintenance {
            await SemanticMemoryStore.shared.synchronize(notes: snapshot)
        }
        #endif
    }

    #if !os(watchOS)
    @discardableResult
    private func enqueueSemanticMaintenance(
        _ operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let predecessor = semanticMaintenanceTask
        let task = Task(priority: .utility) {
            await predecessor?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        semanticMaintenanceTask = task
        return task
    }
    #endif

    static func mergedServerSnapshot(
        serverNotes: [KnowledgeNote],
        existingNotes: [KnowledgeNote],
        cachedServerIDs: Set<String>
    ) -> [KnowledgeNote] {
        var seenServerIDs: Set<String> = []
        let uniqueServerNotes = serverNotes.filter { seenServerIDs.insert($0.id).inserted }
        let incomingServerIDs = Set(uniqueServerNotes.map(\.id))
        let localNotes = existingNotes.filter { note in
            !cachedServerIDs.contains(note.id) &&
                !incomingServerIDs.contains(note.id) &&
                !note.id.hasPrefix("demo-note-")
        }
        return uniqueServerNotes + localNotes
    }

    func getProfile() -> UserProfile {
        _ = ensureDemoContentIfNeeded()
        return profile
    }

    func updateProfile(_ update: ProfileUpdate) -> UserProfile {
        profile = UserProfile(
            name: update.name ?? profile.name,
            role: update.role ?? profile.role,
            goals: update.goals ?? profile.goals,
            interests: update.interests ?? profile.interests,
            currentProjects: update.currentProjects ?? profile.currentProjects,
            constraints: update.constraints ?? profile.constraints,
            ignoredTopics: update.ignoredTopics ?? profile.ignoredTopics
        )
        privateSyncMetadata.profileUpdatedAt = iso.string(from: Date())
        persistProfile()
        persistPrivateSyncMetadata()
        return profile
    }

    func recordDecision(_ request: DecisionCreateRequest) -> SyncDecision {
        let now = iso.string(from: Date())
        let decision = SyncDecision(
            id: UUID().uuidString,
            decision: request.decision,
            reason: request.reason,
            project: request.project,
            assumptions: request.assumptions,
            contextTags: request.project.isEmpty ? [] : [request.project],
            createdAt: now,
            outcome: "",
            impactScore: 0.0
        )
        decisions.insert(decision, at: 0)
        privateSyncMetadata.decisionUpdatedAt[decision.id] = now
        persistDecisions()
        persistPrivateSyncMetadata()
        return decision
    }

    func removeMirroredDecision(decision: String, reason: String, project: String) {
        if let idx = decisions.firstIndex(where: {
            $0.decision == decision && $0.reason == reason && $0.project == project
        }) {
            decisions.remove(at: idx)
            persistDecisions()
        }
    }

    func recordOutcome(_ request: OutcomeCreateRequest) -> SyncDecision? {
        guard let idx = decisions.firstIndex(where: { $0.id == request.decisionId }) else {
            let now = iso.string(from: Date())
            let synthesized = SyncDecision(
                id: request.decisionId,
                decision: "Decision",
                reason: "",
                project: "",
                assumptions: [],
                contextTags: [],
                createdAt: now,
                outcome: request.outcome,
                impactScore: request.impactScore
            )
            decisions.insert(synthesized, at: 0)
            privateSyncMetadata.decisionUpdatedAt[synthesized.id] = now
            persistDecisions()
            persistPrivateSyncMetadata()
            return synthesized
        }

        let existing = decisions[idx]
        let updated = SyncDecision(
            id: existing.id,
            decision: existing.decision,
            reason: existing.reason,
            project: existing.project,
            assumptions: existing.assumptions,
            contextTags: existing.contextTags,
            createdAt: existing.createdAt,
            outcome: request.outcome,
            impactScore: request.impactScore
        )

        decisions[idx] = updated
        privateSyncMetadata.decisionUpdatedAt[updated.id] = iso.string(from: Date())
        persistDecisions()
        persistPrivateSyncMetadata()
        return updated
    }

    func storeInsight(_ request: InsightCreateRequest) -> SyncInsight {
        let insight = SyncInsight(
            id: UUID().uuidString,
            title: request.title,
            summary: request.summary,
            whyItMatters: request.whyItMatters,
            architecturalImplication: request.architecturalImplication,
            nextAction: request.nextAction,
            confidence: request.confidence,
            tags: request.tags,
            relatedProject: request.relatedProject,
            createdAt: iso.string(from: Date())
        )
        insights.insert(insight, at: 0)
        persistInsights()
        return insight
    }

    func recordFeedback(_ request: FeedbackRequest) {
        // Preview interactions are disposable. They must not train ranking or
        // enter the private-sync payload used by the person's real captures.
        guard !isDemoModeEnabled() else { return }
        let cleaned = request.item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        feedback.insert(
            LocalFeedbackEvent(
                item: cleaned,
                useful: request.useful,
                acted: request.acted
            ),
            at: 0
        )
        // A bounded history is enough to learn ranking preferences without
        // letting feedback consume the iCloud key-value quota indefinitely.
        feedback = Array(feedback.prefix(500))
        persistFeedback()
    }

    func privateSyncPayload(deviceID: String) -> PrivateSyncPayload {
        let syncedNotes = notes.filter { !$0.id.hasPrefix("demo-note-") }
        let syncedDecisions = decisions.filter { !$0.id.hasPrefix("demo-decision-") }
        let syncedInsights = insights.filter { !$0.id.hasPrefix("demo-insight-") }
        let demoFeedbackItems = Set(
            notes.filter { $0.id.hasPrefix("demo-note-") }.map(\.title) +
                decisions.filter { $0.id.hasPrefix("demo-decision-") }.map(\.decision)
        )
        let syncedProfile = isDemoProfile(profile) ? .empty : profile
        let syncedDecisionIDs = Set(syncedDecisions.map(\.id))

        return PrivateSyncPayload(
            notes: syncedNotes,
            deletedNoteIDs: privateSyncMetadata.deletedNoteIDs.filter { !$0.key.hasPrefix("demo-note-") },
            profile: syncedProfile,
            profileUpdatedAt: isDemoProfile(profile) ? "" : privateSyncMetadata.profileUpdatedAt,
            decisions: syncedDecisions,
            decisionUpdatedAt: privateSyncMetadata.decisionUpdatedAt.filter { syncedDecisionIDs.contains($0.key) },
            insights: syncedInsights,
            feedback: feedback.filter { !demoFeedbackItems.contains($0.item) },
            modifiedAt: iso.string(from: Date()),
            deviceID: deviceID
        )
    }

    func mergePrivateSyncPayload(_ remote: PrivateSyncPayload, deviceID: String) -> PrivateSyncPayload {
        let local = privateSyncPayload(deviceID: deviceID)
        let merged = Self.mergedPrivateSyncPayload(local: local, remote: remote, deviceID: deviceID)

        notes = merged.notes
        profile = merged.profile
        decisions = merged.decisions
        insights = merged.insights
        feedback = merged.feedback
        privateSyncMetadata = PrivateSyncMetadata(
            deletedNoteIDs: merged.deletedNoteIDs,
            profileUpdatedAt: merged.profileUpdatedAt,
            decisionUpdatedAt: merged.decisionUpdatedAt
        )
        serverNotesMetadata = ServerNoteCacheMetadata()

        persistNotes()
        persistProfile()
        persistDecisions()
        persistInsights()
        persistFeedback()
        persistPrivateSyncMetadata()
        persistServerNotesMetadata()
        scheduleSemanticSynchronization()
        return merged
    }

    static func mergedPrivateSyncPayload(
        local: PrivateSyncPayload,
        remote: PrivateSyncPayload,
        deviceID: String,
        now: Date = Date()
    ) -> PrivateSyncPayload {
        var tombstones = local.deletedNoteIDs
        for (id, timestamp) in remote.deletedNoteIDs {
            tombstones[id] = latestTimestamp(tombstones[id] ?? "", timestamp)
        }

        var notesByID: [String: KnowledgeNote] = [:]
        for note in local.notes + remote.notes where !note.id.hasPrefix("demo-note-") {
            guard let current = notesByID[note.id] else {
                notesByID[note.id] = note
                continue
            }
            let currentDate = current.updatedAt.isEmpty ? current.createdAt : current.updatedAt
            let noteDate = note.updatedAt.isEmpty ? note.createdAt : note.updatedAt
            if isNewer(noteDate, than: currentDate) {
                notesByID[note.id] = note
            }
        }
        var obsoleteTombstones: [String] = []
        for (id, deletionTimestamp) in tombstones {
            guard let note = notesByID[id] else { continue }
            let noteTimestamp = note.updatedAt.isEmpty ? note.createdAt : note.updatedAt
            if deletionWins(deletionTimestamp, over: noteTimestamp) {
                notesByID.removeValue(forKey: id)
            } else {
                obsoleteTombstones.append(id)
            }
        }
        for id in obsoleteTombstones {
            tombstones.removeValue(forKey: id)
        }

        let useRemoteProfile: Bool
        if isNewer(remote.profileUpdatedAt, than: local.profileUpdatedAt) {
            useRemoteProfile = true
        } else if isNewer(local.profileUpdatedAt, than: remote.profileUpdatedAt) {
            useRemoteProfile = false
        } else {
            useRemoteProfile = profileRichness(remote.profile) > profileRichness(local.profile)
        }
        let mergedProfile = useRemoteProfile ? remote.profile : local.profile
        let mergedProfileTimestamp = latestTimestamp(local.profileUpdatedAt, remote.profileUpdatedAt)

        var decisionTimestamps = local.decisionUpdatedAt
        for (id, timestamp) in remote.decisionUpdatedAt {
            decisionTimestamps[id] = latestTimestamp(decisionTimestamps[id] ?? "", timestamp)
        }
        var decisionsByID: [String: SyncDecision] = [:]
        var selectedDecisionTimestamps: [String: String] = [:]
        let decisionSources = [
            (local.decisions, local.decisionUpdatedAt),
            (remote.decisions, remote.decisionUpdatedAt),
        ]
        for (sourceDecisions, sourceTimestamps) in decisionSources {
            for decision in sourceDecisions where !decision.id.hasPrefix("demo-decision-") {
                let candidateTimestamp = sourceTimestamps[decision.id] ?? decision.createdAt
                guard let current = decisionsByID[decision.id] else {
                    decisionsByID[decision.id] = decision
                    selectedDecisionTimestamps[decision.id] = candidateTimestamp
                    continue
                }
                let currentTimestamp = selectedDecisionTimestamps[decision.id] ?? current.createdAt
                if isNewer(candidateTimestamp, than: currentTimestamp) ||
                    (candidateTimestamp == currentTimestamp && decisionRichness(decision) > decisionRichness(current)) {
                    decisionsByID[decision.id] = decision
                    selectedDecisionTimestamps[decision.id] = candidateTimestamp
                }
            }
        }
        let decisionIDs = Set(decisionsByID.keys)
        decisionTimestamps = decisionTimestamps.filter { decisionIDs.contains($0.key) }

        var insightsByID: [String: SyncInsight] = [:]
        for insight in local.insights + remote.insights where !insight.id.hasPrefix("demo-insight-") {
            guard let current = insightsByID[insight.id] else {
                insightsByID[insight.id] = insight
                continue
            }
            if isNewer(insight.createdAt, than: current.createdAt) ||
                (insight.createdAt == current.createdAt && insightRichness(insight) > insightRichness(current)) {
                insightsByID[insight.id] = insight
            }
        }

        var feedbackByID: [String: LocalFeedbackEvent] = [:]
        for event in local.feedback + remote.feedback {
            if let current = feedbackByID[event.id], !isNewer(event.createdAt, than: current.createdAt) {
                continue
            }
            feedbackByID[event.id] = event
        }

        return PrivateSyncPayload(
            schemaVersion: max(local.schemaVersion, remote.schemaVersion),
            notes: notesByID.values.sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return isNewer($0.updatedAt, than: $1.updatedAt)
            },
            deletedNoteIDs: tombstones,
            profile: mergedProfile,
            profileUpdatedAt: mergedProfileTimestamp,
            decisions: decisionsByID.values.sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return isNewer($0.createdAt, than: $1.createdAt)
            },
            decisionUpdatedAt: decisionTimestamps,
            insights: insightsByID.values.sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return isNewer($0.createdAt, than: $1.createdAt)
            },
            feedback: Array(feedbackByID.values.sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return isNewer($0.createdAt, than: $1.createdAt)
            }.prefix(500)),
            modifiedAt: ISO8601DateFormatter().string(from: now),
            deviceID: deviceID
        )
    }

    private static func deletionWins(_ deletionTimestamp: String, over noteTimestamp: String) -> Bool {
        guard !deletionTimestamp.isEmpty else { return false }
        guard !noteTimestamp.isEmpty else { return true }
        guard let deletionDate = parsedDate(deletionTimestamp) else { return true }
        guard let noteDate = parsedDate(noteTimestamp) else { return true }
        return deletionDate >= noteDate
    }

    private static func latestTimestamp(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        return isNewer(rhs, than: lhs) ? rhs : lhs
    }

    private static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        switch (parsedDate(lhs), parsedDate(rhs)) {
        case let (left?, right?): return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs > rhs
        }
    }

    private static func parsedDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func profileRichness(_ profile: UserProfile) -> Int {
        [profile.name, profile.role].filter { !$0.isEmpty }.count +
            profile.goals.count + profile.interests.count + profile.currentProjects.count +
            profile.constraints.count + profile.ignoredTopics.count
    }

    private static func decisionRichness(_ decision: SyncDecision) -> Int {
        [decision.decision, decision.reason, decision.project, decision.outcome].filter { !$0.isEmpty }.count +
            decision.assumptions.count + decision.contextTags.count
    }

    private static func insightRichness(_ insight: SyncInsight) -> Int {
        [insight.title, insight.summary, insight.whyItMatters, insight.architecturalImplication, insight.nextAction]
            .filter { !$0.isEmpty }.count + insight.tags.count
    }

    func ingestSummary(_ request: SummaryIngestRequest) -> IngestResult {
        let trimmed = request.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return IngestResult(itemsIngested: 0, notesCreated: 0)
        }

        let lines = trimmed
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = lines.first.map { String($0) } ?? "Captured summary"
        let summary = lines.dropFirst().joined(separator: " ")

        if request.createNotes {
            _ = createNote(
                NoteCreateRequest(
                    title: title,
                    insight: summary,
                    implication: "",
                    action: "",
                    sourceURL: request.source,
                    tags: request.tags
                )
            )
        }

        let insight = SyncInsight(
            id: UUID().uuidString,
            title: title,
            summary: summary,
            whyItMatters: "Captured locally for later synthesis.",
            architecturalImplication: "",
            nextAction: "Review and connect this with current priorities.",
            confidence: 0.65,
            tags: request.tags,
            relatedProject: profile.currentProjects.first ?? "",
            createdAt: iso.string(from: Date())
        )
        insights.insert(insight, at: 0)
        persistInsights()

        return IngestResult(itemsIngested: 1, notesCreated: request.createNotes ? 1 : 0)
    }

    func snapshot() -> SyncSnapshot {
        _ = ensureDemoContentIfNeeded()

        let now = Date()
        let nowISO = iso.string(from: now)
        let dateString = Self.dateOnly(now)

        let ordered = orderedNotes()
        let includeDemo = isDemoModeEnabled()
        let ranking = LocalPriorityEngine.rank(
            notes: ordered,
            decisions: decisions,
            profile: profile,
            feedback: feedback,
            now: now,
            includeDemo: includeDemo
        )
        let priorities = ranking.priorities

        let brief = priorities.isEmpty ? nil : PriorityBrief(
            date: dateString,
            priorities: priorities,
            ignored: ranking.ignoredTitles,
            emergingSignals: [],
            changesSinceYesterday: []
        )
        let today = buildTodayOutput(brief: brief, date: dateString, nowISO: nowISO)
        let weeklyReview = LocalSynthesisEngine.weeklyReview(
            notes: ordered,
            priorities: ranking,
            now: now,
            includeDemo: includeDemo
        )
        let decisionReplay = LocalSynthesisEngine.decisionReplay(
            notes: ordered,
            priorities: ranking,
            now: now,
            includeDemo: includeDemo
        )

        let activeProjectName = profile.currentProjects.first ?? ""
        let activeProject: ProjectContext? = activeProjectName.isEmpty ? nil : ProjectContext(
            projectName: activeProjectName,
            currentMilestone: "",
            activeBlockers: [],
            recentDecisions: decisions.prefix(3).map { $0.decision },
            architectureNotes: [],
            openQuestions: []
        )

        let signals = buildSignals(from: notes, insights: insights)
        let signalSurfaces = LocalSignalEngine.build(
            notes: ordered,
            decisions: decisions,
            priorities: ranking,
            now: now,
            includeDemo: includeDemo
        )

        return SyncSnapshot(
            profile: SyncProfile(
                name: profile.name,
                role: profile.role,
                goals: profile.goals,
                interests: profile.interests,
                currentProjects: profile.currentProjects,
                ignoredTopics: profile.ignoredTopics
            ),
            activeProject: activeProject,
            priorities: brief,
            today: today,
            weeklyReview: weeklyReview,
            decisionReplay: decisionReplay,
            newsletter: latestNewsletter,
            whatMattersNow: signalSurfaces.whatMattersNow,
            signalTopPriorities: signalSurfaces.topPriorities,
            decisionQueue: signalSurfaces.decisionQueue,
            actionReadyQueue: signalSurfaces.actionReadyQueue,
            recurringPatterns: signalSurfaces.recurringPatterns,
            unresolvedTensions: signalSurfaces.unresolvedTensions,
            contentCandidates: signalSurfaces.contentCandidates,
            resurfacedNow: nil,
            resurfacingRecurringTensions: nil,
            resurfacingWeeklyReviewCandidates: nil,
            resurfacingContentCandidates: nil,
            signalGraph: nil,
            signalMatchingCounts: signalSurfaces.counts,
            recentDecisions: Array(decisions.prefix(50)),
            insights: Array(insights.prefix(50)),
            signals: signals,
            workingMemory: SyncWorkingMemory(
                date: dateString,
                todaysPriorities: priorities.map { $0.title },
                currentlyExploring: signals.map { $0.topic },
                temporaryNotes: Array(ordered.prefix(5).map { $0.title })
            ),
            syncedAt: nowISO
        )
    }

    func generateNewsletterDraft(period: String, mode: String) -> NewsletterGenerationResult {
        let now = Date()
        let ranking = LocalPriorityEngine.rank(
            notes: orderedNotes(),
            decisions: decisions,
            profile: profile,
            feedback: feedback,
            now: now,
            includeDemo: isDemoModeEnabled()
        )
        guard let draft = LocalSynthesisEngine.newsletterDraft(
            notes: notes,
            decisions: decisions,
            priorities: ranking,
            period: period,
            mode: mode,
            now: now,
            includeDemo: isDemoModeEnabled()
        ) else {
            return NewsletterGenerationResult(
                status: "not_enough_material",
                reason: "Not enough public-safe material yet.",
                safeToPublish: false,
                generatedAt: iso.string(from: now)
            )
        }

        do {
            try draft.markdown.write(to: newsletterMarkdownURL, atomically: true, encoding: .utf8)
        } catch {
            return NewsletterGenerationResult(
                status: "error",
                reason: "The draft could not be saved on this device.",
                safeToPublish: false,
                generatedAt: iso.string(from: now)
            )
        }

        let generatedAt = iso.string(from: now)
        latestNewsletter = SyncNewsletter(
            status: draft.status,
            mode: mode,
            periodStart: draft.periodStart,
            periodEnd: draft.periodEnd,
            // Automated checks are necessary but not sufficient. Public export
            // remains locked until the user reviews and approves the draft.
            safeToPublish: false,
            generatedAt: generatedAt,
            title: draft.title,
            subtitle: draft.subtitle,
            preview: draft.preview,
            sourceCountTotal: draft.sourceCountTotal,
            sourceCountUsable: draft.sourceCountUsable,
            safetyReport: SyncNewsletterSafetyReport(
                safeToPublish: draft.safeToPublish,
                remainingConcerns: draft.remainingConcerns,
                recommendation: draft.recommendation
            ),
            tasteGate: SyncNewsletterTasteGate(
                passed: draft.tasteReasons.isEmpty,
                score: draft.tasteScore,
                reasons: draft.tasteReasons
            ),
            markdownPath: newsletterMarkdownURL.path
        )
        persistNewsletter()
        return NewsletterGenerationResult(
            status: draft.status,
            reason: nil,
            safeToPublish: false,
            generatedAt: generatedAt
        )
    }

    func approveNewsletterDraft() -> Bool {
        guard let newsletter = latestNewsletter,
              newsletter.isEligibleForApproval,
              let markdown = try? String(contentsOfFile: newsletter.markdownPath, encoding: .utf8),
              LocalSynthesisEngine.publicationConcerns(in: markdown).isEmpty else {
            return false
        }

        latestNewsletter = newsletter.withPublicationStatus(
            status: "approved",
            safeToPublish: true,
            recommendation: "Approved by you after review. Sharing remains a manual action."
        )
        persistNewsletter()
        return true
    }

    func rejectNewsletterDraft() {
        guard let newsletter = latestNewsletter else { return }
        latestNewsletter = newsletter.withPublicationStatus(
            status: "rejected",
            safeToPublish: false,
            recommendation: "Rejected by you. Regenerate or revise the source material before sharing."
        )
        persistNewsletter()
    }

    private func buildTodayOutput(brief: PriorityBrief?, date: String, nowISO: String) -> SyncTodayOutput? {
        guard let brief else { return nil }

        let compact: [SyncTodayPriority] = brief.priorities.prefix(3).map { item in
            SyncTodayPriority(
                rank: item.rank,
                title: item.title,
                why: item.whyItMatters,
                action: item.nextStep
            )
        }

        var lines = ["SimpliXio Today — \(date)", ""]
        for item in compact {
            lines.append("\(item.rank). \(item.title)")
            lines.append("Why: \(item.why.isEmpty ? "High decision impact." : item.why)")
            lines.append("Do: \(item.action.isEmpty ? "Take the next concrete step." : item.action)")
            lines.append("")
        }
        if !brief.ignored.isEmpty {
            lines.append("Ignored signals:")
            for value in brief.ignored.prefix(5) {
                lines.append("- \(value)")
            }
        }

        return SyncTodayOutput(
            date: date,
            priorities: compact,
            ignoredSignals: brief.ignored,
            changesSinceYesterday: brief.changesSinceYesterday,
            shareText: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            generatedAt: nowISO
        )
    }

    func isDemoModeEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: demoModeMigrationKey) {
            defaults.set(true, forKey: demoModeMigrationKey)
            defaults.set(false, forKey: demoModeKey)
            removeDemoContent()
        }
        return defaults.bool(forKey: demoModeKey)
    }

    func setDemoModeEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: demoModeMigrationKey)
        defaults.set(enabled, forKey: demoModeKey)
        if !enabled {
            removeDemoContent()
        }
    }

    @discardableResult
    func ensureDemoContentIfNeeded(force: Bool = false) -> Bool {
        if !(force || isDemoModeEnabled()) {
            return false
        }

        let hasRealContent = notes.contains { !$0.id.hasPrefix("demo-note-") } ||
            decisions.contains { !$0.id.hasPrefix("demo-decision-") } ||
            insights.contains { !$0.id.hasPrefix("demo-insight-") }
        if hasRealContent {
            return false
        }

        let now = Date()
        let nowISO = iso.string(from: now)
        let previousISO = iso.string(from: now.addingTimeInterval(-3600 * 18))
        let twoDaysAgoISO = iso.string(from: now.addingTimeInterval(-3600 * 42))

        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile = UserProfile(
                name: "Demo Operator",
                role: "Decision Lead",
                goals: [
                    "Protect deep work time this week",
                    "Ship SimpliXio reliability fixes",
                    "Keep product direction clear"
                ],
                interests: ["decision quality", "signal extraction", "system design"],
                currentProjects: ["SimpliXio"],
                constraints: ["clarity over volume", "low friction execution"],
                ignoredTopics: ["trending gossip", "low-signal updates"]
            )
        }

        notes = [
            KnowledgeNote(
                id: "demo-note-1",
                title: "Stability before expansion",
                insight: "Apple review friction is currently the biggest delivery risk.",
                implication: "Reliability work has direct impact on shipping confidence and growth.",
                action: "Harden offline and button interaction paths before adding new features.",
                sourceURL: "local://demo/review",
                tags: ["release", "reliability", "focus"],
                createdAt: twoDaysAgoISO,
                updatedAt: previousISO,
                archived: false
            ),
            KnowledgeNote(
                id: "demo-note-2",
                title: "Offline continuity increases trust",
                insight: "Users continue capturing when they know nothing is lost without network.",
                implication: "Save every change locally first and make private sync state clear.",
                action: "Keep captures available instantly, then reconcile them through iCloud.",
                sourceURL: "local://demo/offline",
                tags: ["offline", "trust", "ux"],
                createdAt: previousISO,
                updatedAt: previousISO,
                archived: false
            ),
            KnowledgeNote(
                id: "demo-note-3",
                title: "Three priorities keeps thinking sharp",
                insight: "Limiting visible priorities avoids noise and drives decisive action.",
                implication: "Top-3 presentation should remain the canonical daily surface.",
                action: "Review each priority in detail and mark acted/not useful to train ranking.",
                sourceURL: "local://demo/priorities",
                tags: ["focus", "prioritisation"],
                createdAt: nowISO,
                updatedAt: nowISO,
                archived: false
            )
        ]

        decisions = [
            SyncDecision(
                id: "demo-decision-1",
                decision: "Prioritize offline-first reliability for this release",
                reason: "Without reliable offline behavior, core capture and decision flow breaks.",
                project: "SimpliXio",
                assumptions: ["Core capture must never depend on network availability"],
                contextTags: ["release", "offline"],
                createdAt: previousISO,
                outcome: "Adopted as release gate",
                impactScore: 0.82
            ),
            SyncDecision(
                id: "demo-decision-2",
                decision: "Keep the daily view at three priorities maximum",
                reason: "Decision quality drops when too many items compete for attention.",
                project: "SimpliXio",
                assumptions: ["Clarity matters more than volume"],
                contextTags: ["product", "focus"],
                createdAt: nowISO,
                outcome: "",
                impactScore: 0.0
            )
        ]

        insights = [
            SyncInsight(
                id: "demo-insight-1",
                title: "Reliability is a product feature",
                summary: "Perceived intelligence falls when basic interactions fail.",
                whyItMatters: "App trust is built from predictable response to every tap.",
                architecturalImplication: "All user mutations should commit locally before synchronization.",
                nextAction: "Display clear local-save and private iCloud sync feedback.",
                confidence: 0.88,
                tags: ["quality", "ux"],
                relatedProject: "SimpliXio",
                createdAt: previousISO
            ),
            SyncInsight(
                id: "demo-insight-2",
                title: "Feedback loop sharpens prioritisation",
                summary: "Acted/not-acted outcomes help ranking converge on useful work.",
                whyItMatters: "The system should learn what actually moves decisions forward.",
                architecturalImplication: "Feed feedback tags into priority scoring.",
                nextAction: "Remove completed items from today and demote repeatedly unhelpful signals.",
                confidence: 0.84,
                tags: ["learning", "priorities"],
                relatedProject: "SimpliXio",
                createdAt: nowISO
            )
        ]

        persistProfile()
        persistNotes()
        persistDecisions()
        persistInsights()
        return true
    }

    private func removeDemoContent() {
        let demoNoteIDs = notes.filter { $0.id.hasPrefix("demo-note-") }.map(\.id)
        let demoFeedbackItems = Set(
            notes.filter { $0.id.hasPrefix("demo-note-") }.map(\.title) +
                decisions.filter { $0.id.hasPrefix("demo-decision-") }.map(\.decision)
        )
        notes.removeAll { $0.id.hasPrefix("demo-note-") }
        decisions.removeAll { $0.id.hasPrefix("demo-decision-") }
        insights.removeAll { $0.id.hasPrefix("demo-insight-") }
        feedback.removeAll { demoFeedbackItems.contains($0.item) }
        privateSyncMetadata.deletedNoteIDs = privateSyncMetadata.deletedNoteIDs.filter {
            !$0.key.hasPrefix("demo-note-")
        }
        privateSyncMetadata.decisionUpdatedAt = privateSyncMetadata.decisionUpdatedAt.filter {
            !$0.key.hasPrefix("demo-decision-")
        }
        if isDemoProfile(profile) {
            profile = .empty
            privateSyncMetadata.profileUpdatedAt = ""
        }
        persistNotes()
        persistProfile()
        persistDecisions()
        persistInsights()
        persistFeedback()
        persistPrivateSyncMetadata()
        for id in demoNoteIDs {
            scheduleSemanticRemoval(id: id)
        }
    }

    private func isDemoProfile(_ value: UserProfile) -> Bool {
        value.name == "Demo Operator" && value.role == "Decision Lead"
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func orderedNotes() -> [KnowledgeNote] {
        notes.sorted { lhs, rhs in
            (iso.date(from: lhs.updatedAt) ?? .distantPast) > (iso.date(from: rhs.updatedAt) ?? .distantPast)
        }
    }

    private func buildPriorities(from notes: [KnowledgeNote], decisions: [SyncDecision]) -> [SyncPriority] {
        var items: [SyncPriority] = []

        for (idx, note) in notes.prefix(3).enumerated() {
            items.append(
                SyncPriority(
                    rank: idx + 1,
                    title: note.title,
                    whyItMatters: note.implication.isEmpty ? "Captured in your local knowledge base." : note.implication,
                    nextStep: note.action.isEmpty ? "Review and decide the next concrete step." : note.action,
                    source: note.sourceURL.isEmpty ? "local" : note.sourceURL,
                    relevanceScore: max(0.5, 1.0 - (Double(idx) * 0.15)),
                    tags: note.tags
                )
            )
        }

        if items.isEmpty, let latestDecision = decisions.first {
            items.append(
                SyncPriority(
                    rank: 1,
                    title: latestDecision.decision,
                    whyItMatters: latestDecision.reason.isEmpty ? "Latest local decision." : latestDecision.reason,
                    nextStep: "Track the outcome and refine assumptions.",
                    source: "local",
                    relevanceScore: 0.8,
                    tags: latestDecision.contextTags
                )
            )
        }

        if items.isEmpty {
            items.append(
                SyncPriority(
                    rank: 1,
                    title: "Define today's most important decision",
                    whyItMatters: "A clear first decision anchors the rest of the day.",
                    nextStep: "Capture one note or decision to initialize your local focus.",
                    source: "local",
                    relevanceScore: 0.7,
                    tags: ["focus"]
                )
            )
        }

        return items.enumerated().map { idx, item in
            SyncPriority(
                rank: idx + 1,
                title: item.title,
                whyItMatters: item.whyItMatters,
                nextStep: item.nextStep,
                source: item.source,
                relevanceScore: item.relevanceScore,
                tags: item.tags
            )
        }
    }

    private func buildSignals(from notes: [KnowledgeNote], insights: [SyncInsight]) -> [SyncSignal] {
        var frequency: [String: Int] = [:]

        for note in notes {
            for tag in note.tags where !tag.isEmpty {
                frequency[tag, default: 0] += 1
            }
        }

        for insight in insights {
            for tag in insight.tags where !tag.isEmpty {
                frequency[tag, default: 0] += 1
            }
        }

        let now = iso.string(from: Date())
        return frequency
            .sorted { $0.value > $1.value }
            .prefix(8)
            .enumerated()
            .map { idx, pair in
                SyncSignal(
                    id: "local-signal-\(idx)-\(pair.key)",
                    topic: pair.key,
                    frequency: pair.value,
                    strength: min(1.0, Double(pair.value) / 5.0),
                    status: pair.value >= 3 ? "confirmed" : "emerging",
                    firstSeen: now,
                    lastSeen: now,
                    sourceTitles: []
                )
            }
    }

    private func persistNotes() {
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: notesURL, options: .atomic)
    }

    private func persistServerNotesMetadata() {
        guard let data = try? encoder.encode(serverNotesMetadata) else { return }
        try? data.write(to: serverNotesMetadataURL, options: .atomic)
    }

    private func persistProfile() {
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: profileURL, options: .atomic)
    }

    private func persistDecisions() {
        guard let data = try? encoder.encode(decisions) else { return }
        try? data.write(to: decisionsURL, options: .atomic)
    }

    private func persistInsights() {
        guard let data = try? encoder.encode(insights) else { return }
        try? data.write(to: insightsURL, options: .atomic)
    }

    private func persistFeedback() {
        guard let data = try? encoder.encode(feedback) else { return }
        try? data.write(to: feedbackURL, options: .atomic)
    }

    private func persistPrivateSyncMetadata() {
        guard let data = try? encoder.encode(privateSyncMetadata) else { return }
        try? data.write(to: privateSyncMetadataURL, options: .atomic)
    }

    private func persistNewsletter() {
        guard let latestNewsletter,
              let data = try? encoder.encode(latestNewsletter) else { return }
        try? data.write(to: newsletterURL, options: .atomic)
    }
}
