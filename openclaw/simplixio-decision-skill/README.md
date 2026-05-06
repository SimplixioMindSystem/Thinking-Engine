# SimpliXio Decision Skill For OpenClaw

SimpliXio turns scattered thoughts, project noise, and open loops into 3 priorities and one next action.

This OpenClaw skill is a public credibility layer for builders. It shows how SimpliXio thinks about signal capture, prioritization, explainability, and public-safe output.

It is not a recruiting workflow, CRM, task manager, or generic AI assistant.

## What The Skill Does

- Accepts messy but public-safe signals.
- Keeps capture lightweight.
- Asks SimpliXio for the current 3 priorities.
- Returns why each priority matters.
- Suggests one concrete next action.
- Keeps private material out of public examples.

## Example Input

```text
I keep adding notes about onboarding, screenshots, and App Store review, but I am not sure what matters first.
The macOS settings screen also needs to feel less technical.
The next release should make the app easier to understand in under 5 seconds.
```

## Example Output

```text
1. Tighten the first-run value moment
Why: Onboarding and screenshots both point to the same problem: users need to see the product promise immediately.
Action: Make the first screen show capture, 3 priorities, why, and one next action.

2. Polish Settings as a trust surface
Why: Settings is where sync, privacy, and control either build trust or create doubt.
Action: Group Sync, Privacy, and About clearly, with short human labels.

3. Use App Store screenshots as proof
Why: Apple review already flagged screenshots that did not reflect the current app in use.
Action: Replace abstract marketing frames with real product screens and concrete captions.
```

## Public-Safe Rules

- Do not paste secrets, tokens, private emails, customer names, or confidential project details.
- Do not publish raw private thoughts.
- Keep public examples sanitized and representative.
- If uncertain, mark the output `needs_review`.

## Suggested OpenClaw Positioning

**Name:** SimpliXio Decision Skill

**Short description:** Turn scattered project signals into 3 priorities, why they matter, and one next action.

**Use cases:**
- Prioritize a messy build week.
- Turn release noise into one next move.
- Review what repeated and what can be ignored.
- Draft public-safe proof from release notes or Decision Replay.

## Author

Built by Pierre-Henry Soria as part of SimpliXio, a calm decision system for founders and builders who have too many inputs and not enough clarity.

## Links

- SimpliXio repo: `https://github.com/SimplixioMindSystem/Thinking-Engine`
- Public-safe API demo: `examples/simplixio_signal_demo.py`
- Decision Examples archive: `docs/decision-examples/index.md`
- Messaging stack: `docs/messaging-stack.md`
