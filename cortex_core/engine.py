"""
CortexOS Engine
----------------
Top-level orchestrator that ties knowledge, digest processing,
post generation, scoring, context memory (4 layers), focus
recommendations, decision engine, signal detection, insights,
retrieval, and pipeline execution together.

Primary feature: "What should I focus on today?"
The real answer: "Here's what matters, why, and your next step."
"""

from __future__ import annotations

import importlib.util
import logging
import sys
from collections import Counter
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from cortex_core.config import CortexConfig
from cortex_core.decisions import DecisionEngine
from cortex_core.digest import DigestProcessor
from cortex_core.focus import FocusEngine
from cortex_core.insights import InsightStore, generate_insight_from_note
from cortex_core.integrations import IntegrationService, export_decisions_markdown
from cortex_core.items import ItemStore, extract_items_from_digest, extract_items_from_summary
from cortex_core.knowledge import KnowledgeNote, KnowledgeStore
from cortex_core.llm import LLMProvider
from cortex_core.memory import ContextMemory
from cortex_core.pipeline import Pipeline
from cortex_core.posts import PostGenerator
from cortex_core.retrieve import HybridRetriever
from cortex_core.scoring import evaluate_digest
from cortex_core.signal_matching import SignalMatcher
from cortex_core.signals import SignalStore, detect_signals
from cortex_core.why_engine import EvaluationContext, SourceItem, WhyEngine


