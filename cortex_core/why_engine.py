"""
Why Engine
-----------
The atomic unit of CortexOS intelligence.

Given ONE source item and the user's full context (goals, projects,
recent decisions, research themes), produce a structured decision
object that answers:

  1. Why does this matter?
  2. How does it affect the user's active project(s)?
  3. Does it confirm or contradict prior assumptions?
  4. What exact next action should be taken?
  5. Can it safely be ignored?

This is the wedge. Summaries are commodity. Decision intelligence
is the product.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime

from cortex_core.scoring import tokenize

# ── Input ───────────────────────────────────────────────────────


@dataclass
class SourceItem:
    """A single piece of incoming information to evaluate."""

    title: str = ""
    content: str = ""
    source_type: str = ""  # article, note, link, digest_item, project_update
    url: str = ""
    tags: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> SourceItem:
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


# ── Output ──────────────────────────────────────────────────────


@dataclass
class DecisionResult:
    """The Why Engine's structured output for a single item."""

    summary: str = ""
    why_it_matters: str = ""
    impact_on_active_project: str = ""
    contradiction_or_confirmation: str = ""  # "supports", "contradicts", "unclear"
    recommended_action: str = ""
    ignore_or_watch: str = ""  # "act_now", "watch", "ignore"
    confidence: float = 0.0  # 0.0—1.0
    tags: list[str] = field(default_factory=list)
    evaluated_at: str = field(
        default_factory=lambda: datetime.now(UTC).isoformat(),
    )

    def to_dict(self) -> dict:
        return asdict(self)


# ── Context bundle (passed from engine, not stored) ─────────────


@dataclass
class EvaluationContext:
    """Snapshot of user context for the Why Engine to reason against."""

    goals: list[str] = field(default_factory=list)
    interests: list[str] = field(default_factory=list)
    current_projects: list[str] = field(default_factory=list)
    ignored_topics: list[str] = field(default_factory=list)
    project_milestones: list[str] = field(default_factory=list)
    project_blockers: list[str] = field(default_factory=list)
    recent_decisions: list[str] = field(default_factory=list)
    recent_themes: list[str] = field(default_factory=list)
    assumptions: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> EvaluationContext:
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})


# ── Why Engine ──────────────────────────────────────────────────


class WhyEngine:
    """Evaluates a single source item against the user's full context.

    Pure logic — no I/O, no LLM calls, no side effects.
    All context is passed in explicitly, making it fully testable.
    """

    def evaluate(
        self,
        item: SourceItem,
        context: EvaluationContext,
    ) -> DecisionResult:
        """Produce a structured decision for *item* given *context*."""
        item_tokens = _item_tokens(item)

        # 1. Relevance score against goals and interests
        goal_tokens = _tokens_from_list(context.goals + context.current_projects)
        interest_tokens = _tokens_from_list(context.interests)
        goal_overlap = _overlap_ratio(item_tokens, goal_tokens)
        interest_overlap = _overlap_ratio(item_tokens, interest_tokens)

        # 2. Ignored-topic check
        ignored_tokens = _tokens_from_list(context.ignored_topics)
        noise_overlap = _overlap_ratio(item_tokens, ignored_tokens)

        # 3. Project impact
        project_tokens = _tokens_from_list(
            context.project_milestones + context.project_blockers,
        )
        project_overlap = _overlap_ratio(item_tokens, project_tokens)

        # 4. Contradiction / confirmation
        prior_tokens = _tokens_from_list(
            context.recent_decisions + context.assumptions + context.recent_themes,
        )
        stance = _detect_stance(item_tokens, prior_tokens, item.content)

        # 5. Composite confidence
        confidence = _compute_confidence(
            goal_overlap,
            interest_overlap,
            project_overlap,
            noise_overlap,
        )

        # 6. Triage: act_now / watch / ignore
        triage = _triage(confidence, noise_overlap, goal_overlap, project_overlap)

        # 7. Build result
        return DecisionResult(
            summary=_build_summary(item),
            why_it_matters=_why_it_matters(
                item,
                goal_overlap,
                interest_overlap,
                project_overlap,
                context,
            ),
            impact_on_active_project=_project_impact(
                item,
                project_overlap,
                context,
            ),
            contradiction_or_confirmation=stance,
            recommended_action=_recommended_action(triage, item, context),
            ignore_or_watch=triage,
            confidence=round(confidence, 2),
            tags=_derive_tags(item, context),
        )


# ── Pure helper functions ───────────────────────────────────────


def _item_tokens(item: SourceItem) -> set[str]:
    """Extract searchable tokens from a source item."""
    text = f"{item.title} {item.content} {' '.join(item.tags)}"
    return set(tokenize(text))


def _tokens_from_list(items: list[str]) -> set[str]:
    """Tokenize a list of strings into one set."""
    return set(tokenize(" ".join(items))) if items else set()


def _overlap_ratio(a: set[str], b: set[str]) -> float:
    """Fraction of *b* tokens found in *a*. Returns 0 if *b* is empty."""
    if not b:
        return 0.0
    return len(a & b) / len(b)


