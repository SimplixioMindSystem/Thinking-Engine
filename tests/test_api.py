"""Unit tests for the FastAPI REST API endpoints."""

import pytest
from fastapi.testclient import TestClient

import cortex_core.api.server as server_module
from cortex_core.api.server import create_app
from cortex_core.config import CortexConfig
from cortex_core.engine import CortexEngine


@pytest.fixture
def client(tmp_data_dir):
    """Create a test client with an isolated data directory."""
    config = CortexConfig(data_dir=tmp_data_dir)
    engine = CortexEngine(config)
    # Override the global engine singleton
    server_module._engine = engine
    app = create_app()
    return TestClient(app)


@pytest.fixture(autouse=True)
def reset_engine():
    """Reset the global engine after each test."""
    yield
    server_module._engine = None


# ── Health ──────────────────────────────────────────────────────


class TestHealthEndpoints:
    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"

    def test_status(self, client):
        resp = client.get("/status")
        assert resp.status_code == 200
        data = resp.json()
        assert "version" in data


# ── Knowledge Notes ─────────────────────────────────────────────


class TestKnowledgeEndpoints:
    def test_list_notes_empty(self, client):
        resp = client.get("/notes/")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_create_note(self, client):
        resp = client.post("/notes/", json={"title": "Test", "insight": "Key"})
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "Test"
        assert data["id"]

    def test_get_note(self, client):
        create_resp = client.post("/notes/", json={"title": "Find Me"})
        note_id = create_resp.json()["id"]
        resp = client.get(f"/notes/{note_id}")
        assert resp.status_code == 200
        assert resp.json()["title"] == "Find Me"

    def test_get_note_not_found(self, client):
        resp = client.get("/notes/nonexistent")
        assert resp.status_code == 404

    def test_update_note(self, client):
        create_resp = client.post("/notes/", json={"title": "Before"})
        note_id = create_resp.json()["id"]
        resp = client.patch(f"/notes/{note_id}", json={"title": "After"})
        assert resp.status_code == 200
        assert resp.json()["title"] == "After"

    def test_delete_note(self, client):
        create_resp = client.post("/notes/", json={"title": "Delete"})
        note_id = create_resp.json()["id"]
        resp = client.delete(f"/notes/{note_id}")
        assert resp.status_code == 204
        # Verify gone
        assert client.get(f"/notes/{note_id}").status_code == 404

    def test_search_notes(self, client):
        client.post("/notes/", json={"title": "AI Agents"})
        client.post("/notes/", json={"title": "Cooking"})
        resp = client.get("/notes/search?q=agents")
        assert resp.status_code == 200
        assert len(resp.json()) == 1


# ── Focus ───────────────────────────────────────────────────────


class TestFocusEndpoints:
    def test_today_brief_not_found(self, client):
        resp = client.get("/focus/today")
        assert resp.status_code == 404

    def test_generate_brief(self, client, tmp_data_dir, sample_digest_text):
        digest_path = tmp_data_dir / "weekly_digest_2026-03-14.md"
        digest_path.write_text(sample_digest_text)
        resp = client.post("/focus/generate", json={"digest_path": str(digest_path)})
        assert resp.status_code == 200
        data = resp.json()
        assert "focus_items" in data
        assert "date" in data


# ── Profile ─────────────────────────────────────────────────────


class TestProfileEndpoints:
    def test_get_profile(self, client):
        resp = client.get("/profile/")
        assert resp.status_code == 200
        data = resp.json()
        assert "name" in data
        assert "goals" in data

    def test_update_profile(self, client):
        resp = client.patch("/profile/", json={"name": "Pierre"})
        assert resp.status_code == 200
        assert resp.json()["name"] == "Pierre"


# ── Digest ──────────────────────────────────────────────────────


class TestDigestEndpoints:
    def test_evaluate_digest(self, client, tmp_data_dir, sample_digest_text):
        digest_path = tmp_data_dir / "weekly_digest_2026-03-14.md"
        digest_path.write_text(sample_digest_text)
        resp = client.post("/digest/evaluate", json={"path": str(digest_path)})
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_articles"] > 0
        assert "ai_article_ratio" in data


# ── Pipeline ────────────────────────────────────────────────────


class TestPipelineEndpoints:
    def test_run_pipeline(self, client, tmp_data_dir, sample_digest_text):
        digest_path = tmp_data_dir / "weekly_digest_2026-03-14.md"
        digest_path.write_text(sample_digest_text)
        resp = client.post("/pipeline/run", json={"use_llm": False})
        assert resp.status_code == 200
        data = resp.json()
        assert "success" in data


# ── Sync ────────────────────────────────────────────────────────


