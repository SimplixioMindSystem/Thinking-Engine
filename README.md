# SimpliXio

*SimpliXio turns scattered thoughts, project noise, and open loops into 3 priorities and one next action.*

![SimpliXio product system](logo.png)

> [!Note]
> Built for founders and builders with too many inputs and not enough clarity.
> SimpliXio answers one daily question: **"What matters now, and what should I do next?"**

## Why SimpliXio

- You capture messy thoughts quickly.
- SimpliXio filters noise into 3 priorities.
- Each priority includes why it matters.
- You get one clear next action.

SimpliXio is not a note backlog, task manager, CRM, ATS, or chatbot. It is the daily decision layer that reduces scattered inputs into what matters now.

## Product Flow

```text
capture -> enrich -> rank -> surface -> act -> review -> learn
```

The visible product stays simple:
- What matters now
- 3 priorities
- Why they matter
- One next action
- Feedback that improves future ranking

## Trust

- Private by default.
- Public content runs through redaction and quality checks.
- Private outreach stays `needs_approval` by default.
- Human judgement stays in control.
- Discord, newsletter, and acquisition outputs are draft-first unless explicitly approved.

---

## Install

**Requirements:** Python 3.11+, macOS 14+ / iOS 17+ (native apps), Xcode 15+ (Swift)

```bash
git clone https://github.com/SimplixioMindSystem/Thinking-Engine.git
cd Thinking-Engine
make install
```

Or manually:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Usage

```bash
.venv/bin/python -m cortex_core pipeline
.venv/bin/python -m cortex_core serve
```

Native app (iOS + macOS + watchOS):

```bash
brew install xcodegen
cp CortexOSApp/local.yml.example CortexOSApp/local.yml
# Edit CortexOSApp/local.yml and set your DEVELOPMENT_TEAM (Apple Developer Membership page)
make generate
open CortexOSApp/CortexOS.xcodeproj
```

Leave server URL empty in Settings to run fully offline.

## API

Server runs on port `8420`.

- `GET /sync/today`: Canonical **SimpliXio Today** output (3 priorities + why + action + ignored)
- `GET /sync/snapshot`: Single-call snapshot for offline-first client hydration
- `POST /integrations/pull`: Pull context from RSS / GitHub / Notion
- `POST /context/signals/capture`: Capture one raw signal into deterministic ranking
- `GET /context/signals/queues`: Ranked queues (`what_matters_now`, decision queue, action-ready queue)

System architecture and scoring model:
- [cortex_os_system.md](cortex_os_system.md)

Public-safe developer demo:

```bash
python3 examples/simplixio_signal_demo.py --dry-run
```

This shows how an external tool can send safe project signals into SimpliXio and receive the same core output: 3 priorities, why they matter, and one next action.

## Developer Credibility Layer

SimpliXio is not being turned into a developer platform. The public examples exist to make the product loop inspectable for builders while keeping private product logic and private user data protected.

- [OpenClaw skill README](openclaw/simplixio-decision-skill/README.md): GitHub-ready positioning, examples, use cases, and author section.
- [Public-safe examples](examples/README.md): API demo for capture -> 3 priorities -> why -> action.
- [Developer credibility plan](docs/developer-credibility-layer.md): GitHub proof layer, real metrics policy, and launch discipline.

## Decision Examples

Decision Examples are public-safe pages that make SimpliXio searchable and easier to understand. Each page shows a frequent decision pain as a concrete transformation:

```text
messy input -> signals detected -> ignored noise -> 3 priorities -> why -> action
```

- [Decision Examples archive](docs/decision-examples/index.md)
- [Decision Example template](docs/decision-examples/_template.md)
- [Decision Example generator](cortexos_automation_scripts/scripts/build_decision_examples.py)

Validate or rebuild them with:

```bash
python3 cortexos_automation_scripts/scripts/build_decision_examples.py --check
python3 cortexos_automation_scripts/scripts/build_decision_examples.py
```

## Public Proof

The SimpliXio Desire Loop turns product value into safe public proof:

```text
capture messy input -> 3 priorities -> why -> action -> public-safe proof
```

- [Public proof archive](docs/public-proof/index.md)
- [Public proof manifest](docs/public-proof/proof_manifest.json)
- [Public proof archive builder](cortexos_automation_scripts/scripts/build_public_proof_archive.py)

Rebuild it with:

```bash
python3 cortexos_automation_scripts/scripts/build_public_proof_archive.py
```

## TestFlight

```bash
cd CortexOSApp/fastlane
cp .env.example .env
# Edit .env: set ASC_KEY_PATH, ASC_ISSUER_ID, ASC_KEY_ID, TEAM_ID
cd ..
fastlane ios testflight_release
fastlane mac testflight_release
fastlane watch_testflight
fastlane all_testflight
```

## Growth Automation

```bash
.venv/bin/python scripts/cortex_growth_loop.py
cd cortexos_automation_scripts
python3 scripts/run_weekly_pipeline.py --strict-quality
python3 scripts/run_acquisition_pipeline.py --mode daily --strict-quality
python3 scripts/run_acquisition_pipeline.py --mode weekly --strict-quality
```

What these automation pipelines do:
- Weekly marketing pipeline: builds Today/Weekly Review/Decision Replay/newsletter artifacts from real product output, drafts posts, runs quality gate, and only queues publish when safe flags are enabled.
- Daily acquisition pipeline: collects public lead signals, scores fit, drafts outreach (approval-required), runs compliance checks, and writes CRM logs/summaries.

Detailed runbook:
- [cortexos_automation_scripts/README.md](cortexos_automation_scripts/README.md)
- [cortexos_automation_scripts/AUTOMATION_RUNBOOK.md](cortexos_automation_scripts/AUTOMATION_RUNBOOK.md)

Positioning + trust playbooks:
- [docs/messaging-stack.md](docs/messaging-stack.md)
- [docs/desire-loop.md](docs/desire-loop.md)
- [docs/developer-credibility-layer.md](docs/developer-credibility-layer.md)
- [docs/integrated-product-system-2026-04-30.md](docs/integrated-product-system-2026-04-30.md)
- [docs/values-alignment-plan-2026-04-29.md](docs/values-alignment-plan-2026-04-29.md)
- [docs/reorg-plan-2026-04-29.md](docs/reorg-plan-2026-04-29.md)

## Tests

```bash
make test
make test-python
make test-swift
```
