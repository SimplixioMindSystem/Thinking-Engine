import Foundation
#if !os(watchOS)
import Accelerate
import CryptoKit
import NaturalLanguage
import SQLite3
#endif

struct SemanticIndexStatus: Equatable, Sendable {
    let indexedNotes: Int
    let totalNotes: Int
    let dimension: Int
    let modelIdentifier: String?
    let isAvailable: Bool
    let isPersistent: Bool
    let storageBytes: Int64
    let errorDescription: String?

    var isReady: Bool {
        isAvailable && isPersistent && indexedNotes >= totalNotes
    }
}

#if !os(watchOS)

struct SemanticSearchHit: Equatable, Sendable {
    let id: String
    let score: Float
}

struct SemanticIndexStatistics: Equatable, Sendable {
    let recordCount: Int
    let compatibleRecordCount: Int
    let dimension: Int
    let modelIdentifier: String?
    let isAvailable: Bool
    let isPersistent: Bool
    let storageBytes: Int64
    let errorDescription: String?
}

protocol SentenceEmbeddingProviding: Sendable {
    var identifier: String { get }
    var dimension: Int { get }
    func vector(for text: String) -> [Float]?
}

final class AppleSentenceEmbeddingProvider: SentenceEmbeddingProviding, @unchecked Sendable {
    private let embedding: NLEmbedding

    let identifier: String
    let dimension: Int

    init?(language: NLLanguage = .english) {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            return nil
        }
        self.embedding = embedding
        dimension = embedding.dimension
        identifier = "apple.nl.sentence.\(language.rawValue).r\(embedding.revision).d\(embedding.dimension)"
    }

    func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let doubles = embedding.vector(for: trimmed),
              doubles.count == dimension else {
            return nil
        }
        return Self.normalize(doubles.map(Float.init))
    }

    static func normalize(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty else { return nil }
        let magnitude = sqrt(vDSP.sumOfSquares(vector))
        guard magnitude.isFinite, magnitude > .ulpOfOne else { return nil }

        var divisor = magnitude
        var normalized = [Float](repeating: 0, count: vector.count)
        vDSP_vsdiv(
            vector,
            1,
            &divisor,
            &normalized,
            1,
            vDSP_Length(vector.count)
        )
        return normalized
    }
}

private struct SemanticIndexRecord: Sendable {
    let id: String
    let contentHash: String
    let modelIdentifier: String
    let dimension: Int
    let vector: [Float]
    let updatedAt: String
}

private enum SemanticDatabaseError: LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SemanticSQLiteDatabase: @unchecked Sendable {
    private let url: URL
    private var handle: OpaquePointer?

