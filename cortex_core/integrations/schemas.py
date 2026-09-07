"""Shared schemas for CortexOS integrations."""

from __future__ import annotations

import hashlib
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from typing import Any


def _compact(text: str, *, limit: int = 400) -> str:
    cleaned = " ".join(str(text or "").split()).strip()
    return cleaned[:limit]


def fingerprint_from_parts(*parts: str) -> str:
    joined = "||".join(str(part or "").strip().lower() for part in parts)
    digest = hashlib.sha1(joined.encode("utf-8"), usedforsecurity=False).hexdigest()
    return digest


@dataclass
class RawRSSItem:
    feed_url: str
    guid: str
    url: str
    title: str
    published_at: str
    summary: str = ""
    raw_payload: dict[str, Any] = field(default_factory=dict)

    def fingerprint(self) -> str:
        return fingerprint_from_parts(self.guid, self.url, self.title)

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["summary"] = _compact(payload["summary"])
        return payload


@dataclass
class RawGitHubItem:
    repo: str
    item_type: str  # issue | pull_request | release
    external_id: str
    url: str
    title: str
    summary: str = ""
    state: str = ""
    updated_at: str = ""
    raw_payload: dict[str, Any] = field(default_factory=dict)

    def fingerprint(self) -> str:
        return fingerprint_from_parts(self.repo, self.item_type, self.external_id, self.url, self.title)

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["summary"] = _compact(payload["summary"])
        return payload


@dataclass
class RawNotionItem:
    source_id: str
    page_id: str
    url: str
    title: str
    summary: str = ""
    last_edited_time: str = ""
    raw_payload: dict[str, Any] = field(default_factory=dict)

    def fingerprint(self) -> str:
        return fingerprint_from_parts(self.source_id, self.page_id, self.url, self.title)

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["summary"] = _compact(payload["summary"])
        return payload


@dataclass
class CortexSignal:
    id: str
    source: str
    title: str
    url: str = ""
    why_it_matters: str = ""
    next_action: str = ""
    source_type: str = ""
    project: str = ""
    relevance_score: float = 0.0
    tags: list[str] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class CortexContextItem:
    id: str
    source: str
    title: str
    content: str = ""
    url: str = ""
    tags: list[str] = field(default_factory=list)
    updated_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["content"] = _compact(payload["content"], limit=800)
        return payload
