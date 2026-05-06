//
//  APIService.swift
//  CortexOS
//
//  Networking layer that talks to the CortexOS Python API server.
//  Uses async/await and Codable for clean Swift concurrency.
//

import Foundation

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)
    case timeout(seconds: Double)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingError(let err):
            return "Decoding error: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .timeout(let seconds):
            return "Request timed out after \(Int(seconds))s."
        }
    }
}

// MARK: - Service

@MainActor
final class APIService: ObservableObject {
    static let serverURLDefaultsKey = "cortex_api_url"
    static let defaultServerURL = "https://cortex-thinking-engine-production.up.railway.app"

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: APIService.serverURLDefaultsKey) }
    }

    var isOffline: Bool {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let shared = APIService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let requestTimeoutSeconds: Double = 10

    init(baseURL: String? = nil) {
        let saved = UserDefaults.standard.string(forKey: APIService.serverURLDefaultsKey)
        self.baseURL = baseURL ?? saved ?? APIService.defaultServerURL

        let config = URLSessionConfiguration.default
        // Keep UI responsive in weak/no-network review environments.
        // We want fast fallback to local/offline data instead of long hangs.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Generic request

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        if isOffline {
            throw APIError.networkError(NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "Offline mode: no server URL configured"]))
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await dataWithTimeout(for: req)
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func requestNoContent(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws {
        if isOffline {
            throw APIError.networkError(NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "Offline mode: no server URL configured"]))
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, response) = try await dataWithTimeout(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func dataWithTimeout(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { [session] in
                try await session.data(for: request)
            }
            group.addTask { [requestTimeoutSeconds] in
                let nanos = UInt64(requestTimeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                throw APIError.timeout(seconds: requestTimeoutSeconds)
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw APIError.timeout(seconds: requestTimeoutSeconds)
            }
            return result
        }
    }

    // MARK: - Health

    func health() async throws -> ServerHealth {
        if isOffline {
            return await OfflineStore.shared.serverHealth()
        }
        return try await request("GET", path: "/health")
    }

    // MARK: - Knowledge Notes

    func createNoteRemote(_ body: NoteCreateRequest) async throws -> KnowledgeNote {
        try await request("POST", path: "/notes/", body: body)
    }

    func listNotes(includeArchived: Bool = false) async throws -> [KnowledgeNote] {
        if isOffline {
            return await OfflineStore.shared.listNotes(includeArchived: includeArchived)
        }
        do {
            return try await request("GET", path: "/notes/?include_archived=\(includeArchived)")
        } catch {
            return await OfflineStore.shared.listNotes(includeArchived: includeArchived)
        }
    }

    func getNote(id: String) async throws -> KnowledgeNote {
        if isOffline, let note = await OfflineStore.shared.getNote(id: id) {
            return note
        }
        do {
            return try await request("GET", path: "/notes/\(id)")
        } catch {
            if let note = await OfflineStore.shared.getNote(id: id) {
                return note
            }
            throw error
        }
    }

    func createNote(_ body: NoteCreateRequest) async throws -> KnowledgeNote {
        if isOffline {
            let local = await OfflineStore.shared.createNote(body)
            await CaptureQueue.shared.enqueueNote(
                title: body.title,
                insight: body.insight,
                implication: body.implication,
                action: body.action,
                sourceURL: body.sourceURL,
                tags: body.tags
            )
            return local
        }
        do {
            return try await createNoteRemote(body)
        } catch {
            let local = await OfflineStore.shared.createNote(body)
            await CaptureQueue.shared.enqueueNote(
                title: body.title,
                insight: body.insight,
                implication: body.implication,
                action: body.action,
                sourceURL: body.sourceURL,
                tags: body.tags
            )
            return local
        }
    }

    func updateNote(id: String, _ body: NoteUpdateRequest) async throws -> KnowledgeNote {
        if isOffline, let note = await OfflineStore.shared.updateNote(id: id, with: body) {
            return note
        }
        do {
            return try await request("PATCH", path: "/notes/\(id)", body: body)
        } catch {
            if let note = await OfflineStore.shared.updateNote(id: id, with: body) {
                return note
            }
            throw error
        }
    }

    func deleteNote(id: String) async throws {
        if isOffline {
            await OfflineStore.shared.deleteNote(id: id)
            return
        }
        do {
            try await requestNoContent("DELETE", path: "/notes/\(id)")
        } catch {
            await OfflineStore.shared.deleteNote(id: id)
        }
    }

    func searchNotes(query: String) async throws -> [KnowledgeNote] {
        if isOffline {
            return await OfflineStore.shared.searchNotes(query: query)
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        do {
            return try await request("GET", path: "/notes/search?q=\(encoded)")
        } catch {
            return await OfflineStore.shared.searchNotes(query: query)
        }
    }

    // MARK: - Profile

    func getProfile() async throws -> UserProfile {
        if isOffline {
            return await OfflineStore.shared.getProfile()
        }
        do {
            return try await request("GET", path: "/profile/")
        } catch {
            return await OfflineStore.shared.getProfile()
        }
    }

    func updateProfile(_ body: ProfileUpdate) async throws -> UserProfile {
        if isOffline {
            return await OfflineStore.shared.updateProfile(body)
        }
        do {
            return try await request("PATCH", path: "/profile/", body: body)
        } catch {
            return await OfflineStore.shared.updateProfile(body)
        }
    }

    // MARK: - Sync

    func fetchSnapshot() async throws -> SyncSnapshot {
        if isOffline {
            return await OfflineStore.shared.snapshot()
        }
        return try await request("GET", path: "/sync/snapshot")
    }

    func generateNewsletterDraft(
        period: String = "weekly",
        mode: String = "weekly-lessons",
        strictSafety: Bool = true,
        strictTaste: Bool = true
    ) async throws -> NewsletterGenerationResult {
        if isOffline {
            throw APIError.networkError(
                NSError(
                    domain: NSURLErrorDomain,
                    code: -1009,
                    userInfo: [NSLocalizedDescriptionKey: "Newsletter generation requires server connection."]
                )
            )
        }
        let requestBody = NewsletterGenerateRequest(
            period: period,
            mode: mode,
            strictSafety: strictSafety,
            strictTaste: strictTaste
        )
        return try await request("POST", path: "/sync/newsletter/generate", body: requestBody)
    }

    // MARK: - Context (mutations)

    func recordDecisionRemote(_ body: DecisionCreateRequest) async throws -> SyncDecision {
        try await request("POST", path: "/context/decision", body: body)
    }

    func recordDecision(_ body: DecisionCreateRequest) async throws -> SyncDecision {
        if isOffline {
            let local = await OfflineStore.shared.recordDecision(body)
            await CaptureQueue.shared.enqueueDecision(
                decision: body.decision,
                reason: body.reason,
                project: body.project,
                assumptions: body.assumptions
            )
            return local
        }
        do {
            return try await recordDecisionRemote(body)
        } catch {
            let local = await OfflineStore.shared.recordDecision(body)
            await CaptureQueue.shared.enqueueDecision(
                decision: body.decision,
                reason: body.reason,
                project: body.project,
                assumptions: body.assumptions
            )
            return local
        }
    }

    func recordOutcome(_ body: OutcomeCreateRequest) async throws -> SyncDecision {
        if isOffline, let decision = await OfflineStore.shared.recordOutcome(body) {
            return decision
        }
        do {
            return try await request("POST", path: "/context/outcome", body: body)
        } catch {
            if let decision = await OfflineStore.shared.recordOutcome(body) {
                return decision
            }
            throw error
        }
    }

    func storeInsight(_ body: InsightCreateRequest) async throws -> SyncInsight {
        if isOffline {
            return await OfflineStore.shared.storeInsight(body)
        }
        do {
            return try await request("POST", path: "/context/insight", body: body)
        } catch {
            return await OfflineStore.shared.storeInsight(body)
        }
    }

    // MARK: - Feedback

    func sendFeedbackRemote(_ body: FeedbackRequest) async throws {
        try await requestNoContent("POST", path: "/context/feedback", body: body)
    }

    func sendFeedback(_ body: FeedbackRequest) async throws {
        if isOffline {
            await CaptureQueue.shared.enqueueFeedback(item: body.item, useful: body.useful, acted: body.acted)
            return
        }
        do {
            try await sendFeedbackRemote(body)
        } catch {
            await CaptureQueue.shared.enqueueFeedback(item: body.item, useful: body.useful, acted: body.acted)
            throw error
        }
    }

    func sendSignalFeedback(_ body: SignalFeedbackRequest) async throws {
        if isOffline {
            throw APIError.networkError(
                NSError(
                    domain: NSURLErrorDomain,
                    code: -1009,
                    userInfo: [NSLocalizedDescriptionKey: "Signal resurfacing actions require server connection."]
                )
            )
        }
        try await requestNoContent("POST", path: "/context/signals/feedback", body: body)
    }

    func sendSignalOverride(_ body: SignalOverrideRequest) async throws {
        if isOffline {
            throw APIError.networkError(
                NSError(
                    domain: NSURLErrorDomain,
                    code: -1009,
                    userInfo: [NSLocalizedDescriptionKey: "Signal resurfacing overrides require server connection."]
                )
            )
        }
        try await requestNoContent("POST", path: "/context/signals/override", body: body)
    }

    // MARK: - Summary Ingestion

    func ingestSummary(_ body: SummaryIngestRequest) async throws -> IngestResult {
        if isOffline {
            return await OfflineStore.shared.ingestSummary(body)
        }
        do {
            return try await request("POST", path: "/ingest/summary", body: body)
        } catch {
            return await OfflineStore.shared.ingestSummary(body)
        }
    }
}

// MARK: - Helpers

/// Type-erased Encodable wrapper.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