    init(url: URL) throws {
        self.url = url
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        Self.protectAndExcludeFromBackup(directory)

        // All access is serialized by SemanticMemoryStore, so SQLite's per-connection
        // mutex would only add overhead.
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open semantic index"
            if let handle { sqlite3_close(handle) }
            self.handle = nil
            throw SemanticDatabaseError.sqlite(message)
        }

        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA temp_store=MEMORY")
        try execute("PRAGMA busy_timeout=3000")
        try execute("PRAGMA wal_autocheckpoint=256")
        try execute("PRAGMA journal_size_limit=1048576")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS semantic_records (
                id TEXT PRIMARY KEY NOT NULL,
                content_hash TEXT NOT NULL,
                model_id TEXT NOT NULL,
                dimension INTEGER NOT NULL,
                vector BLOB NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        Self.protectAndExcludeFromBackup(url)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func loadRecords() throws -> [String: SemanticIndexRecord] {
        let statement = try prepare(
            "SELECT id, content_hash, model_id, dimension, vector, updated_at FROM semantic_records"
        )
        defer { sqlite3_finalize(statement) }

        var records: [String: SemanticIndexRecord] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw lastError() }
            guard let idText = sqlite3_column_text(statement, 0),
                  let hashText = sqlite3_column_text(statement, 1),
                  let modelText = sqlite3_column_text(statement, 2),
                  let updatedText = sqlite3_column_text(statement, 5) else {
                continue
            }

            let dimension = Int(sqlite3_column_int(statement, 3))
            let byteCount = Int(sqlite3_column_bytes(statement, 4))
            guard dimension > 0,
                  dimension <= 16_384,
                  byteCount == dimension * MemoryLayout<Float>.size,
                  let bytes = sqlite3_column_blob(statement, 4) else {
                continue
            }

            var vector = [Float](repeating: 0, count: dimension)
            vector.withUnsafeMutableBytes { destination in
                destination.copyBytes(from: UnsafeRawBufferPointer(start: bytes, count: byteCount))
            }
            guard vector.allSatisfy(\.isFinite) else { continue }

            let record = SemanticIndexRecord(
                id: String(cString: idText),
                contentHash: String(cString: hashText),
                modelIdentifier: String(cString: modelText),
                dimension: dimension,
                vector: vector,
                updatedAt: String(cString: updatedText)
            )
            records[record.id] = record
        }
        return records
    }

    func apply(upserts: [SemanticIndexRecord], removals: Set<String>) throws {
        guard !upserts.isEmpty || !removals.isEmpty else { return }

        try execute("BEGIN IMMEDIATE")
        do {
            if !upserts.isEmpty {
                let statement = try prepare(
                    """
                    INSERT INTO semantic_records(id, content_hash, model_id, dimension, vector, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        content_hash=excluded.content_hash,
                        model_id=excluded.model_id,
                        dimension=excluded.dimension,
                        vector=excluded.vector,
                        updated_at=excluded.updated_at
                    """
                )
                defer { sqlite3_finalize(statement) }

                for record in upserts {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind(record.id, to: 1, in: statement)
                    try bind(record.contentHash, to: 2, in: statement)
                    try bind(record.modelIdentifier, to: 3, in: statement)
                    guard sqlite3_bind_int(statement, 4, Int32(record.dimension)) == SQLITE_OK else {
                        throw lastError()
                    }

                    let result = record.vector.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(
                            statement,
                            5,
                            bytes.baseAddress,
                            Int32(bytes.count),
                            sqliteTransient
                        )
                    }
                    guard result == SQLITE_OK else { throw lastError() }
                    try bind(record.updatedAt, to: 6, in: statement)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
                }
            }

            if !removals.isEmpty {
                let statement = try prepare("DELETE FROM semantic_records WHERE id = ?")
                defer { sqlite3_finalize(statement) }
                for id in removals {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind(id, to: 1, in: statement)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
                }
            }

            try execute("COMMIT")
            Self.protectAndExcludeFromBackup(url)
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func removeAll() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM semantic_records")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        // The delete is already committed. A busy reader may postpone WAL
        // truncation without making the rebuild itself a failure.
        try? execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    func storageBytes() -> Int64 {
        [url.path, url.path + "-wal", url.path + "-shm"].reduce(into: 0) { total, path in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { return }
            total += size.int64Value
        }
    }

    private static func protectAndExcludeFromBackup(_ url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)

        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw lastError()
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let handle else { throw SemanticDatabaseError.sqlite("Semantic index is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let handle else { throw SemanticDatabaseError.sqlite("Semantic index is closed") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorPointer)
            throw SemanticDatabaseError.sqlite(message)
        }
    }

    private func lastError() -> SemanticDatabaseError {
        guard let handle else { return .sqlite("Semantic index is closed") }
        return .sqlite(String(cString: sqlite3_errmsg(handle)))
    }
}

