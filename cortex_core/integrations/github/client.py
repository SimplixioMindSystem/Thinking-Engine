"""GitHub REST client (minimal MVP surface)."""

from __future__ import annotations

import os
from typing import Any

from cortex_core.integrations.schemas import RawGitHubItem

try:
    import requests
except Exception:  # pragma: no cover - optional runtime dependency
    requests = None


GITHUB_BASE_URL = "https://api.github.com"


def _clean(value: Any) -> str:
    return " ".join(str(value or "").split()).strip()


class GitHubClient:
    """Fetches issues, pull requests, and releases for configured repositories."""

    def __init__(self, token: str | None = None):
        self.token = token or os.environ.get("GITHUB_TOKEN", "")

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/vnd.github+json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    def _get(self, path: str, *, params: dict[str, Any]) -> list[dict[str, Any]]:
        if requests is None:
            return []
        url = f"{GITHUB_BASE_URL}{path}"
        try:
            response = requests.get(url, headers=self._headers(), params=params, timeout=20)
            response.raise_for_status()
            payload = response.json()
            return payload if isinstance(payload, list) else []
        except Exception:
            return []

    def fetch_repo_items(self, repo: str, *, max_items: int, since: str = "") -> list[RawGitHubItem]:
        repo = _clean(repo)
        if not repo:
            return []

        rows: list[RawGitHubItem] = []

        issue_params: dict[str, Any] = {
            "state": "open",
            "sort": "updated",
            "direction": "desc",
            "per_page": max_items,
        }
        if since:
            issue_params["since"] = since
        for item in self._get(f"/repos/{repo}/issues", params=issue_params):
            title = _clean(item.get("title", ""))
            if not title:
                continue
            is_pr = "pull_request" in item
            item_type = "pull_request" if is_pr else "issue"
            rows.append(
                RawGitHubItem(
                    repo=repo,
                    item_type=item_type,
                    external_id=_clean(item.get("node_id", "") or item.get("id", "")),
                    url=_clean(item.get("html_url", "")),
                    title=title,
                    summary=_clean(item.get("body", "")),
                    state=_clean(item.get("state", "")),
                    updated_at=_clean(item.get("updated_at", "")),
                    raw_payload=item,
                )
            )

        for release in self._get(
            f"/repos/{repo}/releases",
            params={"per_page": min(max_items, 10)},
        ):
            title = _clean(release.get("name", "") or release.get("tag_name", ""))
            if not title:
                continue
            rows.append(
                RawGitHubItem(
                    repo=repo,
                    item_type="release",
                    external_id=_clean(release.get("node_id", "") or release.get("id", "")),
                    url=_clean(release.get("html_url", "")),
                    title=title,
                    summary=_clean(release.get("body", "")),
                    state="published",
                    updated_at=_clean(release.get("published_at", "") or release.get("created_at", "")),
                    raw_payload=release,
                )
            )

        return rows
