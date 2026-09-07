"""
Structured Item Extraction
---------------------------
Every source becomes a structured Item before any transformation.
This is the canonical data model for raw ingested content.

CortexOS preserves the real source text — not just summaries.
Reproducibility matters.
"""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

SourceType = Literal[
    "digest",
    "rss",
    "note",
    "url",
    "blog_export",
    "project_doc",
    "manual",
    "summary",
]


@dataclass
class Item:
    """A single ingested content item — the canonical CortexOS input object."""

    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    source_type: SourceType = "manual"
    title: str = ""
    url: str = ""
    published_at: str = ""
    content: str = ""
    tags: list[str] = field(default_factory=list)
    author: str = ""
    section: str = ""  # section heading from digest
    raw_metadata: dict = field(default_factory=dict)
    ingested_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    content_hash: str = ""  # dedup finger print

    def __post_init__(self) -> None:
        if not self.content_hash and (self.title or self.content):
            self.content_hash = self._compute_hash()

    def _compute_hash(self) -> str:
        blob = f"{self.title.lower().strip()}|{self.url.strip()}"
        return hashlib.sha256(blob.encode()).hexdigest()[:16]

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> Item:
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


# ── Extraction from digest markdown ──────────────────────────

ARTICLE_RE = re.compile(r"^- \[(.*?)\]\((.*?)\)", re.MULTILINE)
HEADING_RE = re.compile(r"^#{1,3}\s+(.+)", re.MULTILINE)


def extract_items_from_digest(text: str) -> list[Item]:
    """Parse a weekly digest markdown into structured Items."""
    items: list[Item] = []
    current_section = ""

    lines = text.split("\n")
    for line in lines:
        heading_m = HEADING_RE.match(line)
        if heading_m:
            current_section = heading_m.group(1).strip()
            continue

        article_m = ARTICLE_RE.match(line.strip())
        if article_m:
            title = article_m.group(1).strip()
            url = article_m.group(2).strip()
            item = Item(
                source_type="digest",
                title=title,
                url=url,
                section=current_section,
                content=title,  # digest items have title-only content
            )
            items.append(item)

    return items


def extract_items_from_summary(text: str, *, source: str = "", tags: list[str] | None = None) -> list[Item]:
    """Parse a user-written markdown summary into structured Items.

    Splits on headings (## / ###) and double-newlines.
    Each section becomes one Item with title from the heading
    and content from the body.
    """
    items: list[Item] = []
    base_tags = tags or []

    # Split into heading-delimited sections
    section_re = re.compile(r"^(#{1,3})\s+(.+)", re.MULTILINE)
    parts = section_re.split(text)

    # parts: [preamble, level, title, body, level, title, body, ...]
    # Handle preamble (text before first heading)
    preamble = parts[0].strip() if parts else ""
    if preamble:
        items.append(
            Item(
                source_type="summary",
                title=source or "User Summary",
                content=preamble,
                tags=list(base_tags),
                raw_metadata={"source": source} if source else {},
            )
        )

    # Process heading groups (level, title, body)
    i = 1
    while i + 2 < len(parts):
        heading = parts[i + 1].strip()
        body = parts[i + 2].strip()
        i += 3

        if not body:
            continue

        # Split long bodies into paragraphs (separated by blank lines)
        paragraphs = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]

        if len(paragraphs) <= 3:
            # Keep as one item
            items.append(
                Item(
                    source_type="summary",
                    title=heading,
                    content=body,
                    section=heading,
                    tags=list(base_tags),
                    raw_metadata={"source": source} if source else {},
                )
            )
        else:
            # One item per paragraph for long sections
            for idx, para in enumerate(paragraphs, 1):
                items.append(
                    Item(
                        source_type="summary",
                        title=f"{heading} ({idx})",
                        content=para,
                        section=heading,
                        tags=list(base_tags),
                        raw_metadata={"source": source} if source else {},
                    )
                )

    # Fallback: no headings at all — treat whole text as one item
    if not items and text.strip():
        items.append(
            Item(
                source_type="summary",
                title=source or "User Summary",
                content=text.strip(),
                tags=list(base_tags),
                raw_metadata={"source": source} if source else {},
            )
        )

    return items


def extract_items_from_notes(notes_data: list[dict]) -> list[Item]:
    """Convert knowledge notes into Items for unified processing."""
    items: list[Item] = []
    for note in notes_data:
        item = Item(
            source_type="note",
            title=note.get("title", ""),
            url=note.get("source_url", ""),
            content=note.get("insight", ""),
            tags=note.get("tags", []),
            published_at=note.get("created_at", ""),
        )
        items.append(item)
    return items


# ── Item Store (raw data preservation) ───────────────────────


class ItemStore:
    """Persists raw items to JSON — the data/raw layer."""

    def __init__(self, path: Path):
        self.path = path
        self._items: list[Item] = []
        self._hashes: set[str] = set()
        self._load()

    def _load(self) -> None:
        if self.path.exists():
            with open(self.path) as f:
                raw = json.load(f)
            self._items = [Item.from_dict(r) for r in raw]
            self._hashes = {i.content_hash for i in self._items if i.content_hash}

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, "w") as f:
            json.dump([i.to_dict() for i in self._items], f, indent=2)

    def add(self, item: Item, *, deduplicate: bool = True) -> Item:
        """Add an item. Deduplicates by content hash."""
        if deduplicate and item.content_hash in self._hashes:
            return self._find_by_hash(item.content_hash) or item
        item.ingested_at = datetime.now(UTC).isoformat()
        self._items.append(item)
        self._hashes.add(item.content_hash)
        self.save()
        return item

    def add_batch(self, items: list[Item], *, deduplicate: bool = True) -> list[Item]:
        """Add multiple items efficiently (single save)."""
        added: list[Item] = []
        for item in items:
            if deduplicate and item.content_hash in self._hashes:
                existing = self._find_by_hash(item.content_hash)
                if existing:
                    added.append(existing)
                continue
            item.ingested_at = datetime.now(UTC).isoformat()
            self._items.append(item)
            self._hashes.add(item.content_hash)
            added.append(item)
        self.save()
        return added

    def _find_by_hash(self, content_hash: str) -> Item | None:
        for item in self._items:
            if item.content_hash == content_hash:
                return item
        return None

    def get(self, item_id: str) -> Item | None:
        for item in self._items:
            if item.id == item_id:
                return item
        return None

    def search(self, query: str) -> list[Item]:
        query_lower = query.lower()
        return [
            i
            for i in self._items
            if query_lower in i.title.lower()
            or query_lower in i.content.lower()
            or query_lower in " ".join(i.tags).lower()
        ]

    def by_source_type(self, source_type: SourceType) -> list[Item]:
        return [i for i in self._items if i.source_type == source_type]

    def by_tag(self, tag: str) -> list[Item]:
        tag_lower = tag.lower()
        return [i for i in self._items if tag_lower in [t.lower() for t in i.tags]]

    def recent(self, limit: int = 50) -> list[Item]:
        return sorted(self._items, key=lambda i: i.ingested_at, reverse=True)[:limit]

    @property
    def count(self) -> int:
        return len(self._items)

    @property
    def items(self) -> list[Item]:
        return list(self._items)
