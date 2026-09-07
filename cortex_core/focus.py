"""
Focus Recommendation Engine
-----------------------------
The killer feature of CortexOS. Takes scored articles, knowledge
notes, and user context to produce a ranked "What should I focus
on today?" brief. This is what separates CortexOS from every
generic AI summariser.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from cortex_core.knowledge import KnowledgeStore
from cortex_core.llm import LLMProvider
from cortex_core.memory import ContextMemory
from cortex_core.scoring import ArticleScore, evaluate_digest, tokenize


@dataclass
class FocusItem:
    """A single focus recommendation."""

    rank: int
    title: str
    why_it_matters: str
    next_action: str
    source_url: str = ""
    relevance_score: float = 0.0
    tags: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class DailyBrief:
    """The daily focus brief — CortexOS's primary output."""

    date: str = field(default_factory=lambda: datetime.now(UTC).strftime("%Y-%m-%d"))
    focus_items: list[FocusItem] = field(default_factory=list)
    digest_quality: dict | None = None
    profile_summary: dict | None = None

    def to_dict(self) -> dict:
        return {
            "date": self.date,
            "focus_items": [i.to_dict() for i in self.focus_items],
            "digest_quality": self.digest_quality,
            "profile_summary": self.profile_summary,
        }

    def to_markdown(self) -> str:
        """Render the brief as a readable Markdown document."""
        lines = [
            f"# CortexOS Daily Focus — {self.date}",
            "",
        ]
        if not self.focus_items:
            lines.append("_No focus items today. Run the pipeline or add articles._")
        else:
            for item in self.focus_items:
                lines.extend(
                    [
                        f"## {item.rank}. {item.title}",
                        "",
                        f"**Why it matters:** {item.why_it_matters}",
                        "",
                        f"**Next action:** {item.next_action}",
                        "",
                        f"_Relevance: {item.relevance_score:.2f}_",
                    ]
                )
                if item.source_url:
                    lines.append(f"[Source]({item.source_url})")
                if item.tags:
                    lines.append(f"Tags: {', '.join(item.tags)}")
                lines.append("")

        if self.digest_quality:
            lines.extend(
                [
                    "---",
                    "### Digest Quality",
                    f"- AI article ratio: {self.digest_quality.get('ai_article_ratio', 0):.1%}",
                    f"- High signal ratio: {self.digest_quality.get('high_signal_ratio', 0):.1%}",
                    f"- Project fit score: {self.digest_quality.get('project_fit_score', 0):.1%}",
                    "",
                ]
            )

        return "\n".join(lines)


