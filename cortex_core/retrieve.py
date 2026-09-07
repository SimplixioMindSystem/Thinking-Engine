"""
Hybrid Retrieval Layer
-----------------------
Retrieval is not just semantic search. CortexOS uses hybrid
retrieval with four layers:

  1. Metadata filters first (source_type, tags, project)
  2. Keyword matches second
  3. Recency weighting third
  4. (Future: vector similarity fourth)

The goal is small, sharp, and relevant — not everything everywhere.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from cortex_core.scoring import tokenize


@dataclass
class RetrievalResult:
    """A single retrieved item with its relevance score."""

    id: str = ""
    title: str = ""
    content: str = ""
    source_type: str = ""
    tags: list[str] = field(default_factory=list)
    score: float = 0.0
    match_reasons: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "content": self.content[:500],  # truncate for API responses
            "source_type": self.source_type,
            "tags": self.tags,
            "score": round(self.score, 3),
            "match_reasons": self.match_reasons,
        }


class HybridRetriever:
    """Multi-layer retrieval that combines metadata, keywords, and recency.

    Operates over any list of dicts with standard fields:
    id, title, content, tags, source_type, created_at/ingested_at.
    """

    def retrieve(
        self,
        query: str,
        items: list[dict],
        *,
        max_results: int = 10,
        source_type: str | None = None,
        tags: list[str] | None = None,
        project: str | None = None,
        recency_days: int | None = None,
    ) -> list[RetrievalResult]:
        """Run hybrid retrieval over a list of items.

        Layers:
        1. Metadata filter (source_type, tags, project)
        2. Keyword matching (query tokens vs title + content)
        3. Recency weighting (newer items score higher)
        """
        # Layer 1: Metadata filters
        filtered = self._filter_metadata(
            items,
            source_type=source_type,
            tags=tags,
            project=project,
            recency_days=recency_days,
        )

        if not filtered:
            return []

        # Layer 2: Keyword matching + scoring
        query_tokens = set(tokenize(query))
        if not query_tokens:
            # No query → just return by recency
            results = [
                RetrievalResult(
                    id=item.get("id", ""),
                    title=item.get("title", ""),
                    content=item.get("content", item.get("insight", "")),
                    source_type=item.get("source_type", ""),
                    tags=item.get("tags", []),
                    score=0.5,
                    match_reasons=["metadata_match"],
                )
                for item in filtered
            ]
            return self._recency_weight(results, filtered)[:max_results]

        results: list[RetrievalResult] = []
        for item in filtered:
            title = item.get("title", "")
            content = item.get("content", item.get("insight", ""))
            all_text = f"{title} {content} {' '.join(item.get('tags', []))}"
            item_tokens = set(tokenize(all_text))

            # Token overlap ratio
            overlap = query_tokens & item_tokens
            if not overlap:
                continue

            keyword_score = len(overlap) / max(len(query_tokens), 1)

            # Title match bonus (title matches are more precise)
            title_tokens = set(tokenize(title))
            title_overlap = query_tokens & title_tokens
            title_bonus = 0.2 if title_overlap else 0.0

            # Exact phrase bonus
            phrase_bonus = 0.15 if query.lower() in all_text.lower() else 0.0

            score = keyword_score + title_bonus + phrase_bonus
            reasons = [f"keyword_overlap({len(overlap)}/{len(query_tokens)})"]
            if title_bonus:
                reasons.append("title_match")
            if phrase_bonus:
                reasons.append("exact_phrase")

            results.append(
                RetrievalResult(
                    id=item.get("id", ""),
                    title=title,
                    content=content,
                    source_type=item.get("source_type", ""),
                    tags=item.get("tags", []),
                    score=min(score, 1.0),
                    match_reasons=reasons,
                )
            )

        # Layer 3: Recency weighting
        results = self._recency_weight(results, filtered)

        # Sort and limit
        results.sort(key=lambda r: r.score, reverse=True)
        return results[:max_results]

    def _filter_metadata(
        self,
        items: list[dict],
        *,
        source_type: str | None = None,
        tags: list[str] | None = None,
        project: str | None = None,
        recency_days: int | None = None,
    ) -> list[dict]:
        """Layer 1: filter by metadata."""
        filtered = items

        if source_type:
            filtered = [i for i in filtered if i.get("source_type") == source_type]

        if tags:
            tag_set = {t.lower() for t in tags}
            filtered = [i for i in filtered if tag_set & {t.lower() for t in i.get("tags", [])}]

        if project:
            project_lower = project.lower()
            filtered = [
                i
                for i in filtered
                if project_lower in i.get("related_project", "").lower()
                or project_lower in " ".join(i.get("tags", [])).lower()
            ]

        if recency_days is not None:
            cutoff = (datetime.now(UTC) - timedelta(days=recency_days)).isoformat()
            filtered = [i for i in filtered if i.get("created_at", i.get("ingested_at", "")) >= cutoff]

        return filtered

    def _recency_weight(
        self,
        results: list[RetrievalResult],
        source_items: list[dict],
    ) -> list[RetrievalResult]:
        """Layer 3: boost scores for recent items."""
        # Build a map of id → created_at from source items
        date_map: dict[str, str] = {}
        for item in source_items:
            item_id = item.get("id", "")
            created = item.get("created_at", item.get("ingested_at", ""))
            if item_id and created:
                date_map[item_id] = created

        now = datetime.now(UTC)

        for result in results:
            created_str = date_map.get(result.id, "")
            if not created_str:
                continue
            try:
                created = datetime.fromisoformat(created_str)
                age_days = (now - created).days
                # Items less than 7 days old get up to 0.15 boost
                if age_days <= 7:
                    recency_boost = 0.15 * (1 - age_days / 7)
                    result.score = min(result.score + recency_boost, 1.0)
                    result.match_reasons.append(f"recent({age_days}d)")
            except (ValueError, TypeError):
                pass

        return results
