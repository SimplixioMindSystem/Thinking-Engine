"""GitHub sync orchestration."""

from __future__ import annotations

from cortex_core.integrations.github.client import GitHubClient
from cortex_core.integrations.github.mapper import map_github_to_signal
from cortex_core.integrations.repositories import IntegrationRepository


class GitHubSync:
    def __init__(self, repository: IntegrationRepository, client: GitHubClient | None = None):
        self.repository = repository
        self.client = client or GitHubClient()

    def run(self, *, repositories: list[str], max_items: int, active_projects: list[str]) -> dict:
        all_raw = 0
        duplicates = 0
        signals: list[dict] = []

        for repo_name in repositories:
            clean_repo = str(repo_name or "").strip()
            if not clean_repo:
                continue
            cursor = self.repository.get_cursor("github", clean_repo.lower())
            raw_items = self.client.fetch_repo_items(clean_repo, max_items=max_items, since=cursor)
            all_raw += len(raw_items)

            latest_seen = cursor
            for item in raw_items:
                fingerprint = item.fingerprint()
                if self.repository.has_seen("github", fingerprint):
                    duplicates += 1
                    continue
                self.repository.append_raw(
                    source="github",
                    kind=item.item_type,
                    external_id=item.external_id,
                    fingerprint=fingerprint,
                    payload=item.to_dict(),
                )
                signals.append(map_github_to_signal(item, active_projects).to_dict())
                if item.updated_at and item.updated_at > latest_seen:
                    latest_seen = item.updated_at

            if latest_seen:
                self.repository.set_cursor("github", clean_repo.lower(), latest_seen)

        self.repository.mark_synced("github")
        return {
            "source": "github",
            "fetched": all_raw,
            "raw_saved": all_raw - duplicates,
            "duplicates": duplicates,
            "signals": signals,
            "context_items": [],
        }
