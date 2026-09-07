"""RSS to CortexOS signal mapping."""

from __future__ import annotations

from cortex_core.integrations.schemas import CortexSignal, RawRSSItem, fingerprint_from_parts


def _matches_active_project(title: str, active_projects: list[str]) -> bool:
    title_lower = title.lower()
    return any(project.strip().lower() in title_lower for project in active_projects if project.strip())


def map_rss_to_signal(item: RawRSSItem, active_projects: list[str]) -> CortexSignal:
    relevance = 0.55
    if _matches_active_project(item.title, active_projects):
        relevance = 0.75

    return CortexSignal(
        id=fingerprint_from_parts("rss", item.fingerprint()),
        source="rss",
        title=item.title,
        url=item.url,
        why_it_matters="External signal that may affect active priorities.",
        next_action="Review this signal and decide if it changes today's top 3 priorities.",
        source_type="article",
        relevance_score=relevance,
        tags=["rss", "signal"],
    )
