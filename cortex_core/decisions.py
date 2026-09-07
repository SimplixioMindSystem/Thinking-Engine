"""
Decision Engine
----------------
The feature that makes CortexOS genuinely useful every day.
Most tools stop at summarisation. CortexOS goes one step further.

Outputs:
  - Top priorities for today
  - Why each one matters
  - Exact next step
  - What can be safely ignored
  - What changed since yesterday

Also stores decision history — what was chosen, why, and what
assumptions existed at the time. This makes CortexOS compounding.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path


@dataclass
class Priority:
    """A single prioritised action item."""

    rank: int = 0
    title: str = ""
    why_it_matters: str = ""
    next_step: str = ""
    source: str = ""  # where this came from (signal, insight, note, etc.)
    relevance_score: float = 0.0
    tags: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> Priority:
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


@dataclass
class Decision:
    """A recorded decision with full context."""

    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    decision: str = ""
    reason: str = ""
    project: str = ""
    assumptions: list[str] = field(default_factory=list)
    context_tags: list[str] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    outcome: str = ""  # filled later
    impact_score: float = 0.0  # 0.0—1.0, filled later

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> Decision:
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


@dataclass
class DailyDecisionBrief:
    """The daily intelligence brief — CortexOS's primary decision output."""

    date: str = field(default_factory=lambda: datetime.now(UTC).strftime("%Y-%m-%d"))
    priorities: list[Priority] = field(default_factory=list)
    ignored: list[str] = field(default_factory=list)
    emerging_signals: list[str] = field(default_factory=list)
    changes_since_yesterday: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "date": self.date,
            "priorities": [p.to_dict() for p in self.priorities],
            "ignored": self.ignored,
            "emerging_signals": self.emerging_signals,
            "changes_since_yesterday": self.changes_since_yesterday,
        }

    def to_markdown(self) -> str:
        lines = [
            f"# CortexOS Daily Intelligence — {self.date}",
            "",
        ]

        if self.emerging_signals:
            lines.append("## Emerging Signals")
            for sig in self.emerging_signals:
                lines.append(f"- {sig}")
            lines.append("")

        if self.priorities:
            lines.append("## Focus Today")
            for p in self.priorities:
                lines.extend(
                    [
                        f"### {p.rank}. {p.title}",
                        f"**Why it matters:** {p.why_it_matters}",
                        f"**Next step:** {p.next_step}",
                        f"_Relevance: {p.relevance_score:.2f} | Source: {p.source}_",
                        "",
                    ]
                )
        else:
            lines.append("_No priorities today. Run the pipeline to generate._")
            lines.append("")

        if self.ignored:
            lines.append("## Safely Ignored")
            for item in self.ignored:
                lines.append(f"- {item}")
            lines.append("")

        if self.changes_since_yesterday:
            lines.append("## What Changed Since Yesterday")
            for change in self.changes_since_yesterday:
                lines.append(f"- {change}")
            lines.append("")

        return "\n".join(lines)


