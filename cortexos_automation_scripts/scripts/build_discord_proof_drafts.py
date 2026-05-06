#!/usr/bin/env python3
"""Build curated Discord proof drafts from safe SimpliXio artifacts.

Draft-only by design:
- never posts to Discord
- writes local markdown/json drafts for manual approval
"""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

AUTOMATION_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = AUTOMATION_ROOT / "output" / "discord"
WEEKLY_REVIEW_PATH = AUTOMATION_ROOT / "output" / "weekly_review" / "latest.json"
DECISION_REPLAY_PATH = AUTOMATION_ROOT / "output" / "decision_replay" / "latest.json"
NEWSLETTER_DRAFT_PATH = AUTOMATION_ROOT / "output" / "newsletters" / "drafts" / "latest.json"
DECISION_EXAMPLES_PATH = AUTOMATION_ROOT.parent / "docs" / "decision-examples" / "decision_examples.json"

REDACT_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", re.IGNORECASE), "[personal detail removed]"),
    (re.compile(r"https?://\\S+", re.IGNORECASE), "[link removed]"),
]

BLOCKED_KEYWORDS = {
    "private",
    "sensitive",
    "internal",
    "confidential",
    "client",
    "do-not-publish",
    "do not publish",
}


def ensure_dirs() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def sanitize_text(text: str) -> tuple[str, bool]:
    value = text.strip()
    changed = False

    for pattern, replacement in REDACT_PATTERNS:
        next_value = pattern.sub(replacement, value)
        if next_value != value:
            changed = True
        value = next_value

    lowered = value.lower()
    if any(keyword in lowered for keyword in BLOCKED_KEYWORDS):
        return "[confidential detail removed]", True

    return value, changed


def safe_line(text: str, fallback: str) -> tuple[str, bool]:
    raw = text.strip()
    if not raw:
        return fallback, False
    clean, changed = sanitize_text(raw)
    if not clean:
        return fallback, changed
    return clean, changed


def build_release_notes(weekly: dict[str, Any], replay: dict[str, Any]) -> tuple[str, list[str]]:
    redactions: list[str] = []
    summary, changed = safe_line(
        str(weekly.get("summary", "")),
        "SimpliXio kept refining daily priorities from real captured signals.",
    )
    if changed:
        redactions.append("weekly_summary")

    top_title = "Sharpen daily priorities"
    priorities = weekly.get("top_priorities", [])
    if priorities:
        top_title, changed = safe_line(str(priorities[0].get("title", "")), top_title)
        if changed:
            redactions.append("weekly_top_priority")

    replay_summary, changed = safe_line(
        str(replay.get("summary", "")),
        "Decision Replay remains focused on explainable signal filtering.",
    )
    if changed:
        redactions.append("decision_replay_summary")

    lines = [
        "#release-notes",
        "",
        "**What changed**",
        f"- Improved focus around: {top_title}.",
        "- Refined the daily decision loop so 3 priorities stay clear.",
        "",
        "**Why it matters**",
        f"- {summary}",
        f"- {replay_summary}",
        "",
        "**CTA**",
        "- Try today's run and tell us if the top priority felt right.",
    ]
    return "\n".join(lines) + "\n", redactions


def build_weekly_proof(weekly: dict[str, Any], replay: dict[str, Any], newsletter: dict[str, Any]) -> tuple[str, list[str]]:
    redactions: list[str] = []

    days = int(weekly.get("days_covered", 0) or 0)
    ignored = int(weekly.get("total_ignored_signals", 0) or 0)
    reviewed = int(replay.get("signals_reviewed", 0) or 0)
    kept = int(replay.get("signals_kept", 0) or 0)

    recommendation = "Keep capture lightweight, then decide from ranked context."
    recs = weekly.get("recommendations", [])
    if recs:
        recommendation, changed = safe_line(str(recs[0]), recommendation)
        if changed:
            redactions.append("weekly_recommendation")

    newsletter_status = str(newsletter.get("status", "draft")).strip() or "draft"
    safe_to_publish = bool(newsletter.get("safe_to_publish", False))

    lines = [
        "#build-in-public",
        "",
        "This week in SimpliXio:",
        f"- Reviewed {reviewed} signals from {days} day(s) of output.",
        f"- Kept {kept} signals and ignored {ignored} low-signal items.",
        f"- Newsletter draft status: {newsletter_status} (safe_to_publish={str(safe_to_publish).lower()}).",
        "",
        "What we learned:",
        f"- {recommendation}",
        "",
        "Next:",
        "- Tighten ranking explanations and keep surfaces calm.",
        "",
        "Feedback prompt:",
        "- Which surfaced priority was most useful this week?",
    ]
    return "\n".join(lines) + "\n", redactions


def build_weekly_review_post(weekly: dict[str, Any]) -> tuple[str, list[str]]:
    redactions: list[str] = []

    days = int(weekly.get("days_covered", 0) or 0)
    ignored = int(weekly.get("total_ignored_signals", 0) or 0)
    summary, changed = safe_line(
        str(weekly.get("summary", "")),
        "SimpliXio reviewed the week and kept the focus on what mattered.",
    )
    if changed:
        redactions.append("weekly_review_summary")

    priority = "Keep the top priority clear."
    priorities = weekly.get("top_priorities", [])
    if priorities:
        priority, changed = safe_line(str(priorities[0].get("title", "")), priority)
        if changed:
            redactions.append("weekly_review_top_priority")

    lines = [
        "#weekly-review",
        "",
        "**Weekly Review**",
        f"- Covered {days} day(s) of output.",
        f"- Ignored {ignored} low-signal item(s).",
        f"- Top pattern: {priority}.",
        "",
        "**What mattered**",
        f"- {summary}",
        "",
        "**CTA**",
        "- Share whether this weekly pattern feels useful.",
    ]
    return "\n".join(lines) + "\n", redactions


