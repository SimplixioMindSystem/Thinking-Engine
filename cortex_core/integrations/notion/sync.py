"""Notion sync orchestration."""

from __future__ import annotations

from cortex_core.integrations.notion.client import NotionClient
from cortex_core.integrations.notion.mapper import map_notion_to_context
from cortex_core.integrations.repositories import IntegrationRepository


class NotionSync:
    def __init__(self, repository: IntegrationRepository, client: NotionClient | None = None):
        self.repository = repository
        self.client = client or NotionClient()

    def run(self, *, database_id: str, query: str, max_items: int) -> dict:
        source_id = str(database_id or "").strip() or "search"
        cursor = self.repository.get_cursor("notion", source_id)

        raw_items = []
        if database_id:
            raw_items = self.client.fetch_database_pages(database_id=database_id, max_items=max_items)
        elif query:
            raw_items = self.client.search_pages(query=query, max_items=max_items)

        context_items: list[dict] = []
        duplicates = 0
        max_edited = cursor

        for item in raw_items:
            if cursor and item.last_edited_time and item.last_edited_time <= cursor:
                duplicates += 1
                continue

            fingerprint = item.fingerprint()
            if self.repository.has_seen("notion", fingerprint):
                duplicates += 1
                continue

            self.repository.append_raw(
                source="notion",
                kind="page",
                external_id=item.page_id,
                fingerprint=fingerprint,
                payload=item.to_dict(),
            )
            context_items.append(map_notion_to_context(item).to_dict())
            if item.last_edited_time and item.last_edited_time > max_edited:
                max_edited = item.last_edited_time

        if max_edited:
            self.repository.set_cursor("notion", source_id, max_edited)
        self.repository.mark_synced("notion")

        return {
            "source": "notion",
            "fetched": len(raw_items),
            "raw_saved": len(raw_items) - duplicates,
            "duplicates": duplicates,
            "signals": [],
            "context_items": context_items,
        }
