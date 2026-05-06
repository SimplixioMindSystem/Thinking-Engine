#!/usr/bin/env python3
"""Build public-safe Decision Example pages for SimpliXio.

Decision Examples are Ludwig-inspired acquisition assets:
they target frequent micro-pains and show a concrete transformation from
messy inputs into 3 priorities, why they matter, and one next action.

The examples in this file are synthetic, public-safe examples. They do not
claim to be user data.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

GENERATED_DATE = "2026-05-06"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "docs" / "decision-examples"

HYPE_WORDS = {
    "ai productivity platform",
    "cutting-edge",
    "game changer",
    "next-gen",
    "revolutionary",
    "seamless",
    "supercharge",
    "transform your life",
    "unlock",
}

SENSITIVE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", re.IGNORECASE),
    re.compile(r"https?://\S+", re.IGNORECASE),
    re.compile(r"\b(api[_ -]?key|password|token|secret|credential|private key)\b", re.IGNORECASE),
    re.compile(r"\b(confidential|do not publish|client name|employer name)\b", re.IGNORECASE),
)


@dataclass(frozen=True)
class Priority:
    title: str
    why: str
    action: str


@dataclass(frozen=True)
class DecisionExample:
    title: str
    slug: str
    category: str
    meta_description: str
    pain: str
    messy_input: str
    signals_detected: list[str]
    ignored_noise: list[str]
    priorities: list[Priority]
    practical_takeaway: str
    cta: str = "Turn scattered thoughts into 3 priorities and one next action."
    source_note: str = "Synthetic public-safe example."
    public_safe_status: str = "public_safe"
    generated_at: str = GENERATED_DATE

    @property
    def canonical_path(self) -> str:
        return f"/decision-examples/{self.slug}"


DECISION_EXAMPLES: list[DecisionExample] = [
    DecisionExample(
        title="How to Decide What to Work on Today",
        slug="how-to-decide-what-to-work-on-today",
        category="Founder Focus",
        meta_description="A practical example showing how scattered thoughts and open loops can become 3 priorities and one clear next action.",
        pain="You have a full day, too many inputs, and no obvious first move.",
        messy_input=(
            "I need to fix onboarding, answer feedback, review the macOS screenshots, write a release note, "
            "and maybe start the next feature. Everything feels important, so I keep switching."
        ),
        signals_detected=[
            "onboarding clarity is blocking first-use value",
            "App Store proof still needs current product screenshots",
            "release communication needs one clear message",
            "new feature work is less urgent than trust and conversion",
        ],
        ignored_noise=[
            "starting another feature before fixing the first-use moment",
            "checking every minor setting label again",
            "rewriting the whole roadmap instead of choosing today's bottleneck",
        ],
        priorities=[
            Priority(
                title="Make onboarding show the value faster",
                why="Users cannot want SimpliXio if the first screen does not make 3 priorities, why, and action obvious.",
                action="Rewrite the first onboarding moment around one messy input becoming 3 priorities.",
            ),
            Priority(
                title="Update the screenshots with real app surfaces",
                why="Screenshots are the first proof that the product is real and useful, especially after App Store review feedback.",
                action="Use current iPhone and macOS screens that show priorities, why, action, and trust.",
            ),
            Priority(
                title="Write one release note with the core promise",
                why="A focused release note turns shipped work into proof instead of invisible effort.",
                action="Publish one short note that explains what changed and why it helps users decide faster.",
            ),
        ],
        practical_takeaway="When everything feels important, choose the bottleneck that makes the product easier to understand, trust, or use today.",
    ),
    DecisionExample(
        title="How to Prioritize Startup Ideas",
        slug="how-to-prioritize-startup-ideas",
        category="Startup Prioritization",
        meta_description="See how a messy list of startup ideas can be filtered into 3 priorities, clear reasoning, and one next action.",
        pain="You have several promising ideas, but no evidence about which one deserves attention now.",
        messy_input=(
            "I could build a founder newsletter tool, a GitHub prioritisation tool, a habit tracker, or an AI note app. "
            "The GitHub angle feels sharper, but the newsletter idea might be easier to explain."
        ),
        signals_detected=[
            "the GitHub angle has a clearer audience and sharper pain",
            "the newsletter idea is understandable but risks becoming broad",
            "the habit tracker does not reinforce the SimpliXio wedge",
            "the note app framing creates category confusion",
        ],
        ignored_noise=[
            "choosing the idea with the largest imagined market",
            "building a generic note product",
            "optimising for novelty before evidence",
        ],
        priorities=[
            Priority(
                title="Test the GitHub prioritisation angle",
                why="It maps directly to project noise, builder pain, and the promise of turning signals into 3 priorities.",
                action="Write one landing section and one Decision Example about turning GitHub issues into priorities.",
            ),
            Priority(
                title="Keep the newsletter idea as a proof layer",
                why="Newsletter output is useful when it comes from real decisions, but it should not become the product category.",
                action="Position newsletter drafts as public-safe proof, not as the main product.",
            ),
            Priority(
                title="Reject ideas that dilute the wedge",
                why="Every broad idea increases messaging cost and makes the product harder to want.",
                action="Park habit tracking and generic notes until the decision system has real traction.",
            ),
        ],
        practical_takeaway="The best startup idea is not always the biggest idea. It is the one with the clearest pain, audience, and next proof step.",
    ),
    DecisionExample(
        title="How to Choose the Next Feature to Build",
        slug="how-to-choose-the-next-feature-to-build",
        category="Product Decisions",
        meta_description="A product decision example showing how feature noise becomes 3 priorities and one practical build step.",
        pain="You have more feature ideas than engineering capacity.",
        messy_input=(
            "Users might need Notion import, better widgets, a Discord community, a macOS menu bar capture window, "
            "and a better newsletter flow. I do not know which one actually moves the product forward."
        ),
        signals_detected=[
            "capture access improves the core loop",
            "newsletter flow supports proof but not first-use value",
            "Notion import improves context later but adds setup complexity",
            "Discord helps distribution only after proof quality is strong",
        ],
        ignored_noise=[
            "adding all integrations at once",
            "shipping a broad settings panel",
            "treating community setup as a product substitute",
        ],
        priorities=[
            Priority(
                title="Improve capture access first",
                why="SimpliXio only gets better when signals enter the system easily where thoughts happen.",
                action="Add or refine the fastest capture entry point already supported by the app.",
            ),
            Priority(
                title="Polish the newsletter safety flow",
                why="Public output only builds trust if safety, redaction, and approval are visible.",
                action="Make the newsletter workbench show source, safety status, and copy/export clearly.",
            ),
            Priority(
                title="Postpone broad imports",
                why="Imports can add signal, but they also add noise and setup before the core value is obvious.",
                action="Document Notion and GitHub as next integration candidates, not this release's main build.",
            ),
        ],
        practical_takeaway="Choose the feature that strengthens the core loop before choosing the feature that expands the surface area.",
    ),
    DecisionExample(
        title="How to Stop Overthinking Product Decisions",
        slug="how-to-stop-overthinking-product-decisions",
        category="Product Decisions",
        meta_description="A concrete example for reducing product decision loops into 3 priorities, why they matter, and one next action.",
        pain="You keep revisiting the same decision without making the next move.",
        messy_input=(
            "I keep comparing onboarding copy, homepage positioning, screenshot order, and pricing language. "
            "Each version seems plausible, so I keep reopening the same decision."
        ),
        signals_detected=[
            "the decision lacks a single success criterion",
            "copy debates are hiding a conversion question",
            "pricing can wait until trial intent is clearer",
            "screenshot order matters because users need value in seconds",
        ],
        ignored_noise=[
            "rewriting every headline again",
            "debating pricing before users understand the product",
            "collecting more opinions without a test",
        ],
        priorities=[
            Priority(
                title="Pick one success criterion",
                why="A decision becomes easier when it is tied to one measurable outcome instead of personal preference.",
                action="Use 'understand SimpliXio in under 5 seconds' as the criterion for this pass.",
            ),
            Priority(
                title="Run the screenshot order test",
                why="Screenshots show whether the promise is concrete before users install the app.",
                action="Compare the first three screenshots against the sequence: what matters, why, next action.",
            ),
            Priority(
                title="Defer pricing language",
                why="Pricing cannot fix a product that is not yet instantly understood.",
                action="Keep one simple pricing note and revisit after onboarding and screenshots improve.",
            ),
        ],
        practical_takeaway="Overthinking usually means the decision does not have a clear constraint. Add the constraint, then choose.",
    ),
    DecisionExample(
        title="How to Turn Scattered Notes Into Action",
        slug="how-to-turn-scattered-notes-into-action",
        category="Founder Focus",
        meta_description="A decision example showing how scattered notes become filtered signals, 3 priorities, and one concrete action.",
        pain="Your notes keep growing, but your next action is not getting clearer.",
        messy_input=(
            "I have notes about acquisition, Discord, screenshots, onboarding, privacy, and GitHub examples. "
            "They all seem useful, but the note list is becoming another backlog."
        ),
        signals_detected=[
            "onboarding and screenshots are both about first understanding",
            "privacy and GitHub examples are both about trust",
            "Discord depends on having proof worth posting",
            "the notes need grouping by outcome, not topic",
        ],
        ignored_noise=[
            "turning every note into a task",
            "creating a large folder taxonomy",
            "posting proof before the proof is concrete",
        ],
        priorities=[
            Priority(
                title="Group notes by outcome",
                why="Outcome grouping reveals repeated bottlenecks that a flat note list hides.",
                action="Label each note as clarity, trust, proof, capture, or distribution.",
            ),
            Priority(
                title="Turn the clarity notes into one app change",
                why="Onboarding and screenshots point to the same user problem: understanding the value fast.",
                action="Ship one change that makes 3 priorities visible earlier.",
            ),
            Priority(
                title="Turn proof notes into one public-safe example",
                why="A useful example builds more trust than a long list of planned proof ideas.",
                action="Publish one Decision Example from synthetic public-safe material.",
            ),
        ],
        practical_takeaway="Notes become useful when they are filtered into decisions. Do not organize more than you act.",
    ),
    DecisionExample(
        title="How to Reduce Project Noise",
        slug="how-to-reduce-project-noise",
        category="Engineering Focus",
        meta_description="See how project noise can be filtered into what matters, what to ignore, and one next engineering move.",
        pain="Your project has too many issues, release details, and small tasks competing for attention.",
        messy_input=(
            "The build needs checking, the macOS app had a sync issue before, screenshots need review, tests should run, "
            "and there are several UI polish tasks. I am worried something important will be missed."
        ),
        signals_detected=[
            "build stability is the first trust requirement",
            "the previous sync issue is the highest review risk",
            "screenshots affect App Store approval and conversion",
            "minor UI polish matters only after core review blockers are clear",
        ],
        ignored_noise=[
            "polishing secondary labels before verifying sync",
            "opening new design explorations during release prep",
            "treating every UI nit as equal priority",
        ],
        priorities=[
            Priority(
                title="Verify the release build path",
                why="A product cannot convert if the submitted build is incomplete or unstable.",
                action="Run the iOS, macOS, and watchOS build checks before touching lower-priority polish.",
            ),
            Priority(
                title="Re-test the Sync action",
                why="Apple already flagged unresponsiveness, so this is a trust and approval risk.",
                action="Tap Sync on a clean install and confirm the UI stays responsive.",
            ),
            Priority(
                title="Confirm screenshots match the current app",
                why="Accurate screenshots are both a review requirement and a conversion surface.",
                action="Replace any stale marketing frames with current in-app screens showing core value.",
            ),
        ],
        practical_takeaway="Project noise drops when review blockers, trust risks, and conversion surfaces are ranked separately.",
    ),
    DecisionExample(
        title="How to Review Your Week as a Solo Founder",
        slug="how-to-review-your-week-as-a-solo-founder",
        category="Weekly Review",
        meta_description="A weekly review example showing how repeated signals become 3 priorities and one next action.",
        pain="The week was busy, but it is unclear what actually moved the product forward.",
        messy_input=(
            "I worked on screenshots, App Store messages, onboarding copy, Discord proof, GitHub examples, and UI polish. "
            "It feels like progress, but I am not sure what repeated or what to cut."
        ),
        signals_detected=[
            "clarity work repeated across screenshots, onboarding, and README",
            "trust work repeated across settings, safety, and proof layers",
            "distribution work is useful only when tied to concrete examples",
            "UI polish helped only when it made the core promise clearer",
        ],
        ignored_noise=[
            "counting activity as progress",
            "treating every shipped change as equally important",
            "adding more channels before one proof loop is consistent",
        ],
        priorities=[
            Priority(
                title="Keep sharpening first understanding",
                why="The strongest repeated theme is that users need to understand SimpliXio before they trust or share it.",
                action="Review the first screen, first screenshot, and README opening as one system.",
            ),
            Priority(
                title="Turn the week into one proof artifact",
                why="A weekly review should create visible evidence that the product is improving.",
                action="Publish one public-safe build note with what changed, what repeated, and what was ignored.",
            ),
            Priority(
                title="Cut one weak channel",
                why="Too many acquisition channels create founder noise and dilute learning.",
                action="Pick the weakest channel from the week and pause it for seven days.",
            ),
        ],
        practical_takeaway="A weekly review is not a status report. It should reveal what repeated, what mattered, and what to stop doing.",
    ),
    DecisionExample(
        title="How to Turn GitHub Issues Into Priorities",
        slug="how-to-turn-github-issues-into-priorities",
        category="Engineering Focus",
        meta_description="A builder-focused example showing how GitHub issue noise can become 3 priorities and one next action.",
        pain=(
            "Your issue list is long, mixed, and noisy. Bugs, release work, UX polish, and growth tasks sit beside each other, "
            "so the list creates pressure without giving direction."
        ),
        messy_input=(
            "There are issues about onboarding, screenshot automation, TestFlight upload, settings polish, widgets, and Discord automation. "
            "Some are bugs, some are growth work, and some are nice-to-have."
        ),
        signals_detected=[
            "TestFlight upload affects release ability",
            "onboarding and screenshots affect conversion",
            "settings polish affects trust",
            "Discord automation is useful only after proof artifacts exist",
        ],
        ignored_noise=[
            "sorting issues by newest first",
            "building every integration mentioned in the issue list",
            "treating nice-to-have polish as release-critical",
        ],
        priorities=[
            Priority(
                title="Fix the release path first",
                why="If the app cannot ship reliably, every other improvement stays invisible.",
                action="Resolve upload and build blockers before changing lower-risk UI.",
            ),
            Priority(
                title="Improve conversion surfaces second",
                why="Onboarding and screenshots determine whether the right users understand the product.",
                action="Choose the issue that most directly improves first-use clarity.",
            ),
            Priority(
                title="Batch proof automation later",
                why="Proof automation compounds only after the product has real proof to package.",
                action="Group Discord and release note work into one weekly proof task.",
            ),
        ],
        practical_takeaway=(
            "A GitHub issue list becomes useful when ranked by release risk, user understanding, and proof value. "
            "The point is not to process every issue. The point is to protect the next release from the work that only looks urgent."
        ),
    ),
    DecisionExample(
        title="How to Decide What to Ignore",
        slug="how-to-decide-what-to-ignore",
        category="Decision Replay",
        meta_description="A Decision Replay style example showing how ignored noise helps reveal the right 3 priorities.",
        pain="Ignoring feels risky, so too many low-signal items stay active.",
        messy_input=(
            "I could improve the icon, rewrite the tagline, add another integration, polish an old script, start Product Hunt prep, "
            "or write more public examples. I do not want to drop something important."
        ),
        signals_detected=[
            "public examples directly explain the product",
            "Product Hunt prep is premature without proof archive depth",
            "another integration risks broadening the product",
            "icon polish is less urgent than conversion clarity",
        ],
        ignored_noise=[
            "starting Product Hunt prep before the archive has enough examples",
            "adding another integration without a ranking benefit",
            "polishing visual assets that do not change understanding",
        ],
        priorities=[
            Priority(
                title="Publish the first Decision Examples",
                why="Examples make the product concrete and searchable without changing the app itself.",
                action="Create ten public-safe examples that show messy input becoming 3 priorities.",
            ),
            Priority(
                title="Keep Product Hunt in preparation mode",
                why="Launch attention is wasted if the proof layer is still thin.",
                action="Write the maker comment, but do not launch until screenshots, examples, and onboarding are ready.",
            ),
            Priority(
                title="Reject integration breadth this week",
                why="More inputs are only useful when they improve prioritisation, not when they create another feed.",
                action="Do not add a new integration unless it directly strengthens capture or ranking.",
            ),
        ],
        practical_takeaway="Ignoring is not neglect. It is how a decision system protects attention for the bottleneck that matters.",
    ),
    DecisionExample(
        title="How to Turn Open Loops Into Next Actions",
        slug="how-to-turn-open-loops-into-next-actions",
        category="Resurfacing",
        meta_description="A practical example showing how open loops can be filtered into 3 priorities and one clear next action.",
        pain="Open loops keep resurfacing, but they do not become action.",
        messy_input=(
            "I still need to review pricing, improve App Store copy, confirm macOS screenshots, write a newsletter draft, "
            "and decide whether Discord is ready. These loops keep coming back."
        ),
        signals_detected=[
            "macOS screenshots have a concrete approval deadline",
            "App Store copy is tied to conversion and clarity",
            "pricing can wait until trial and install signals improve",
            "Discord depends on having public-safe proof to post",
        ],
        ignored_noise=[
            "finalising pricing before demand signal",
            "opening Discord before proof cadence is stable",
            "turning every loop into an immediate task",
        ],
        priorities=[
            Priority(
                title="Close the screenshot loop",
                why="Screenshots are both a review requirement and the clearest way to show what SimpliXio does.",
                action="Audit each supported device size and replace any stale screenshot.",
            ),
            Priority(
                title="Tighten App Store copy",
                why="The listing must explain the product before users decide whether to install.",
                action="Make the opening line say 3 priorities, why, and one next action.",
            ),
            Priority(
                title="Queue Discord as proof, not setup",
                why="A Discord community is valuable only when it contains useful public-safe progress.",
                action="Prepare one weekly build-in-public post from real release notes.",
            ),
        ],
        practical_takeaway="An open loop becomes useful when it is assigned a time horizon: now, today, this week, or later.",
    ),
]


def slug_to_filename(slug: str) -> str:
    return f"{slug}.md"


def flatten_example(example: DecisionExample) -> str:
    parts: list[str] = [
        example.title,
        example.category,
        example.meta_description,
        example.pain,
        example.messy_input,
        " ".join(example.signals_detected),
        " ".join(example.ignored_noise),
        example.practical_takeaway,
        example.cta,
        example.source_note,
        example.public_safe_status,
    ]
    for priority in example.priorities:
        parts.extend([priority.title, priority.why, priority.action])
    return "\n".join(parts)


def word_count(text: str) -> int:
    return len(re.findall(r"\b[\w'-]+\b", text))


def validate_example(example: DecisionExample) -> list[str]:
    errors: list[str] = []
    text = flatten_example(example)
    lowered = text.lower()

    if not example.slug or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", example.slug):
        errors.append("slug must be lowercase kebab-case")
    if len(example.meta_description) < 80 or len(example.meta_description) > 170:
        errors.append("meta description should be 80-170 characters")
    if example.public_safe_status != "public_safe":
        errors.append("public_safe_status must be public_safe")
    if len(example.signals_detected) < 3:
        errors.append("requires at least 3 detected signals")
    if len(example.ignored_noise) < 3:
        errors.append("requires at least 3 ignored noise items")
    if len(example.priorities) != 3:
        errors.append("requires exactly 3 priorities")
    if word_count(text) < 220:
        errors.append("example is too thin")

    for pattern in SENSITIVE_PATTERNS:
        if pattern.search(text):
            errors.append(f"sensitive pattern detected: {pattern.pattern}")
    for word in HYPE_WORDS:
        if word in lowered:
            errors.append(f"hype wording detected: {word}")

    for idx, priority in enumerate(example.priorities, start=1):
        if len(priority.title.split()) < 3:
            errors.append(f"priority {idx} title is too vague")
        if word_count(priority.why) < 10:
            errors.append(f"priority {idx} why is too thin")
        if word_count(priority.action) < 8:
            errors.append(f"priority {idx} action is too vague")

    return errors


def validate_examples(examples: Iterable[DecisionExample]) -> dict[str, list[str]]:
    report: dict[str, list[str]] = {}
    seen_slugs: set[str] = set()
    for example in examples:
        errors = validate_example(example)
        if example.slug in seen_slugs:
            errors.append("duplicate slug")
        seen_slugs.add(example.slug)
        if errors:
            report[example.slug] = errors
    return report


def render_front_matter(example: DecisionExample) -> str:
    return "\n".join(
        [
            "---",
            f'title: "{example.title}"',
            f'slug: "{example.slug}"',
            f'meta_description: "{example.meta_description}"',
            f'canonical_path: "{example.canonical_path}"',
            f'category: "{example.category}"',
            f'public_safe_status: "{example.public_safe_status}"',
            f'generated_at: "{example.generated_at}"',
            f'source_note: "{example.source_note}"',
            "---",
            "",
        ]
    )


def render_example(example: DecisionExample) -> str:
    lines: list[str] = [
        render_front_matter(example),
        f"# {example.title}",
        "",
        example.pain,
        "",
        "## Messy input",
        "",
        f"> {example.messy_input}",
        "",
        "## Signals detected",
        "",
    ]
    lines.extend(f"- {item}" for item in example.signals_detected)
    lines.extend(["", "## Ignored noise", ""])
    lines.extend(f"- {item}" for item in example.ignored_noise)
    lines.extend(["", "## 3 priorities", ""])
    for index, priority in enumerate(example.priorities, start=1):
        lines.extend(
            [
                f"### {index}. {priority.title}",
                "",
                f"Why: {priority.why}",
                "",
                f"Action: {priority.action}",
                "",
            ]
        )
    lines.extend(
        [
            "## Practical takeaway",
            "",
            example.practical_takeaway,
            "",
            "## Try SimpliXio",
            "",
            example.cta,
            "",
            "Public-safe status: `public_safe`.",
            "",
        ]
    )
    return "\n".join(lines)


def example_metadata(example: DecisionExample) -> dict:
    payload = asdict(example)
    payload["canonical_path"] = example.canonical_path
    payload["path"] = f"docs/decision-examples/{slug_to_filename(example.slug)}"
    payload["url_path"] = example.canonical_path
    payload["priority_count"] = len(example.priorities)
    return payload


def render_index(examples: list[DecisionExample]) -> str:
    lines = [
        "---",
        'title: "Decision Examples"',
        'meta_description: "Public-safe examples showing how messy thoughts and project noise become 3 priorities and one next action."',
        'canonical_path: "/decision-examples"',
        'public_safe_status: "public_safe"',
        f'generated_at: "{GENERATED_DATE}"',
        "---",
        "",
        "# Decision Examples",
        "",
        "Public-safe examples showing how common decision pains become filtered signals, ignored noise, 3 priorities, why they matter, and one next action.",
        "",
        "These are useful examples, not fake traction claims. They are synthetic public-safe scenarios designed to explain SimpliXio clearly.",
        "",
        "| Example | Category | Description | Status |",
        "| --- | --- | --- | --- |",
    ]
    for example in examples:
        lines.append(
            f"| [{example.title}]({slug_to_filename(example.slug)}) | {example.category} | {example.meta_description} | `{example.public_safe_status}` |"
        )
    lines.extend(
        [
            "",
            "## Use These Examples For",
            "",
            "- App Store screenshot copy",
            "- Discord build-in-public posts",
            "- newsletter angles",
            "- Product Hunt preparation",
            "- README and OpenClaw proof links",
            "",
            "## Quality Standard",
            "",
            "Every Decision Example must show a concrete transformation: messy input -> signals -> ignored noise -> 3 priorities -> why -> action.",
            "",
        ]
    )
    return "\n".join(lines)


def write_outputs(output_dir: Path = DEFAULT_OUTPUT_DIR, examples: list[DecisionExample] | None = None) -> dict:
    selected = examples or DECISION_EXAMPLES
    report = validate_examples(selected)
    if report:
        raise ValueError(json.dumps(report, indent=2))

    output_dir.mkdir(parents=True, exist_ok=True)
    files: dict[str, str] = {}
    for example in selected:
        path = output_dir / slug_to_filename(example.slug)
        path.write_text(render_example(example), encoding="utf-8")
        files[example.slug] = str(path)

    index_path = output_dir / "index.md"
    index_path.write_text(render_index(selected), encoding="utf-8")

    manifest = {
        "generated_at": GENERATED_DATE,
        "count": len(selected),
        "public_safe_status": "public_safe",
        "examples": [example_metadata(example) for example in selected],
    }
    manifest_path = output_dir / "decision_examples.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    return {
        "status": "ok",
        "count": len(selected),
        "output_dir": str(output_dir),
        "index": str(index_path),
        "manifest": str(manifest_path),
        "files": files,
    }


def run_check(examples: list[DecisionExample] | None = None) -> dict:
    selected = examples or DECISION_EXAMPLES
    report = validate_examples(selected)
    return {
        "status": "failed" if report else "ok",
        "count": len(selected),
        "errors": report,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build public-safe SimpliXio Decision Examples.")
    parser.add_argument("--check", action="store_true", help="Validate examples without writing files.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_DIR), help="Output directory for Markdown pages.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.check:
        payload = run_check()
    else:
        payload = write_outputs(Path(args.output))

    print(json.dumps(payload, indent=2))
    return 0 if payload["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