def build_product_lesson(weekly: dict[str, Any], replay: dict[str, Any]) -> tuple[str, list[str]]:
    redactions: list[str] = []

    lesson = "Fewer surfaced items can create more trust than longer queues."
    recs = weekly.get("recommendations", [])
    if recs:
        lesson, changed = safe_line(str(recs[0]), lesson)
        if changed:
            redactions.append("product_lesson_recommendation")

    replay_summary, changed = safe_line(
        str(replay.get("summary", "")),
        "Decision Replay showed what was kept, ignored, and why.",
    )
    if changed:
        redactions.append("product_lesson_replay_summary")

    lines = [
        "#product-lessons",
        "",
        "**Product lesson**",
        f"- {lesson}",
        "",
        "**Why it matters**",
        f"- {replay_summary}",
        "- SimpliXio should reduce mental load, not create another backlog.",
        "",
        "**CTA**",
        "- Tell us which surface still feels too noisy.",
    ]
    return "\n".join(lines) + "\n", redactions


def build_feedback_prompt() -> str:
    return "\n".join(
        [
            "#feedback",
            "",
            "Quick check:",
            "- Did SimpliXio pick the right top priority today?",
            "- Was the why clear enough to act?",
            "- What should the system ignore better next time?",
        ]
    ) + "\n"


def pick_decision_example() -> dict[str, Any]:
    payload = load_json(DECISION_EXAMPLES_PATH)
    examples = payload.get("examples", [])
    if not isinstance(examples, list):
        return {}

    preferred = {
        "how-to-prioritize-startup-ideas",
        "how-to-turn-github-issues-into-priorities",
        "how-to-review-your-week-as-a-solo-founder",
    }
    for item in examples:
        if isinstance(item, dict) and str(item.get("slug", "")) in preferred:
            return item
    for item in examples:
        if isinstance(item, dict):
            return item
    return {}


def build_decision_example_spotlight(example: dict[str, Any]) -> tuple[str, list[str]]:
    redactions: list[str] = []
    title, changed = safe_line(str(example.get("title", "")), "How scattered project noise becomes 3 priorities")
    if changed:
        redactions.append("decision_example_title")
    description, changed = safe_line(
        str(example.get("meta_description", "")),
        "A public-safe example showing messy input becoming 3 priorities and one next action.",
    )
    if changed:
        redactions.append("decision_example_description")

    path = str(example.get("path", "")).strip() or "docs/decision-examples/index.md"
    if not path.startswith("docs/decision-examples/"):
        path = "docs/decision-examples/index.md"

    lines = [
        "#build-in-public",
        "",
        "**Decision Example spotlight**",
        f"- {title}",
        f"- {description}",
        "",
        "**Why it matters**",
        "- SimpliXio is easiest to understand when people can see messy input become 3 priorities, why, and action.",
        "",
        "**CTA**",
        f"- Read the example: {path}",
    ]
    return "\n".join(lines) + "\n", redactions


def write_file(path: Path, content: str) -> str:
    path.write_text(content, encoding="utf-8")
    return str(path)


def run() -> dict[str, Any]:
    ensure_dirs()
    weekly = load_json(WEEKLY_REVIEW_PATH)
    replay = load_json(DECISION_REPLAY_PATH)
    newsletter = load_json(NEWSLETTER_DRAFT_PATH)
    decision_example = pick_decision_example()

    if not weekly and not replay:
        payload = {
            "status": "skipped",
            "reason": "missing_weekly_or_replay_artifacts",
            "draft_only": True,
            "requires_manual_post": True,
        }
        print(json.dumps(payload, indent=2))
        return payload

    release_md, release_redactions = build_release_notes(weekly, replay)
    weekly_md, weekly_redactions = build_weekly_proof(weekly, replay, newsletter)
    review_md, review_redactions = build_weekly_review_post(weekly)
    lesson_md, lesson_redactions = build_product_lesson(weekly, replay)
    feedback_md = build_feedback_prompt()
    decision_example_md, decision_example_redactions = build_decision_example_spotlight(decision_example)

    release_path = OUTPUT_DIR / "release_notes_latest.md"
    weekly_path = OUTPUT_DIR / "build_in_public_latest.md"
    review_path = OUTPUT_DIR / "weekly_review_latest.md"
    lesson_path = OUTPUT_DIR / "product_lesson_latest.md"
    feedback_path = OUTPUT_DIR / "feedback_prompt_latest.md"
    decision_example_path = OUTPUT_DIR / "decision_example_spotlight_latest.md"
    manifest_path = OUTPUT_DIR / "latest.json"

    payload = {
        "generated_at": datetime.now(UTC).replace(microsecond=0).isoformat(),
        "status": "draft",
        "draft_only": True,
        "requires_manual_post": True,
        "channels": ["release-notes", "build-in-public", "weekly-review", "product-lessons", "feedback"],
        "posting_rules": {
            "manual_review_required": True,
            "autopublish": False,
            "private_material_allowed": False,
        },
        "redactions_applied": sorted(
            set(
                release_redactions
                + weekly_redactions
                + review_redactions
                + lesson_redactions
                + decision_example_redactions
            )
        ),
        "files": {
            "release_notes": write_file(release_path, release_md),
            "build_in_public": write_file(weekly_path, weekly_md),
            "weekly_review": write_file(review_path, review_md),
            "product_lesson": write_file(lesson_path, lesson_md),
            "feedback": write_file(feedback_path, feedback_md),
            "decision_example_spotlight": write_file(decision_example_path, decision_example_md),
        },
    }

    manifest_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    payload["manifest"] = str(manifest_path)
    print(json.dumps(payload, indent=2))
    return payload


if __name__ == "__main__":
    run()