class DecisionEngine:
    """Produces prioritised daily briefs and stores decision history.

    Inputs: scored items, insights, signals, user profile
    Output: ranked priorities + what to ignore + changes
    """

    def __init__(self, data_dir: Path):
        self._data_dir = data_dir
        self._decisions_path = data_dir / "decisions.json"
        self._decisions: list[Decision] = []
        self._load()

    def _load(self) -> None:
        if self._decisions_path.exists():
            with open(self._decisions_path) as f:
                raw = json.load(f)
            self._decisions = [Decision.from_dict(d) for d in raw]

    def save(self) -> None:
        self._data_dir.mkdir(parents=True, exist_ok=True)
        with open(self._decisions_path, "w") as f:
            json.dump([d.to_dict() for d in self._decisions], f, indent=2)

    # ── Priority generation ──────────────────────────────────

    def generate_brief(
        self,
        *,
        scored_items: list[dict] | None = None,
        insights: list[dict] | None = None,
        signals: list[dict] | None = None,
        profile: dict | None = None,
        previous_brief: dict | None = None,
        feedback_notes: list[str] | None = None,
        max_priorities: int = 3,
    ) -> DailyDecisionBrief:
        """Generate today's decision brief from all available context."""
        brief = DailyDecisionBrief()
        candidates: list[Priority] = []

        # Score from items (articles with scores)
        if scored_items:
            for item in scored_items:
                score = item.get("composite", item.get("relevance_score", 0))
                candidates.append(
                    Priority(
                        title=item.get("title", ""),
                        why_it_matters=item.get("why_it_matters", f"Scored {score:.2f} against your profile."),
                        next_step=item.get("next_action", "Review and extract key insight."),
                        source="scored_item",
                        relevance_score=score,
                        tags=item.get("tags", []),
                    )
                )

        # Score from insights (already structured)
        if insights:
            for ins in insights:
                conf = ins.get("confidence", 0.5)
                candidates.append(
                    Priority(
                        title=ins.get("title", ""),
                        why_it_matters=ins.get("why_it_matters", ins.get("summary", "")),
                        next_step=ins.get("next_action", ""),
                        source="insight",
                        relevance_score=conf,
                        tags=ins.get("tags", []),
                    )
                )

        # Score from signals
        if signals:
            for sig in signals:
                strength = sig.get("strength", 0)
                candidates.append(
                    Priority(
                        title=f"Signal: {sig.get('topic', '')}",
                        why_it_matters=f"Detected in {sig.get('frequency', 0)} sources. Trending topic.",
                        next_step="Investigate further — this topic is gaining traction.",
                        source="signal",
                        relevance_score=strength,
                        tags=[sig.get("topic", "")],
                    )
                )

        # Apply profile-based re-ranking if profile is available
        if profile:
            goals_tokens = self._significant_tokens(profile.get("goals", []))
            interests_tokens = self._significant_tokens(profile.get("interests", []))
            ignored = set(t.lower() for t in profile.get("ignored_topics", []))

            for c in candidates:
                title_lower = c.title.lower()
                # Boost if title matches goals or interests
                goal_boost = 0.15 if any(w in title_lower for w in goals_tokens) else 0.0
                interest_boost = 0.10 if any(w in title_lower for w in interests_tokens) else 0.0
                c.relevance_score = min(c.relevance_score + goal_boost + interest_boost, 1.0)

                # Demote if matches ignored topics
                if any(ig in title_lower for ig in ignored):
                    c.relevance_score *= 0.1

        # Apply lightweight learning from recent feedback notes.
        useful_terms, not_useful_terms, acted_terms, stalled_terms = self._feedback_terms(feedback_notes or [])
        if useful_terms or not_useful_terms or acted_terms or stalled_terms:
            for c in candidates:
                title_lower = c.title.lower()
                if any(self._matches_feedback_term(title_lower, term) for term in useful_terms):
                    c.relevance_score = min(c.relevance_score + 0.12, 1.0)
                if any(self._matches_feedback_term(title_lower, term) for term in acted_terms):
                    c.relevance_score = min(c.relevance_score + 0.08, 1.0)
                if any(self._matches_feedback_term(title_lower, term) for term in not_useful_terms):
                    c.relevance_score *= 0.4
                if any(self._matches_feedback_term(title_lower, term) for term in stalled_terms):
                    c.relevance_score *= 0.75

        # Merge duplicate titles from different sources to reduce noise.
        merged: dict[str, Priority] = {}
        for c in candidates:
            key = c.title.strip().lower()
            if not key:
                continue
            existing = merged.get(key)
            if existing is None:
                merged[key] = c
                continue

            if c.relevance_score > existing.relevance_score:
                existing.relevance_score = c.relevance_score
            if not existing.why_it_matters and c.why_it_matters:
                existing.why_it_matters = c.why_it_matters
            if not existing.next_step and c.next_step:
                existing.next_step = c.next_step
            existing.tags = list(dict.fromkeys([*existing.tags, *c.tags]))
        candidates = list(merged.values())

        # Sort by relevance and take top N
        candidates.sort(key=lambda c: c.relevance_score, reverse=True)

        # Separate into priorities and ignored
        top = candidates[:max_priorities]
        for i, p in enumerate(top, 1):
            p.rank = i
        brief.priorities = top

        # Items below threshold are "safely ignored"
        threshold = 0.15
        ignored_items = [c for c in candidates[max_priorities:] if c.relevance_score < threshold]
        brief.ignored = [f"{c.title} (score: {c.relevance_score:.2f})" for c in ignored_items[:10]]

        # Emerging signals
        if signals:
            brief.emerging_signals = [
                f"{s.get('topic', '')} (seen in {s.get('frequency', 0)} sources)"
                for s in signals
                if s.get("status") in ("emerging", "confirmed")
            ]

        # Changes since yesterday
        if previous_brief:
            prev_titles = {p.get("title", "") for p in previous_brief.get("priorities", [])}
            curr_titles = {p.title for p in brief.priorities}
            new_items = curr_titles - prev_titles
            removed_items = prev_titles - curr_titles
            for t in new_items:
                if t:
                    brief.changes_since_yesterday.append(f"NEW: {t}")
            for t in removed_items:
                if t:
                    brief.changes_since_yesterday.append(f"DROPPED: {t}")

        return brief

    @staticmethod
    def _significant_tokens(lines: list[str]) -> set[str]:
        tokens: set[str] = set()
        for line in lines:
            for raw in line.lower().split():
                token = "".join(ch for ch in raw if ch.isalnum())
                if len(token) >= 4:
                    tokens.add(token)
        return tokens

    @staticmethod
    def _feedback_terms(notes: list[str]) -> tuple[set[str], set[str], set[str], set[str]]:
        useful: set[str] = set()
        not_useful: set[str] = set()
        acted: set[str] = set()
        not_acted: set[str] = set()

        for note in notes[-200:]:
            text = note.strip()
            if text.startswith("[useful]"):
                useful.add(text.removeprefix("[useful]").strip().lower())
            elif text.startswith("[not_useful]"):
                not_useful.add(text.removeprefix("[not_useful]").strip().lower())
            elif text.startswith("[acted]"):
                acted.add(text.removeprefix("[acted]").strip().lower())
            elif text.startswith("[not_acted]"):
                not_acted.add(text.removeprefix("[not_acted]").strip().lower())

        useful.discard("")
        not_useful.discard("")
        acted.discard("")
        not_acted.discard("")
        return useful, not_useful, acted, not_acted

    @staticmethod
    def _matches_feedback_term(title: str, term: str) -> bool:
        if not term:
            return False
        return term in title or title in term

    # ── Decision recording ───────────────────────────────────

    def record_decision(
        self,
        decision: str,
        reason: str,
        *,
        project: str = "",
        assumptions: list[str] | None = None,
        context_tags: list[str] | None = None,
    ) -> Decision:
        """Record a decision with full context for future reference."""
        dec = Decision(
            decision=decision,
            reason=reason,
            project=project,
            assumptions=assumptions or [],
            context_tags=context_tags or [],
        )
        self._decisions.append(dec)
        self.save()
        return dec

    def record_outcome(
        self,
        decision_id: str,
        outcome: str,
        impact_score: float = 0.0,
    ) -> Decision | None:
        """Record the outcome of a past decision (feedback loop)."""
        for d in self._decisions:
            if d.id == decision_id:
                d.outcome = outcome
                d.impact_score = max(0.0, min(1.0, impact_score))
                self.save()
                return d
        return None

    def recent_decisions(self, limit: int = 10) -> list[Decision]:
        return sorted(self._decisions, key=lambda d: d.created_at, reverse=True)[:limit]

    def decisions_by_project(self, project: str) -> list[Decision]:
        project_lower = project.lower()
        return [d for d in self._decisions if project_lower in d.project.lower()]

    def decision_effectiveness(self) -> dict:
        """Aggregate decision outcomes for self-assessment."""
        rated = [d for d in self._decisions if d.impact_score > 0]
        if not rated:
            return {"total_decisions": len(self._decisions), "rated": 0, "avg_impact": 0.0}
        avg = sum(d.impact_score for d in rated) / len(rated)
        return {
            "total_decisions": len(self._decisions),
            "rated": len(rated),
            "avg_impact": round(avg, 2),
        }

    # ── Brief persistence ────────────────────────────────────

    def save_brief(self, brief: DailyDecisionBrief) -> Path:
        """Save decision brief as JSON and Markdown."""
        self._data_dir.mkdir(parents=True, exist_ok=True)
        json_path = self._data_dir / f"decision_{brief.date}.json"
        md_path = self._data_dir / f"decision_{brief.date}.md"

        with open(json_path, "w") as f:
            json.dump(brief.to_dict(), f, indent=2)
        with open(md_path, "w") as f:
            f.write(brief.to_markdown())
        return json_path

    def get_previous_brief(self) -> dict | None:
        """Load the most recent decision brief."""
        briefs = sorted(self._data_dir.glob("decision_*.json"), reverse=True)
        if not briefs:
            return None
        with open(briefs[0]) as f:
            return json.load(f)

    @property
    def all_decisions(self) -> list[Decision]:
        return list(self._decisions)
