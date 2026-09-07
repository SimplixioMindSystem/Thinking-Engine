"""Backend-first MVP integrations for CortexOS.

This package keeps integrations explicit and low-complexity:
- source-specific adapters (rss/github/notion)
- raw payload persistence for audit/trust
- normalized mapping into CortexOS signal/context objects
"""

from __future__ import annotations

from typing import Any

from cortex_core.integrations.schemas import CortexContextItem, CortexSignal
from cortex_core.integrations.service import IntegrationService


def export_decisions_markdown(decisions: list[dict[str, Any]]) -> str:
    """Build a minimal markdown export for decision sharing."""
    lines = ["# CortexOS Decisions Export", ""]
    if not decisions:
        lines.append("_No decisions available._")
        return "\n".join(lines)

    for idx, item in enumerate(decisions, start=1):
        decision = str(item.get("decision", "")).strip()
        reason = str(item.get("reason", "")).strip()
        outcome = str(item.get("outcome", "")).strip()
        project = str(item.get("project", "")).strip()
        lines.append(f"## {idx}. {decision or 'Untitled decision'}")
        if reason:
            lines.append(f"- Why: {reason}")
        if project:
            lines.append(f"- Project: {project}")
        if outcome:
            lines.append(f"- Outcome: {outcome}")
        lines.append("")
    return "\n".join(lines).strip() + "\n"


__all__ = [
    "CortexContextItem",
    "CortexSignal",
    "IntegrationService",
    "export_decisions_markdown",
]
