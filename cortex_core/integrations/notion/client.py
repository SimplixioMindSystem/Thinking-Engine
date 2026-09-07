"""Notion API client (minimal import surface)."""

from __future__ import annotations

import os
from typing import Any

from cortex_core.integrations.schemas import RawNotionItem

try:
    import requests
except Exception:  # pragma: no cover - optional runtime dependency
    requests = None


NOTION_DATABASE_QUERY_URL = "https://api.notion.com/v1/databases/{database_id}/query"
NOTION_SEARCH_URL = "https://api.notion.com/v1/search"


def _clean(value: Any) -> str:
    return " ".join(str(value or "").split()).strip()


def _extract_notion_title(properties: dict[str, Any]) -> str:
    for prop in properties.values():
        if prop.get("type") == "title":
            title_parts = prop.get("title", [])
            return _clean("".join(part.get("plain_text", "") for part in title_parts))
    return ""


def _extract_notion_summary(properties: dict[str, Any]) -> str:
    chunks: list[str] = []
    for prop in properties.values():
        prop_type = prop.get("type")
        if prop_type == "rich_text":
            chunks.extend(part.get("plain_text", "") for part in prop.get("rich_text", []))
        elif prop_type == "select" and prop.get("select"):
            chunks.append(str(prop["select"].get("name", "")))
    return _clean(" ".join(chunks))


class NotionClient:
    """Fetches pages from a selected Notion source."""

    def __init__(self, token: str | None = None):
        self.token = token or os.environ.get("NOTION_API_KEY", "") or os.environ.get("NOTION_TOKEN", "")

    def _headers(self) -> dict[str, str]:
        if not self.token:
            return {}
        return {
            "Authorization": f"Bearer {self.token}",
            "Notion-Version": "2022-06-28",
            "Content-Type": "application/json",
        }

    def _post(self, url: str, payload: dict[str, Any]) -> list[dict[str, Any]]:
        if requests is None or not self.token:
            return []
        try:
            response = requests.post(url, headers=self._headers(), json=payload, timeout=20)
            response.raise_for_status()
            data = response.json()
            results = data.get("results", [])
            return results if isinstance(results, list) else []
        except Exception:
            return []

    def fetch_database_pages(self, *, database_id: str, max_items: int) -> list[RawNotionItem]:
        database_id = _clean(database_id)
        if not database_id:
            return []
        payload = {"page_size": max_items}
        rows: list[RawNotionItem] = []
        for page in self._post(NOTION_DATABASE_QUERY_URL.format(database_id=database_id), payload):
            props = page.get("properties", {})
            title = _extract_notion_title(props)
            if not title:
                continue
            rows.append(
                RawNotionItem(
                    source_id=database_id,
                    page_id=_clean(page.get("id", "")),
                    url=_clean(page.get("url", "")),
                    title=title,
                    summary=_extract_notion_summary(props),
                    last_edited_time=_clean(page.get("last_edited_time", "")),
                    raw_payload=page,
                )
            )
        return rows

    def search_pages(self, *, query: str, max_items: int) -> list[RawNotionItem]:
        query = _clean(query)
        if not query:
            return []
        payload = {
            "query": query,
            "filter": {"value": "page", "property": "object"},
            "page_size": max_items,
        }
        rows: list[RawNotionItem] = []
        for page in self._post(NOTION_SEARCH_URL, payload):
            page_id = _clean(page.get("id", ""))
            title = _clean(page.get("url", ""))
            if not page_id:
                continue
            rows.append(
                RawNotionItem(
                    source_id="search",
                    page_id=page_id,
                    url=_clean(page.get("url", "")),
                    title=title or "Notion page",
                    summary="",
                    last_edited_time=_clean(page.get("last_edited_time", "")),
                    raw_payload=page,
                )
            )
        return rows