class TestSyncEndpoints:
    def test_snapshot_returns_200(self, client):
        resp = client.get("/sync/snapshot")
        assert resp.status_code == 200

    def test_snapshot_has_required_keys(self, client):
        data = client.get("/sync/snapshot").json()
        for key in (
            "profile",
            "active_project",
            "priorities",
            "today",
            "weekly_review",
            "decision_replay",
            "newsletter",
            "what_matters_now",
            "signal_top_priorities",
            "decision_queue",
            "action_ready_queue",
            "recurring_patterns",
            "unresolved_tensions",
            "resurfaced_now",
            "resurfacing_recurring_tensions",
            "resurfacing_weekly_review_candidates",
            "resurfacing_content_candidates",
            "content_candidates",
            "signal_graph",
            "signal_matching_counts",
            "recent_decisions",
            "insights",
            "signals",
            "working_memory",
            "synced_at",
        ):
            assert key in data, f"missing key: {key}"

    def test_snapshot_profile_shape(self, client):
        profile = client.get("/sync/snapshot").json()["profile"]
        assert isinstance(profile["goals"], list)
        assert isinstance(profile["interests"], list)
        assert isinstance(profile["current_projects"], list)
        assert "name" in profile
        assert "role" in profile

    def test_snapshot_synced_at_is_iso(self, client):
        data = client.get("/sync/snapshot").json()
        # Should be a valid ISO timestamp
        assert "T" in data["synced_at"]

    def test_snapshot_recent_decisions_is_list(self, client):
        data = client.get("/sync/snapshot").json()
        assert isinstance(data["recent_decisions"], list)

    def test_snapshot_signals_is_list(self, client):
        data = client.get("/sync/snapshot").json()
        assert isinstance(data["signals"], list)

    def test_snapshot_working_memory_shape(self, client):
        wm = client.get("/sync/snapshot").json()["working_memory"]
        assert "date" in wm
        assert isinstance(wm["todays_priorities"], list)

    def test_snapshot_after_decision_includes_it(self, client):
        client.post(
            "/context/decision",
            json={
                "decision": "Use rule-based scoring for v1",
                "reason": "Simplicity over accuracy at this stage",
                "project": "CortexOS",
            },
        )
        decisions = client.get("/sync/snapshot").json()["recent_decisions"]
        texts = [d["decision"] for d in decisions]
        assert "Use rule-based scoring for v1" in texts

    def test_feedback_useful(self, client):
        r = client.post("/context/feedback", json={"item": "Build sync layer", "useful": True})
        assert r.status_code == 204

    def test_feedback_not_useful(self, client):
        r = client.post("/context/feedback", json={"item": "Refactor naming", "useful": False})
        assert r.status_code == 204

    def test_feedback_stores_in_working_memory(self, client):
        client.post("/context/feedback", json={"item": "Ship MVP", "useful": True})
        wm = client.get("/sync/snapshot").json()["working_memory"]
        assert any("Ship MVP" in n for n in wm["temporary_notes"])

    def test_snapshot_weekly_review_is_nullable(self, client):
        data = client.get("/sync/snapshot").json()
        assert "weekly_review" in data
        assert data["weekly_review"] is None

    def test_snapshot_decision_replay_is_nullable(self, client):
        data = client.get("/sync/snapshot").json()
        assert "decision_replay" in data
        assert data["decision_replay"] is None

    def test_snapshot_newsletter_is_nullable(self, client):
        data = client.get("/sync/snapshot").json()
        assert "newsletter" in data
        newsletter = data["newsletter"]
        if newsletter is not None:
            assert isinstance(newsletter, dict)
            assert "status" in newsletter
            assert "safe_to_publish" in newsletter

    def test_generate_newsletter_endpoint_returns_payload(self, client):
        resp = client.post("/sync/newsletter/generate", json={"period": "weekly", "mode": "weekly-lessons"})
        assert resp.status_code == 200
        data = resp.json()
        assert "status" in data
        assert "safe_to_publish" in data

    def test_signal_capture_and_ranked_queues(self, client):
        capture = client.post(
            "/context/signals/capture",
            json={
                "text": "I am blocked on shipping offline queue and need to decide retry strategy today.",
                "source": "quick_capture",
                "project": "SimpliXio",
                "tags": ["offline", "queue"],
            },
        )
        assert capture.status_code == 200
        payload = capture.json()
        assert "signal" in payload
        signal_id = payload["signal"]["id"]

        queues = client.get("/context/signals/queues")
        assert queues.status_code == 200
        q = queues.json()
        assert "top_priorities" in q
        assert "decision_queue" in q
        assert "action_ready_queue" in q
        assert "signal_graph" in q
        assert any(
            item["signal_id"] == signal_id
            for item in q["decision_queue"] + q["action_ready_queue"] + q["what_matters_now"]
        )

    def test_signal_feedback_and_override(self, client):
        capture = client.post(
            "/context/signals/capture",
            json={"text": "Should we keep weekly replay in the macOS sidebar?", "source": "capture"},
        )
        signal_id = capture.json()["signal"]["id"]

        fb = client.post(
            "/context/signals/feedback",
            json={"signal_id": signal_id, "action_type": "acted_on", "note": "used in planning"},
        )
        assert fb.status_code == 200
        assert fb.json()["signal"]["feedback_counts"]["acted_on"] >= 1

        ov = client.post(
            "/context/signals/override",
            json={"signal_id": signal_id, "override_type": "pin", "note": "critical this week"},
        )
        assert ov.status_code == 200
        assert ov.json()["signal"]["status"] == "pinned"

    def test_signal_routes_return_expected_shapes(self, client):
        capture = client.post(
            "/context/signals/capture",
            json={"text": "Recurring issue in offline queue retries", "source": "capture"},
        )
        assert capture.status_code == 200
        signal_id = capture.json()["signal"]["id"]

        captured = client.get("/context/signals")
        assert captured.status_code == 200
        captured_rows = captured.json()
        assert isinstance(captured_rows, list)
        assert any(row["id"] == signal_id for row in captured_rows)

        emerging = client.get("/context/signals/emerging")
        assert emerging.status_code == 200
        assert isinstance(emerging.json(), list)

    def test_signal_queue_endpoint_enforces_calm_defaults(self, client):
        for idx in range(20):
            client.post(
                "/context/signals/capture",
                json={"text": f"Recurring decision blocker {idx} in release flow", "source": "capture"},
            )

        queues = client.get("/context/signals/queues")
        assert queues.status_code == 200
        payload = queues.json()
        assert len(payload["top_priorities"]) <= 3
        assert len(payload["what_matters_now"]) <= 3
        assert len(payload["decision_queue"]) <= 5
        assert len(payload["action_ready_queue"]) <= 5
        assert len(payload["recurring_patterns"]) <= 5
        assert len(payload["unresolved_tensions"]) <= 5
        assert len(payload["content_candidates"]) <= 5
        assert len(payload["resurfaced_now"]) <= 3
        assert len(payload["resurfacing_recurring_tensions"]) <= 5
        assert len(payload["resurfacing_weekly_review_candidates"]) <= 5
        assert len(payload["resurfacing_content_candidates"]) <= 5

    def test_signal_resurfacing_actions_update_state(self, client):
        capture = client.post(
            "/context/signals/capture",
            json={"text": "Recurring unresolved tension in weekly planning.", "source": "capture"},
        )
        signal_id = capture.json()["signal"]["id"]

        snooze = client.post(
            "/context/signals/feedback",
            json={"signal_id": signal_id, "action_type": "snoozed", "note": "this week"},
        )
        assert snooze.status_code == 200
        assert snooze.json()["signal"]["resurfacing_status"] in {"scheduled", "waiting_for_context"}

        dismiss = client.post(
            "/context/signals/feedback",
            json={"signal_id": signal_id, "action_type": "dismissed"},
        )
        assert dismiss.status_code == 200
        assert dismiss.json()["signal"]["resurfacing_status"] == "dismissed"

    def test_snapshot_weekly_review_aggregates_recent_decision_artifacts(self, client, tmp_data_dir):
        payloads = {
            "2026-04-12": {
                "date": "2026-04-12",
                "priorities": [
                    {"title": "Build sync layer"},
                    {"title": "Improve offline queue"},
                ],
                "ignored": ["low signal one"],
                "emerging_signals": ["Edge AI"],
                "changes_since_yesterday": [],
            },
            "2026-04-13": {
                "date": "2026-04-13",
                "priorities": [
                    {"title": "Build sync layer"},
                    {"title": "Ship TestFlight"},
                ],
                "ignored": ["low signal two", "low signal three"],
                "emerging_signals": ["Edge AI", "On-device models"],
                "changes_since_yesterday": [],
            },
            "2026-04-18": {
                "date": "2026-04-18",
                "priorities": [
                    {"title": "Ship TestFlight"},
                    {"title": "Weekly review loop"},
                ],
                "ignored": ["low signal four"],
                "emerging_signals": ["On-device models"],
                "changes_since_yesterday": [],
            },
            "2026-04-01": {
                "date": "2026-04-01",
                "priorities": [{"title": "Out of range"}],
                "ignored": ["too old"],
                "emerging_signals": ["Old signal"],
                "changes_since_yesterday": [],
            },
        }

        import json

        for day, payload in payloads.items():
            (tmp_data_dir / f"decision_{day}.json").write_text(json.dumps(payload), encoding="utf-8")

        data = client.get("/sync/snapshot").json()
        review = data["weekly_review"]
        assert review is not None
        for key in (
            "week_start",
            "week_end",
            "period_label",
            "days_covered",
            "top_priorities",
            "top_signals",
            "total_ignored_signals",
            "summary",
            "recommendations",
            "generated_at",
        ):
            assert key in review
        assert review["week_start"] == "2026-04-12"
        assert review["week_end"] == "2026-04-18"
        assert review["period_label"] == "2026-04-12 to 2026-04-18"
        assert review["days_covered"] == 3
        assert review["quality"] == "insufficient_history"
        assert review["confidence"] == pytest.approx(0.43, abs=0.01)
        assert review["total_ignored_signals"] == 4

        priorities = {item["title"]: item["count"] for item in review["top_priorities"]}
        assert priorities["Build sync layer"] == 2
        assert priorities["Ship TestFlight"] == 2
        assert "Out of range" not in priorities

        signals = {item["title"]: item["count"] for item in review["top_signals"]}
        assert signals["Edge AI"] == 2
        assert signals["On-device models"] == 2
        assert "Old signal" not in signals

    def test_snapshot_decision_replay_aggregates_latest_decision_artifact(self, client, tmp_data_dir):
        payload = {
            "date": "2026-04-21",
            "priorities": [
                {
                    "title": "Finish Weekly Review Loop",
                    "why_it_matters": "Compounding weekly learning",
                    "next_step": "Ship macOS surface",
                },
                {
                    "title": "Stabilize offline queue",
                    "why_it_matters": "Reliable travel usage",
                    "next_step": "Retry queued sync",
                },
                {
                    "title": "Close TestFlight feedback loop",
                    "why_it_matters": "Improve decision quality",
                    "next_step": "Tag acted vs not useful",
                },
                {"title": "Extra item should be capped", "why_it_matters": "", "next_step": ""},
            ],
            "ignored": [
                "Low relevance AI news",
                "Celebrity AI post",
                "Duplicate launch noise",
                "Clickbait thread",
                "Non-project tutorial",
                "extra ignored should be capped",
            ],
            "emerging_signals": [
                "GitHub issue repeated twice",
                "Offline sync failures in logs",
                "User feedback asks for replay",
                "TestFlight friction notes",
                "Context drift in priorities",
                "extra kept should be capped",
            ],
            "changes_since_yesterday": [],
        }

        import json

        (tmp_data_dir / "decision_2026-04-21.json").write_text(json.dumps(payload), encoding="utf-8")
        data = client.get("/sync/snapshot").json()
        replay = data["decision_replay"]
        assert replay is not None
        for key in (
            "date",
            "signals_reviewed",
            "signals_kept",
            "signals_ignored",
            "kept_signals",
            "ignored_signals",
            "final_priorities",
            "summary",
            "generated_at",
        ):
            assert key in replay
        assert replay["date"] == "2026-04-21"
        assert replay["signals_kept"] == 5
        assert replay["signals_ignored"] == 5
        assert replay["signals_reviewed"] == 10
        assert replay["signals_reviewed"] == replay["signals_kept"] + replay["signals_ignored"]
        assert len(replay["kept_signals"]) == 5
        assert len(replay["ignored_signals"]) == 5
        assert len(replay["final_priorities"]) == 3
        assert "reduced" in replay["summary"].lower()


# ── Integrations + Today Output ────────────────────────────────


class TestIntegrationsEndpoints:
    def test_pull_context_without_network_dependencies(self, client):
        resp = client.post(
            "/integrations/pull",
            json={
                "rss_feeds": [],
                "github_repositories": [],
                "github_topic": "",
                "notion_database_id": "",
                "notion_query": "",
                "max_items": 3,
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["fetched"] == 0
        assert data["ingested"] == 0
        assert data["rss_feeds"] == 0
        assert data["github_topic"] == ""
        assert data["notion_enabled"] is False
        assert data["raw_saved"] == 0
        assert data["deduplicated"] == 0
        assert data["mapped_signals"] == 0
        assert data["mapped_context_items"] == 0
        assert "sources" in data

    def test_today_endpoint_returns_shareable_payload(self, client):
        resp = client.get("/sync/today")
        assert resp.status_code == 200
        data = resp.json()
        assert "date" in data
        assert "priorities" in data
        assert "ignored_signals" in data
        assert "changes_since_yesterday" in data
        assert "share_text" in data
        assert "generated_at" in data
