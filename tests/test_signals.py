"""Tests for Signal Detection and SignalStore."""

import pytest

from cortex_core.signals import (
    Signal,
    SignalStore,
    detect_signals,
    extract_topics,
)


class TestTopicExtraction:
    def test_extract_ai_agents(self):
        topics = extract_topics("New AI Agent Framework Released")
        assert "ai agents" in topics

    def test_extract_context_engineering(self):
        topics = extract_topics("Guide to Context Engineering for LLMs")
        assert "context engineering" in topics

    def test_extract_multiple_topics(self):
        topics = extract_topics("AI Agents Use RAG for Context Engineering")
        assert "ai agents" in topics
        assert "retrieval augmented generation" in topics
        assert "context engineering" in topics

    def test_no_topics(self):
        topics = extract_topics("Random unrelated text about cooking")
        assert len(topics) == 0


class TestSignalDetection:
    def test_detect_emerging_signal(self):
        titles = [
            "AI Agent Framework 1",
            "New AI Agent for Code",
            "AI Agent Orchestration Tool",
            "Unrelated Article",
        ]
        signals = detect_signals(titles, min_frequency=3)
        assert len(signals) >= 1
        topics = [s.topic for s in signals]
        assert "ai agents" in topics

    def test_signal_with_urls(self):
        titles = ["AI Agent A", "AI Agent B", "AI Agent C"]
        urls = ["https://a.com", "https://b.com", "https://c.com"]
        signals = detect_signals(titles, urls=urls, min_frequency=3)
        assert len(signals) >= 1
        assert len(signals[0].source_urls) == 3

    def test_below_threshold(self):
        titles = ["AI Agent Framework", "Unrelated"]
        signals = detect_signals(titles, min_frequency=3)
        assert len(signals) == 0

    def test_signal_strength(self):
        titles = [f"AI Agent Tool {i}" for i in range(10)]
        signals = detect_signals(titles, min_frequency=3)
        ai_signal = next(s for s in signals if s.topic == "ai agents")
        assert ai_signal.strength == 1.0  # 10/10 = capped at 1.0

    def test_confirmed_status(self):
        titles = [f"AI Agent Tool {i}" for i in range(6)]
        signals = detect_signals(titles, min_frequency=3)
        ai_signal = next(s for s in signals if s.topic == "ai agents")
        assert ai_signal.status == "confirmed"

    def test_emerging_status(self):
        titles = ["AI Agent A", "AI Agent B", "AI Agent C"]
        signals = detect_signals(titles, min_frequency=3)
        ai_signal = next(s for s in signals if s.topic == "ai agents")
        assert ai_signal.status == "emerging"


class TestSignalStore:
    @pytest.fixture()
    def store_path(self, tmp_path):
        return tmp_path / "signals.json"

    def test_update_signals(self, store_path):
        store = SignalStore(store_path)
        signals = [Signal(id="sig-ai-agents", topic="ai agents", frequency=3, strength=0.3, status="emerging")]
        updated = store.update_signals(signals)
        assert len(updated) == 1
        assert store.count == 1

    def test_merge_signals(self, store_path):
        store = SignalStore(store_path)
        sig1 = Signal(
            id="sig-ai-agents",
            topic="ai agents",
            frequency=3,
            source_titles=["A", "B", "C"],
            strength=0.3,
            last_seen="2026-03-15",
        )
        store.update_signals([sig1])

        sig2 = Signal(
            id="sig-ai-agents",
            topic="ai agents",
            frequency=2,
            source_titles=["D", "E"],
            strength=0.2,
            last_seen="2026-03-16",
        )
        updated = store.update_signals([sig2])
        merged = next(s for s in updated if s.topic == "ai agents")
        assert merged.frequency == 5  # 3 original + 2 new
        assert merged.last_seen == "2026-03-16"

    def test_active_vs_archived(self, store_path):
        store = SignalStore(store_path)
        store.update_signals(
            [
                Signal(topic="active", frequency=3, strength=0.3, status="emerging"),
                Signal(topic="old", frequency=1, strength=0.1, status="archived"),
            ]
        )
        assert len(store.active_signals()) == 1

    def test_confirmed_signals(self, store_path):
        store = SignalStore(store_path)
        store.update_signals(
            [
                Signal(topic="confirmed", frequency=6, strength=0.6, status="confirmed"),
                Signal(topic="emerging", frequency=3, strength=0.3, status="emerging"),
            ]
        )
        assert len(store.confirmed_signals()) == 1

    def test_persistence(self, store_path):
        store = SignalStore(store_path)
        store.update_signals([Signal(topic="test", frequency=3, strength=0.3)])
        store2 = SignalStore(store_path)
        assert store2.count >= 1
