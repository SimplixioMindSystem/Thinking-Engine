import Foundation

@MainActor
final class WatchDecisionModel: ObservableObject {
    @Published var snapshot: SyncSnapshot?
    @Published var isSyncing = false
    @Published var status = "Ready"
    @Published var captureText = ""
    @Published var pendingCount = 0
    @Published var isOffline = false

    let api = APIService.shared
    private let iso = ISO8601DateFormatter()

    var topPriority: SyncTodayPriority? {
        snapshot?.today?.priorities.first
    }

    var isLocalMode: Bool {
        api.isOffline
    }

    var updatedStatus: String {
        if api.isOffline { return "Local mode" }
        if isOffline { return "Offline" }
        guard let raw = snapshot?.syncedAt, let date = iso.date(from: raw) else { return status }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return "Updated \(relative.localizedString(for: date, relativeTo: Date()))"
    }

    var captureStatusText: String {
        api.isOffline ? "Stores locally." : (isOffline ? "Queues offline." : "Syncs automatically.")
    }

    func bootstrap() async {
        if let cached = await SnapshotCache.shared.load() {
            snapshot = cached
        }
        if snapshot == nil {
            snapshot = await OfflineStore.shared.snapshot()
        }
        await refreshPending()
        await sync()
    }

    func sync() async {
        if isSyncing { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let fresh = try await api.fetchSnapshot()
            snapshot = fresh
            await SnapshotCache.shared.save(fresh)
            isOffline = api.isOffline

            if api.isOffline {
                status = "Local mode"
            } else {
                let flushedNotes = await CaptureQueue.shared.flushNotes(using: api)
                let flushedDecisions = await CaptureQueue.shared.flushDecisions(using: api)
                let flushedFeedback = await CaptureQueue.shared.flushFeedback(using: api)
                if flushedNotes + flushedDecisions + flushedFeedback > 0 {
                    snapshot = try? await api.fetchSnapshot()
                    status = "Synced queued updates"
                } else {
                    status = "Synced"
                }
            }
        } catch {
            isOffline = true
            if snapshot == nil {
                snapshot = await OfflineStore.shared.snapshot()
            }
            status = "Offline mode"
        }
        await refreshPending()
    }

    func captureByVoice() async {
        let cleaned = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let title = String(cleaned.prefix(90))
        let request = NoteCreateRequest(
            title: title,
            insight: cleaned,
            implication: "Captured from Apple Watch voice flow.",
            action: "Review this in Focus and decide next action.",
            sourceURL: "",
            tags: ["watch", "voice-capture"]
        )

        do {
            _ = try await api.createNote(request)
            captureText = ""
            await refreshPending()
            if api.isOffline {
                status = "Saved locally"
            } else {
                status = pendingCount > 0 ? "Saved, queued for sync" : "Captured"
            }
        } catch {
            status = "Saved offline"
            await refreshPending()
            return
        }
    }

    func sendQuickFeedback(for priority: SyncTodayPriority, useful: Bool, acted: Bool?) async {
        let request = FeedbackRequest(item: priority.title, useful: useful, acted: acted)
        do {
            try await api.sendFeedback(request)
        } catch {
            // Feedback is best-effort; queue handles offline.
        }
        await refreshPending()
        status = pendingCount > 0 ? "Feedback queued" : "Feedback saved"
    }

    private func refreshPending() async {
        let counts = await CaptureQueue.shared.pendingCounts()
        pendingCount = counts.total
    }
}
