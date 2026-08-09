import Foundation

@MainActor
final class WatchDecisionModel: ObservableObject {
    @Published var snapshot: SyncSnapshot?
    @Published var isSyncing = false
    @Published var status = "Ready"
    @Published var captureText = ""
    @Published var isOffline = false
    @Published var iCloudSyncEnabled = true

    private let store = OfflineStore.shared
    private let cloudSync = ICloudSyncService.shared
    private let iso = ISO8601DateFormatter()
    private var cloudSyncTask: Task<Void, Never>?
    private var cloudSyncID: UUID?
    private var cloudSyncRequestedAfterCurrent = false

    var topPriority: SyncTodayPriority? {
        snapshot?.today?.priorities.first
    }

    var isLocalMode: Bool {
        !iCloudSyncEnabled
    }

    var updatedStatus: String {
        if isLocalMode { return "On this Watch" }
        if isOffline { return status }
        guard let raw = snapshot?.syncedAt, let date = iso.date(from: raw) else { return status }
        if abs(date.timeIntervalSinceNow) < 60 { return "Updated now" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return "Updated \(relative.localizedString(for: date, relativeTo: Date()))"
    }

    var captureStatusText: String {
        if isLocalMode { return "Saves on this Watch." }
        if isOffline { return "Saves here; iCloud retries." }
        return "Saves here, then syncs privately."
    }

    func bootstrap() async {
        if ProcessInfo.processInfo.arguments.contains("-UITests") {
            await store.setDemoModeEnabled(true)
            _ = await store.ensureDemoContentIfNeeded(force: true)
        }
        if let cached = await SnapshotCache.shared.load() {
            snapshot = cached
        }
        iCloudSyncEnabled = await cloudSync.isEnabled
        await sync()
    }

    func sync() async {
        snapshot = await store.snapshot()
        if let snapshot {
            await SnapshotCache.shared.save(snapshot)
        }

        guard cloudSyncTask == nil else {
            cloudSyncRequestedAfterCurrent = true
            return
        }
        isSyncing = true
        let operationID = UUID()
        cloudSyncID = operationID

        let cloudSync = self.cloudSync
        let store = self.store
        cloudSyncTask = Task(priority: .utility) { [weak self] in
            let result = await cloudSync.synchronize(store: store)
            guard !Task.isCancelled else { return }
            await self?.completeSync(result, operationID: operationID)
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.markSyncAsContinuing(operationID: operationID)
        }
    }

    private func completeSync(_ result: ICloudSyncResult, operationID: UUID) async {
        guard cloudSyncID == operationID else { return }
        let shouldSyncAgain = cloudSyncRequestedAfterCurrent
        cloudSyncRequestedAfterCurrent = false
        cloudSyncTask = nil
        cloudSyncID = nil
        isSyncing = false
        iCloudSyncEnabled = await cloudSync.isEnabled
        switch result.state {
        case .synced:
            isOffline = false
            status = "Private iCloud sync"
        case .disabled:
            isOffline = false
            status = "On this Watch"
        case .localOnly, .waitingForKey, .failed:
            isOffline = true
            status = "Saved locally"
        case .storageFull:
            isOffline = true
            status = "iCloud storage full"
        }

        snapshot = await store.snapshot()
        if let snapshot {
            await SnapshotCache.shared.save(snapshot)
        }
        if shouldSyncAgain {
            await sync()
        }
    }

    private func markSyncAsContinuing(operationID: UUID) {
        guard cloudSyncID == operationID, cloudSyncTask != nil else { return }
        isSyncing = false
        isOffline = true
        status = "Saved locally"
    }

    func saveCapture() async {
        let cleaned = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        _ = await store.createNote(
            NoteCreateRequest(
                title: String(cleaned.prefix(90)),
                insight: cleaned,
                implication: "Captured from Apple Watch for later prioritisation.",
                action: "Review this signal and choose its next concrete step.",
                sourceURL: "",
                tags: ["watch", "capture"]
            )
        )
        captureText = ""
        status = "Saved locally"
        await sync()
    }

    func sendQuickFeedback(for priority: SyncTodayPriority, useful: Bool, acted: Bool?) async {
        await store.recordFeedback(FeedbackRequest(item: priority.title, useful: useful, acted: acted))
        status = "Feedback saved"
        await sync()
    }
}
