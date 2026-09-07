"""Tests for structured Insight objects and InsightStore."""

import pytest

from cortex_core.insights import (
    Insight,
    InsightStore,
    generate_insight_from_note,
)


class TestInsightGeneration:
    def test_generate_from_complete_note(self):
        insight = generate_insight_from_note(
            title="Context windows are growing",
            insight_text="Models now support 1M tokens.",
            implication="Retrieval strategies may need rethinking.",
            action="Experiment with full-context pipelines.",
            tags=["ai", "retrieval"],
        )
        assert insight.title == "Context windows are growing"
        assert insight.confidence == 1.0  # all 3 fields filled
        assert insight.why_it_matters == "Retrieval strategies may need rethinking."
        assert insight.next_action == "Experiment with full-context pipelines."

    def test_generate_partial_note(self):
        insight = generate_insight_from_note(
            title="New tool released",
            insight_text="Some tool exists.",
            implication="",
            action="",
            tags=["developer-tools"],
        )
        assert insight.confidence == pytest.approx(0.33, abs=0.01)

    def test_generate_with_project(self):
        insight = generate_insight_from_note(
            title="Test",
            insight_text="Insight text",
            implication="Implication",
            action="Action",
            tags=[],
            project="CortexOS",
        )
        assert insight.related_project == "CortexOS"

    def test_insight_roundtrip(self):
        insight = Insight(
            title="Test",
            summary="Summary",
            why_it_matters="Matters",
            confidence=0.8,
            tags=["ai"],
        )
        d = insight.to_dict()
        restored = Insight.from_dict(d)
        assert restored.title == insight.title
        assert restored.confidence == insight.confidence


class TestInsightStore:
    @pytest.fixture()
    def store_path(self, tmp_path):
        return tmp_path / "insights.json"

    def test_add_and_get(self, store_path):
        store = InsightStore(store_path)
        insight = Insight(title="Test", summary="Summary")
        store.add(insight)
        assert store.count == 1
        assert store.get(insight.id) is not None

    def test_batch_add(self, store_path):
        store = InsightStore(store_path)
        insights = [Insight(title=f"Insight {i}", summary=f"Summary {i}") for i in range(5)]
        store.add_batch(insights)
        assert store.count == 5

    def test_by_project(self, store_path):
        store = InsightStore(store_path)
        store.add(Insight(title="A", related_project="CortexOS"))
        store.add(Insight(title="B", related_project="Other"))
        assert len(store.by_project("cortexos")) == 1

    def test_by_tag(self, store_path):
        store = InsightStore(store_path)
        store.add(Insight(title="A", tags=["ai", "agents"]))
        store.add(Insight(title="B", tags=["health"]))
        assert len(store.by_tag("ai")) == 1

    def test_high_confidence(self, store_path):
        store = InsightStore(store_path)
        store.add(Insight(title="High", confidence=0.9))
        store.add(Insight(title="Low", confidence=0.2))
        high = store.high_confidence(0.6)
        assert len(high) == 1
        assert high[0].title == "High"

    def test_search(self, store_path):
        store = InsightStore(store_path)
        store.add(Insight(title="Agent memory design", summary="Agents need state."))
        store.add(Insight(title="Cooking tips", summary="Use garlic."))
        results = store.search("agent")
        assert len(results) == 1

    def test_link_insights(self, store_path):
        store = InsightStore(store_path)
        a = Insight(title="A")
        b = Insight(title="B")
        store.add(a)
        store.add(b)
        assert store.link(a.id, b.id)
        assert b.id in store.get(a.id).related_insight_ids
        assert a.id in store.get(b.id).related_insight_ids

    def test_summary(self, store_path):
        store = InsightStore(store_path)
        store.add(Insight(title="A", tags=["ai"], confidence=0.8, related_project="CortexOS"))
        store.add(Insight(title="B", tags=["ai", "agents"], confidence=0.6, related_project="CortexOS"))
        s = store.summary()
        assert s["total"] == 2
        assert s["avg_confidence"] == 0.7
        assert "CortexOS" in s["projects"]

    def test_persistence(self, store_path):
        store = InsightStore(store_path)
        store.add(Insight(title="Persisted", summary="Persistent insight"))
        store2 = InsightStore(store_path)
        assert store2.count == 1
