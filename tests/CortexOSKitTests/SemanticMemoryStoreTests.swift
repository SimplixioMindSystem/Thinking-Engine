import Foundation
import XCTest
@testable import CortexOSKit

final class SemanticMemoryStoreTests: XCTestCase {
    private final class CountingEmbeddingProvider: SentenceEmbeddingProviding, @unchecked Sendable {
        let identifier: String
        let dimension = 8
        private let lock = NSLock()
        private var callCount = 0

        init(identifier: String = "test.embedding.counting.v1") {
            self.identifier = identifier
        }

        func vector(for text: String) -> [Float]? {
            lock.lock()
            callCount += 1
            lock.unlock()
            var vector = [Float](repeating: 0, count: dimension)
            vector[Int(UInt(bitPattern: text.hashValue) % UInt(dimension))] = 1
            return vector
        }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return callCount
        }
    }

    private struct TestEmbeddingProvider: SentenceEmbeddingProviding {
        let identifier = "test.embedding.v1"
        let dimension = 8

        func vector(for text: String) -> [Float]? {
            let lower = text.lowercased()
            var vector = [Float](repeating: 0, count: dimension)
            if lower.contains("remember") || lower.contains("recall") || lower.contains("memory") {
                vector[0] = 1
            } else if lower.contains("weather") || lower.contains("rain") {
                vector[1] = 1
            } else {
                var hash: UInt64 = 14_695_981_039_346_656_037
                for byte in lower.utf8 {
                    hash ^= UInt64(byte)
                    hash &*= 1_099_511_628_211
                }
                vector[2 + Int(hash % UInt64(dimension - 2))] = 1
            }
            return vector
        }
    }

    private struct BenchmarkEmbeddingProvider: SentenceEmbeddingProviding {
        let identifier = "test.embedding.benchmark.v1"
        let dimension = 512

        func vector(for text: String) -> [Float]? {
            var vector = [Float](repeating: 0, count: dimension)
            if text.lowercased().contains("unique needle") {
                vector[0] = 1
                return vector
            }

            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            vector[1 + Int(hash % UInt64(dimension - 1))] = 1
            return vector
        }
    }

    func testSemanticSearchFindsParaphraseAndPersistsIndex() async throws {
        let url = temporaryDatabaseURL()
        let provider = TestEmbeddingProvider()
        let store = SemanticMemoryStore(fileURL: url, provider: provider)
        let memory = note(id: "memory", title: "Remember important product decisions")
        let weather = note(id: "weather", title: "The weather will be rainy")

        await store.synchronize(notes: [memory, weather])
        let hits = await store.search(query: "recall past choices", limit: 2)

        XCTAssertEqual(hits.first?.id, memory.id)
        let statistics = await store.statistics()
        XCTAssertEqual(statistics.recordCount, 2)
        XCTAssertEqual(statistics.compatibleRecordCount, 2)
        XCTAssertTrue(statistics.isAvailable)
        XCTAssertTrue(statistics.isPersistent)
        XCTAssertGreaterThan(statistics.storageBytes, 0)

        let reopened = SemanticMemoryStore(fileURL: url, provider: provider)
        let persistedHits = await reopened.search(query: "recall past choices", limit: 2)
        XCTAssertEqual(persistedHits.first?.id, memory.id)
    }

    func testSynchronizeSkipsUnchangedContentAndRebuildRegeneratesIt() async throws {
        let provider = CountingEmbeddingProvider()
        let store = SemanticMemoryStore(fileURL: temporaryDatabaseURL(), provider: provider)
        let notes = [
            note(id: "one", title: "First note"),
            note(id: "two", title: "Second note"),
        ]

        await store.synchronize(notes: notes)
        XCTAssertEqual(provider.calls, 2)

        await store.synchronize(notes: notes)
        XCTAssertEqual(provider.calls, 2, "Content hashes should prevent duplicate embedding work")

        await store.rebuild(notes: notes)
        XCTAssertEqual(provider.calls, 4)
        let statistics = await store.statistics()
        XCTAssertEqual(statistics.compatibleRecordCount, 2)
    }

    func testSynchronizeRemovesDeletedAndArchivedRecords() async throws {
        let store = SemanticMemoryStore(
            fileURL: temporaryDatabaseURL(),
            provider: TestEmbeddingProvider()
        )
        let active = note(id: "active", title: "Memory system")
        var archived = note(id: "archived", title: "Remember this")

        await store.synchronize(notes: [active, archived])
        archived.archived = true
        await store.synchronize(notes: [archived])

        let stats = await store.statistics()
        let hits = await store.search(query: "memory", limit: 10)
        XCTAssertEqual(stats.recordCount, 0)
        XCTAssertTrue(hits.isEmpty)
    }

    func testCancelledSynchronizationCannotRemoveCurrentRecords() async throws {
        let store = SemanticMemoryStore(
            fileURL: temporaryDatabaseURL(),
            provider: TestEmbeddingProvider()
        )
        let current = note(id: "current", title: "Remember this")
        await store.synchronize(notes: [current])

        let cancelledSynchronization = Task {
            while !Task.isCancelled { await Task.yield() }
            await store.synchronize(notes: [])
        }
        cancelledSynchronization.cancel()
        await cancelledSynchronization.value

        let statistics = await store.statistics()
        XCTAssertEqual(statistics.recordCount, 1)
    }

    func testTopKUsesStableOrderingForEqualScores() async throws {
        let store = SemanticMemoryStore(
            fileURL: temporaryDatabaseURL(),
            provider: TestEmbeddingProvider()
        )
        let notes = ["zeta", "alpha", "gamma", "beta"].map {
            note(id: $0, title: "Remember \($0)")
        }
        await store.synchronize(notes: notes)

        let hits = await store.search(query: "memory", limit: 3)

        XCTAssertEqual(hits.map(\.id), ["alpha", "beta", "gamma"])
    }

    func testExactSearchAcrossTenThousandVectors() async throws {
        let store = SemanticMemoryStore(
            fileURL: temporaryDatabaseURL(),
            provider: BenchmarkEmbeddingProvider()
        )
        var notes = (0..<9_999).map {
            note(id: "note-\($0)", title: "Background note \($0)")
        }
        notes.append(note(id: "needle", title: "Unique needle"))
        await store.synchronize(notes: notes)

        let start = ContinuousClock.now
        let hits = await store.search(query: "unique needle", limit: 10)
        let elapsed = start.duration(to: .now)

        let warmStart = ContinuousClock.now
        let warmHits = await store.search(query: "unique needle", limit: 10)
        let warmElapsed = warmStart.duration(to: .now)

        XCTAssertEqual(hits.first?.id, "needle")
        XCTAssertEqual(warmHits.first?.id, "needle")
        XCTAssertLessThan(warmElapsed, .seconds(2))
        if ProcessInfo.processInfo.environment["SIMPLIXIO_ENFORCE_COLD_SEARCH_BUDGET"] == "1" {
            XCTAssertLessThan(elapsed, .seconds(5))
        }
        print("Semantic search over 10,000 × 512 vectors: \(elapsed)")
        print("Warm semantic search over 10,000 × 512 vectors: \(warmElapsed)")
    }

    func testServerSnapshotReconciliationPreservesPendingLocalNotes() {
        let staleServer = note(id: "server-stale", title: "Old server note")
        let previousServer = note(id: "server-current", title: "Old title")
        let localCapture = note(id: "local-pending", title: "Pending capture")
        let demo = note(id: "demo-note-1", title: "Demo content")
        let refreshedServer = note(id: "server-current", title: "Updated title")

        let merged = OfflineStore.mergedServerSnapshot(
            serverNotes: [refreshedServer, refreshedServer],
            existingNotes: [staleServer, previousServer, localCapture, demo],
            cachedServerIDs: [staleServer.id, previousServer.id]
        )

        XCTAssertEqual(merged.map(\.id), [refreshedServer.id, localCapture.id])
        XCTAssertEqual(merged.first?.title, "Updated title")
        XCTAssertFalse(merged.contains(where: { $0.id == staleServer.id }))
        XCTAssertFalse(merged.contains(where: { $0.id == demo.id }))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simplixio-semantic-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("semantic.sqlite")
    }

    private func note(id: String, title: String) -> KnowledgeNote {
        KnowledgeNote(
            id: id,
            title: title,
            insight: "",
            implication: "",
            action: "",
            sourceURL: "",
            tags: [],
            createdAt: "2026-07-16T00:00:00Z",
            updatedAt: "2026-07-16T00:00:00Z",
            archived: false
        )
    }
}
