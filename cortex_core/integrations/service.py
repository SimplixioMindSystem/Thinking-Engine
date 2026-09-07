"""Integration service that orchestrates source syncs."""

from __future__ import annotations

from pathlib import Path

from cortex_core.integrations.github.sync import GitHubSync
from cortex_core.integrations.notion.sync import NotionSync
from cortex_core.integrations.repositories import IntegrationRepository
from cortex_core.integrations.rss.sync import RSSSync


class IntegrationService:
    """Runs minimal MVP sync flows: RSS, GitHub repos, and Notion import."""

    def __init__(self, data_dir: Path):
        self.repository = IntegrationRepository(data_dir)
        self.rss = RSSSync(self.repository)
        self.github = GitHubSync(self.repository)
        self.notion = NotionSync(self.repository)

    def pull(
        self,
        *,
        rss_feeds: list[str] | None,
        github_repositories: list[str] | None,
        notion_database_id: str,
        notion_query: str,
        max_items: int,
        active_projects: list[str] | None = None,
    ) -> dict:
        projects = [str(item).strip() for item in (active_projects or []) if str(item).strip()]
        clean_repos = [str(item).strip() for item in (github_repositories or []) if str(item).strip()]
        feeds = [str(item).strip() for item in (rss_feeds or []) if str(item).strip()]

        rss_result = self.rss.run(feeds=feeds, max_items=max_items, active_projects=projects)
        github_result = self.github.run(
            repositories=clean_repos,
            max_items=max_items,
            active_projects=projects,
        )
        notion_result = self.notion.run(
            database_id=str(notion_database_id or "").strip(),
            query=str(notion_query or "").strip(),
            max_items=max_items,
        )

        self.repository.save()

        source_results = [rss_result, github_result, notion_result]
        signals: list[dict] = []
        context_items: list[dict] = []
        fetched = 0
        raw_saved = 0
        duplicates = 0
        for result in source_results:
            signals.extend(result["signals"])
            context_items.extend(result["context_items"])
            fetched += int(result["fetched"])
            raw_saved += int(result["raw_saved"])
            duplicates += int(result["duplicates"])

        return {
            "fetched": fetched,
            "raw_saved": raw_saved,
            "deduplicated": duplicates,
            "signals": signals,
            "context_items": context_items,
            "sources": {
                "rss": {
                    "feeds": len(feeds),
                    "fetched": rss_result["fetched"],
                    "saved": rss_result["raw_saved"],
                },
                "github": {
                    "repositories": len(clean_repos),
                    "fetched": github_result["fetched"],
                    "saved": github_result["raw_saved"],
                },
                "notion": {
                    "enabled": bool(notion_database_id or notion_query),
                    "fetched": notion_result["fetched"],
                    "saved": notion_result["raw_saved"],
                },
            },
        }
