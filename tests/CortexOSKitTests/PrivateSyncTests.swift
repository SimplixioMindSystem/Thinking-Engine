import XCTest
import CryptoKit
@testable import CortexOSKit

final class PrivateSyncTests: XCTestCase {
    func testCodecRoundTripPreservesPrivateState() throws {
        let payload = makePayload(
            notes: [note(id: "n1", title: "A private thought", updatedAt: "2026-08-08T01:00:00Z")],
            profile: UserProfile(name: "Pierre", goals: ["Ship clearly"])
        )

        let key = SymmetricKey(size: .bits256)
        let encoded = try ICloudSyncCodec.encode(payload, key: key)
        let decoded = try ICloudSyncCodec.decode(encoded, key: key)

        XCTAssertLessThan(encoded.count, 10_000)
        XCTAssertFalse(encoded.contains(Data("A private thought".utf8)))
        XCTAssertEqual(decoded.notes.first?.title, "A private thought")
        XCTAssertEqual(decoded.profile.name, "Pierre")
        XCTAssertEqual(decoded.profile.goals, ["Ship clearly"])
    }

    func testCodecRejectsTheWrongPrivateKey() throws {
        let payload = makePayload(
            notes: [note(id: "n1", title: "Private", updatedAt: "2026-08-08T01:00:00Z")]
        )
        let encoded = try ICloudSyncCodec.encode(payload, key: SymmetricKey(size: .bits256))

        XCTAssertThrowsError(
            try ICloudSyncCodec.decode(encoded, key: SymmetricKey(size: .bits256))
        )
    }

    func testCodecRejectsANewerSchemaBeforeItCanBeRewritten() throws {
        let payload = makePayload(schemaVersion: PrivateSyncPayload.currentSchemaVersion + 1)
        let key = SymmetricKey(size: .bits256)
        let encoded = try ICloudSyncCodec.encode(payload, key: key)

        XCTAssertThrowsError(try ICloudSyncCodec.decode(encoded, key: key))
    }

    func testContentComparisonIgnoresSyncEnvelopeMetadata() throws {
        let first = makePayload(
            notes: [note(id: "n1", title: "Same private thought", updatedAt: "2026-08-08T01:00:00Z")]
        )
        var second = first
        second.modifiedAt = "2026-08-09T10:00:00Z"
        second.deviceID = "another-device"

        XCTAssertTrue(try ICloudSyncCodec.hasSameContent(first, second))
    }

    func testContentComparisonDetectsARealChange() throws {
        let first = makePayload(
            notes: [note(id: "n1", title: "Original", updatedAt: "2026-08-08T01:00:00Z")]
        )
        let second = makePayload(
            notes: [note(id: "n1", title: "Changed", updatedAt: "2026-08-08T02:00:00Z")]
        )

        XCTAssertFalse(try ICloudSyncCodec.hasSameContent(first, second))
    }

    func testContentComparisonIgnoresCollectionOrder() throws {
        let first = makePayload(
            notes: [
                note(id: "n1", title: "First", updatedAt: "2026-08-08T01:00:00Z"),
                note(id: "n2", title: "Second", updatedAt: "2026-08-08T02:00:00Z"),
            ],
            decisions: [
                decision(id: "d1", reason: "First reason", outcome: ""),
                decision(id: "d2", reason: "Second reason", outcome: ""),
            ],
            decisionUpdatedAt: [
                "d1": "2026-08-08T03:00:00Z",
                "d2": "2026-08-08T04:00:00Z",
            ]
        )
        let second = makePayload(
            notes: Array(first.notes.reversed()),
            decisions: Array(first.decisions.reversed()),
            decisionUpdatedAt: first.decisionUpdatedAt
        )

        XCTAssertTrue(try ICloudSyncCodec.hasSameContent(first, second))
    }

    func testNewerDeletionPreventsNoteResurrection() {
        let local = makePayload(
            notes: [],
            deletedNoteIDs: ["n1": "2026-08-08T03:00:00Z"]
        )
        let remote = makePayload(
            notes: [note(id: "n1", title: "Stale copy", updatedAt: "2026-08-08T02:00:00Z")]
        )

        let merged = OfflineStore.mergedPrivateSyncPayload(
            local: local,
            remote: remote,
            deviceID: "test",
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(merged.notes.isEmpty)
        XCTAssertEqual(merged.deletedNoteIDs["n1"], "2026-08-08T03:00:00Z")
    }

    func testNewerEditSupersedesOldDeletion() {
        let local = makePayload(
            notes: [],
            deletedNoteIDs: ["n1": "2026-08-08T01:00:00Z"]
        )
        let remote = makePayload(
            notes: [note(id: "n1", title: "Restored intentionally", updatedAt: "2026-08-08T04:00:00Z")]
        )

        let merged = OfflineStore.mergedPrivateSyncPayload(
            local: local,
            remote: remote,
            deviceID: "test"
        )

        XCTAssertEqual(merged.notes.map(\.title), ["Restored intentionally"])
        XCTAssertNil(merged.deletedNoteIDs["n1"])
    }

    func testNewestDecisionWinsEvenWhenOlderDecisionHasMoreFields() {
        let older = decision(id: "d1", reason: "Detailed old reason", outcome: "Old outcome")
        let newer = decision(id: "d1", reason: "", outcome: "")
        let local = makePayload(
            decisions: [older],
            decisionUpdatedAt: ["d1": "2026-08-08T01:00:00Z"]
        )
        let remote = makePayload(
            decisions: [newer],
            decisionUpdatedAt: ["d1": "2026-08-08T05:00:00Z"]
        )

        let merged = OfflineStore.mergedPrivateSyncPayload(
            local: local,
            remote: remote,
            deviceID: "test"
        )

        XCTAssertEqual(merged.decisions.count, 1)
        XCTAssertEqual(merged.decisions[0].reason, "")
        XCTAssertEqual(merged.decisionUpdatedAt["d1"], "2026-08-08T05:00:00Z")
    }

    private func makePayload(
        schemaVersion: Int = PrivateSyncPayload.currentSchemaVersion,
        notes: [KnowledgeNote] = [],
        deletedNoteIDs: [String: String] = [:],
        profile: UserProfile = .empty,
        decisions: [SyncDecision] = [],
        decisionUpdatedAt: [String: String] = [:]
    ) -> PrivateSyncPayload {
        PrivateSyncPayload(
            schemaVersion: schemaVersion,
            notes: notes,
            deletedNoteIDs: deletedNoteIDs,
            profile: profile,
            profileUpdatedAt: profile.name.isEmpty ? "" : "2026-08-08T01:00:00Z",
            decisions: decisions,
            decisionUpdatedAt: decisionUpdatedAt,
            insights: [],
            feedback: [],
            modifiedAt: "2026-08-08T06:00:00Z",
            deviceID: "source"
        )
    }

    private func note(id: String, title: String, updatedAt: String) -> KnowledgeNote {
        KnowledgeNote(
            id: id,
            title: title,
            insight: "",
            implication: "",
            action: "",
            sourceURL: "",
            tags: [],
            createdAt: "2026-08-08T00:00:00Z",
            updatedAt: updatedAt,
            archived: false
        )
    }

    private func decision(id: String, reason: String, outcome: String) -> SyncDecision {
        SyncDecision(
            id: id,
            decision: "Choose a direction",
            reason: reason,
            project: "SimpliXio",
            assumptions: reason.isEmpty ? [] : ["One assumption"],
            contextTags: ["product"],
            createdAt: "2026-08-08T00:00:00Z",
            outcome: outcome,
            impactScore: 0.5
        )
    }
}