actor SemanticMemoryStore {
    static let shared = SemanticMemoryStore(
        fileURL: defaultDatabaseURL(),
        provider: AppleSentenceEmbeddingProvider()
    )

    private let fileURL: URL
    private let provider: (any SentenceEmbeddingProviding)?

    private var database: SemanticSQLiteDatabase?
    private var records: [String: SemanticIndexRecord] = [:]
    private var hasLoaded = false
    private var lastPersistenceError: String?

    private var cachedIDs: [String] = []
    private var cachedMatrix: [Float] = []
    private var matrixIsDirty = true

    init(fileURL: URL, provider: (any SentenceEmbeddingProviding)?) {
        self.fileURL = fileURL
        self.provider = provider
    }

    func synchronize(notes: [KnowledgeNote]) async {
        guard Self.shouldContinueBackgroundIndexing else { return }
        ensureLoaded()
        guard let provider else { return }

        let activeNotes = notes.filter { !$0.archived }
        let liveIDs = Set(activeNotes.map(\.id))
        let staleIDs = Set(records.keys.filter { !liveIDs.contains($0) })
        guard persist(upserts: [], removals: staleIDs) else { return }

        let batchLimit = Self.backfillBatchSize
        var batch: [SemanticIndexRecord] = []
        batch.reserveCapacity(batchLimit)

        for (offset, note) in activeNotes.enumerated() {
            guard Self.shouldContinueBackgroundIndexing else { break }
            if offset > 0, offset.isMultiple(of: 8) {
                // Keep interactive searches responsive during a large initial
                // backfill without sacrificing batched SQLite writes.
                await Task.yield()
                guard Self.shouldContinueBackgroundIndexing else { break }
            }

            let text = note.semanticSearchText
            let contentHash = Self.contentHash(text)
            if let existing = records[note.id],
               existing.contentHash == contentHash,
               existing.modelIdentifier == provider.identifier,
               existing.dimension == provider.dimension {
                continue
            }

            guard let record = makeRecord(note: note, text: text, contentHash: contentHash) else {
                guard persist(upserts: [], removals: [note.id]) else { return }
                continue
            }
            batch.append(record)

            if batch.count == batchLimit {
                guard persist(upserts: batch, removals: []) else { return }
                batch.removeAll(keepingCapacity: true)
            }
        }

        _ = persist(upserts: batch, removals: [])
    }

    func index(note: KnowledgeNote) {
        guard Self.shouldContinueBackgroundIndexing else { return }
        ensureLoaded()
        guard !note.archived else {
            remove(id: note.id)
            return
        }

        let text = note.semanticSearchText
        let contentHash = Self.contentHash(text)
        if let existing = records[note.id],
           let provider,
           existing.contentHash == contentHash,
           existing.modelIdentifier == provider.identifier,
           existing.dimension == provider.dimension {
            return
        }

        guard let record = makeRecord(note: note, text: text, contentHash: contentHash) else {
            remove(id: note.id)
            return
        }
        persist(upserts: [record], removals: [])
    }

    func remove(id: String) {
        guard !Task.isCancelled else { return }
        ensureLoaded()
        persist(upserts: [], removals: [id])
    }

    func search(query: String, limit: Int = 50) -> [SemanticSearchHit] {
        ensureLoaded()
        guard !Task.isCancelled,
              limit > 0,
              let provider,
              let queryVector = provider.vector(for: query),
              queryVector.count == provider.dimension else {
            return []
        }

        rebuildMatrixIfNeeded()
        guard !cachedIDs.isEmpty,
              cachedMatrix.count == cachedIDs.count * provider.dimension else {
            return []
        }

        var scores = [Float](repeating: 0, count: cachedIDs.count)
        vDSP_mmul(
            cachedMatrix,
            1,
            queryVector,
            1,
            &scores,
            1,
            vDSP_Length(cachedIDs.count),
            1,
            vDSP_Length(provider.dimension)
        )
        guard !Task.isCancelled else { return [] }

        return Self.topHits(
            ids: cachedIDs,
            scores: scores,
            limit: min(limit, scores.count)
        )
    }

    func statistics() -> SemanticIndexStatistics {
        ensureLoaded()
        let compatibleCount: Int
        if let provider {
            compatibleCount = records.values.reduce(into: 0) { count, record in
                if record.modelIdentifier == provider.identifier && record.dimension == provider.dimension {
                    count += 1
                }
            }
        } else {
            compatibleCount = 0
        }
        return SemanticIndexStatistics(
            recordCount: records.count,
            compatibleRecordCount: compatibleCount,
            dimension: provider?.dimension ?? 0,
            modelIdentifier: provider?.identifier,
            isAvailable: provider != nil,
            isPersistent: database != nil && lastPersistenceError == nil,
            storageBytes: database?.storageBytes() ?? 0,
            errorDescription: lastPersistenceError
        )
    }

    func rebuild(notes: [KnowledgeNote]) async {
        ensureLoaded()
        if let database {
            do {
                try database.removeAll()
                lastPersistenceError = nil
            } catch {
                lastPersistenceError = error.localizedDescription
                return
            }
        }
        records.removeAll(keepingCapacity: true)
        cachedIDs.removeAll(keepingCapacity: true)
        cachedMatrix.removeAll(keepingCapacity: false)
        matrixIsDirty = true
        await synchronize(notes: notes)
    }

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            let database = try SemanticSQLiteDatabase(url: fileURL)
            self.database = database
            records = try database.loadRecords()
            lastPersistenceError = nil
        } catch {
            database = nil
            records = [:]
            lastPersistenceError = error.localizedDescription
        }
        matrixIsDirty = true
    }

    private func makeRecord(
        note: KnowledgeNote,
        text: String,
        contentHash: String
    ) -> SemanticIndexRecord? {
        guard let provider,
              provider.dimension > 0,
              provider.dimension <= 16_384,
              let vector = provider.vector(for: text),
              vector.count == provider.dimension,
              vector.allSatisfy(\.isFinite) else {
            return nil
        }
        return SemanticIndexRecord(
            id: note.id,
            contentHash: contentHash,
            modelIdentifier: provider.identifier,
            dimension: provider.dimension,
            vector: vector,
            updatedAt: note.updatedAt
        )
    }

    @discardableResult
    private func persist(upserts: [SemanticIndexRecord], removals: Set<String>) -> Bool {
        if let database {
            do {
                try database.apply(upserts: upserts, removals: removals)
                lastPersistenceError = nil
            } catch {
                lastPersistenceError = error.localizedDescription
                return false
            }
        }
        for id in removals { records.removeValue(forKey: id) }
        for record in upserts { records[record.id] = record }
        if !upserts.isEmpty || !removals.isEmpty { matrixIsDirty = true }
        return true
    }

    private func rebuildMatrixIfNeeded() {
        guard matrixIsDirty, let provider else { return }
        let compatible = records.values
            .filter {
                $0.modelIdentifier == provider.identifier &&
                    $0.dimension == provider.dimension &&
                    $0.vector.count == provider.dimension
            }
            .sorted { $0.id < $1.id }

        cachedIDs = compatible.map(\.id)
        cachedMatrix = compatible.flatMap(\.vector)
        matrixIsDirty = false
    }

    private static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return "sha256:" + Data(digest).base64EncodedString()
    }

    /// Keeps only K candidates in memory and performs O(N log K) comparisons.
    private static func topHits(
        ids: [String],
        scores: [Float],
        limit: Int
    ) -> [SemanticSearchHit] {
        guard limit > 0, ids.count == scores.count else { return [] }
        var heap: [SemanticSearchHit] = []
        heap.reserveCapacity(limit)

        for index in scores.indices where scores[index].isFinite {
            let hit = SemanticSearchHit(id: ids[index], score: scores[index])
            if heap.count < limit {
                heap.append(hit)
                siftUp(&heap, from: heap.count - 1)
            } else if isBetter(hit, than: heap[0]) {
                heap[0] = hit
                siftDown(&heap, from: 0)
            }
        }

        return heap.sorted { isBetter($0, than: $1) }
    }

    private static func isBetter(_ lhs: SemanticSearchHit, than rhs: SemanticSearchHit) -> Bool {
        if lhs.score == rhs.score { return lhs.id < rhs.id }
        return lhs.score > rhs.score
    }

    private static func isWorse(_ lhs: SemanticSearchHit, than rhs: SemanticSearchHit) -> Bool {
        if lhs.score == rhs.score { return lhs.id > rhs.id }
        return lhs.score < rhs.score
    }

    private static func siftUp(_ heap: inout [SemanticSearchHit], from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard isWorse(heap[child], than: heap[parent]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private static func siftDown(_ heap: inout [SemanticSearchHit], from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var worseChild = left
            if right < heap.count, isWorse(heap[right], than: heap[left]) {
                worseChild = right
            }
            guard isWorse(heap[worseChild], than: heap[parent]) else { return }
            heap.swapAt(parent, worseChild)
            parent = worseChild
        }
    }

    private static var shouldContinueBackgroundIndexing: Bool {
        guard !Task.isCancelled else { return false }
        let process = ProcessInfo.processInfo
        guard process.thermalState != .serious && process.thermalState != .critical else {
            return false
        }
        #if os(iOS)
        return !process.isLowPowerModeEnabled
        #else
        return true
        #endif
    }

    private static var backfillBatchSize: Int {
        #if os(iOS)
        24
        #else
        64
        #endif
    }

    private static func defaultDatabaseURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CortexOS", isDirectory: true)
        return support.appendingPathComponent("semantic_notes.sqlite")
    }
}
#endif

extension KnowledgeNote {
    var lexicalSearchText: String {
        [title, insight, implication, action, tags.joined(separator: " ")]
            .joined(separator: " ")
    }

    #if !os(watchOS)
    var semanticSearchText: String {
        let combined = [title, insight, implication, action, tags.joined(separator: " ")]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        // Bound model work for unusually large imports while retaining complete
        // text for lexical search.
        return String(combined.prefix(4_096))
    }
    #endif
}
