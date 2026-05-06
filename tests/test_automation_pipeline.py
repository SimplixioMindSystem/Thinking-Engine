"""Tests for SimpliXio automation orchestration and quality guardrails."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
AUTOMATION_ROOT = REPO_ROOT / "cortexos_automation_scripts"
AUTOMATION_SCRIPTS = AUTOMATION_ROOT / "scripts"

if str(AUTOMATION_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(AUTOMATION_SCRIPTS))


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)  # type: ignore[attr-defined]
    return module


pipeline_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "run_weekly_pipeline.py",
    "run_weekly_pipeline_module",
)
acq_pipeline_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "run_acquisition_pipeline.py",
    "run_acquisition_pipeline_module",
)
quality_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "marketing_quality_gate.py",
    "marketing_quality_gate_module",
)
acq_quality_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "acquisition_quality_gate.py",
    "acquisition_quality_gate_module",
)
outreach_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "outreach_drafter.py",
    "outreach_drafter_module",
)
acq_crm_mod = importlib.import_module("acquisition_crm")
lead_scorer_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "lead_scorer.py",
    "lead_scorer_module",
)
marketing_mod = load_module(
    AUTOMATION_ROOT / "marketing_automation.py",
    "marketing_automation_module",
)
newsletter_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "generate_newsletter.py",
    "generate_newsletter_module",
)
discord_mod = load_module(
    AUTOMATION_ROOT / "scripts" / "build_discord_proof_drafts.py",
    "build_discord_proof_drafts_module",
)
marketing_mod.CortexBrief.model_rebuild(_types_namespace={"Priority": marketing_mod.Priority})
marketing_mod.WeeklyReview.model_rebuild(_types_namespace={"Any": Any})
marketing_mod.DecisionReplay.model_rebuild(_types_namespace={"Any": Any})
marketing_mod.Config.model_rebuild(_types_namespace={"Path": Path})


def test_pipeline_step_order():
    steps = pipeline_mod.build_steps(strict_quality=False)
    names = [name for name, _cmd, _strict in steps]
    assert names == [
        "Filter signals",
        "Build SimpliXio Today artifact",
        "Build weekly review",
        "Build decision replay",
        "Build public newsletter",
        "Generate marketing content",
        "Run marketing quality gate",
        "Generate Discord proof drafts",
        "Publish outputs",
    ]
    newsletter = next(step for step in steps if step[0] == "Build public newsletter")
    _name, cmd, _strict = newsletter
    assert "--strict-safety" in cmd
    assert "--strict-taste" in cmd


def test_pipeline_strict_quality_flag():
    steps = pipeline_mod.build_steps(strict_quality=True)
    quality = next(step for step in steps if step[0] == "Run marketing quality gate")
    _name, cmd, fail_on_error = quality
    assert "--strict" in cmd
    assert fail_on_error is True


def test_acquisition_pipeline_step_order():
    steps = acq_pipeline_mod.build_daily_steps(strict_quality=False)
    names = [name for name, _cmd, _strict in steps]
    assert names == [
        "Collect lead signals",
        "Score leads",
        "Draft outreach",
        "Generate public content",
        "Run acquisition quality gate",
    ]


def test_acquisition_pipeline_strict_quality_flag():
    steps = acq_pipeline_mod.build_daily_steps(strict_quality=True)
    quality = next(step for step in steps if step[0] == "Run acquisition quality gate")
    _name, cmd, fail_on_error = quality
    assert "--strict" in cmd
    assert fail_on_error is True


def test_acquisition_quality_gate_detects_hype_phrase():
    result = acq_quality_mod.analyse_text("This revolutionary AI-powered productivity app will supercharge everything.")
    assert result.passed is False
    assert result.score < 70


def test_lead_scorer_boosts_high_signal_github_repos():
    score, reason = lead_scorer_mod.score_lead(
        "Founder shipping decision system for builders",
        "github",
        {
            "excerpt": "We ship weekly and focus on prioritization and context.",
            "tags": ["open source", "workflow"],
            "raw": {"stars": 800, "forks": 120, "updated_at": "2026-04-20T00:00:00Z"},
        },
    )
    assert score >= 55
    assert "github:high_stars" in reason or "founder" in reason


def test_lead_scorer_penalizes_internal_artifacts():
    score, _reason = lead_scorer_mod.score_lead(
        "Internal weekly review",
        "simplixio_weekly_review",
        {"excerpt": "internal artifact", "tags": ["internal_artifact"], "raw": {}},
    )
    assert score <= 20


def test_quality_gate_detects_repeated_hash():
    analysis = quality_mod.analyse_text(
        "Decision system with 3 priorities. Why and next action. Ignored signals.",
        previous_hashes={
            quality_mod.text_hash("Decision system with 3 priorities. Why and next action. Ignored signals.")
        },
    )
    assert analysis["repeated_hash"] is True
    assert analysis["passed"] is True or analysis["score"] < 100


def test_content_plan_skips_when_no_signal():
    brief = marketing_mod.CortexBrief(date="2026-04-19", priorities=[], ignored_signals_count=0)
    weekly = marketing_mod.WeeklyReview(days_covered=0, top_priorities=[], recommendations=[])
    replay = marketing_mod.DecisionReplay()
    plan = marketing_mod.choose_content_plan(brief, weekly, replay, memory={"angles": [], "hashes": []})
    assert plan.skip_generation is True
    assert plan.angle == "insufficient_signal"


def test_content_plan_avoids_recent_angle():
    brief = marketing_mod.CortexBrief(
        date="2026-04-19",
        priorities=[marketing_mod.Priority(title="Ship release", why="Users need stability", action="Publish build")],
        ignored_signals_count=4,
    )
    weekly = marketing_mod.WeeklyReview(days_covered=0, top_priorities=[], recommendations=[])
    replay = marketing_mod.DecisionReplay()
    plan = marketing_mod.choose_content_plan(
        brief,
        weekly,
        replay,
        memory={"angles": [{"angle": "today_priority"}], "hashes": []},
    )
    assert plan.angle == "ignored_signals"


def test_generated_copy_uses_simplixio_branding():
    cfg = marketing_mod.Config()
    brief = marketing_mod.CortexBrief(
        date="2026-04-19",
        priorities=[
            marketing_mod.Priority(
                title="Strengthen offline queue",
                why="Reliability during travel",
                action="Sync when online resumes",
            )
        ],
        ignored_signals_count=3,
    )
    weekly = marketing_mod.WeeklyReview(days_covered=4)
    replay = marketing_mod.DecisionReplay(
        date="2026-04-19",
        signals_reviewed=20,
        signals_kept=6,
        signals_ignored=14,
        summary="SimpliXio reduced 20 signals into 3 priorities.",
    )
    plan = marketing_mod.ContentPlan(
        angle="today_priority",
        score=4,
        reason="Daily top priority exists with why/action context.",
        title="Top priority angle",
    )
    posts = marketing_mod.deterministic_posts(cfg, brief, weekly, replay, trends=[], plan=plan)
    assert posts
    assert all("SimpliXio" in post.body for post in posts.values())
    assert all("CortexOS today" not in post.body for post in posts.values())


def test_content_plan_prefers_decision_replay_signal():
    brief = marketing_mod.CortexBrief(
        date="2026-04-19",
        priorities=[],
        ignored_signals_count=0,
    )
    weekly = marketing_mod.WeeklyReview(days_covered=0, top_priorities=[], recommendations=[])
    replay = marketing_mod.DecisionReplay(signals_reviewed=30, signals_kept=8, signals_ignored=22)
    plan = marketing_mod.choose_content_plan(brief, weekly, replay, memory={"angles": [], "hashes": []})
    assert plan.angle == "decision_replay_proof"


def test_outreach_drafts_only_fit_leads(tmp_path):
    db_path = tmp_path / "acq.sqlite3"
    output_dir = tmp_path / "output"
    acq_crm_mod.DB_PATH = db_path
    acq_crm_mod.OUTPUT_DIR = output_dir
    outreach_mod.OUTPUT_DIR = output_dir
    acq_quality_mod.OUTPUT_DIR = output_dir

    conn = acq_crm_mod.connect()
    acq_crm_mod.init_db(conn)

    fit_id = acq_crm_mod.upsert_lead(
        conn,
        source="github",
        source_url="https://github.com/example/fit",
        title="Founder shipping prioritization workflows",
        pain_signal="Decision fatigue",
        raw_payload={"excerpt": "strong fit"},
    )
    candidate_id = acq_crm_mod.upsert_lead(
        conn,
        source="github",
        source_url="https://github.com/example/candidate",
        title="Interesting but weaker match",
        pain_signal="Unknown",
        raw_payload={"excerpt": "candidate"},
    )
    acq_crm_mod.update_lead_score(
        conn,
        lead_id=fit_id,
        fit_score=82,
        pain_signal="Decision fatigue",
        status="fit",
        next_action="draft_outreach",
    )
    acq_crm_mod.update_lead_score(
        conn,
        lead_id=candidate_id,
        fit_score=50,
        pain_signal="Unknown",
        status="candidate",
        next_action="manual_review",
    )

    result = outreach_mod.run(limit=20)
    assert result["created"] == 1
    assert result["from_fit"] == 1
    assert result["from_candidate"] == 0


def test_acquisition_quality_gate_rejects_non_fit_outreach(tmp_path):
    db_path = tmp_path / "acq.sqlite3"
    output_dir = tmp_path / "output"
    acq_crm_mod.DB_PATH = db_path
    acq_crm_mod.OUTPUT_DIR = output_dir
    acq_quality_mod.OUTPUT_DIR = output_dir

    conn = acq_crm_mod.connect()
    acq_crm_mod.init_db(conn)

    lead_id = acq_crm_mod.upsert_lead(
        conn,
        source="rss",
        source_url="https://example.com/low-fit",
        title="Low-fit generic content",
        pain_signal="Unknown",
        raw_payload={"excerpt": "generic"},
    )
    acq_crm_mod.update_lead_score(
        conn,
        lead_id=lead_id,
        fit_score=34,
        pain_signal="Unknown",
        status="candidate",
        next_action="manual_review",
    )
    acq_crm_mod.insert_message(
        conn,
        lead_id=lead_id,
        channel="private_outreach",
        message_type="private",
        draft_text="Hi, https://example.com/low-fit looked relevant for decision system workflows.",
        status="needs_approval",
    )

    result = acq_quality_mod.run(strict=False)
    assert result["failed_count"] >= 1
    assert any(item["status"] == "rejected_quality" for item in result["messages"])


def test_scoring_queue_includes_existing_fit_leads(tmp_path):
    db_path = tmp_path / "acq.sqlite3"
    output_dir = tmp_path / "output"
    acq_crm_mod.DB_PATH = db_path
    acq_crm_mod.OUTPUT_DIR = output_dir

    conn = acq_crm_mod.connect()
    acq_crm_mod.init_db(conn)
    lead_id = acq_crm_mod.upsert_lead(
        conn,
        source="github",
        source_url="https://github.com/example/re-score",
        title="Founder building decision workflows",
        pain_signal="Decision fatigue",
        raw_payload={"excerpt": "active project"},
    )
    acq_crm_mod.update_lead_score(
        conn,
        lead_id=lead_id,
        fit_score=78,
        pain_signal="Decision fatigue",
        status="fit",
        next_action="draft_outreach",
    )

    queue = acq_crm_mod.list_leads_for_scoring(conn, limit=10)
    assert any(item.id == lead_id for item in queue)


def test_newsletter_generation_strict_safety_marks_needs_review(tmp_path):
    data_dir = tmp_path / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    notes = [
        {
            "id": "n1",
            "title": "Weekly insight",
            "insight": "I noticed founders are overwhelmed. Contact me at me@example.com.",
            "created_at": "2026-04-21T10:00:00Z",
            "archived": False,
        },
        {
            "id": "n2",
            "title": "Do not publish",
            "insight": "This is confidential and internal only.",
            "created_at": "2026-04-21T12:00:00Z",
            "archived": False,
        },
    ]
    (data_dir / "knowledge_notes.json").write_text(json.dumps(notes, indent=2), encoding="utf-8")

    decisions = [
        {
            "id": "d1",
            "decision": "Ship decision replay to users",
            "reason": "Context is at https://private.example.com/internal",
            "created_at": "2026-04-21T13:00:00Z",
        }
    ]
    (data_dir / "decisions.json").write_text(json.dumps(decisions, indent=2), encoding="utf-8")

    newsletter_mod.pick_data_dir = lambda: data_dir
    output_dir = tmp_path / "out" / "newsletters"

    payload = newsletter_mod.run_generation(
        period="custom",
        from_date="2026-04-20",
        to_date="2026-04-22",
        mode="weekly-lessons",
        strict_safety=True,
        output=str(output_dir),
    )
    latest_md = Path(payload["outputs"]["markdown"])

    assert latest_md.exists()
    text = latest_md.read_text(encoding="utf-8").lower()
    assert "me@example.com" not in text
    assert "private.example.com" not in text
    assert "this is confidential and internal only" not in text
    assert "[personal detail removed]" in text
    assert payload["status"] == "needs_review"
    assert payload["safe_to_publish"] is False
    assert "n1" in payload["source_ids"]
    assert "n2" in payload["source_ids"]
    assert any(item["item_type"] == "url" for item in payload["safety_report"]["redactions_applied"])


def test_newsletter_generation_custom_range_and_source_ids_filter(tmp_path):
    data_dir = tmp_path / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    notes = [
        {
            "id": "old-note",
            "title": "Old thought",
            "insight": "Should be excluded by custom range.",
            "created_at": "2026-03-01T10:00:00Z",
            "archived": False,
        },
        {
            "id": "target-note",
            "title": "Builder lesson",
            "insight": "Reduce noise into action with 3 priorities.",
            "created_at": "2026-04-21T10:00:00Z",
            "archived": False,
        },
    ]
    (data_dir / "knowledge_notes.json").write_text(json.dumps(notes, indent=2), encoding="utf-8")
    newsletter_mod.pick_data_dir = lambda: data_dir

    output_dir = tmp_path / "out" / "newsletters"
    payload = newsletter_mod.run_generation(
        period="custom",
        from_date="2026-04-20",
        to_date="2026-04-22",
        mode="product-builder-notes",
        source_ids="target-note",
        strict_safety=True,
        strict_taste=False,
        output=str(output_dir),
    )

    assert payload["status"] == "draft"
    assert payload["period_start"] == "2026-04-20"
    assert payload["period_end"] == "2026-04-22"
    assert payload["source_ids"] == ["target-note"]
    assert payload["selected_filters"]["source_ids"] == ["target-note"]
    assert payload["source_count_total"] == 1


def test_newsletter_generation_applies_classification_labels(tmp_path):
    data_dir = tmp_path / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    notes = [
        {
            "id": "private-note",
            "title": "Private thread",
            "insight": "Do not publish this private conversation.",
            "created_at": "2026-04-21T10:00:00Z",
            "archived": False,
        },
        {
            "id": "safe-note",
            "title": "Public lesson",
            "insight": "Choose 3 priorities and act on one concrete next step.",
            "created_at": "2026-04-21T11:00:00Z",
            "archived": False,
        },
    ]
    (data_dir / "knowledge_notes.json").write_text(json.dumps(notes, indent=2), encoding="utf-8")
    newsletter_mod.pick_data_dir = lambda: data_dir

    payload = newsletter_mod.run_generation(
        period="custom",
        from_date="2026-04-20",
        to_date="2026-04-22",
        mode="weekly-lessons",
        strict_safety=True,
        strict_taste=False,
        output=str(tmp_path / "out" / "newsletters"),
    )
    counts = payload["classification_summary"]["counts"]
    assert counts["private"] >= 1
    assert payload["classification_summary"]["items"]


def test_newsletter_taste_gate_blocks_repeated_output(tmp_path):
    data_dir = tmp_path / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    notes = [
        {
            "id": "n1",
            "title": "Builder notes",
            "insight": "Reduce noise into action with 3 priorities and clear why.",
            "created_at": "2026-04-21T09:00:00Z",
            "archived": False,
        },
        {
            "id": "n2",
            "title": "Decision loop",
            "insight": "What matters is deciding what to ignore before adding more inputs.",
            "created_at": "2026-04-21T09:30:00Z",
            "archived": False,
        },
    ]
    (data_dir / "knowledge_notes.json").write_text(json.dumps(notes, indent=2), encoding="utf-8")
    newsletter_mod.pick_data_dir = lambda: data_dir

    output_dir = tmp_path / "out" / "newsletters"
    first = newsletter_mod.run_generation(
        period="custom",
        from_date="2026-04-20",
        to_date="2026-04-22",
        mode="weekly-lessons",
        strict_safety=True,
        strict_taste=True,
        output=str(output_dir),
    )
    second = newsletter_mod.run_generation(
        period="custom",
        from_date="2026-04-20",
        to_date="2026-04-22",
        mode="weekly-lessons",
        strict_safety=True,
        strict_taste=True,
        output=str(output_dir),
    )

    assert first["status"] == "draft"
    assert second["status"] == "needs_review"
    assert "too_similar_to_previous_output" in second["taste_gate"]["reasons"]


def test_discord_proof_drafts_are_generated_as_manual_only(tmp_path):
    output_dir = tmp_path / "output"
    (output_dir / "weekly_review").mkdir(parents=True, exist_ok=True)
    (output_dir / "decision_replay").mkdir(parents=True, exist_ok=True)
    (output_dir / "newsletters" / "drafts").mkdir(parents=True, exist_ok=True)

    (output_dir / "weekly_review" / "latest.json").write_text(
        json.dumps(
            {
                "summary": "SimpliXio reviewed 5 day(s) of output.",
                "days_covered": 5,
                "total_ignored_signals": 12,
                "top_priorities": [{"title": "Stability before expansion", "count": 3}],
                "recommendations": ["Keep queue outputs focused and explainable."],
            }
        ),
        encoding="utf-8",
    )
    (output_dir / "decision_replay" / "latest.json").write_text(
        json.dumps(
            {
                "summary": "SimpliXio reviewed 22 signals, ignored 15, and selected 3 priorities.",
                "signals_reviewed": 22,
                "signals_kept": 7,
            }
        ),
        encoding="utf-8",
    )
    (output_dir / "newsletters" / "drafts" / "latest.json").write_text(
        json.dumps({"status": "needs_review", "safe_to_publish": False}),
        encoding="utf-8",
    )

    discord_mod.AUTOMATION_ROOT = tmp_path
    discord_mod.OUTPUT_DIR = output_dir / "discord"
    discord_mod.WEEKLY_REVIEW_PATH = output_dir / "weekly_review" / "latest.json"
    discord_mod.DECISION_REPLAY_PATH = output_dir / "decision_replay" / "latest.json"
    discord_mod.NEWSLETTER_DRAFT_PATH = output_dir / "newsletters" / "drafts" / "latest.json"

    payload = discord_mod.run()
    assert payload["status"] == "draft"
    assert payload["draft_only"] is True
    assert payload["requires_manual_post"] is True
    assert payload["posting_rules"]["autopublish"] is False
    assert "weekly-review" in payload["channels"]
    assert "product-lessons" in payload["channels"]
    assert Path(payload["manifest"]).exists()
    assert Path(payload["files"]["weekly_review"]).exists()
    assert Path(payload["files"]["product_lesson"]).exists()
    assert Path(payload["files"]["decision_example_spotlight"]).exists()


def test_discord_proof_drafts_apply_redaction(tmp_path):
    output_dir = tmp_path / "output"
    (output_dir / "weekly_review").mkdir(parents=True, exist_ok=True)
    (output_dir / "decision_replay").mkdir(parents=True, exist_ok=True)

    (output_dir / "weekly_review" / "latest.json").write_text(
        json.dumps(
            {
                "summary": "Contact me at founder@example.com for the confidential plan.",
                "days_covered": 4,
                "total_ignored_signals": 8,
                "top_priorities": [{"title": "Internal project launch", "count": 2}],
                "recommendations": ["Do not publish this private detail."],
            }
        ),
        encoding="utf-8",
    )
    (output_dir / "decision_replay" / "latest.json").write_text(
        json.dumps({"summary": "Review happened at https://private.example.com/replay"}),
        encoding="utf-8",
    )

    discord_mod.AUTOMATION_ROOT = tmp_path
    discord_mod.OUTPUT_DIR = output_dir / "discord"
    discord_mod.WEEKLY_REVIEW_PATH = output_dir / "weekly_review" / "latest.json"
    discord_mod.DECISION_REPLAY_PATH = output_dir / "decision_replay" / "latest.json"
    discord_mod.NEWSLETTER_DRAFT_PATH = output_dir / "newsletters" / "drafts" / "latest.json"

    payload = discord_mod.run()
    release_text = Path(payload["files"]["release_notes"]).read_text(encoding="utf-8").lower()
    assert "founder@example.com" not in release_text
    assert "private.example.com" not in release_text
    assert "[confidential detail removed]" in release_text or "[personal detail removed]" in release_text