def _detect_stance(
    item_tokens: set[str],
    prior_tokens: set[str],
    content: str,
) -> str:
    """Lightweight contradiction/confirmation detection.

    v1 heuristic:
    - If item overlaps strongly with prior context → "supports"
    - If item contains contrary signal words → "contradicts"
    - Otherwise → "unclear"
    """
    if not prior_tokens:
        return "unclear"

    overlap = _overlap_ratio(item_tokens, prior_tokens)

    # Check for contradiction signal words in content
    contrary_signals = {
        "however",
        "but",
        "contrary",
        "wrong",
        "incorrect",
        "overestimated",
        "underestimated",
        "failed",
        "disproven",
        "flawed",
        "misleading",
        "myth",
        "debunked",
        "reconsidered",
        "pivot",
        "reversal",
        "abandoned",
        "deprecated",
    }
    content_tokens = set(tokenize(content.lower())) if content else set()
    has_contrary = bool(content_tokens & contrary_signals)

    if has_contrary and overlap > 0.1:
        return "contradicts"
    if overlap > 0.2:
        return "supports"
    return "unclear"


def _compute_confidence(
    goal_overlap: float,
    interest_overlap: float,
    project_overlap: float,
    noise_overlap: float,
) -> float:
    """Weighted confidence score in [0, 1]."""
    raw = 0.40 * goal_overlap + 0.25 * interest_overlap + 0.25 * project_overlap - 0.30 * noise_overlap
    return max(0.0, min(1.0, raw))


def _triage(
    confidence: float,
    noise: float,
    goal_overlap: float,
    project_overlap: float,
) -> str:
    """Decide: act_now, watch, or ignore."""
    if noise > 0.3:
        return "ignore"
    if confidence >= 0.3 or goal_overlap > 0.3 or project_overlap > 0.3:
        return "act_now"
    if confidence >= 0.1:
        return "watch"
    return "ignore"


def _build_summary(item: SourceItem) -> str:
    """One-line summary from the item's available content."""
    if item.content and len(item.content) > 20:
        # Take first sentence or first 200 chars
        first_sentence = item.content.split(".")[0].strip()
        if len(first_sentence) > 200:
            return first_sentence[:197] + "..."
        return first_sentence + "." if not first_sentence.endswith(".") else first_sentence
    return item.title


def _why_it_matters(
    item: SourceItem,
    goal_overlap: float,
    interest_overlap: float,
    project_overlap: float,
    context: EvaluationContext,
) -> str:
    """Generate the 'why it matters' explanation."""
    reasons: list[str] = []

    if goal_overlap > 0.2:
        matched_goals = _matched_items(item, context.goals)
        if matched_goals:
            reasons.append(f"Aligns with goals: {', '.join(matched_goals[:2])}")

    if project_overlap > 0.2:
        reasons.append(
            f"Relevant to {context.current_projects[0]}" if context.current_projects else "Relevant to active project"
        )

    if interest_overlap > 0.2:
        matched = _matched_items(item, context.interests)
        if matched:
            reasons.append(f"Touches interests: {', '.join(matched[:2])}")

    if not reasons:
        if goal_overlap > 0 or interest_overlap > 0:
            reasons.append("Has peripheral relevance to your current focus.")
        else:
            reasons.append("Low relevance to current goals and projects.")

    return " ".join(reasons)


def _project_impact(
    item: SourceItem,
    project_overlap: float,
    context: EvaluationContext,
) -> str:
    """Assess impact on the active project."""
    if project_overlap <= 0.05:
        return "No direct impact on active project detected."

    parts: list[str] = []
    item_tokens = _item_tokens(item)

    # Check blocker relevance
    for blocker in context.project_blockers:
        blocker_tokens = set(tokenize(blocker))
        if item_tokens & blocker_tokens:
            parts.append(f"May help resolve blocker: '{blocker}'")
            break

    # Check milestone relevance
    for milestone in context.project_milestones:
        milestone_tokens = set(tokenize(milestone))
        if item_tokens & milestone_tokens:
            parts.append(f"Relevant to milestone: '{milestone}'")
            break

    if not parts:
        project = context.current_projects[0] if context.current_projects else "active project"
        parts.append(f"Has keyword overlap with {project} context ({project_overlap:.0%} match).")

    return " ".join(parts)


def _recommended_action(
    triage: str,
    item: SourceItem,
    context: EvaluationContext,
) -> str:
    """Concrete next action based on triage result."""
    if triage == "ignore":
        return "Skip — not relevant to current priorities."
    if triage == "watch":
        return "Bookmark for later review. Revisit if the topic gains momentum."
    # act_now
    if item.source_type in ("article", "link"):
        return "Read in full, extract key insight, and link to project notes."
    if item.source_type == "project_update":
        return "Review impact on current milestone and update project memory."
    return "Review, extract actionable insight, and decide next step."


def _matched_items(item: SourceItem, candidates: list[str]) -> list[str]:
    """Return candidates whose tokens overlap with the item."""
    item_tokens = _item_tokens(item)
    return [c for c in candidates if set(tokenize(c)) & item_tokens]


def _derive_tags(item: SourceItem, context: EvaluationContext) -> list[str]:
    """Combine item tags with any matched interest/goal tags."""
    tags = list(item.tags)
    item_tokens = _item_tokens(item)
    for interest in context.interests:
        interest_tok = set(tokenize(interest))
        if interest_tok & item_tokens and interest.lower() not in tags:
            tags.append(interest.lower())
    return tags[:8]  # cap at 8 tags
