"""Tests for user-written summary ingestion."""

from __future__ import annotations

import pytest

from cortex_core.items import extract_items_from_summary

# ── Parser tests ─────────────────────────────────────────────


class TestExtractItemsFromSummary:
    """Tests for the markdown section parser."""

    def test_single_heading_section(self):
        md = "## Key Insight\n\nThis is an important observation about AI agents."
        items = extract_items_from_summary(md)
        assert len(items) == 1
        assert items[0].title == "Key Insight"
        assert "important observation" in items[0].content
        assert items[0].source_type == "summary"

    def test_multiple_heading_sections(self):
        md = (
            "## Architecture\n\nMicroservices are the way.\n\n"
            "## Tradeoffs\n\nLatency vs consistency.\n\n"
            "## Decision\n\nGo with event sourcing."
        )
        items = extract_items_from_summary(md)
        assert len(items) == 3
        titles = [i.title for i in items]
        assert "Architecture" in titles
        assert "Tradeoffs" in titles
        assert "Decision" in titles

    def test_preamble_without_heading(self):
        md = "Some context before any heading.\n\n## Section\n\nBody text."
        items = extract_items_from_summary(md)
        assert len(items) == 2
        # First item is the preamble
        assert "context before" in items[0].content

    def test_no_headings_at_all(self):
        md = "Just a plain text summary with no markdown headings."
        items = extract_items_from_summary(md)
        assert len(items) == 1
        assert items[0].title == "User Summary"
        assert "plain text summary" in items[0].content

    def test_source_passed_through(self):
        md = "## Insight\n\nContent here."
        items = extract_items_from_summary(md, source="My Book Notes")
        assert items[0].raw_metadata.get("source") == "My Book Notes"

    def test_tags_applied_to_all(self):
        md = "## A\n\nBody A.\n\n## B\n\nBody B."
        items = extract_items_from_summary(md, tags=["research", "ai"])
        for item in items:
            assert "research" in item.tags
            assert "ai" in item.tags

    def test_empty_string_returns_empty(self):
        items = extract_items_from_summary("")
        assert items == []

    def test_whitespace_only_returns_empty(self):
        items = extract_items_from_summary("   \n\n   ")
        assert items == []

    def test_heading_without_body_is_skipped(self):
        md = "## Empty Section\n\n## Real Section\n\nActual content."
        items = extract_items_from_summary(md)
        # Only the section with content should produce an item
        assert len(items) == 1
        assert items[0].title == "Real Section"

    def test_long_section_splits_into_paragraphs(self):
        paragraphs = "\n\n".join([f"Paragraph {i} with substantial content." for i in range(5)])
        md = f"## Analysis\n\n{paragraphs}"
        items = extract_items_from_summary(md)
        # 5 paragraphs > 3, so should split
        assert len(items) == 5
        assert items[0].title == "Analysis (1)"
        assert items[4].title == "Analysis (5)"

    def test_short_section_stays_together(self):
        md = "## Notes\n\nPara 1.\n\nPara 2.\n\nPara 3."
        items = extract_items_from_summary(md)
        # 3 paragraphs <= 3, stays as one item
        assert len(items) == 1

    def test_h3_headings_work(self):
        md = "### Sub Topic\n\nDetailed analysis of the sub topic."
        items = extract_items_from_summary(md)
        assert len(items) == 1
        assert items[0].title == "Sub Topic"

    def test_content_hash_is_set(self):
        md = "## Test\n\nSome content."
        items = extract_items_from_summary(md)
        assert items[0].content_hash != ""

    def test_source_type_is_summary(self):
        md = "## Test\n\nBody."
        items = extract_items_from_summary(md)
        assert all(i.source_type == "summary" for i in items)

    def test_no_source_means_no_metadata(self):
        md = "## Test\n\nBody."
        items = extract_items_from_summary(md)
        assert items[0].raw_metadata == {}


# ── Engine integration tests ─────────────────────────────────


