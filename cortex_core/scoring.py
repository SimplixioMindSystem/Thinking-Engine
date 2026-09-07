"""
Scoring Engine
---------------
Scores articles and knowledge items by AI relevance, signal
strength, context overlap, and project fit. This is the core
intelligence that separates CortexOS from a dumb news feed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# ── Keyword dictionaries ───────────────────────────────────────

AI_KEYWORDS: set[str] = {
    "ai",
    "artificial",
    "intelligence",
    "model",
    "models",
    "llm",
    "llms",
    "agent",
    "agents",
    "context",
    "prompt",
    "prompts",
    "embedding",
    "embeddings",
    "inference",
    "training",
    "reasoning",
    "vision",
    "nlp",
    "robotics",
    "rag",
    "retrieval",
    "transformer",
    "diffusion",
    "gpt",
    "claude",
    "gemini",
    "anthropic",
    "openai",
    "deepmind",
    "meta ai",
    "fine-tuning",
    "fine tuning",
    "finetuning",
    "vector",
    "orchestration",
    "hallucination",
    "grounding",
    "evaluation",
    "benchmark",
}

HIGH_SIGNAL_KEYWORDS: set[str] = {
    "ai",
    "agent",
    "agents",
    "context",
    "model",
    "models",
    "reasoning",
    "robotics",
    "developer",
    "infrastructure",
    "evaluation",
    "security",
    "ethics",
    "governance",
    "productivity",
    "retrieval",
    "knowledge",
    "learning",
    "architecture",
    "pipeline",
    "observability",
    "system",
    "framework",
    "tool",
    "workflow",
    "automation",
}

NOISE_KEYWORDS: set[str] = {
    "spotify",
    "spielberg",
    "facebook",
    "headphone",
    "headphones",
    "digg",
    "celebrity",
    "gossip",
    "tiktok",
    "instagram",
    "dating",
    "reality tv",
    "kardashian",
}

TOKEN_PATTERN = re.compile(r"[a-zA-Z0-9]+")
ARTICLE_PATTERN = re.compile(r"^- \[(.*?)\]\((.*?)\)", re.MULTILINE)


def tokenize(text: str) -> list[str]:
    return TOKEN_PATTERN.findall(text.lower())


def contains_keyword(text: str, keywords: set[str]) -> bool:
    text_lower = text.lower()
    return any(kw in text_lower for kw in keywords)


# ── Actionability keywords ──────────────────────────────────────

ACTIONABLE_KEYWORDS: set[str] = {
    "launch",
    "release",
    "open source",
    "open-source",
    "api",
    "sdk",
    "framework",
    "tool",
    "library",
    "tutorial",
    "guide",
    "how to",
    "how-to",
    "build",
    "deploy",
    "implement",
    "integrate",
    "migrate",
    "upgrade",
    "available",
    "announced",
    "shipped",
    "developer preview",
}


# ── Per-article scoring ────────────────────────────────────────


@dataclass
class ArticleScore:
    """Score for a single article across four dimensions.

    Dimensions:
      - ai_relevance: how related to AI/ML topics
      - project_relevance: how relevant to user's active goals/projects
      - novelty: how new/unseen this topic is
      - actionability: whether this leads to concrete action
      - noise: penalty for irrelevant content
      - composite: weighted final score
    """

    title: str
    url: str = ""
    ai_relevance: float = 0.0
    project_relevance: float = 0.0
    novelty: float = 0.0
    actionability: float = 0.0
    noise: float = 0.0
    composite: float = 0.0
    # Legacy aliases — kept for backward compat in existing tests
    ai_related: float = 0.0
    high_signal: float = 0.0
    context_overlap: float = 0.0

    def to_dict(self) -> dict:
        return {
            "title": self.title,
            "url": self.url,
            "ai_relevance": round(self.ai_relevance, 3),
            "project_relevance": round(self.project_relevance, 3),
            "novelty": round(self.novelty, 3),
            "actionability": round(self.actionability, 3),
            "noise": self.noise,
            "composite": round(self.composite, 3),
            # Legacy keys for backward compat
            "ai_related": self.ai_related,
            "high_signal": self.high_signal,
            "context_overlap": round(self.context_overlap, 3),
        }


def score_article(
    title: str,
    url: str,
    context_tokens: set[str],
    *,
    seen_titles: set[str] | None = None,
    ignored_topics: set[str] | None = None,
    goal_tokens: set[str] | None = None,
) -> ArticleScore:
    """Score a single article across four dimensions + noise.

    Dimensions:
      ai_relevance (0.25): AI/ML keyword match
      project_relevance (0.35): overlap with user goals/projects
      novelty (0.20): not previously seen
      actionability (0.20): actionable keywords present
    """
    title_lower = title.lower()
    title_tokens = set(tokenize(title_lower))
    _seen = seen_titles or set()
    _ignored = ignored_topics or set()
    _goals = goal_tokens or context_tokens

    # Dimension 1: AI relevance (granular, not binary)
    ai_matches = sum(1 for kw in AI_KEYWORDS if kw in title_lower)
    ai_relevance = min(ai_matches / 3.0, 1.0)  # 3+ matches = 1.0

    # Dimension 2: Project relevance (goal + interest overlap)
    goal_overlap = len(title_tokens & _goals) / max(len(title_tokens), 1)
    context_overlap = len(title_tokens & context_tokens) / max(len(title_tokens), 1)
    project_relevance = min((goal_overlap * 0.6 + context_overlap * 0.4) * 1.5, 1.0)

    # Dimension 3: Novelty (have we seen this before?)
    novelty = 0.0 if title_lower.strip() in _seen else 1.0

    # Dimension 4: Actionability (does this lead to concrete action?)
    action_matches = sum(1 for kw in ACTIONABLE_KEYWORDS if kw in title_lower)
    actionability = min(action_matches / 2.0, 1.0)  # 2+ matches = 1.0

    # Noise detection (including user-defined ignored topics)
    is_noise = contains_keyword(title_lower, NOISE_KEYWORDS)
    is_ignored = any(ig in title_lower for ig in _ignored) if _ignored else False
    noise = 1.0 if (is_noise or is_ignored) else 0.0

    # Legacy: high_signal (kept for backward compat)
    high_signal = 1.0 if contains_keyword(title_lower, HIGH_SIGNAL_KEYWORDS) else 0.0

    # Weighted composite
    composite = 0.35 * project_relevance + 0.25 * ai_relevance + 0.20 * novelty + 0.20 * actionability - 0.10 * noise

    return ArticleScore(
        title=title,
        url=url,
        ai_relevance=ai_relevance,
        project_relevance=round(project_relevance, 3),
        novelty=novelty,
        actionability=actionability,
        noise=noise,
        composite=max(0.0, composite),
        # Legacy fields
        ai_related=1.0 if ai_relevance > 0 else 0.0,
        high_signal=high_signal,
        context_overlap=round(context_overlap, 3),
    )


# ── Digest-level evaluation ────────────────────────────────────


@dataclass
class DigestScore:
    """Aggregate metrics for a full digest."""

    total_articles: int = 0
    ai_article_ratio: float = 0.0
    high_signal_ratio: float = 0.0
    signal_to_noise_ratio: float = 0.0
    context_keyword_coverage: float = 0.0
    project_fit_score: float = 0.0
    articles: list[ArticleScore] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "total_articles": self.total_articles,
            "ai_article_ratio": round(self.ai_article_ratio, 3),
            "high_signal_ratio": round(self.high_signal_ratio, 3),
            "signal_to_noise_ratio": round(self.signal_to_noise_ratio, 3),
            "context_keyword_coverage": round(self.context_keyword_coverage, 3),
            "project_fit_score": round(self.project_fit_score, 3),
            "articles": [a.to_dict() for a in self.articles],
        }


def evaluate_digest(
    markdown_text: str,
    context_snippets: list[str],
    *,
    seen_titles: set[str] | None = None,
    ignored_topics: set[str] | None = None,
    goal_tokens: set[str] | None = None,
) -> DigestScore:
    """Score an entire digest markdown file."""
    matches = ARTICLE_PATTERN.findall(markdown_text)

    if not matches:
        return DigestScore()

    # Build context token set from user context snippets
    context_tokens: set[str] = set()
    for snippet in context_snippets:
        context_tokens.update(tokenize(snippet))

    scores = [
        score_article(
            title,
            url,
            context_tokens,
            seen_titles=seen_titles,
            ignored_topics=ignored_topics,
            goal_tokens=goal_tokens,
        )
        for title, url in matches
    ]

    total = len(scores)
    ai_count = sum(1 for s in scores if s.ai_related > 0)
    signal_count = sum(1 for s in scores if s.high_signal > 0)
    noise_count = sum(1 for s in scores if s.noise > 0)

    # Digest-level keyword coverage
    digest_tokens: set[str] = set()
    for title, _ in matches:
        digest_tokens.update(tokenize(title))
    matched_context = context_tokens & digest_tokens
    coverage = len(matched_context) / max(len(context_tokens), 1)

    ai_ratio = ai_count / total
    signal_ratio = signal_count / total
    sn_ratio = signal_count / max(noise_count, 1)

    fit = 0.40 * ai_ratio + 0.35 * signal_ratio + 0.15 * min(sn_ratio / 3, 1.0) + 0.10 * coverage

    return DigestScore(
        total_articles=total,
        ai_article_ratio=ai_ratio,
        high_signal_ratio=signal_ratio,
        signal_to_noise_ratio=sn_ratio,
        context_keyword_coverage=coverage,
        project_fit_score=fit,
        articles=sorted(scores, key=lambda s: s.composite, reverse=True),
    )


def filter_high_signal(digest_score: DigestScore, threshold: float = 0.3) -> list[ArticleScore]:
    """Return only articles above the composite threshold."""
    return [a for a in digest_score.articles if a.composite >= threshold]
