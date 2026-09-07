"""RSS client."""

from __future__ import annotations

import logging
from typing import Any

from cortex_core.integrations.schemas import RawRSSItem

try:
    import feedparser
except Exception:  # pragma: no cover - optional runtime dependency
    feedparser = None


def _clean(value: Any) -> str:
    return " ".join(str(value or "").split()).strip()


class RSSClient:
    """Fetches RSS entries as raw integration items."""

    def fetch(self, feed_urls: list[str], *, max_items: int) -> list[RawRSSItem]:
        if feedparser is None:
            return []

        rows: list[RawRSSItem] = []
        for url in feed_urls:
            if not str(url).strip():
                continue
            try:
                parsed = feedparser.parse(url)
            except Exception:
                logging.getLogger(__name__).warning("Skipping an RSS feed that could not be parsed")
                continue
            for entry in parsed.entries[:max_items]:
                title = _clean(getattr(entry, "title", ""))
                link = _clean(getattr(entry, "link", ""))
                guid = _clean(getattr(entry, "id", "") or getattr(entry, "guid", ""))
                published = _clean(getattr(entry, "published", "") or getattr(entry, "updated", ""))
                summary = _clean(getattr(entry, "summary", "") or getattr(entry, "description", ""))
                if not title:
                    continue
                rows.append(
                    RawRSSItem(
                        feed_url=str(url),
                        guid=guid,
                        url=link,
                        title=title,
                        published_at=published,
                        summary=summary,
                        raw_payload={
                            "id": guid,
                            "title": title,
                            "link": link,
                            "published": published,
                            "summary": summary,
                        },
                    )
                )
        return rows
