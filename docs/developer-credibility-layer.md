# SimpliXio Developer Credibility Layer

This layer borrows the best product-led distribution mechanics from developer-friendly companies without changing SimpliXio's product category.

SimpliXio stays a decision system:

```text
scattered thoughts + project noise + open loops -> 3 priorities -> why -> action
```

## Goal

Make SimpliXio more credible to builders by showing the product loop in public-safe, inspectable examples.

This layer should help people understand:
- what SimpliXio does
- how signals enter the system
- what the system returns
- what remains private
- why the product is serious, not theoretical

## What Exists Now

- OpenClaw skill README: `openclaw/simplixio-decision-skill/README.md`
- Public-safe API demo: `examples/simplixio_signal_demo.py`
- Decision Examples archive: `docs/decision-examples/index.md`
- GitHub social preview source: `assets/github-social-preview.svg`
- Automation proof scripts:
  - Discord release notes
  - weekly build-in-public drafts
  - Weekly Review exports
  - Decision Replay exports
  - newsletter draft generation
- Main README positioning around the wedge.

## GitHub Presentation Checklist

- README opens with the core promise.
- API examples show capture -> today output.
- Decision Examples show messy input -> ignored noise -> 3 priorities -> why -> action.
- Examples use public-safe data only.
- Trust defaults are visible.
- Release notes explain user-facing value, not just internal changes.
- Social preview uses `assets/github-social-preview.svg` as source. Export to PNG before uploading in GitHub repository settings if required.
- Topics should stay narrow:
  - `decision-system`
  - `founder-tools`
  - `prioritization`
  - `swift`
  - `fastapi`
  - `openclaw`
  - `build-in-public`

## Public Proof Metrics

Only publish real metrics. If a metric is unavailable, show `not tracked yet` or omit it.

Recommended metrics:
- GitHub stars
- OpenClaw skill usage
- Discord members
- release count
- public-safe decision examples
- newsletter drafts generated
- waitlist signups
- App Store installs

Do not publish:
- fake users
- fake revenue
- fake retention
- inflated waitlist numbers
- private customer data

## Developer Demo Boundary

The demo may show:
- public-safe signal capture
- API request shape
- ranked 3-priority output
- ignored signal examples
- redaction and approval rules

The demo must not show:
- private app data
- internal project secrets
- raw user notes
- unredacted newsletter drafts
- paid product logic that weakens the app layer

## Launch Discipline

Prepare Product Hunt only after:
- App Store screenshots reflect the current app in use.
- Onboarding shows the promise in under 5 seconds.
- OpenClaw skill page is polished.
- Public proof archive has real examples.
- Demo video or GIF exists.
- Maker comment is ready.
- Discord proof flow is active and curated.

Maker comment structure:

```text
I built SimpliXio because my own project work kept creating too many notes, tabs, and open loops.

The product does one thing:
it turns scattered thoughts and project noise into 3 priorities, why they matter, and one next action.

The first version is intentionally narrow:
- capture quickly
- see what matters now
- understand why
- act
- review what repeated or was ignored

Private by default. Public-safe only after redaction. No autopublish.

I am looking for feedback from founders and builders who feel overloaded by their own project signals.
```

## What To Post Publicly

- One release note for each meaningful release.
- One weekly build-in-public note when there is real progress.
- One Decision Replay example when it is public-safe.
- One Decision Example when it targets a real repeated decision pain.
- One product lesson when it teaches a concrete prioritization principle.

Do not post every commit.
Do not turn Discord or GitHub into a raw activity feed.
