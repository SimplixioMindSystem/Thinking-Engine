"""GitHub to CortexOS signal mapping."""

from __future__ import annotations

from cortex_core.integrations.schemas import CortexSignal, RawGitHubItem, fingerprint_from_parts


def _match_project(repo: str, active_projects: list[str]) -> str:
    repo_lower = repo.lower()
    for project in active_projects:
        clean = project.strip()
        if clean and clean.lower() in repo_lower:
            return clean
    return ""


def map_github_to_signal(item: RawGitHubItem, active_projects: list[str]) -> CortexSignal:
    matched_project = _match_project(item.repo, active_projects)

    relevance = 0.6
    if item.item_type == "release":
        relevance = 0.72
    if matched_project:
        relevance = min(relevance + 0.2, 1.0)

    why = "Engineering signal from tracked repository."
    action = "Review impact and decide if it changes active work."
    if item.item_type == "issue":
        why = "Open issue may represent a blocker or risk."
        action = "Triage issue priority for the active roadmap."
    elif item.item_type == "pull_request":
        why = "Open pull request signals implementation progress or dependency change."
        action = "Decide merge/review priority."
    elif item.item_type == "release":
        why = "New release can change dependencies and delivery risk."
        action = "Assess release impact and update plan."

    tags = ["github", item.item_type, item.repo]
    return CortexSignal(
        id=fingerprint_from_parts("github", item.fingerprint()),
        source="github",
        title=f"{item.repo}: {item.title}",
        url=item.url,
        why_it_matters=why,
        next_action=action,
        source_type=item.item_type,
        project=matched_project or item.repo,
        relevance_score=relevance,
        tags=tags,
    )
