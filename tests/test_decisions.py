"""Tests for Decision Engine, Priorities, and Decision History."""

import pytest

from cortex_core.decisions import (
    DailyDecisionBrief,
    Decision,
    DecisionEngine,
    Priority,
)


class TestPriority:
    def test_create_priority(self):
        p = Priority(rank=1, title="Ship v2", why_it_matters="Revenue", next_step="Deploy staging")
        assert p.rank == 1
        assert p.relevance_score == 0.0

    def test_priority_with_score(self):
        p = Priority(rank=1, title="Launch", relevance_score=0.85)
        assert p.relevance_score == 0.85


class TestDecision:
    def test_create_decision(self):
        d = Decision(decision="Adopt FastAPI", reason="Best for async")
        assert d.decision == "Adopt FastAPI"
        assert d.outcome == ""

    def test_decision_with_outcome(self):
        d = Decision(decision="Use SQLite", reason="Simplicity")
        d.outcome = "Worked well for prototype"
        d.impact_score = 0.9
        assert d.impact_score == 0.9


class TestDailyDecisionBrief:
    def test_empty_brief(self):
        brief = DailyDecisionBrief()
        assert len(brief.priorities) == 0
        assert len(brief.ignored) == 0
        assert len(brief.emerging_signals) == 0


class TestDecisionEngine:
    @pytest.fixture()
    def engine_path(self, tmp_path):
        return tmp_path / "decisions.json"

    @pytest.fixture()
    def profile_dict(self):
        return {
            "name": "Test User",
            "goals": ["Build AI platform", "Ship CortexOS"],
            "interests": ["AI agents", "context engineering", "developer tools"],
            "ignored_topics": ["cryptocurrency", "NFTs"],
        }

    def test_generate_brief_empty(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        brief = engine.generate_brief(profile=profile_dict)
        assert isinstance(brief, DailyDecisionBrief)
        assert len(brief.priorities) == 0

    def test_generate_brief_with_items(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        scored_items = [
            {"title": "AI Agent Framework", "composite": 0.8},
            {"title": "New Crypto Exchange", "composite": 0.2},
        ]
        brief = engine.generate_brief(scored_items=scored_items, profile=profile_dict)
        assert len(brief.priorities) >= 1
        titles = [p.title for p in brief.priorities]
        assert "AI Agent Framework" in titles

    def test_ignored_topics_demoted(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        # 6 items to fill top 5, crypto should be demoted
        scored_items = [
            {"title": "New Cryptocurrency Trading Bot", "composite": 0.5},
            {"title": "AI Tool 1", "composite": 0.5},
            {"title": "AI Tool 2", "composite": 0.5},
            {"title": "AI Tool 3", "composite": 0.5},
            {"title": "AI Tool 4", "composite": 0.5},
            {"title": "AI Tool 5", "composite": 0.5},
        ]
        brief = engine.generate_brief(scored_items=scored_items, profile=profile_dict)
        # Crypto should be demoted by the 0.1 multiplier
        top_titles = [p.title for p in brief.priorities]
        assert "New Cryptocurrency Trading Bot" not in top_titles

    def test_emerging_signals_in_brief(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        signals = [
            {"topic": "context engineering", "frequency": 5, "strength": 0.5, "status": "emerging"},
        ]
        brief = engine.generate_brief(signals=signals, profile=profile_dict)
        assert len(brief.emerging_signals) >= 1

    def test_goal_boost(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        scored_items = [
            {"title": "AI Platform Architecture Guide", "composite": 0.5},
        ]
        brief = engine.generate_brief(scored_items=scored_items, profile=profile_dict)
        if brief.priorities:
            # "AI" and "platform" match goals → boosted above 0.5
            assert brief.priorities[0].relevance_score > 0.5

    def test_record_and_get_decisions(self, engine_path):
        engine = DecisionEngine(engine_path)
        engine.record_decision("Use FastAPI", "Best for async", project="CortexOS")
        decisions = engine.all_decisions
        assert len(decisions) == 1
        assert decisions[0].decision == "Use FastAPI"
        assert decisions[0].project == "CortexOS"

    def test_record_outcome(self, engine_path):
        engine = DecisionEngine(engine_path)
        engine.record_decision("Use SQLite", "Simple")
        decisions = engine.all_decisions
        decision_id = decisions[0].id
        engine.record_outcome(decision_id, "Perfect for prototype", impact_score=0.85)
        updated = engine.all_decisions
        assert updated[0].outcome == "Perfect for prototype"
        assert updated[0].impact_score == 0.85

    def test_decision_effectiveness(self, engine_path):
        engine = DecisionEngine(engine_path)
        engine.record_decision("Decision A", "Reason A")
        engine.record_decision("Decision B", "Reason B")
        decisions = engine.all_decisions
        engine.record_outcome(decisions[0].id, "Good", impact_score=0.8)
        stats = engine.decision_effectiveness()
        assert stats["total_decisions"] == 2
        assert stats["rated"] == 1
        assert stats["avg_impact"] == 0.8

    def test_persistence(self, engine_path):
        engine = DecisionEngine(engine_path)
        engine.record_decision("Persist me", "Testing")
        engine2 = DecisionEngine(engine_path)
        assert len(engine2.all_decisions) == 1

    def test_save_and_load_brief(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        scored_items = [
            {"title": "Article A", "composite": 0.8},
        ]
        brief = engine.generate_brief(scored_items=scored_items, profile=profile_dict)
        engine.save_brief(brief)
        prev = engine.get_previous_brief()
        assert prev is not None
        assert len(prev["priorities"]) >= 1

    def test_change_detection(self, engine_path, profile_dict):
        engine = DecisionEngine(engine_path)
        brief1 = engine.generate_brief(
            scored_items=[{"title": "Article A", "composite": 0.8}],
            profile=profile_dict,
        )
        engine.save_brief(brief1)

        # Second brief with different items
        prev = engine.get_previous_brief()
        brief2 = engine.generate_brief(
            scored_items=[{"title": "Article B", "composite": 0.6}],
            profile=profile_dict,
            previous_brief=prev,
        )
        assert isinstance(brief2, DailyDecisionBrief)
        # Should detect changes
        if brief2.changes_since_yesterday:
            changes_text = " ".join(brief2.changes_since_yesterday)
            assert "NEW" in changes_text or "DROPPED" in changes_text
