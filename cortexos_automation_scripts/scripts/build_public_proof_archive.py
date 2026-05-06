#!/usr/bin/env python3
"""Build the committed SimpliXio public proof archive.

The archive is intentionally simple: it points to public-safe proof surfaces
without copying private runtime output into the repo.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
PROOF_DIR = REPO_ROOT / "docs" / "public-proof"
DECISION_EXAMPLES_MANIFEST = REPO_ROOT / "docs" / "decision-examples" / "decision_examples.json"


PROOF_SECTIONS: list[dict[str, str]] = [
    {
        "title": "Decision Examples",
        "slug": "decision-examples",
        "description": "Public-safe examples showing messy input becoming signals, ignored noise, 3 priorities, why, and action.",
        "source_type": "synthetic_public_safe_examples",
        "path": "../decision-examples/index.md",
        "cta": "Read the Decision Examples.",
    },
    {
        "title": "Changelog",
        "slug": "changelog",
        "description": "Release notes that explain what changed, why it matters, and what users can do next.",
        "source_type": "release_notes",
        "path": "changelog/README.md",
        "cta": "Use meaningful releases as proof.",
    },
    {
        "title": "Weekly Review",
        "slug": "weekly-review",
        "description": "Public-safe weekly summaries of what repeated, what mattered, what was ignored, and what comes next.",
        "source_type": "weekly_review",
        "path": "weekly-review/README.md",
        "cta": "Turn weekly learning into visible proof.",
    },
    {
        "title": "Decision Replay",
        "slug": "decision-replay",
        "description": "Examples showing which signals were reviewed, kept, ignored, and turned into final priorities.",
        "source_type": "decision_replay",
        "path": "decision-replay/README.md",
        "cta": "Show why priorities surfaced.",
    },
    {
        "title": "Newsletter Examples",
        "slug": "newsletter-examples",
        "description": "Public-safe newsletter drafts generated from reviews, replays, product lessons, and approved examples.",
        "source_type": "newsletter",
        "path": "newsletter-examples/README.md",
        "cta": "Turn private thinking into a safe public lesson.",
    },
]


def load_decision_examples() -> list[dict[str, Any]]:
    if not DECISION_EXAMPLES_MANIFEST.exists():
        return []
    try:
        payload = json.loads(DECISION_EXAMPLES_MANIFEST.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    examples = payload.get("examples", [])
    return examples if isinstance(examples, list) else []


def top_decision_examples(examples: list[dict[str, Any]]) -> list[dict[str, str]]:
    wanted_slugs = [
        "how-to-prioritize-startup-ideas",
        "how-to-turn-github-issues-into-priorities",
        "how-to-review-your-week-as-a-solo-founder",
    ]
    by_slug = {str(item.get("slug", "")): item for item in examples}
    selected: list[dict[str, str]] = []
    for slug in wanted_slugs:
        item = by_slug.get(slug)
        if not item:
            continue
        selected.append(
            {
                "title": str(item.get("title", "")),
                "slug": slug,
                "description": str(item.get("meta_description", "")),
                "category": str(item.get("category", "")),
                "path": "../decision-examples/" + slug + ".md",
            }
        )
    return selected


def render_archive(sections: list[dict[str, str]], featured_examples: list[dict[str, str]]) -> str:
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    lines = [
        "---",
        'title: "SimpliXio Public Proof"',
        'meta_description: "Public-safe proof showing how SimpliXio turns scattered thoughts and project noise into 3 priorities and one next action."',
        'canonical_path: "/public-proof"',
        'public_safe_status: "public_safe"',
        f'generated_at: "{today}"',
        "---",
        "",
        "# SimpliXio Public Proof",
        "",
        "Public-safe proof that SimpliXio is real, useful, improving, and trustworthy.",
        "",
        "Core loop:",
        "",
        "```text",
        "messy input -> filtered signal -> 3 priorities -> why -> next action -> public-safe proof",
        "```",
        "",
        "Private context stays private. Public proof is filtered, redacted, and approved before publishing.",
        "",
        "## Proof Surfaces",
        "",
        "| Surface | Description | Source type | Status | CTA |",
        "| --- | --- | --- | --- | --- |",
    ]
    for section in sections:
        lines.append(
            f"| [{section['title']}]({section['path']}) | {section['description']} | `{section['source_type']}` | `public_safe` | {section['cta']} |"
        )

    lines.extend(
        [
            "",
            "## Featured Desire Loop Examples",
            "",
            "These are the first three examples to use in App Store copy, Discord posts, newsletter angles, and warm outreach.",
            "",
        ]
    )
    for example in featured_examples:
        lines.extend(
            [
                f"### [{example['title']}]({example['path']})",
                "",
                f"- Category: {example['category']}",
                f"- Why it matters: {example['description']}",
                "- CTA: Turn scattered thoughts into 3 priorities and one next action.",
                "",
            ]
        )

    lines.extend(
        [
            "## Publishing Rules",
            "",
            "- No private raw notes.",
            "- No confidential details.",
            "- No fake users, fake traction, or fake revenue.",
            "- No autopublish.",
            "- Human approval stays required.",
            "- If unsure, redact or reject.",
            "",
            "## Desire Loop",
            "",
            "Use the operating plan in [SimpliXio Desire Loop](../desire-loop.md) to decide what proof to create, what to publish, and what to postpone.",
            "",
        ]
    )
    return "\n".join(lines)


def render_surface_readme(section: dict[str, str]) -> str:
    return "\n".join(
        [
            f"# {section['title']}",
            "",
            section["description"],
            "",
            "## Required Metadata",
            "",
            "- title",
            "- short description",
            "- category",
            "- generated_at or published_at",
            "- public-safe status",
            "- source type",
            "- CTA",
            "",
            "## Safety Standard",
            "",
            "Private by default. Public-safe only after redaction. No autopublish.",
            "",
        ]
    )


def build_archive(output_dir: Path = PROOF_DIR) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    for section in PROOF_SECTIONS:
        if section["slug"] == "decision-examples":
            continue
        section_dir = output_dir / section["slug"]
        section_dir.mkdir(parents=True, exist_ok=True)
        (section_dir / "README.md").write_text(render_surface_readme(section), encoding="utf-8")

    examples = load_decision_examples()
    featured = top_decision_examples(examples)
    index_path = output_dir / "index.md"
    manifest_path = output_dir / "proof_manifest.json"

    index_path.write_text(render_archive(PROOF_SECTIONS, featured), encoding="utf-8")
    manifest = {
        "generated_at": datetime.now(UTC).replace(microsecond=0).isoformat(),
        "status": "public_safe",
        "proof_surface_count": len(PROOF_SECTIONS),
        "featured_examples": featured,
        "surfaces": PROOF_SECTIONS,
        "publishing_rules": {
            "autopublish": False,
            "manual_approval_required": True,
            "private_material_allowed": False,
        },
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return {
        "status": "ok",
        "index": str(index_path),
        "manifest": str(manifest_path),
        "proof_surface_count": len(PROOF_SECTIONS),
        "featured_example_count": len(featured),
    }


def main() -> int:
    payload = build_archive()
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
