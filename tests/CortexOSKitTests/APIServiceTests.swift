//
//  APIServiceTests.swift
//  CortexOSKitTests
//
//  Tests for APIService URL construction and error types.
//

import Foundation
import XCTest
@testable import CortexOSKit

private final class NoteURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var requestedURLs: [URL] = []

    static func reset(responseData: Data) {
        lock.lock()
        self.responseData = responseData
        requestedURLs = []
        lock.unlock()
    }

    static func requests() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        Self.requestedURLs.append(url)
        let data = Self.responseData
        Self.lock.unlock()

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor ConnectedNoteStoreStub: NoteStoreProviding {
    private var notes: [KnowledgeNote] = []
    private let pendingNoteIDs: Set<String>
    private var hasSnapshot = false
    private var preparationCount = 0
    private var searchQueries: [String] = []

    init(notes: [KnowledgeNote] = [], pendingNoteIDs: Set<String> = []) {
        self.notes = notes
        self.pendingNoteIDs = pendingNoteIDs
    }

    func listNotes(includeArchived: Bool) -> [KnowledgeNote] {
        notes.filter { includeArchived || !$0.archived }
    }

    func getNote(id: String) -> KnowledgeNote? {
        notes.first { $0.id == id }
    }

    func createNote(_ body: NoteCreateRequest) -> KnowledgeNote {
        fatalError("Not used by this test")
    }

    func updateNote(id: String, with body: NoteUpdateRequest) -> KnowledgeNote? {
        fatalError("Not used by this test")
    }

    func deleteNote(id: String) {
        notes.removeAll { $0.id == id }
    }

    func cacheServerSnapshot(_ notes: [KnowledgeNote], sourceIdentifier: String) {
        let incomingIDs = Set(notes.map(\.id))
        let pending = self.notes.filter {
            pendingNoteIDs.contains($0.id) && !incomingIDs.contains($0.id)
        }
        self.notes = notes + pending
        hasSnapshot = true
    }

    func cacheServerNote(_ note: KnowledgeNote, sourceIdentifier: String) {
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }

    func removeCachedServerNote(id: String, sourceIdentifier: String) {
        notes.removeAll { $0.id == id }
    }

    func hasCompleteServerSnapshot(sourceIdentifier: String) -> Bool {
        hasSnapshot
    }

    func prepareSemanticIndex() {
        preparationCount += 1
    }

    func searchNotes(query: String) -> [KnowledgeNote] {
        searchQueries.append(query)
        let normalized = query.lowercased()
        return notes.filter { $0.lexicalSearchText.lowercased().contains(normalized) }
    }

    func observedState() -> (preparations: Int, queries: [String]) {
        (preparationCount, searchQueries)
    }
}

final class APIErrorTests: XCTestCase {

    func testInvalidURLDescription() {
        let error = APIError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid server URL.")
    }

    func testHTTPErrorDescription() {
        let error = APIError.httpError(statusCode: 404, body: "Not Found")
        XCTAssertEqual(error.errorDescription, "HTTP 404: Not Found")
    }

    func testDecodingErrorDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad json"])
        let error = APIError.decodingError(underlying)
        XCTAssertTrue(error.errorDescription?.contains("Decoding error") ?? false)
    }

    func testNetworkErrorDescription() {
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "offline"])
        let error = APIError.networkError(underlying)
        XCTAssertTrue(error.errorDescription?.contains("Network error") ?? false)
    }
}

@MainActor
final class APIServiceInitTests: XCTestCase {

    func testDefaultBaseURL() {
        let service = APIService(baseURL: "http://test:9999")
        XCTAssertEqual(service.baseURL, "http://test:9999")
    }

    func testNewInstallDefaultsToLocalOnly() {
        let service = APIService(baseURL: "")
        XCTAssertEqual(APIService.defaultServerURL, "")
        XCTAssertTrue(service.isOffline)
    }

    func testConnectedSearchHydratesOnceThenQueriesOnlyTheEmbeddedStore() async throws {
        let note = KnowledgeNote(
            id: "server-note",
            title: "Offline continuity increases trust",
            insight: "Local search stays responsive.",
            implication: "Search does not need a round trip.",
            action: "Keep the index embedded.",
            sourceURL: "https://example.com/note",
            tags: ["offline"],
            createdAt: "2026-07-17T00:00:00Z",
            updatedAt: "2026-07-17T00:00:00Z",
            archived: false
        )
        NoteURLProtocolStub.reset(responseData: try JSONEncoder().encode([note]))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoteURLProtocolStub.self]
        let store = ConnectedNoteStoreStub()
        let service = APIService(
            baseURL: "https://connected-search-test.example",
            session: URLSession(configuration: configuration),
            noteStore: store
        )

        let first = try await service.searchNotes(query: "offline")
        let second = try await service.searchNotes(query: "continuity")

        XCTAssertEqual(first.map(\.id), [note.id])
        XCTAssertEqual(second.map(\.id), [note.id])
        let requests = NoteURLProtocolStub.requests()
        XCTAssertEqual(requests.count, 1, "Only the initial note snapshot should use the network")
        XCTAssertEqual(requests.first?.path, "/notes")
        XCTAssertFalse(requests.contains { $0.path.contains("search") })

        let state = await store.observedState()
        XCTAssertEqual(state.preparations, 1)
        XCTAssertEqual(state.queries, ["offline", "continuity"])
    }

    func testConnectedListReturnsServerNotesAndPendingLocalCaptures() async throws {
        let server = KnowledgeNote(
            id: "server-note",
            title: "Synced note",
            insight: "",
            implication: "",
            action: "",
            sourceURL: "",
            tags: [],
            createdAt: "2026-07-17T00:00:00Z",
            updatedAt: "2026-07-17T00:00:00Z",
            archived: false
        )
        let pending = KnowledgeNote(
            id: "pending-local-note",
            title: "Pending local capture",
            insight: "",
            implication: "",
            action: "",
            sourceURL: "",
            tags: [],
            createdAt: "2026-07-18T00:00:00Z",
            updatedAt: "2026-07-18T00:00:00Z",
            archived: false
        )
        NoteURLProtocolStub.reset(responseData: try JSONEncoder().encode([server]))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoteURLProtocolStub.self]
        let store = ConnectedNoteStoreStub(
            notes: [pending],
            pendingNoteIDs: [pending.id]
        )
        let service = APIService(
            baseURL: "https://connected-list-test.example",
            session: URLSession(configuration: configuration),
            noteStore: store
        )

        let listed = try await service.listNotes()

        XCTAssertEqual(listed.map(\.id), [server.id, pending.id])
    }
}
