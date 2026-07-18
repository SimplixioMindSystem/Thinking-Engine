//
//  CortexEngine.swift
//  CortexOS
//
//  Client-side engine that wraps APIService with observable state
//  for SwiftUI bindings.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class CortexEngine: ObservableObject {

    struct QueuedActionPreview: Identifiable {
        let id: String
        let kind: String
        let title: String
        let capturedAt: Date
    }

    // MARK: - Published State

    @Published var notes: [KnowledgeNote] = []
    @Published var profile: UserProfile = .empty
    @Published var snapshot: SyncSnapshot?
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncStatus: String?
    @Published var newsletterStatus: String?
    @Published var demoModeEnabled = false
    @Published var pendingSyncActions = 0
    @Published var pendingNotes = 0
    @Published var pendingDecisions = 0
    @Published var pendingFeedback = 0
    @Published var queuedActions: [QueuedActionPreview] = []
    @Published var semanticIndexStatus: SemanticIndexStatus?
    @Published var isRebuildingSemanticIndex = false

    // MARK: - Dependencies

    let api: APIService
    private var noteRequestGeneration: UInt64 = 0
    private var semanticPreparationTask: Task<Void, Never>?
    private var semanticPreparationRequested = false

    init(api: APIService? = nil) {
        self.api = api ?? APIService.shared

        // Always load cached snapshot for instant launch
        Task { [weak self] in
            if let cached = await SnapshotCache.shared.load() {
                self?.snapshot = cached
            }
            self?.demoModeEnabled = await OfflineStore.shared.isDemoModeEnabled()
            _ = await OfflineStore.shared.ensureDemoContentIfNeeded()
            if self?.snapshot == nil {
                self?.snapshot = await OfflineStore.shared.snapshot()
            }
            await self?.refreshPendingSyncActions()
            self?.resumeSemanticIndexing()
        }
    }

    // MARK: - Connection

    func checkConnection() async {
        if api.isOffline {
            isConnected = true
            errorMessage = nil
            return
        }
        do {
            _ = try await api.health()
            isConnected = true
            errorMessage = nil
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Notes

    func fetchNotes() async {
        let requestGeneration = beginNoteRequest()
        if demoModeEnabled {
            let result = await OfflineStore.shared.listNotes()
            guard isCurrentNoteRequest(requestGeneration), !Task.isCancelled else { return }
            notes = result
            errorMessage = nil
            resumeSemanticIndexing()
            return
        }

        isLoading = true
        defer {
            if isCurrentNoteRequest(requestGeneration) { isLoading = false }
        }
        do {
            let result = try await api.listNotes()
            try Task.checkCancellation()
            guard isCurrentNoteRequest(requestGeneration) else { return }
            notes = result
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if isCurrentNoteRequest(requestGeneration) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createNote(_ request: NoteCreateRequest) async -> Bool {
        do {
            let note = try await api.createNote(request)
            notes.insert(note, at: 0)
            errorMessage = nil
            await refreshPendingSyncActions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await refreshPendingSyncActions()
            return false
        }
    }

    func deleteNote(_ id: String) async -> Bool {
        do {
            try await api.deleteNote(id: id)
            notes.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func searchNotes(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await fetchNotes()
            return
        }

        let requestGeneration = beginNoteRequest()
        isLoading = true
        defer {
            if isCurrentNoteRequest(requestGeneration) { isLoading = false }
        }
        do {
            let result = try await api.searchNotes(query: trimmed)
            try Task.checkCancellation()
            guard isCurrentNoteRequest(requestGeneration) else { return }
            notes = result
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if isCurrentNoteRequest(requestGeneration) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginNoteRequest() -> UInt64 {
        noteRequestGeneration &+= 1
        return noteRequestGeneration
    }

    private func isCurrentNoteRequest(_ generation: UInt64) -> Bool {
        generation == noteRequestGeneration
    }

    // MARK: - On-device semantic index

    func resumeSemanticIndexing() {
        semanticPreparationRequested = true
        guard semanticPreparationTask == nil else { return }
        semanticPreparationTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.semanticPreparationRequested = false
                await OfflineStore.shared.prepareSemanticIndex()
                guard !Task.isCancelled else { break }
                let status = await OfflineStore.shared.semanticIndexStatus()
                guard !Task.isCancelled else { break }
                if self.semanticPreparationRequested { continue }
                self.semanticIndexStatus = status
                self.semanticPreparationTask = nil
                return
            }
            self.semanticPreparationTask = nil
        }
    }

    func refreshSemanticIndexStatus() async {
        semanticIndexStatus = await OfflineStore.shared.semanticIndexStatus()
    }

    func rebuildSemanticIndex() async {
        guard !isRebuildingSemanticIndex else { return }
        semanticPreparationTask?.cancel()
        semanticPreparationTask = nil
        semanticPreparationRequested = false
        isRebuildingSemanticIndex = true
        defer { isRebuildingSemanticIndex = false }

        await OfflineStore.shared.rebuildSemanticIndex()
        semanticIndexStatus = await OfflineStore.shared.semanticIndexStatus()
    }

    // MARK: - Profile

    func fetchProfile() async {
        if demoModeEnabled {
            profile = await OfflineStore.shared.getProfile()
            errorMessage = nil
            return
        }

        do {
            profile = try await api.getProfile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProfile(_ update: ProfileUpdate) async -> Bool {
        do {
            profile = try await api.updateProfile(update)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Sync (single-call pull + offline-first)

    func sync() async {
        if isSyncing { return }
        isSyncing = true
        defer { isSyncing = false }
        lastSyncStatus = "Syncing..."

        if await applyDemoStateIfEnabled(force: false) {
            return
        }

        do {
            snapshot = try await api.fetchSnapshot()
            isConnected = true
            errorMessage = nil
            lastSyncStatus = api.isOffline ? "Updated locally" : "Synced"

            // Cache for instant launch next time
            if let snapshot { await SnapshotCache.shared.save(snapshot) }

            // Update Lock Screen / Home Screen widget
            updateWidgetData()

            // Flush any queued offline captures
            let flushedNotes = await CaptureQueue.shared.flushNotes(using: api)
            let flushedDecisions = await CaptureQueue.shared.flushDecisions(using: api)
            let flushedFeedback = await CaptureQueue.shared.flushFeedback(using: api)
            if flushedNotes + flushedDecisions + flushedFeedback > 0 {
                // Re-sync to pick up server-side changes
                snapshot = try? await api.fetchSnapshot()
                updateWidgetData()
                lastSyncStatus = "Synced queued offline updates"
            }
            await refreshPendingSyncActions()
        } catch {
            isConnected = false
            // Fall back to locally generated snapshot — app still works offline
            _ = await OfflineStore.shared.ensureDemoContentIfNeeded()
            snapshot = await OfflineStore.shared.snapshot()
            if let snapshot { await SnapshotCache.shared.save(snapshot) }
            errorMessage = nil
            lastSyncStatus = "Using local data (offline fallback)"
            await refreshPendingSyncActions()
        }
    }

    func generateNewsletterDraft(period: String = "weekly", mode: String = "weekly-lessons") async -> Bool {
        do {
            let result = try await api.generateNewsletterDraft(
                period: period,
                mode: mode,
                strictSafety: true,
                strictTaste: true
            )
            newsletterStatus = result.status
            await sync()
            return result.status != "error"
        } catch {
            newsletterStatus = "error"
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Widget Data

    private func updateWidgetData() {
        guard let brief = snapshot?.priorities else { return }

        let widgetPriorities = brief.priorities.prefix(3).map { p in
            WidgetPriority(
                rank: p.rank,
                title: p.title,
                whyItMatters: p.whyItMatters,
                nextStep: p.nextStep
            )
        }

        let data = CortexWidgetData(
            topPriority: widgetPriorities.first,
            priorities: Array(widgetPriorities),
            date: brief.date,
            updatedAt: Date()
        )

        WidgetDataBridge.write(data)

        // Tell WidgetKit to refresh
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "CortexFocusWidget")
        #endif
    }

    // MARK: - Decisions

    func recordDecision(_ request: DecisionCreateRequest) async -> Bool {
        do {
            _ = try await api.recordDecision(request)
            // Merge into local snapshot if available
            if snapshot != nil {
                await sync()
            }
            errorMessage = nil
            await refreshPendingSyncActions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await refreshPendingSyncActions()
            return false
        }
    }

    // MARK: - Feedback (was this useful?)

    func sendFeedback(item: String, useful: Bool, acted: Bool? = nil) async {
        do {
            try await api.sendFeedback(FeedbackRequest(item: item, useful: useful, acted: acted))
        } catch {
            // Silent — feedback is best-effort, never block UX
        }
        await refreshPendingSyncActions()
    }

    func applyResurfacingAction(signalID: String, actionType: String, note: String = "") async {
        do {
            try await api.sendSignalFeedback(
                SignalFeedbackRequest(
                    signalID: signalID,
                    actionType: actionType,
                    note: note
                )
            )
            await sync()
        } catch {
            lastSyncStatus = "Resurface action needs server connection"
        }
    }

    // MARK: - Summary Ingestion

    @Published var lastIngestResult: IngestResult?

    func ingestSummary(content: String, source: String = "", tags: [String] = []) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let request = SummaryIngestRequest(content: content, source: source, tags: tags)
            lastIngestResult = try await api.ingestSummary(request)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Demo Mode

    func setDemoMode(enabled: Bool) async {
        await OfflineStore.shared.setDemoModeEnabled(enabled)
        demoModeEnabled = enabled

        if enabled {
            _ = await applyDemoStateIfEnabled(force: true)
        } else {
            await sync()
            await fetchNotes()
            await fetchProfile()
        }
    }

    func populateDemoContent() async {
        await OfflineStore.shared.setDemoModeEnabled(true)
        demoModeEnabled = true
        _ = await applyDemoStateIfEnabled(force: true)
    }

    private func applyDemoStateIfEnabled(force: Bool) async -> Bool {
        guard demoModeEnabled else { return false }

        _ = await OfflineStore.shared.ensureDemoContentIfNeeded(force: force)
        notes = await OfflineStore.shared.listNotes()
        profile = await OfflineStore.shared.getProfile()
        snapshot = await OfflineStore.shared.snapshot()

        if let snapshot {
            await SnapshotCache.shared.save(snapshot)
        }
        updateWidgetData()

        // Demo mode is intentionally local-first to guarantee app reviewability.
        isConnected = true
        errorMessage = nil
        lastSyncStatus = force ? "Demo content loaded" : "Demo mode active"
        await refreshPendingSyncActions()
        return true
    }

    // MARK: - Queue visibility

    func refreshPendingSyncActions() async {
        let counts = await CaptureQueue.shared.pendingCounts()
        pendingSyncActions = counts.total
        pendingNotes = counts.notes
        pendingDecisions = counts.decisions
        pendingFeedback = counts.feedback

        let actions = await CaptureQueue.shared.pendingActions(limit: 30)
        queuedActions = actions.map {
            QueuedActionPreview(
                id: $0.id,
                kind: $0.kind,
                title: $0.title,
                capturedAt: $0.capturedAt
            )
        }
    }

    func retryPendingSyncActions() async {
        if isSyncing { return }

        if api.isOffline {
            lastSyncStatus = "Local Offline Mode — set server URL to sync queued actions"
            await refreshPendingSyncActions()
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let flushedNotes = await CaptureQueue.shared.flushNotes(using: api)
        let flushedDecisions = await CaptureQueue.shared.flushDecisions(using: api)
        let flushedFeedback = await CaptureQueue.shared.flushFeedback(using: api)
        let totalFlushed = flushedNotes + flushedDecisions + flushedFeedback

        if totalFlushed > 0 {
            do {
                snapshot = try await api.fetchSnapshot()
                if let snapshot { await SnapshotCache.shared.save(snapshot) }
                updateWidgetData()
                isConnected = true
                errorMessage = nil
                lastSyncStatus = "Synced queued offline updates"
            } catch {
                isConnected = false
                lastSyncStatus = "Queue synced partially — snapshot refresh failed"
            }
        } else {
            lastSyncStatus = "No queued actions to sync"
        }

        await refreshPendingSyncActions()
    }
}
