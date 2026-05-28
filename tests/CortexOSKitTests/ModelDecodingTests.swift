//
//  ModelDecodingTests.swift
//  CortexOSKitTests
//
//  Tests JSON decoding for all CortexOS models to ensure
//  API contract compliance and prevent regressions.
//

import XCTest
@testable import CortexOSKit

final class UserProfileTests: XCTestCase {

    func testDecodeProfile() throws {
        let json = """
        {
            "name": "Pierre",
            "goals": ["Ship SimpliXio"],
            "interests": ["AI", "Swift"],
            "current_projects": ["SimpliXio"],
            "constraints": ["Solo founder"],
            "ignored_topics": ["crypto"]
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        XCTAssertEqual(profile.name, "Pierre")
        XCTAssertEqual(profile.goals, ["Ship SimpliXio"])
        XCTAssertEqual(profile.interests, ["AI", "Swift"])
        XCTAssertEqual(profile.currentProjects, ["SimpliXio"])
        XCTAssertEqual(profile.constraints, ["Solo founder"])
        XCTAssertEqual(profile.ignoredTopics, ["crypto"])
    }

    func testEmptyProfile() {
        let profile = UserProfile.empty
        XCTAssertEqual(profile.name, "")
        XCTAssertTrue(profile.goals.isEmpty)
        XCTAssertTrue(profile.interests.isEmpty)
    }

    func testProfileRoundtrip() throws {
        let profile = UserProfile(
            name: "Test",
            goals: ["g1"],
            interests: ["i1"],
            currentProjects: ["p1"],
            constraints: [],
            ignoredTopics: []
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.goals, profile.goals)
        XCTAssertEqual(decoded.currentProjects, profile.currentProjects)
    }
}

final class ProfileUpdateTests: XCTestCase {

    func testEncodePartialUpdate() throws {
        let update = ProfileUpdate(name: "Pierre", goals: ["Ship v1"])
        let data = try JSONEncoder().encode(update)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(dict?["name"])
        XCTAssertNotNil(dict?["goals"])
    }
}

final class KnowledgeNoteTests: XCTestCase {

    func testDecodeNote() throws {
        let json = """
        {
            "id": "abc123",
            "title": "Context-Aware Retrieval",
            "insight": "Dynamic embeddings work better.",
            "implication": "Use in SimpliXio.",
            "action": "Prototype it.",
            "source_url": "https://example.com",
            "tags": ["AI", "retrieval"],
            "created_at": "2026-03-15T10:00:00Z",
            "updated_at": "",
            "archived": false
        }
        """.data(using: .utf8)!

        let note = try JSONDecoder().decode(KnowledgeNote.self, from: json)
        XCTAssertEqual(note.id, "abc123")
        XCTAssertEqual(note.title, "Context-Aware Retrieval")
        XCTAssertEqual(note.tags, ["AI", "retrieval"])
        XCTAssertFalse(note.archived)
        XCTAssertEqual(note.sourceURL, "https://example.com")
    }

    func testNoteIdentifiable() throws {
        let note = KnowledgeNote.example
        XCTAssertEqual(note.id, "abc123")
    }

    func testNoteHashable() {
        let note1 = KnowledgeNote.example
        let note2 = KnowledgeNote.example
        // Both have same id, both hash equal
        XCTAssertEqual(note1, note2)
    }

    func testDisplayTags() {
        var note = KnowledgeNote.example
        note.tags = ["AI", "retrieval"]
        XCTAssertTrue(note.displayTags.contains("#AI"))
        XCTAssertTrue(note.displayTags.contains("#retrieval"))
    }

    func testCreatedDate() {
        let note = KnowledgeNote.example
        // createdAt is set via ISO8601DateFormatter so createdDate should parse
        XCTAssertNotNil(note.createdDate)
    }

    func testNoteRoundtrip() throws {
        let original = KnowledgeNote.example
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KnowledgeNote.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.tags, original.tags)
    }
}

final class NoteRequestTests: XCTestCase {

    func testCreateRequestEncode() throws {
        let req = NoteCreateRequest(title: "Test", insight: "Insight", tags: ["ai"])
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["title"] as? String, "Test")
        XCTAssertEqual(dict?["insight"] as? String, "Insight")
    }

    func testUpdateRequestEncode() throws {
        let req = NoteUpdateRequest(title: "Updated", archived: true)
        let data = try JSONEncoder().encode(req)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["title"] as? String, "Updated")
        XCTAssertEqual(dict?["archived"] as? Bool, true)
    }
}

// MARK: - ServerHealth

final class ServerHealthTests: XCTestCase {

    func testDecodeServerHealth() throws {
        let json = """
        {"status": "ok", "timestamp": "2026-03-15T10:00:00Z"}
        """.data(using: .utf8)!

        let health = try JSONDecoder().decode(ServerHealth.self, from: json)
        XCTAssertEqual(health.status, "ok")
        XCTAssertFalse(health.timestamp.isEmpty)
    }
}

// MARK: - Sync Snapshot Decoding

final class SyncSnapshotDecodingTests: XCTestCase {

    func testDecodeSnapshotWithWeeklyReview() throws {
        let json = """
        {
          "profile": {
            "name": "Pierre",
            "role": "Builder",
            "goals": ["Ship weekly"],
            "interests": ["decision systems"],
            "current_projects": ["SimpliXio"],
            "ignored_topics": ["noise"]
          },
          "active_project": null,
          "priorities": null,
          "today": {
            "date": "2026-04-19",
            "priorities": [],
            "ignored_signals": [],
            "changes_since_yesterday": [],
            "share_text": "SimpliXio Today",
            "generated_at": "2026-04-19T00:00:00Z"
          },
          "weekly_review": {
            "week_start": "2026-04-13",
            "week_end": "2026-04-19",
            "period_label": "2026-04-13 to 2026-04-19",
            "days_covered": 7,
            "quality": "sufficient_history",
            "confidence": 1.0,
            "top_priorities": [
              {"title": "Build sync layer", "count": 3}
            ],
            "top_signals": [
              {"title": "Edge AI", "count": 2}
            ],
            "total_ignored_signals": 12,
            "summary": "Reviewed 7 days.",
            "recommendations": ["Promote recurring priority to roadmap decision."],
            "generated_at": "2026-04-19T00:00:00Z"
          },
          "decision_replay": {
            "date": "2026-04-19",
            "signals_reviewed": 42,
            "signals_kept": 6,
            "signals_ignored": 36,
            "kept_signals": [
              {"title": "GitHub issue repeated twice", "reason": "Related to active project"}
            ],
            "ignored_signals": [
              {"title": "Low relevance AI news", "reason": "Not connected to current goals"}
            ],
            "final_priorities": [
              {"title": "Finish Weekly Review Loop", "why": "Compounds learning", "action": "Ship macOS surface"}
            ],
            "summary": "SimpliXio reduced 42 inputs into 3 priorities.",
            "generated_at": "2026-04-19T00:00:00Z"
          },
          "newsletter": {
            "status": "draft",
            "mode": "weekly-lessons",
            "period_start": "2026-04-13",
            "period_end": "2026-04-19",
            "safe_to_publish": true,
            "generated_at": "2026-04-19T00:00:00Z",
            "title": "From Noise to Action",
            "subtitle": "A practical reflection from real notes and decisions.",
            "preview": "This draft comes from real captured thoughts and decisions.",
            "source_count_total": 5,
            "source_count_usable": 4,
            "safety_report": {
              "safe_to_publish": true,
              "remaining_concerns": [],
              "recommendation": "No critical safety blockers detected."
            },
            "taste_gate": {
              "passed": true,
              "score": 88,
              "reasons": []
            },
            "markdown_path": "/tmp/newsletter.md"
          },
          "resurfaced_now": [
            {
              "signal_id": "sig_1",
              "title": "Revisit offline sync edge case",
              "signal_type": "tension",
              "horizon": "today",
              "rank_score": 78.0,
              "scores": {
                "importance": 82,
                "clarity": 61,
                "decision_readiness": 72,
                "action_readiness": 64,
                "recurrence": 69,
                "emotional_intensity": 55,
                "publishability": 40,
                "staleness": 21
              },
              "topics": ["offline", "sync"],
              "sensitivity": "internal",
              "explainability": {
                "why_it_surfaced": "Surfaced because unresolved tension.",
                "top_contributors": ["recurring signal"],
                "lowered_confidence": [],
                "missing_for_readiness": [],
                "rank_score": 78.0
              },
              "next_action": "Resolve the main blocker behind offline sync.",
              "captured_at": "2026-04-19T00:00:00Z",
              "resurfacing_status": "resurfaced",
              "resurfacing_reason": "unresolved_tension",
              "resurfacing_time_horizon": "this_week",
              "resurfacing_at": "2026-04-20T00:00:00Z",
              "resurfacing_count": 2,
              "resurfacing_confidence": 81.0,
              "resurfacing_mode": "recurrence_based",
              "resurfacing_explanation": "This recurring tension is still blocking progress."
            }
          ],
          "resurfacing_recurring_tensions": [],
          "resurfacing_weekly_review_candidates": [],
          "resurfacing_content_candidates": [],
          "recent_decisions": [],
          "insights": [],
          "signals": [],
          "working_memory": {
            "date": "2026-04-19",
            "todays_priorities": [],
            "currently_exploring": [],
            "temporary_notes": []
          },
          "synced_at": "2026-04-19T00:00:00Z"
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(SyncSnapshot.self, from: json)
        XCTAssertNotNil(snapshot.weeklyReview)
        XCTAssertEqual(snapshot.weeklyReview?.weekStart, "2026-04-13")
        XCTAssertEqual(snapshot.weeklyReview?.weekEnd, "2026-04-19")
        XCTAssertEqual(snapshot.weeklyReview?.periodLabel, "2026-04-13 to 2026-04-19")
        XCTAssertEqual(snapshot.weeklyReview?.daysCovered, 7)
        XCTAssertEqual(snapshot.weeklyReview?.quality, "sufficient_history")
        XCTAssertEqual(snapshot.weeklyReview?.confidence, 1.0)
        XCTAssertEqual(snapshot.weeklyReview?.totalIgnoredSignals, 12)
        XCTAssertEqual(snapshot.weeklyReview?.topPriorities.first?.title, "Build sync layer")
        XCTAssertNotNil(snapshot.decisionReplay)
        XCTAssertEqual(snapshot.decisionReplay?.signalsReviewed, 42)
        XCTAssertEqual(snapshot.decisionReplay?.signalsKept, 6)
        XCTAssertEqual(snapshot.decisionReplay?.signalsIgnored, 36)
        XCTAssertEqual(snapshot.decisionReplay?.finalPriorities.first?.title, "Finish Weekly Review Loop")
        XCTAssertNotNil(snapshot.newsletter)
        XCTAssertEqual(snapshot.newsletter?.status, "draft")
        XCTAssertEqual(snapshot.newsletter?.mode, "weekly-lessons")
        XCTAssertEqual(snapshot.newsletter?.sourceCountUsable, 4)
        XCTAssertEqual(snapshot.resurfacedNow?.first?.signalID, "sig_1")
        XCTAssertEqual(snapshot.resurfacedNow?.first?.resurfacingReason, "unresolved_tension")
    }

    func testDecodeSnapshotWithNullWeeklyReview() throws {
        let json = """
        {
          "profile": {
            "name": "Pierre",
            "role": "Builder",
            "goals": [],
            "interests": [],
            "current_projects": [],
            "ignored_topics": []
          },
          "active_project": null,
          "priorities": null,
          "today": {
            "date": "2026-04-19",
            "priorities": [],
            "ignored_signals": [],
            "changes_since_yesterday": [],
            "share_text": "SimpliXio Today",
            "generated_at": "2026-04-19T00:00:00Z"
          },
          "weekly_review": null,
          "decision_replay": null,
          "newsletter": null,
          "recent_decisions": [],
          "insights": [],
          "signals": [],
          "working_memory": {
            "date": "2026-04-19",
            "todays_priorities": [],
            "currently_exploring": [],
            "temporary_notes": []
          },
          "synced_at": "2026-04-19T00:00:00Z"
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(SyncSnapshot.self, from: json)
        XCTAssertNil(snapshot.weeklyReview)
        XCTAssertNil(snapshot.decisionReplay)
        XCTAssertNil(snapshot.newsletter)
    }

    func testDecodeSnapshotWithoutWeeklyReviewKey() throws {
        let json = """
        {
          "profile": {
            "name": "Pierre",
            "role": "Builder",
            "goals": [],
            "interests": [],
            "current_projects": [],
            "ignored_topics": []
          },
          "active_project": null,
          "priorities": null,
          "today": {
            "date": "2026-04-19",
            "priorities": [],
            "ignored_signals": [],
            "changes_since_yesterday": [],
            "share_text": "SimpliXio Today",
            "generated_at": "2026-04-19T00:00:00Z"
          },
          "recent_decisions": [],
          "insights": [],
          "signals": [],
          "working_memory": {
            "date": "2026-04-19",
            "todays_priorities": [],
            "currently_exploring": [],
            "temporary_notes": []
          },
          "synced_at": "2026-04-19T00:00:00Z"
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(SyncSnapshot.self, from: json)
        XCTAssertNil(snapshot.weeklyReview)
        XCTAssertNil(snapshot.decisionReplay)
        XCTAssertNil(snapshot.newsletter)
    }
}
