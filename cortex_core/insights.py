"""
Structured Insight Objects
----------------------------
Every important item becomes a structured Insight — not just a
summary. This is how CortexOS accumulates compounding knowledge.

An Insight answers:
  - What happened?
  - Why does it matter?
  - What are the architectural implications?
  - What should I do next?
  - How confident are we?
"""

from __future__ import annotations

import json
import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path


@dataclass
class Insight:
    """A structured research insight — CortexOS's unit of knowledge."""

    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    source_item_id: str = ""  # link back to Item
    title: str = ""
    summary: str = ""
    why_it_matters: str = ""
    architectural_implication: str = ""
    next_action: str = ""
    confidence: float = 0.0  # 0.0—1.0
    tags: list[str] = field(default_factory=list)
    related_project: str = ""
    related_insight_ids: list[str] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> Insight:
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


def generate_insight_from_note(
    title: str,
    insight_text: str,
    implication: str,
    action: str,
    tags: list[str],
    *,
    source_item_id: str = "",
    project: str = "",
) -> Insight:
    """Create a structured Insight from a knowledge note."""
    # Determine confidence from completeness
    filled = sum(1 for v in [insight_text, implication, action] if v.strip())
    confidence = filled / 3.0

    return Insight(
        source_item_id=source_item_id,
        title=title,
        summary=insight_text,
        why_it_matters=implication or f"{title} may affect current project direction.",
        architectural_implication=implication,
        next_action=action or "Review and decide if action is needed.",
        confidence=round(confidence, 2),
        tags=tags,
        related_project=project,
    )


# ── Insight Store ────────────────────────────────────────────


class InsightStore:
    """Persists structured insights to JSON."""

    def __init__(self, path: Path):
        self.path = path
        self._insights: list[Insight] = []
        self._load()

    def _load(self) -> None:
        if self.path.exists():
            with open(self.path) as f:
                raw = json.load(f)
            self._insights = [Insight.from_dict(r) for r in raw]

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, "w") as f:
            json.dump([i.to_dict() for i in self._insights], f, indent=2)

    def add(self, insight: Insight) -> Insight:
        self._insights.append(insight)
        self.save()
        return insight

    def add_batch(self, insights: list[Insight]) -> list[Insight]:
        self._insights.extend(insights)
        self.save()
        return insights

    def get(self, insight_id: str) -> Insight | None:
        for i in self._insights:
            if i.id == insight_id:
                return i
        return None

    def by_project(self, project: str) -> list[Insight]:
        project_lower = project.lower()
        return [i for i in self._insights if project_lower in i.related_project.lower()]

    def by_tag(self, tag: str) -> list[Insight]:
        tag_lower = tag.lower()
        return [i for i in self._insights if tag_lower in [t.lower() for t in i.tags]]

    def high_confidence(self, threshold: float = 0.6) -> list[Insight]:
        return [i for i in self._insights if i.confidence >= threshold]

    def recent(self, limit: int = 20) -> list[Insight]:
        return sorted(self._insights, key=lambda i: i.created_at, reverse=True)[:limit]

    def search(self, query: str) -> list[Insight]:
        query_lower = query.lower()
        return [
            i
            for i in self._insights
            if query_lower in i.title.lower()
            or query_lower in i.summary.lower()
            or query_lower in i.why_it_matters.lower()
            or query_lower in i.architectural_implication.lower()
        ]

    def link(self, insight_id: str, related_id: str) -> bool:
        """Create a bidirectional link between two insights."""
        a = self.get(insight_id)
        b = self.get(related_id)
        if not a or not b:
            return False
        if related_id not in a.related_insight_ids:
            a.related_insight_ids.append(related_id)
        if insight_id not in b.related_insight_ids:
            b.related_insight_ids.append(insight_id)
        self.save()
        return True

    @property
    def count(self) -> int:
        return len(self._insights)

    @property
    def insights(self) -> list[Insight]:
        return list(self._insights)

    def summary(self) -> dict:
        all_tags: dict[str, int] = {}
        for insight in self._insights:
            for t in insight.tags:
                all_tags[t] = all_tags.get(t, 0) + 1
        projects = {i.related_project for i in self._insights if i.related_project}
        return {
            "total": self.count,
            "tags": all_tags,
            "projects": sorted(projects),
            "avg_confidence": (
                round(sum(i.confidence for i in self._insights) / len(self._insights), 2) if self._insights else 0.0
            ),
        }