class FocusEngine:
    """Produces daily focus briefs from scored content + user context."""

    def __init__(
        self,
        memory: ContextMemory,
        store: KnowledgeStore,
        llm: LLMProvider | None = None,
    ):
        self.memory = memory
        self.store = store
        self.llm = llm

    # ── Core recommendation ─────────────────────────────────────

    def generate_brief(
        self,
        digest_text: str | None = None,
        *,
        max_items: int = 5,
        use_llm: bool = False,
        scored_articles: list[ArticleScore] | None = None,
        insights: list[dict] | None = None,
        signals: list[dict] | None = None,
    ) -> DailyBrief:
        """Generate today's focus brief.

        When *scored_articles*, *insights*, and *signals* are supplied
        (e.g. by the pipeline), the engine skips redundant re-scoring
        and uses the full intelligence chain to produce richer items.
        """
        context_snippets = self.memory.get_context_snippets()

        brief = DailyBrief()
        brief.profile_summary = self.memory.summary()

        # Build signal and insight lookup tables for enrichment
        signal_topics = _build_signal_lookup(signals or [])
        insight_map = _build_insight_lookup(insights or [])

        # Use pre-computed scored articles if provided, else score digest
        if scored_articles is not None:
            # Filter to relevant unread articles
            articles = [a for a in scored_articles if a.composite >= 0.2 and not self.memory.already_read(a.title)]
            brief.digest_quality = {
                "total_articles": len(scored_articles),
                "ai_article_ratio": _ratio(scored_articles, lambda a: a.ai_related),
                "high_signal_ratio": _ratio(scored_articles, lambda a: a.high_signal),
                "project_fit_score": _ratio(scored_articles, lambda a: a.project_relevance > 0.3),
            }
        elif digest_text:
            digest_score = evaluate_digest(digest_text, context_snippets)
            brief.digest_quality = {
                "total_articles": digest_score.total_articles,
                "ai_article_ratio": digest_score.ai_article_ratio,
                "high_signal_ratio": digest_score.high_signal_ratio,
                "project_fit_score": digest_score.project_fit_score,
            }
            articles = [
                a for a in digest_score.articles if a.composite >= 0.2 and not self.memory.already_read(a.title)
            ]
        else:
            articles = []

        # Also pull recent unactioned knowledge notes
        recent_notes = self.store.notes[:10]

        # Build focus items from scored articles
        focus_items: list[FocusItem] = []

        for article in articles[:max_items]:
            if use_llm and self.llm:
                item = self._llm_focus_item(article)
            else:
                item = self._rule_focus_item(
                    article,
                    signal_topics=signal_topics,
                    insight_map=insight_map,
                )
            focus_items.append(item)

        # Fill remaining slots from knowledge notes
        remaining_slots = max_items - len(focus_items)
        for note in recent_notes[:remaining_slots]:
            if note.action and not any(f.title == note.title for f in focus_items):
                focus_items.append(
                    FocusItem(
                        rank=0,
                        title=note.title,
                        why_it_matters=note.implication or note.insight,
                        next_action=note.action,
                        relevance_score=0.5,
                        tags=note.tags,
                    )
                )

        # Assign final ranks
        for i, item in enumerate(focus_items[:max_items], 1):
            item.rank = i

        brief.focus_items = focus_items[:max_items]
        return brief

    # ── Focus item strategies ───────────────────────────────────

    @staticmethod
    def _rule_focus_item(
        article: ArticleScore,
        *,
        signal_topics: dict[str, dict] | None = None,
        insight_map: dict[str, dict] | None = None,
    ) -> FocusItem:
        """Create a focus item using rule-based logic, enriched by signals and insights."""
        title_lower = article.title.lower()
        title_tokens = tokenize(title_lower)

        # Check if this article matches a known signal
        matched_signal = _match_signal(title_tokens, signal_topics or {})

        # Check if there's a related insight
        matched_insight = insight_map.get(article.title) if insight_map else None

        # Build why_it_matters — prefer insight over signal over generic
        if matched_insight and matched_insight.get("why_it_matters"):
            why = matched_insight["why_it_matters"]
        elif matched_signal:
            sig = matched_signal
            why = (
                f"'{sig['topic']}' is a {sig['status']} signal "
                f"(appeared {sig['frequency']}x across sources). "
                f"{article.title} adds to this pattern."
            )
        elif article.project_relevance > 0.3:
            why = f"Directly relevant to active projects (project fit: {article.project_relevance:.0%})."
        elif article.ai_related:
            why = f"AI-relevant with actionability score {article.actionability:.0%}."
        elif article.high_signal:
            why = f"High-signal content (novelty: {article.novelty:.0%}, relevance: {article.composite:.0%})."
        else:
            why = f"Moderate relevance ({article.composite:.0%}). Worth a quick scan."

        # Build next_action — prefer insight over generic
        _default_action = "Review and decide if action is needed."
        if matched_insight and matched_insight.get("next_action") and matched_insight["next_action"] != _default_action:
            action = matched_insight["next_action"]
        elif matched_insight and matched_insight.get("architectural_implication"):
            action = f"Evaluate implication: {matched_insight['architectural_implication']}"
        elif article.actionability > 0.5:
            action = "Read in full — likely contains actionable patterns or tools."
        elif article.project_relevance > 0.3:
            action = "Extract key insight and link to relevant project notes."
        else:
            action = "Skim for applicable patterns; bookmark if relevant."

        # Merge tags from article + insight
        tags = _infer_tags(article)
        if matched_insight:
            for t in matched_insight.get("tags", []):
                if t not in tags:
                    tags.append(t)

        return FocusItem(
            rank=0,
            title=article.title,
            why_it_matters=why,
            next_action=action,
            source_url=article.url,
            relevance_score=article.composite,
            tags=tags,
        )

    def _llm_focus_item(self, article: ArticleScore) -> FocusItem:
        """Create a focus item using LLM analysis."""
        profile = self.memory.profile
        prompt = (
            f"You are CortexOS, a thinking engine for ambitious builders.\n"
            f"User goals: {', '.join(profile.goals)}\n"
            f"User interests: {', '.join(profile.interests)}\n"
            f"Current projects: {', '.join(profile.current_projects)}\n\n"
            f"Article: {article.title}\n"
            f"URL: {article.url}\n"
            f"AI relevance: {'Yes' if article.ai_related else 'No'}\n"
            f"Score: {article.composite:.2f}\n\n"
            f"Provide a JSON object with:\n"
            f"- why_it_matters (1-2 sentences, specific to user's goals)\n"
            f"- next_action (concrete actionable step)\n"
            f"- tags (list of 2-3 topic tags)\n"
        )
        resp = self.llm.generate(prompt)  # type: ignore[union-attr]
        try:
            data = json.loads(resp.text)
        except Exception:
            return self._rule_focus_item(article)

        return FocusItem(
            rank=0,
            title=article.title,
            why_it_matters=data.get("why_it_matters", ""),
            next_action=data.get("next_action", ""),
            source_url=article.url,
            relevance_score=article.composite,
            tags=data.get("tags", []),
        )

    # ── History integration ─────────────────────────────────────

    def mark_read(self, title: str, url: str = "", insight: str = "") -> None:
        """Record that the user has read/processed a focus item."""
        self.memory.record_read(title=title, url=url, insight=insight)

    # ── File-based workflow ─────────────────────────────────────

    def generate_from_file(
        self,
        digest_path: Path,
        *,
        max_items: int = 5,
        use_llm: bool = False,
        scored_articles: list[ArticleScore] | None = None,
        insights: list[dict] | None = None,
        signals: list[dict] | None = None,
    ) -> DailyBrief:
        """Load a digest file and generate the brief."""
        text = digest_path.read_text(encoding="utf-8")
        return self.generate_brief(
            text,
            max_items=max_items,
            use_llm=use_llm,
            scored_articles=scored_articles,
            insights=insights,
            signals=signals,
        )

    def generate_from_latest(
        self,
        directory: Path,
        *,
        max_items: int = 5,
        use_llm: bool = False,
        scored_articles: list[ArticleScore] | None = None,
        insights: list[dict] | None = None,
        signals: list[dict] | None = None,
    ) -> DailyBrief:
        """Find the latest digest and generate."""
        candidates = sorted(directory.glob("weekly_digest_*.md"))
        if not candidates:
            return self.generate_brief(
                max_items=max_items,
                use_llm=use_llm,
                scored_articles=scored_articles,
                insights=insights,
                signals=signals,
            )
        return self.generate_from_file(
            candidates[-1],
            max_items=max_items,
            use_llm=use_llm,
            scored_articles=scored_articles,
            insights=insights,
            signals=signals,
        )

    def save_brief(self, brief: DailyBrief, directory: Path) -> Path:
        """Save brief as both JSON and Markdown."""
        directory.mkdir(parents=True, exist_ok=True)
        json_path = directory / f"focus_{brief.date}.json"
        md_path = directory / f"focus_{brief.date}.md"

        with open(json_path, "w") as f:
            json.dump(brief.to_dict(), f, indent=2)
        with open(md_path, "w") as f:
            f.write(brief.to_markdown())

        return md_path