class CortexEngine:
    """Facade for all CortexOS operations."""

    def __init__(self, config: CortexConfig | None = None):
        self.config = config or CortexConfig.load()
        self.config.data_dir.mkdir(parents=True, exist_ok=True)

        # Core components
        self.llm = LLMProvider(self.config.llm)
        self.store = KnowledgeStore(self.config.knowledge_path)
        self.digest = DigestProcessor(self.store, self.llm)
        self.posts = PostGenerator(self.store, self.llm)

        # Context & intelligence layer
        self.memory = ContextMemory(self.config.data_dir)
        self.focus = FocusEngine(self.memory, self.store, self.llm)

        # New subsystems
        self.items = ItemStore(self.config.data_dir / "items.json")
        self.insights = InsightStore(self.config.data_dir / "insights.json")
        self.signal_store = SignalStore(self.config.data_dir / "signals.json")
        self.signal_matcher = SignalMatcher(self.config.data_dir)
        self.decision_engine = DecisionEngine(self.config.data_dir)
        self.retriever = HybridRetriever()
        self.why_engine = WhyEngine()
        self.integration_service = IntegrationService(self.config.data_dir)

    # ------------------------------------------------------ knowledge CRUD

    def list_notes(self, *, include_archived: bool = False) -> list[dict]:
        notes = self.store.all_notes if include_archived else self.store.notes
        return [n.to_dict() for n in notes]

    def get_note(self, note_id: str) -> dict | None:
        note = self.store.get(note_id)
        return note.to_dict() if note else None

    def add_note(self, **fields) -> dict:
        note = KnowledgeNote(**{k: v for k, v in fields.items() if k in KnowledgeNote.__dataclass_fields__})
        saved = self.store.add(note)
        signal_text = " ".join(
            part for part in (saved.title, saved.insight, saved.implication, saved.action) if str(part).strip()
        ).strip()
        if signal_text:
            active_project = self.memory.profile.current_projects[0] if self.memory.profile.current_projects else ""
            self.signal_matcher.ingest(
                text=signal_text,
                source="note",
                source_id=saved.id,
                project=active_project,
                tags=saved.tags,
            )
        return saved.to_dict()

    def update_note(self, note_id: str, **fields) -> dict | None:
        note = self.store.update(note_id, **fields)
        return note.to_dict() if note else None

    def delete_note(self, note_id: str) -> bool:
        return self.store.delete(note_id)

    def search_notes(self, query: str) -> list[dict]:
        return [n.to_dict() for n in self.store.search(query)]

    # ------------------------------------------------------ digest workflow

    def process_digest(self, path: str | None = None, *, use_llm: bool = False) -> list[dict]:
        if path:
            notes = self.digest.process_file(Path(path), use_llm=use_llm)
        else:
            notes = self.digest.process_latest(self.config.data_dir, use_llm=use_llm)
        return [n.to_dict() for n in notes]

    # ------------------------------------------------------- post generation

    def generate_posts(
        self,
        *,
        limit: int = 3,
        platform: str = "general",
        use_llm: bool = False,
    ) -> list[dict]:
        posts = self.posts.generate(limit=limit, platform=platform, use_llm=use_llm)
        return [{"text": p.text, "platform": p.platform, "note_id": p.source_note_id} for p in posts]

    def export_posts(self, *, limit: int = 3, platform: str = "general") -> str:
        posts = self.posts.generate(limit=limit, platform=platform)
        out_path = self.config.posts_path
        self.posts.export(posts, out_path)
        return str(out_path)

    # -------------------------------------------------------- full pipeline

    def build_pipeline(self, *, use_llm: bool = False) -> Pipeline:
        """Create the standard CortexOS pipeline."""
        pipe = Pipeline("CortexOS Daily Pipeline")

        pipe.add_step("Ingest items", lambda: self.ingest_digest())
        pipe.add_step("Process digest", lambda: self.process_digest(use_llm=use_llm))
        pipe.add_step("Evaluate digest", lambda: self.evaluate_digest())
        pipe.add_step("Detect signals", lambda: self.detect_signals())
        pipe.add_step("Generate insights", lambda: self.generate_insights())
        pipe.add_step("Generate focus brief", lambda: self.generate_focus_brief(use_llm=use_llm))
        pipe.add_step("Generate decision brief", lambda: self.generate_decision_brief())
        pipe.add_step("Generate posts", lambda: self.generate_posts(use_llm=use_llm))
        pipe.add_step("Export posts", lambda: self.export_posts())

        return pipe

    def run_pipeline(self, *, use_llm: bool = False) -> dict:
        """Build and execute the full pipeline, returning results."""
        pipe = self.build_pipeline(use_llm=use_llm)
        result = pipe.run()
        return result.to_dict()

    # -------------------------------------------------------- status / info

    def status(self) -> dict:
        return {
            "version": "0.2.0",
            "data_dir": str(self.config.data_dir),
            "notes_count": self.store.count,
            "items_count": self.items.count,
            "insights_count": self.insights.count,
            "signals_count": self.signal_store.count,
            "signal_events_count": len(self.signal_matcher.list_signals(limit=1000)),
            "decisions_count": len(self.decision_engine.all_decisions),
            "llm_provider": self.config.llm.provider,
            "llm_model": self.config.llm.model,
            "cocoindex": self.signal_matcher.cocoindex_stats(),
            "profile_loaded": self.memory.profile.name != "",
            "memory_layers": {
                "identity": True,
                "projects": len(self.memory.projects),
                "research_themes": len(self.memory.research.recurring_themes),
                "working_priorities": len(self.memory.working.todays_priorities),
            },
        }

    # -------------------------------------------------------- focus / daily brief

    def generate_focus_brief(
        self,
        digest_path: str | None = None,
        *,
        use_llm: bool = False,
    ) -> dict:
        """Generate today's focus recommendations.

        Passes pre-computed scored articles, insights, and signals into
        the FocusEngine so the brief reflects the full intelligence chain
        instead of re-deriving everything from scratch.
        """
        # Gather pre-computed enrichment data
        scored = self._latest_scored_articles() or []
        insights_data = [i.to_dict() for i in self.insights.recent(20)]
        signals_data = [s.to_dict() for s in self.signal_store.active_signals()]

        kwargs = dict(
            use_llm=use_llm,
            scored_articles=scored if scored else None,
            insights=insights_data if insights_data else None,
            signals=signals_data if signals_data else None,
        )

        if digest_path:
            brief = self.focus.generate_from_file(Path(digest_path), **kwargs)
        else:
            brief = self.focus.generate_from_latest(self.config.data_dir, **kwargs)
        self.focus.save_brief(brief, self.config.data_dir)
        return brief.to_dict()

    def get_latest_brief(self) -> dict | None:
        """Return the most recent saved focus brief, if any."""
        briefs = sorted(self.config.data_dir.glob("focus_*.json"), reverse=True)
        if not briefs:
            return None
        import json

        with open(briefs[0]) as f:
            return json.load(f)

    # -------------------------------------------------------- profile / memory

    def get_profile(self) -> dict:
        p = self.memory.profile
        return {
            "name": p.name,
            "role": p.role,
            "preferred_style": p.preferred_style,
            "goals": p.goals,
            "interests": p.interests,
            "current_projects": p.current_projects,
            "constraints": p.constraints,
            "ignored_topics": p.ignored_topics,
        }

    def update_profile(self, **fields: Any) -> dict:
        p = self.memory.profile
        for key, val in fields.items():
            if hasattr(p, key):
                setattr(p, key, val)
        self.memory.save()
        return self.get_profile()

    # -------------------------------------------------------- digest evaluation

    def evaluate_digest(
        self,
        path: str | None = None,
        context: list[str] | None = None,
    ) -> dict:
        """Score a digest file for quality and relevance."""
        if path:
            with open(path) as f:
                content = f.read()
        else:
            files = sorted(self.config.data_dir.glob(self.config.digest_glob))
            if not files:
                paths = sorted(Path(".").glob("weekly_digest_*.md"))
                if not paths:
                    return {"error": "No digest file found"}
                content = paths[-1].read_text()
            else:
                content = files[-1].read_text()

        ctx = context or self.memory.get_context_snippets()
        score = evaluate_digest(
            content,
            ctx,
            seen_titles={e.title.lower().strip() for e in self.memory.history},
            ignored_topics=self.memory.profile.ignored_set(),
            goal_tokens=self.memory.profile.goal_tokens(),
        )
        return {
            "total_articles": score.total_articles,
            "ai_article_ratio": round(score.ai_article_ratio, 3),
            "high_signal_ratio": round(score.high_signal_ratio, 3),
            "signal_to_noise_ratio": round(score.signal_to_noise_ratio, 3),
            "context_keyword_coverage": round(score.context_keyword_coverage, 3),
            "project_fit_score": round(score.project_fit_score, 3),
            "top_articles": [{"title": a.title, "score": round(a.composite, 3)} for a in score.articles[:5]],
        }

    # -------------------------------------------------------- spaced repetition

    def due_for_review(self) -> list[dict]:
        """Return reading entries due for spaced-repetition review."""
        entries = self.memory.due_for_review()
        return [e.to_dict() for e in entries]

    def advance_review(self, title: str) -> dict | None:
        """Mark an entry as reviewed and advance to the next interval."""
        entry = self.memory.advance_review(title)
        return entry.to_dict() if entry else None

    # ============================================================
    # NEW: Item ingestion
    # ============================================================

    def ingest_digest(self, path: str | None = None) -> list[dict]:
        """Ingest a digest file into structured Items (raw data preservation)."""
        if path:
            text = Path(path).read_text(encoding="utf-8")
        else:
            files = sorted(self.config.data_dir.glob(self.config.digest_glob))
            if not files:
                paths = sorted(Path(".").glob("weekly_digest_*.md"))
                if not paths:
                    return []
                text = paths[-1].read_text(encoding="utf-8")
            else:
                text = files[-1].read_text(encoding="utf-8")

        raw_items = extract_items_from_digest(text)
        added = self.items.add_batch(raw_items)
        return [i.to_dict() for i in added]

    # ============================================================
    # Summary ingestion (user-authored content)
    # ============================================================

    def ingest_summary(
        self,
        text: str,
        *,
        source: str = "",
        tags: list[str] | None = None,
        create_notes: bool = True,
    ) -> dict:
        """Ingest a user-written markdown summary.

        1. Parses into Items (raw preservation)
        2. Optionally creates KnowledgeNotes for each section
        3. Returns count of items and notes created

        This is how personal analysis and summaries become
        ranked SimpliXio signals.
        """
        raw_items = extract_items_from_summary(text, source=source, tags=tags)
        added_items = self.items.add_batch(raw_items)

        notes_created: list[dict] = []
        if create_notes:
            for item in added_items:
                note = KnowledgeNote(
                    title=item.title,
                    insight=item.content,
                    implication="",
                    action="",
                    source_url=item.url,
                    tags=item.tags,
                )
                saved = self.store.add(note)
                notes_created.append(saved.to_dict())

        return {
            "items_ingested": len(added_items),
            "notes_created": len(notes_created),
            "items": [i.to_dict() for i in added_items],
            "notes": notes_created,
        }

    # ============================================================
    # NEW: Signal detection
    # ============================================================

    def detect_signals(self) -> list[dict]:
        """Detect emerging signals from all ingested items."""
        all_items = self.items.recent(200)
        titles = [i.title for i in all_items]
        urls = [i.url for i in all_items]
        new_signals = detect_signals(titles, urls=urls, min_frequency=2)
        updated = self.signal_store.update_signals(new_signals)

        # Feed confirmed signals into research memory
        for sig in self.signal_store.confirmed_signals():
            self.memory.add_research_theme(sig.topic)

        return [s.to_dict() for s in updated]

    def get_signals(self) -> list[dict]:
        """Return current active signals."""
        return [s.to_dict() for s in self.signal_store.active_signals()]

    # ============================================================
    # NEW: Insight generation
    # ============================================================

    def generate_insights(self) -> list[dict]:
        """Generate structured Insights from recent knowledge notes."""
        recent_notes = self.store.notes[-20:]
        new_insights = []
        existing_titles = {i.title for i in self.insights.insights}

        for note in recent_notes:
            if note.title in existing_titles:
                continue
            insight = generate_insight_from_note(
                title=note.title,
                insight_text=note.insight,
                implication=note.implication,
                action=note.action,
                tags=note.tags,
                source_item_id=note.id,
                project=self.memory.profile.current_projects[0] if self.memory.profile.current_projects else "",
            )
            new_insights.append(insight)

        if new_insights:
            self.insights.add_batch(new_insights)

        return [i.to_dict() for i in new_insights]

    def get_insights(self, *, limit: int = 20) -> list[dict]:
        """Return recent insights."""
        return [i.to_dict() for i in self.insights.recent(limit)]

    # ============================================================
    # NEW: Decision engine
    # ============================================================

    def generate_decision_brief(self) -> dict:
        """Generate today's decision brief from all available context."""
        # Gather scored items
        scored = [a.to_dict() for a in self._latest_scored_articles()]

        # Gather insights
        insights_data = [i.to_dict() for i in self.insights.recent(10)]

        # Gather signals
        signals_data = [s.to_dict() for s in self.signal_store.active_signals()]

        # Previous brief for change detection
        prev = self.decision_engine.get_previous_brief()

        brief = self.decision_engine.generate_brief(
            scored_items=scored,
            insights=insights_data,
            signals=signals_data,
            profile=self.memory.profile.to_dict(),
            previous_brief=prev,
            feedback_notes=self.memory.working.temporary_notes,
        )

        # Update working memory with today's priorities
        self.memory.set_today_priorities([p.title for p in brief.priorities])

        self.decision_engine.save_brief(brief)
        return brief.to_dict()

    def record_decision(
        self,
        decision: str,
        reason: str,
        *,
        project: str = "",
        assumptions: list[str] | None = None,
    ) -> dict:
        """Record a decision with context."""
        dec = self.decision_engine.record_decision(
            decision=decision,
            reason=reason,
            project=project,
            assumptions=assumptions,
        )
        # Also add to project memory if project specified
        if project:
            self.memory.add_project_decision(project, decision)
        signal_text = " ".join(part for part in (decision, reason, " ".join(assumptions or [])) if part).strip()
        if signal_text:
            self.signal_matcher.ingest(
                text=signal_text,
                source="decision",
                source_id=dec.id,
                project=project,
                tags=["decision"],
                signal_type_hint="decision",
            )
        return dec.to_dict()

    def record_outcome(self, decision_id: str, outcome: str, impact_score: float = 0.0) -> dict | None:
        """Record the outcome of a past decision (feedback loop)."""
        dec = self.decision_engine.record_outcome(decision_id, outcome, impact_score)
        return dec.to_dict() if dec else None

    def record_feedback(self, *, item: str, useful: bool, acted: bool | None = None) -> None:
        """Record user feedback on a focus item (was this useful?).

        Stores in working memory so the next priority brief can
        incorporate what the user found valuable or not.
        """
        cleaned = item.strip()
        if not cleaned:
            return

        notes = self.memory.working.temporary_notes
        notes.append(f"[{'useful' if useful else 'not_useful'}] {cleaned}")
        if acted is not None:
            notes.append(f"[{'acted' if acted else 'not_acted'}] {cleaned}")

        # Keep only recent notes so working memory stays fast and relevant.
        if len(notes) > 200:
            self.memory.working.temporary_notes = notes[-200:]

        self.memory.save()

        signal_id = self.signal_matcher.find_best_signal_id(cleaned)
        if signal_id:
            self.signal_matcher.apply_feedback(
                signal_id=signal_id,
                action_type="acted_on" if useful and acted else ("ignored" if not useful else "reopened"),
                note=f"useful={useful},acted={acted}",
            )

    def get_decisions(self, *, project: str | None = None, limit: int = 10) -> list[dict]:
        """Get recent decisions, optionally filtered by project."""
        if project:
            decisions = self.decision_engine.decisions_by_project(project)
        else:
            decisions = self.decision_engine.recent_decisions(limit)
        return [d.to_dict() for d in decisions]

    # ============================================================
    # NEW: Hybrid retrieval
    # ============================================================

    def retrieve(
        self,
        query: str,
        *,
        source_type: str | None = None,
        tags: list[str] | None = None,
        max_results: int = 10,
    ) -> list[dict]:
        """Search across knowledge, insights, and items."""
        # Build a unified item pool
        pool: list[dict] = []

        for note in self.store.notes:
            d = note.to_dict()
            d["source_type"] = "note"
            pool.append(d)

        for insight in self.insights.insights:
            d = insight.to_dict()
            d["source_type"] = "insight"
            d["content"] = insight.summary
            pool.append(d)

        for item in self.items.recent(100):
            pool.append(item.to_dict())

        results = self.retriever.retrieve(query, pool, max_results=max_results, source_type=source_type, tags=tags)
        return [r.to_dict() for r in results]

    # ============================================================
    # NEW: Agent Context API
    # ============================================================

    def get_active_goals(self) -> list[str]:
        return self.memory.profile.goals

    def get_project_context(self, project_name: str) -> dict:
        """Return full project context for agents."""
        pm = self.memory.get_project(project_name)
        notes = self.store.search(project_name)
        decisions = self.decision_engine.decisions_by_project(project_name)
        return {
            "project": pm.to_dict(),
            "notes_count": len(notes),
            "recent_decisions": [d.to_dict() for d in decisions[:5]],
        }

    def get_recent_decisions(self, limit: int = 5) -> list[dict]:
        return [d.to_dict() for d in self.decision_engine.recent_decisions(limit)]

    def get_priority_brief(self) -> dict | None:
        """Return today's decision brief for agents."""
        return self.decision_engine.get_previous_brief()

    def store_new_insight(self, **fields) -> dict:
        """Allow agents to store new insights."""
        from cortex_core.insights import Insight

        insight = Insight(**{k: v for k, v in fields.items() if k in Insight.__dataclass_fields__})
        self.insights.add(insight)
        return insight.to_dict()

    def get_full_context(self) -> dict:
        """Return complete memory state for agent consumption."""
        return self.memory.full_context()

    # ── Signal matching (backend-first ranking core) ──────────────────────

    def capture_signal(
        self,
        *,
        text: str,
        source: str = "capture",
        source_id: str = "",
        context: str = "",
        project: str = "",
        tags: list[str] | None = None,
        signal_type_hint: str = "",
    ) -> dict | None:
        """Capture one raw signal for deterministic normalization and ranking."""
        return self.signal_matcher.ingest(
            text=text,
            source=source,
            source_id=source_id,
            context=context,
            project=project,
            tags=tags or [],
            signal_type_hint=signal_type_hint,
        )

    def list_captured_signals(self, *, limit: int = 200) -> list[dict]:
        return self.signal_matcher.list_signals(limit=limit)

    def feedback_signal(self, *, signal_id: str, action_type: str, note: str = "") -> dict | None:
        return self.signal_matcher.apply_feedback(signal_id=signal_id, action_type=action_type, note=note)

    def override_signal(
        self,
        *,
        signal_id: str,
        override_type: str,
        note: str = "",
        expires_at: str = "",
    ) -> dict | None:
        return self.signal_matcher.apply_override(
            signal_id=signal_id,
            override_type=override_type,
            note=note,
            expires_at=expires_at,
        )

    def build_signal_matching_output(self) -> dict:
        return self.signal_matcher.build_ranked_output()

    # ── Sync ────────────────────────────────────────────────────

    def build_sync_snapshot(self) -> dict:
        """Single-call snapshot of everything Apple clients need.

        Bundles profile, active project, priorities, decisions,
        insights, signals, and working memory into one dict.
        Backend is source of truth — clients pull this on launch.
        """
        profile = self.memory.profile

        # Active project context (first project, if any)
        active_project: dict | None = None
        if profile.current_projects:
            pm = self.memory.get_project(profile.current_projects[0])
            active_project = pm.to_dict()

        # Priority brief (may not exist yet)
        signal_matching = self.build_signal_matching_output()
        priorities = self.decision_engine.get_previous_brief()
        weekly_review = self.build_weekly_review_output(signal_matching=signal_matching)
        decision_replay = self.build_decision_replay_output()
        newsletter = self.build_newsletter_output()
        today_output = self.build_today_output()

        return {
            "profile": {
                "name": profile.name,
                "role": profile.role,
                "goals": profile.goals,
                "interests": profile.interests,
                "current_projects": profile.current_projects,
                "ignored_topics": profile.ignored_topics,
            },
            "active_project": active_project,
            "priorities": priorities,
            "recent_decisions": self.get_recent_decisions(10),
            "insights": self.get_insights(limit=10),
            "signals": self.get_signals(),
            "working_memory": self.memory.working.to_dict(),
            "today": today_output,
            "weekly_review": weekly_review,
            "decision_replay": decision_replay,
            "newsletter": newsletter,
            "what_matters_now": signal_matching.get("what_matters_now", []),
            "signal_top_priorities": signal_matching.get("top_priorities", []),
            "decision_queue": signal_matching.get("decision_queue", []),
            "action_ready_queue": signal_matching.get("action_ready_queue", []),
            "recurring_patterns": signal_matching.get("recurring_patterns", []),
            "unresolved_tensions": signal_matching.get("unresolved_tensions", []),
            "content_candidates": signal_matching.get("content_candidates", []),
            "resurfaced_now": signal_matching.get("resurfaced_now", []),
            "resurfacing_recurring_tensions": signal_matching.get("resurfacing_recurring_tensions", []),
            "resurfacing_weekly_review_candidates": signal_matching.get("resurfacing_weekly_review_candidates", []),
            "resurfacing_content_candidates": signal_matching.get("resurfacing_content_candidates", []),
            "signal_graph": signal_matching.get("signal_graph", {}),
            "signal_matching_counts": signal_matching.get("counts", {}),
            "synced_at": datetime.now(UTC).isoformat(),
        }

    def build_today_output(self) -> dict:
        """Canonical, shareable daily output from backend source-of-truth."""
        brief = self.decision_engine.get_previous_brief()
        if brief is None:
            # Generate lazily so first sync still has usable output.
            brief = self.generate_decision_brief()

        ranked = self.build_signal_matching_output()
        ranked_priorities = ranked.get("top_priorities", [])
        compact: list[dict[str, Any]] = []
        if isinstance(ranked_priorities, list) and ranked_priorities:
            compact = [
                {
                    "rank": idx + 1,
                    "title": str(item.get("title", "")).strip(),
                    "why": str(item.get("why", "")).strip(),
                    "action": str(item.get("action", "")).strip(),
                }
                for idx, item in enumerate(ranked_priorities[:3])
                if str(item.get("title", "")).strip()
            ]

        if not compact:
            priorities = brief.get("priorities", [])[:3]
            compact = [
                {
                    "rank": int(item.get("rank", idx + 1)),
                    "title": str(item.get("title", "")).strip(),
                    "why": str(item.get("why_it_matters", "")).strip(),
                    "action": str(item.get("next_step", "")).strip(),
                }
                for idx, item in enumerate(priorities)
                if str(item.get("title", "")).strip()
            ]

        ignored = [str(item).strip() for item in brief.get("ignored", []) if str(item).strip()][:5]
        lines = [f"SimpliXio Today — {brief.get('date', datetime.now(UTC).strftime('%Y-%m-%d'))}", ""]
        for item in compact:
            lines.extend(
                [
                    f"{item['rank']}. {item['title']}",
                    f"Why: {item['why'] or 'High decision impact.'}",
                    f"Do: {item['action'] or 'Take the next concrete step.'}",
                    "",
                ]
            )
        if ignored:
            lines.append("Ignored signals:")
            lines.extend(f"- {item}" for item in ignored)

        return {
            "date": brief.get("date", datetime.now(UTC).strftime("%Y-%m-%d")),
            "priorities": compact,
            "ignored_signals": ignored,
            "changes_since_yesterday": brief.get("changes_since_yesterday", []),
            "share_text": "\n".join(lines).strip(),
            "generated_at": datetime.now(UTC).isoformat(),
        }

    def build_weekly_review_output(self, signal_matching: dict | None = None) -> dict | None:
        """Return a compact weekly review from recent decision brief artifacts.

        Source of truth: backend decision artifacts (decision_*.json).
        Returns None when no usable artifacts exist.
        """
        briefs_by_date: dict[str, dict] = {}
        for path in sorted(self.config.data_dir.glob("decision_*.json")):
            try:
                import json

                with open(path) as f:
                    payload = json.load(f)
            except Exception:
                logging.getLogger(__name__).warning("Skipping an unreadable decision artifact")
                continue

            if not isinstance(payload, dict):
                continue

            date_value = str(payload.get("date", "")).strip()
            if not date_value:
                continue
            try:
                datetime.strptime(date_value, "%Y-%m-%d")
            except ValueError:
                continue
            briefs_by_date[date_value] = payload

        if not briefs_by_date:
            return None

        ordered_dates = sorted(briefs_by_date.keys())
        latest_date = datetime.strptime(ordered_dates[-1], "%Y-%m-%d").date()
        start_date = latest_date - timedelta(days=6)

        selected: list[dict] = []
        for day in ordered_dates:
            day_date = datetime.strptime(day, "%Y-%m-%d").date()
            if start_date <= day_date <= latest_date:
                selected.append(briefs_by_date[day])

        if not selected:
            return None

        priority_counter: Counter[str] = Counter()
        signal_counter: Counter[str] = Counter()
        total_ignored_signals = 0

        for brief in selected:
            priorities = brief.get("priorities", [])
            if isinstance(priorities, list):
                for item in priorities:
                    if not isinstance(item, dict):
                        continue
                    title = str(item.get("title", "")).strip()
                    if title:
                        priority_counter[title] += 1

            signals = brief.get("emerging_signals", [])
            if isinstance(signals, list):
                for signal in signals:
                    value = str(signal).strip()
                    if value:
                        signal_counter[value] += 1

            ignored = brief.get("ignored", [])
            if isinstance(ignored, list):
                total_ignored_signals += len([item for item in ignored if str(item).strip()])

        top_priorities = [{"title": title, "count": count} for title, count in priority_counter.most_common(5)]
        top_signals = [{"title": title, "count": count} for title, count in signal_counter.most_common(5)]

        week_start = selected[0].get("date", ordered_dates[-1])
        week_end = selected[-1].get("date", ordered_dates[-1])
        days_covered = len(selected)
        confidence = round(days_covered / 7.0, 2)
        quality = "insufficient_history" if days_covered < 4 else "sufficient_history"

        summary_parts = [
            f"Reviewed {days_covered} day(s) of SimpliXio decisions.",
            f"Ignored {total_ignored_signals} low-signal item(s).",
        ]
        if top_priorities:
            top = top_priorities[0]
            summary_parts.append(f"Top repeated priority: '{top['title']}' ({top['count']}x).")
        if top_signals:
            top = top_signals[0]
            summary_parts.append(f"Top repeated signal: '{top['title']}' ({top['count']}x).")

        recommendations: list[str] = []
        if top_priorities:
            recommendations.append(
                f"Decide whether '{top_priorities[0]['title']}' should become a committed initiative."
            )
        if top_signals:
            recommendations.append(f"Investigate recurring signal '{top_signals[0]['title']}' for roadmap impact.")
        if total_ignored_signals > 0:
            recommendations.append("Keep filtering weak signals early to preserve decision clarity.")
        if not recommendations:
            recommendations.append("Collect more daily outputs before changing prioritisation strategy.")

        surfaced = signal_matching or self.build_signal_matching_output()
        resurfaced = surfaced.get("resurfaced_now", [])
        recurring_tensions = surfaced.get("resurfacing_recurring_tensions", [])
        weekly_candidates = surfaced.get("resurfacing_weekly_review_candidates", [])

        return {
            "week_start": week_start,
            "week_end": week_end,
            "period_label": f"{week_start} to {week_end}",
            "days_covered": days_covered,
            "quality": quality,
            "confidence": confidence,
            "top_priorities": top_priorities,
            "top_signals": top_signals,
            "total_ignored_signals": total_ignored_signals,
            "summary": " ".join(summary_parts),
            "recommendations": recommendations,
            "resurfaced_thoughts": resurfaced[:5],
            "resurfacing_recurring_tensions": recurring_tensions[:5],
            "ignored_but_important_items": [
                item
                for item in weekly_candidates
                if str(item.get("resurfacing_reason", "")).strip() == "ignored_but_important"
            ][:5],
            "resurfaced_content_candidates": surfaced.get("resurfacing_content_candidates", [])[:5],
            "generated_at": datetime.now(UTC).isoformat(),
        }

    def build_decision_replay_output(self) -> dict | None:
        """Return a compact replay of how today's decision was formed.

        Source of truth: latest backend decision brief artifact.
        Returns None when no usable artifact exists.
        """
        brief = self.decision_engine.get_previous_brief()
        if not isinstance(brief, dict):
            return None

        date_value = str(brief.get("date", "")).strip()
        priorities_raw = brief.get("priorities", [])
        ignored_raw = brief.get("ignored", [])
        signals_raw = brief.get("emerging_signals", [])

        priorities: list[dict[str, str]] = []
        if isinstance(priorities_raw, list):
            for item in priorities_raw:
                if not isinstance(item, dict):
                    continue
                title = str(item.get("title", "")).strip()
                if not title:
                    continue
                priorities.append(
                    {
                        "title": title,
                        "why": str(item.get("why_it_matters", "")).strip(),
                        "action": str(item.get("next_step", "")).strip(),
                    }
                )
        priorities = priorities[:3]

        kept_signals: list[dict[str, str]] = []
        if isinstance(signals_raw, list):
            for signal in signals_raw:
                title = str(signal).strip()
                if title:
                    kept_signals.append(
                        {
                            "title": title,
                            "reason": "Connected to current goals or repeated in recent context.",
                        }
                    )

        # Safe fallback when explicit kept signals are missing.
        if not kept_signals and priorities:
            for item in priorities:
                kept_signals.append(
                    {
                        "title": item["title"],
                        "reason": "Selected as a final priority with concrete next action.",
                    }
                )
        kept_signals = kept_signals[:5]

        ignored_signals: list[dict[str, str]] = []
        if isinstance(ignored_raw, list):
            for signal in ignored_raw:
                title = str(signal).strip()
                if title:
                    ignored_signals.append(
                        {
                            "title": title,
                            "reason": "Not connected strongly enough to current priorities.",
                        }
                    )
        ignored_signals = ignored_signals[:5]

        signals_kept = len(kept_signals)
        signals_ignored = len(ignored_signals)
        signals_reviewed = signals_kept + signals_ignored

        if signals_reviewed == 0 and not priorities:
            return None

        replay_date = date_value or datetime.now(UTC).strftime("%Y-%m-%d")
        summary = (
            f"SimpliXio reduced {signals_reviewed} inputs into {len(priorities)} priorities."
            if signals_reviewed > 0
            else f"SimpliXio produced {len(priorities)} priorities from available context."
        )

        return {
            "date": replay_date,
            "signals_reviewed": signals_reviewed,
            "signals_kept": signals_kept,
            "signals_ignored": signals_ignored,
            "kept_signals": kept_signals,
            "ignored_signals": ignored_signals,
            "final_priorities": priorities,
            "summary": summary,
            "generated_at": datetime.now(UTC).isoformat(),
        }

    def build_newsletter_output(self) -> dict | None:
        """Return latest newsletter draft summary when available.

        Source of truth: automation output artifact at
        cortexos_automation_scripts/output/newsletters/latest.json.
        """
        latest_path = (
            Path(__file__).resolve().parents[1]
            / "cortexos_automation_scripts"
            / "output"
            / "newsletters"
            / "latest.json"
        )
        if not latest_path.exists():
            return None

        try:
            import json

            payload = json.loads(latest_path.read_text(encoding="utf-8"))
        except Exception:
            return None
        if not isinstance(payload, dict):
            return None

        outputs = payload.get("outputs", {})
        markdown_path = ""
        if isinstance(outputs, dict):
            markdown_path = str(outputs.get("markdown", "")).strip()

        title = ""
        subtitle = ""
        preview = ""
        if markdown_path:
            try:
                md_lines = Path(markdown_path).read_text(encoding="utf-8").splitlines()
            except Exception:
                md_lines = []
            for raw_line in md_lines:
                line = raw_line.strip()
                if not line:
                    continue
                if not title and line.startswith("# "):
                    title = line[2:].strip()
                    continue
                if title and not subtitle:
                    subtitle = line
                    continue
                if title and subtitle and not preview and not line.startswith("## "):
                    preview = line
                    break

        safety_report = payload.get("safety_report", {})
        classification_summary = payload.get("classification_summary", {})
        taste_gate = payload.get("taste_gate", {})

        return {
            "status": str(payload.get("status", "")).strip(),
            "mode": str(payload.get("mode", "")).strip(),
            "period_start": str(payload.get("period_start", "")).strip(),
            "period_end": str(payload.get("period_end", "")).strip(),
            "safe_to_publish": bool(payload.get("safe_to_publish", False)),
            "generated_at": str(payload.get("generated_at", "")).strip(),
            "title": title,
            "subtitle": subtitle,
            "preview": preview,
            "source_count_total": int(payload.get("source_count_total", 0) or 0),
            "source_count_usable": int(payload.get("source_count_usable", 0) or 0),
            "safety_report": safety_report if isinstance(safety_report, dict) else {},
            "classification_summary": classification_summary if isinstance(classification_summary, dict) else {},
            "taste_gate": taste_gate if isinstance(taste_gate, dict) else {},
            "markdown_path": markdown_path,
        }

    def generate_newsletter_draft(
        self,
        *,
        period: str = "weekly",
        mode: str = "weekly-lessons",
        strict_safety: bool = True,
        strict_taste: bool = True,
    ) -> dict:
        """Generate newsletter draft through shared automation script."""
        script_path = (
            Path(__file__).resolve().parents[1] / "cortexos_automation_scripts" / "scripts" / "generate_newsletter.py"
        )
        if not script_path.exists():
            return {
                "status": "error",
                "reason": "newsletter_script_missing",
                "safe_to_publish": False,
            }

        spec = importlib.util.spec_from_file_location("simplixio_newsletter_module", script_path)
        if spec is None or spec.loader is None:
            return {
                "status": "error",
                "reason": "newsletter_script_load_failed",
                "safe_to_publish": False,
            }

        module = importlib.util.module_from_spec(spec)
        try:
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)  # type: ignore[attr-defined]
            run_generation = module.run_generation
            return run_generation(
                period=period,
                mode=mode,
                strict_safety=strict_safety,
                strict_taste=strict_taste,
            )
        except Exception as exc:
            return {
                "status": "error",
                "reason": "newsletter_generation_failed",
                "error": str(exc),
                "safe_to_publish": False,
            }

    # ── Integrations ────────────────────────────────────────────

    def pull_integration_context(
        self,
        *,
        rss_feeds: list[str] | None = None,
        github_repositories: list[str] | None = None,
        github_topic: str = "",
        notion_database_id: str = "",
        notion_query: str = "",
        max_items: int = 8,
    ) -> dict:
        """Pull high-signal external context and ingest as notes."""
        integrations = self.integration_service.pull(
            rss_feeds=rss_feeds,
            github_repositories=github_repositories,
            notion_database_id=notion_database_id,
            notion_query=notion_query,
            max_items=max_items,
            active_projects=self.memory.profile.current_projects,
        )

        existing_titles = {n.title.lower().strip() for n in self.store.notes if n.title.strip()}
        ingested = 0
        for signal in integrations.get("signals", []):
            title = str(signal.get("title", "")).strip()
            if not title:
                continue
            key = title.lower()
            if key in existing_titles:
                continue
            self.add_note(
                title=title,
                insight=str(signal.get("why_it_matters", "")).strip() or "Captured from integration signal.",
                implication=f"Source: {str(signal.get('source', '')).strip() or 'integration'}.",
                action=str(signal.get("next_action", "")).strip()
                or "Review and decide whether this changes today's priorities.",
                source_url=str(signal.get("url", "")).strip(),
                tags=[tag for tag in signal.get("tags", []) if str(tag).strip()] or ["integration", "signal"],
            )
            existing_titles.add(key)
            ingested += 1

        for context_item in integrations.get("context_items", []):
            title = str(context_item.get("title", "")).strip()
            if not title:
                continue
            key = title.lower()
            if key in existing_titles:
                continue
            self.add_note(
                title=title,
                insight=str(context_item.get("content", "")).strip() or "Imported context note.",
                implication="Trusted personal context from Notion.",
                action="Use this context when deciding what matters next.",
                source_url=str(context_item.get("url", "")).strip(),
                tags=[tag for tag in context_item.get("tags", []) if str(tag).strip()] or ["integration", "context"],
            )
            existing_titles.add(key)
            ingested += 1

        return {
            "fetched": int(integrations.get("fetched", 0)),
            "ingested": ingested,
            "rss_feeds": len(rss_feeds or []),
            "github_topic": github_topic,
            "notion_enabled": bool(notion_database_id or notion_query),
            "github_repositories": len(github_repositories or []),
            "raw_saved": int(integrations.get("raw_saved", 0)),
            "deduplicated": int(integrations.get("deduplicated", 0)),
            "mapped_signals": len(integrations.get("signals", [])),
            "mapped_context_items": len(integrations.get("context_items", [])),
            "sources": integrations.get("sources", {}),
        }

    def export_decisions_for_notion(self, *, limit: int = 20) -> dict:
        """Return markdown payload ready to paste into Notion."""
        decisions = self.get_decisions(limit=limit)
        markdown = export_decisions_markdown(decisions)
        return {
            "count": len(decisions),
            "markdown": markdown,
        }

    # ── Why Engine ──────────────────────────────────────────────

    def evaluate_why(self, item_data: dict) -> dict:
        """Evaluate a single source item through the Why Engine.

        Assembles full evaluation context from all memory layers and
        returns a structured DecisionResult.
        """
        item = SourceItem.from_dict(item_data)
        context = self._build_evaluation_context()
        result = self.why_engine.evaluate(item, context)
        return result.to_dict()

    def _build_evaluation_context(self) -> EvaluationContext:
        """Assemble evaluation context from all four memory layers."""
        profile = self.memory.profile

        # Project layer: milestones, blockers from first active project
        milestones: list[str] = []
        blockers: list[str] = []
        if profile.current_projects:
            pm = self.memory.get_project(profile.current_projects[0])
            milestones = [pm.current_milestone] if pm.current_milestone else []
            blockers = list(pm.active_blockers)

        # Decision history: recent decision descriptions
        recent_decisions = [d.decision for d in self.decision_engine.recent_decisions(10)]

        # Research layer: themes
        recent_themes = list(self.memory.research.recurring_themes)

        # Assumptions: from recent decisions
        assumptions: list[str] = []
        for d in self.decision_engine.recent_decisions(5):
            assumptions.extend(d.assumptions)

        return EvaluationContext(
            goals=profile.goals,
            interests=profile.interests,
            current_projects=profile.current_projects,
            ignored_topics=profile.ignored_topics,
            project_milestones=milestones,
            project_blockers=blockers,
            recent_decisions=recent_decisions,
            recent_themes=recent_themes,
            assumptions=assumptions,
        )

    # ── Internal helpers ────────────────────────────────────────

    def _latest_scored_articles(self) -> list:
        """Get scored articles from the latest digest."""
        from cortex_core.scoring import evaluate_digest as _eval

        files = sorted(self.config.data_dir.glob(self.config.digest_glob))
        if not files:
            paths = sorted(Path(".").glob("weekly_digest_*.md"))
            if not paths:
                return []
            content = paths[-1].read_text(encoding="utf-8")
        else:
            content = files[-1].read_text(encoding="utf-8")

        ctx = self.memory.get_context_snippets()
        score = _eval(
            content,
            ctx,
            seen_titles={e.title.lower().strip() for e in self.memory.history},
            ignored_topics=self.memory.profile.ignored_set(),
            goal_tokens=self.memory.profile.goal_tokens(),
        )
        return score.articles