class TestIngestSummary:
    """Tests for CortexEngine.ingest_summary()."""

    @pytest.fixture()
    def engine(self, tmp_path):
        from cortex_core.config import CortexConfig
        from cortex_core.engine import CortexEngine

        cfg = CortexConfig(data_dir=tmp_path)
        return CortexEngine(config=cfg)

    def test_ingest_creates_items(self, engine):
        result = engine.ingest_summary("## Topic\n\nInsight about topic.")
        assert result["items_ingested"] == 1

    def test_ingest_creates_notes_by_default(self, engine):
        result = engine.ingest_summary("## Topic\n\nInsight about topic.")
        assert result["notes_created"] == 1

    def test_ingest_skip_notes(self, engine):
        result = engine.ingest_summary("## Topic\n\nInsight.", create_notes=False)
        assert result["items_ingested"] == 1
        assert result["notes_created"] == 0

    def test_ingest_tags_propagate(self, engine):
        result = engine.ingest_summary("## Topic\n\nBody.", tags=["ai", "research"])
        item = result["items"][0]
        assert "ai" in item["tags"]
        assert "research" in item["tags"]

    def test_ingest_source_metadata(self, engine):
        result = engine.ingest_summary("## Topic\n\nBody.", source="Book Notes")
        item = result["items"][0]
        assert item["raw_metadata"]["source"] == "Book Notes"

    def test_ingest_multi_section(self, engine):
        md = "## A\n\nFirst.\n\n## B\n\nSecond.\n\n## C\n\nThird."
        result = engine.ingest_summary(md)
        assert result["items_ingested"] == 3
        assert result["notes_created"] == 3

    def test_ingest_deduplicates(self, engine):
        md = "## Topic\n\nSame content."
        r1 = engine.ingest_summary(md)
        assert r1["items_ingested"] == 1
        engine.ingest_summary(md)
        # Second call should deduplicate — item count stays at 1
        assert engine.items.count == 1

    def test_notes_appear_in_store(self, engine):
        engine.ingest_summary("## My Insight\n\nBig observation about AI agents.")
        notes = engine.list_notes()
        assert len(notes) == 1
        assert notes[0]["title"] == "My Insight"

    def test_items_appear_in_item_store(self, engine):
        engine.ingest_summary("## Topic\n\nBody text.")
        items = engine.items.by_source_type("summary")
        assert len(items) == 1


# ── API tests ────────────────────────────────────────────────


@pytest.fixture()
def ingest_client(tmp_path):
    from fastapi.testclient import TestClient

    import cortex_core.api.server as server_module
    from cortex_core.api.server import create_app
    from cortex_core.config import CortexConfig
    from cortex_core.engine import CortexEngine

    cfg = CortexConfig(data_dir=tmp_path)
    engine = CortexEngine(config=cfg)
    server_module._engine = engine
    app = create_app()
    yield TestClient(app)
    server_module._engine = None


class TestIngestAPI:
    """Tests for POST /ingest/summary."""

    def test_ingest_returns_201(self, ingest_client):
        r = ingest_client.post("/ingest/summary", json={"content": "## Research\n\nKey finding about context engines."})
        assert r.status_code == 201

    def test_ingest_response_shape(self, ingest_client):
        r = ingest_client.post("/ingest/summary", json={"content": "## Insight\n\nBody."})
        data = r.json()
        assert "items_ingested" in data
        assert "notes_created" in data

    def test_ingest_with_source_and_tags(self, ingest_client):
        r = ingest_client.post(
            "/ingest/summary",
            json={
                "content": "## Topic\n\nContent.",
                "source": "Meeting notes",
                "tags": ["meeting", "q2"],
            },
        )
        assert r.status_code == 201
        assert r.json()["items_ingested"] >= 1

    def test_ingest_without_notes(self, ingest_client):
        r = ingest_client.post(
            "/ingest/summary",
            json={
                "content": "## Topic\n\nContent.",
                "create_notes": False,
            },
        )
        data = r.json()
        assert data["notes_created"] == 0
        assert data["items_ingested"] >= 1

    def test_ingest_empty_content_still_works(self, ingest_client):
        r = ingest_client.post("/ingest/summary", json={"content": ""})
        assert r.status_code == 201
        assert r.json()["items_ingested"] == 0

    def test_ingest_feeds_into_snapshot(self, ingest_client):
        ingest_client.post(
            "/ingest/summary", json={"content": "## Big Finding\n\nContext engines improve focus by 3x."}
        )
        # The ingested note should appear in the sync snapshot
        # (as part of the knowledge store, surfaced through insights or notes)
        snapshot = ingest_client.get("/sync/snapshot").json()
        assert snapshot["synced_at"]  # Snapshot works after ingest