def _infer_tags(article: ArticleScore) -> list[str]:
    """Infer topic tags from article title keywords."""
    tags = []
    title_lower = article.title.lower()
    tag_map = {
        "ai": ["ai", "artificial", "llm", "gpt", "claude", "gemini"],
        "agents": ["agent", "agents", "agentic"],
        "retrieval": ["retrieval", "rag", "context", "vector", "search"],
        "infrastructure": ["infrastructure", "chip", "supply", "helium"],
        "robotics": ["robot", "robotics"],
        "safety": ["safety", "psychosis", "ethics", "risk"],
        "developer-tools": ["developer", "docker", "github", "tool"],
        "productivity": ["productivity", "focus", "learning"],
    }
    for tag, keywords in tag_map.items():
        if any(kw in title_lower for kw in keywords):
            tags.append(tag)
    return tags or ["general"]


# ── Enrichment helpers (module-private) ─────────────────────


def _build_signal_lookup(signals: list[dict]) -> dict[str, dict]:
    """Index signals by topic for fast matching."""
    return {s["topic"]: s for s in signals if s.get("topic")}


def _build_insight_lookup(insights: list[dict]) -> dict[str, dict]:
    """Index insights by title for matching against articles."""
    return {i["title"]: i for i in insights if i.get("title")}


def _match_signal(
    title_tokens: set[str] | list[str],
    signal_topics: dict[str, dict],
) -> dict | None:
    """Return the best matching signal for a set of title tokens, or None."""
    best: dict | None = None
    best_overlap = 0
    tokens = set(title_tokens)
    for topic, sig in signal_topics.items():
        topic_tokens = set(tokenize(topic))
        overlap = len(tokens & topic_tokens)
        if overlap > 0 and overlap > best_overlap:
            best = sig
            best_overlap = overlap
    return best


def _ratio(articles: list[ArticleScore], pred) -> float:
    """Compute the ratio of articles satisfying *pred*."""
    if not articles:
        return 0.0
    return sum(1 for a in articles if pred(a)) / len(articles)
