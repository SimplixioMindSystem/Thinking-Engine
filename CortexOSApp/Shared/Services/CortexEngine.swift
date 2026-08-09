//
//  CortexEngine.swift
//  CortexOS
//
//  On-device product engine. User data is committed locally first and may be
//  synchronized privately through the user's iCloud account.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class CortexEngine: ObservableObject {
    @Published var notes: [KnowledgeNote] = []
    @Published var profile: UserProfile = .empty
    @Published var snapshot: SyncSnapshot?
    @Published var isConnected = true
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncStatus: String?
    @Published var newsletterStatus: String?
    @Published var demoModeEnabled = false
    @Published var semanticIndexStatus: SemanticIndexStatus?
    @Published var isRebuildingSemanticIndex = false
    @Published private(set) var iCloudSyncEnabled = true
    @Published private(set) var iCloudSyncState: ICloudSyncState = .localOnly

    @Published var lastIngestResult: IngestResult?

    private let store: OfflineStore
    private let cloudSync: ICloudSyncService
    private var noteRequestGeneration: UInt64 = 0
    private var semanticPreparationTask: Task<Void, Never>?
    private var semanticPreparationRequested = false
    private var cloudSyncTask: Task<Void, Never>?
    private var cloudSyncID: UUID?
    private var cloudSyncRequestedAfterCurrent = false

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITests")
    }

    private var usesUITestPreview: Bool {
        isRunningUITests && !ProcessInfo.processInfo.arguments.contains("-UITestsNoDemo")
    }

    init(
        store: OfflineStore = .shared,
        cloudSync: ICloudSyncService = .shared
    ) {
        self.store = store
        self.cloudSync = cloudSync

        Task { [weak self] in
            guard let self else { return }
            if let cached = await SnapshotCache.shared.load() {
                snapshot = cached
            }
            demoModeEnabled = await store.isDemoModeEnabled()
            iCloudSyncEnabled = await cloudSync.isEnabled
            _ = await store.ensureDemoContentIfNeeded()
            await reloadLocalState()
            resumeSemanticIndexing()
        }
    }

    // MARK: - Notes

    func fetchNotes() async {
        let generation = beginNoteRequest()
        isLoading = true
        defer {
            if isCurrentNoteRequest(generation) { isLoading = false }
        }
        let result = await store.listNotes()
        guard isCurrentNoteRequest(generation), !Task.isCancelled else { return }
        notes = result
        errorMessage = nil
        resumeSemanticIndexing()
    }

    func createNote(_ request: NoteCreateRequest) async -> Bool {
        let note = await store.createNote(request)
        notes.removeAll { $0.id == note.id }
        notes.insert(note, at: 0)
        errorMessage = nil
        await synchronizeAfterMutation()
        resumeSemanticIndexing()
        return true
    }

    func deleteNote(_ id: String) async -> Bool {
        await store.deleteNote(id: id)
        notes.removeAll { $0.id == id }
        errorMessage = nil
        await synchronizeAfterMutation()
        resumeSemanticIndexing()
        return true
    }

    func searchNotes(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await fetchNotes()
            return
        }

        let generation = beginNoteRequest()
        isLoading = true
        defer {
            if isCurrentNoteRequest(generation) { isLoading = false }
        }
        let result = await store.searchNotes(query: trimmed)
        guard isCurrentNoteRequest(generation), !Task.isCancelled else { return }
        notes = result
        errorMessage = nil
    }

    private func beginNoteRequest() -> UInt64 {
        noteRequestGeneration &+= 1
        return noteRequestGeneration
    }

    private func isCurrentNoteRequest(_ generation: UInt64) -> Bool {
        generation == noteRequestGeneration
    }

    // MARK: - Private sync

    func sync() async {
        if demoModeEnabled || usesUITestPreview {
            cancelCloudSync()
            _ = await applyDemoStateIfEnabled(force: false)
            iCloudSyncState = .disabled
            iCloudSyncEnabled = await cloudSync.isEnabled
            lastSyncStatus = "Preview content stays on this device"
            return
        }

        await reloadLocalState()
        scheduleCloudSync(showProgress: true)
    }

    func setICloudSync(enabled: Bool) async {
        await cloudSync.setEnabled(enabled)
        iCloudSyncEnabled = enabled
        if enabled {
            await sync()
        } else {
            cancelCloudSync()
            iCloudSyncState = .disabled
            isConnected = true
            lastSyncStatus = "Saved only on this device"
        }
    }

    private func synchronizeAfterMutation() async {
        if demoModeEnabled {
            await reloadLocalState()
            lastSyncStatus = "Saved preview on this device"
            return
        }

        // Local state is authoritative. Never make capture or feedback wait
        // for iCloud account and Keychain reconciliation.
        await reloadLocalState()
        lastSyncStatus = "Saved on this device"
        scheduleCloudSync(showProgress: false)
    }

    private func scheduleCloudSync(showProgress: Bool) {
        if let cloudSyncID, cloudSyncTask != nil {
            cloudSyncRequestedAfterCurrent = true
            if showProgress {
                isSyncing = true
                lastSyncStatus = "Syncing privately…"
                scheduleSyncProgressTimeout(for: cloudSyncID)
            }
            return
        }

        let operationID = UUID()
        cloudSyncID = operationID
        if showProgress {
            isSyncing = true
            lastSyncStatus = "Syncing privately…"
            scheduleSyncProgressTimeout(for: operationID)
        }

        let cloudSync = self.cloudSync
        let store = self.store
        cloudSyncTask = Task(priority: .utility) { [weak self] in
            let result = await cloudSync.synchronize(store: store)
            guard !Task.isCancelled else { return }
            await self?.completeCloudSync(result, operationID: operationID)
        }
    }

    private func scheduleSyncProgressTimeout(for operationID: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.markCloudSyncAsContinuing(operationID: operationID)
        }
    }

    private func markCloudSyncAsContinuing(operationID: UUID) {
        guard cloudSyncID == operationID, cloudSyncTask != nil else { return }
        isSyncing = false
        iCloudSyncState = .localOnly
        isConnected = false
        lastSyncStatus = "Saved locally - iCloud is still retrying"
    }

    private func completeCloudSync(_ result: ICloudSyncResult, operationID: UUID) async {
        guard cloudSyncID == operationID else { return }
        let shouldSyncAgain = cloudSyncRequestedAfterCurrent
        cloudSyncRequestedAfterCurrent = false
        cloudSyncTask = nil
        cloudSyncID = nil
        isSyncing = false
        applySyncResult(result)
        await reloadLocalState()
        if shouldSyncAgain {
            scheduleCloudSync(showProgress: false)
        }
    }

    private func cancelCloudSync() {
        cloudSyncTask?.cancel()
        cloudSyncTask = nil
        cloudSyncID = nil
        cloudSyncRequestedAfterCurrent = false
        isSyncing = false
    }

    private func applySyncResult(_ result: ICloudSyncResult) {
        iCloudSyncState = result.state
        iCloudSyncEnabled = result.state != .disabled
        isConnected = result.state == .synced || result.state == .disabled
        lastSyncStatus = result.userMessage
        if case let .failed(message) = result.state {
            errorMessage = message
        } else {
            errorMessage = nil
        }
    }

    private func reloadLocalState() async {
        notes = await store.listNotes()
        profile = await store.getProfile()
        snapshot = await store.snapshot()
        if let snapshot {
            await SnapshotCache.shared.save(snapshot)
        }
        updateWidgetData()
    }

    // MARK: - On-device semantic index

    func resumeSemanticIndexing() {
        semanticPreparationRequested = true
        guard semanticPreparationTask == nil else { return }
        semanticPreparationTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                semanticPreparationRequested = false
                await store.prepareSemanticIndex()
                guard !Task.isCancelled else { break }
                let status = await store.semanticIndexStatus()
                guard !Task.isCancelled else { break }
                if semanticPreparationRequested { continue }
                semanticIndexStatus = status
                semanticPreparationTask = nil
                return
            }
            semanticPreparationTask = nil
        }
    }

    func refreshSemanticIndexStatus() async {
        semanticIndexStatus = await store.semanticIndexStatus()
    }

    func rebuildSemanticIndex() async {
        guard !isRebuildingSemanticIndex else { return }
        semanticPreparationTask?.cancel()
        semanticPreparationTask = nil
        semanticPreparationRequested = false
        isRebuildingSemanticIndex = true
        defer { isRebuildingSemanticIndex = false }

        await store.rebuildSemanticIndex()
        semanticIndexStatus = await store.semanticIndexStatus()
    }

    // MARK: - Profile

    func fetchProfile() async {
        profile = await store.getProfile()
        errorMessage = nil
    }

    func saveProfile(_ update: ProfileUpdate) async -> Bool {
        profile = await store.updateProfile(update)
        errorMessage = nil
        await synchronizeAfterMutation()
        return true
    }

    // MARK: - Newsletter

    func generateNewsletterDraft(period: String = "weekly", mode: String = "weekly-lessons") async -> Bool {
        let result = await store.generateNewsletterDraft(period: period, mode: mode)
        newsletterStatus = result.reason ?? newsletterStatusMessage(for: result.status)
        if result.status == "error" || result.status == "not_enough_material" {
            errorMessage = result.reason
            await reloadLocalState()
            return false
        }
        errorMessage = nil
        await reloadLocalState()
        return true
    }

    func approveNewsletterDraft() async -> Bool {
        let approved = await store.approveNewsletterDraft()
        newsletterStatus = approved
            ? "Draft approved. Sharing is now available."
            : "Approval is blocked until safety, quality, and full review requirements pass."
        await reloadLocalState()
        return approved
    }

    func rejectNewsletterDraft() async {
        await store.rejectNewsletterDraft()
        newsletterStatus = "Draft rejected. Nothing was shared."
        await reloadLocalState()
    }

    private func newsletterStatusMessage(for status: String) -> String {
        switch status {
        case "needs_review":
            return "Draft ready for your review."
        case "approved":
            return "Draft approved."
        case "rejected":
            return "Draft needs revision before sharing."
        default:
            return "Draft updated."
        }
    }

    // MARK: - Widget data

    private func updateWidgetData() {
        guard let brief = snapshot?.priorities else { return }
        let widgetPriorities = brief.priorities.prefix(3).map { priority in
            WidgetPriority(
                rank: priority.rank,
                title: priority.title,
                whyItMatters: priority.whyItMatters,
                nextStep: priority.nextStep
            )
        }
        let data = CortexWidgetData(
            topPriority: widgetPriorities.first,
            priorities: Array(widgetPriorities),
            date: brief.date,
            updatedAt: Date()
        )
        WidgetDataBridge.write(data)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "CortexFocusWidget")
        #endif
    }

    // MARK: - Decisions and feedback

    func recordDecision(_ request: DecisionCreateRequest) async -> Bool {
        _ = await store.recordDecision(request)
        errorMessage = nil
        await synchronizeAfterMutation()
        return true
    }

    func sendFeedback(item: String, useful: Bool, acted: Bool? = nil) async {
        await store.recordFeedback(FeedbackRequest(item: item, useful: useful, acted: acted))
        await synchronizeAfterMutation()
    }

    func applyResurfacingAction(signalID: String, actionType: String, note: String = "") async {
        let feedback: FeedbackRequest
        switch actionType {
        case "acted_on":
            feedback = FeedbackRequest(item: signalID, useful: true, acted: true)
        case "dismissed":
            feedback = FeedbackRequest(item: signalID, useful: false, acted: nil)
        default:
            feedback = FeedbackRequest(item: signalID, useful: true, acted: false)
        }
        await store.recordFeedback(feedback)
        await synchronizeAfterMutation()
    }

    // MARK: - Summary ingestion

    func ingestSummary(content: String, source: String = "", tags: [String] = []) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        let request = SummaryIngestRequest(content: content, source: source, tags: tags)
        lastIngestResult = await store.ingestSummary(request)
        errorMessage = nil
        await synchronizeAfterMutation()
        return true
    }

    // MARK: - Preview content

    func setDemoMode(enabled: Bool) async {
        await store.setDemoModeEnabled(enabled)
        demoModeEnabled = enabled
        if enabled {
            cancelCloudSync()
            _ = await applyDemoStateIfEnabled(force: true)
        } else {
            await sync()
        }
    }

    func populateDemoContent() async {
        cancelCloudSync()
        await store.setDemoModeEnabled(true)
        demoModeEnabled = true
        _ = await applyDemoStateIfEnabled(force: true)
    }

    private func applyDemoStateIfEnabled(force: Bool) async -> Bool {
        guard demoModeEnabled else { return false }
        let populated = await store.ensureDemoContentIfNeeded(force: force)
        if force && !populated {
            await store.setDemoModeEnabled(false)
            demoModeEnabled = false
        }
        await reloadLocalState()
        isConnected = true
        errorMessage = nil
        if force && !populated {
            lastSyncStatus = "Your captures stay active; preview content was not added"
        } else {
            lastSyncStatus = force ? "Preview content loaded" : "Preview mode active"
        }
        return true
    }
}
