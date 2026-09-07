"""
Integrations API routes.

Minimal pull/export endpoints so CortexOS can:
- ingest external context (RSS, GitHub, Notion)
- export decisions for Notion distribution
"""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from cortex_core.api.server import get_engine

router = APIRouter(prefix="/integrations", tags=["integrations"])


class PullRequest(BaseModel):
    rss_feeds: list[str] = Field(default_factory=list)
    github_repositories: list[str] = Field(default_factory=list)
    github_topic: str = ""
    notion_database_id: str = ""
    notion_query: str = ""
    max_items: int = 8


class NotionExportRequest(BaseModel):
    limit: int = 20


@router.post("/pull")
async def pull_integrations(body: PullRequest) -> dict:
    """Pull context from RSS/GitHub/Notion and ingest into knowledge notes."""
    engine = get_engine()
    return engine.pull_integration_context(
        rss_feeds=body.rss_feeds or None,
        github_repositories=body.github_repositories or None,
        github_topic=body.github_topic,
        notion_database_id=body.notion_database_id,
        notion_query=body.notion_query,
        max_items=max(1, min(25, body.max_items)),
    )


@router.post("/notion/export-decisions")
async def export_decisions_for_notion(body: NotionExportRequest) -> dict:
    """Export recent decisions as markdown payload for Notion pages."""
    engine = get_engine()
    return engine.export_decisions_for_notion(limit=max(1, min(100, body.limit)))
