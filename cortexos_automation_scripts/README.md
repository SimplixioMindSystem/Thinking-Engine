# SimpliXio Automation (Monorepo)

This folder is the automation engine for proof, weekly learning, and warm acquisition loops.
It includes acquisition research + drafting automation with compliance gates.

It is monorepo-aware:
- reads source data from the main repo (`../growth_output`, `../weekly_digest_*.md`)
- writes automation artifacts to `cortexos_automation_scripts/output/`

## What It Does (Simple Words)

### Proof automation

The proof scripts do this:
1. Collect and filter real project signals.
2. Build real product artifacts (`SimpliXio Today`, `Weekly Review`, `Decision Replay`).
3. Generate draft posts (X, LinkedIn, blog), Discord proof drafts, HTML pages, and cards from those artifacts.
4. Run quality checks (no hype words, no weak/generic copy, no repeated angle).
5. Only queue publish output if quality passes and publish flags are enabled.

Important:
- By default this is safe/dry-run.
- It does not invent traction/users/revenue.
- It writes logs and summaries every run.

### Acquisition / prospection automation

The acquisition scripts do this:
1. Collect public, compliant lead signals (GitHub, RSS, HN, internal artifacts).
2. Score lead fit for SimpliXio (`fit`, `candidate`, `not_fit`).
3. Draft personalized private outreach messages for high-fit leads.
4. Run acquisition quality/compliance checks.
5. Save everything in SQLite CRM + JSON/Markdown reports.

Important:
- Private outreach is draft-only by default (`needs_approval`).
- No LinkedIn scraping.
- No automatic cold DM/email sending by default.
- Public content queueing still requires quality pass + explicit publish flags.

## What Is Automatic vs Manual

Fully automated:
- lead discovery
- lead scoring
- outreach draft generation
- public content draft generation
- quality gate checks
- run logs + summaries

Manual approval required:
- private outbound sending (DM/email/comment/reply)
- any high-risk public posting choice

## Trust Defaults

- Private by default.
- Public drafts must pass quality gates before queueing.
- No LinkedIn scraping or automated LinkedIn activity.
- No automatic cold outreach sends in this repo.
- Human approval stays required for private outbound.

## Structure

```text
cortexos_automation_scripts/
  marketing_automation.py
  scripts/
    filter_signals.py
    build_cortex_today.py
    build_weekly_review.py
    build_decision_replay.py
    build_public_newsletter.py
    build_discord_proof_drafts.py
    generate_newsletter.py
    build_decision_examples.py
    build_public_proof_archive.py
    marketing_quality_gate.py
    publish_outputs.py
    run_weekly_pipeline.py
    acquisition_crm.py
    lead_collector.py
    lead_scorer.py
    outreach_drafter.py
    content_engine.py
    acquisition_quality_gate.py
    run_acquisition_pipeline.py
  output/
    cortex_today/
      cortex_today.json
      cortex_today.md
      cortex_today.html
      archive/
    filtered_signals/
    weekly_review/
      latest.json
      latest.md
      latest.html
      archive/
    decision_replay/
      latest.json
      latest.md
      latest.html
      archive/
    newsletters/
      drafts/
      approved/
      rejected/
      logs/
      latest.json
    discord/
      release_notes_latest.md
      build_in_public_latest.md
      weekly_review_latest.md
      product_lesson_latest.md
      feedback_prompt_latest.md
      latest.json
    decision_examples/
      # runtime exports may be added later
    drafts/
    quality_gate/
    logs/
```

## Local setup

```bash
cd cortexos_automation_scripts
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

## Daily run order (artifact-first)

```bash
python3 scripts/filter_signals.py
python3 scripts/build_cortex_today.py
python3 scripts/build_weekly_review.py
python3 scripts/build_decision_replay.py
python3 scripts/generate_newsletter.py --period weekly --mode weekly-lessons --strict-safety --strict-taste
python3 marketing_automation.py
python3 scripts/marketing_quality_gate.py --strict
python3 scripts/build_discord_proof_drafts.py
python3 scripts/publish_outputs.py
```

Single command (recommended):

```bash
python3 scripts/run_weekly_pipeline.py --strict-quality
```

## Weekly pipeline

```bash
python3 scripts/run_weekly_pipeline.py --strict-quality
```

## Decision Examples

Decision Examples are the public-safe long-tail acquisition layer. They are committed under `../docs/decision-examples/` so they can be reviewed, linked, and published without depending on runtime output.

Validate:

```bash
python3 scripts/build_decision_examples.py --check
```

Rebuild the committed Markdown archive:

```bash
python3 scripts/build_decision_examples.py
```

Rules:
- synthetic examples must be clearly marked as examples
- every example must include exactly 3 priorities
- every priority needs a concrete why and action
- sensitive/private material is rejected
- no fake traction, fake users, or fake metrics
- no thin SEO pages

## Public Proof Archive

The public proof archive packages safe proof surfaces into one Desire Loop:

```text
capture messy input -> 3 priorities -> why -> action -> public-safe proof
```

Rebuild:

```bash
python3 scripts/build_public_proof_archive.py
```

Committed outputs:
- `../docs/public-proof/index.md`
- `../docs/public-proof/proof_manifest.json`
- `../docs/public-proof/changelog/README.md`
- `../docs/public-proof/weekly-review/README.md`
- `../docs/public-proof/decision-replay/README.md`
- `../docs/public-proof/newsletter-examples/README.md`

## Fastest way (recommended)

From repo root (`/Users/pierre/Code/CortexOSLLM`), use the Makefile wrappers:

```bash
make autopilot-weekly
make autopilot-acq-daily
make autopilot-acq-weekly
make autopilot-all
```

Why this helps:
- avoids forgetting command order
- keeps strict quality checks on by default
- reduces copy/paste mistakes during releases

Canonical runbook:
- `/Users/pierre/Code/CortexOSLLM/cortexos_automation_scripts/AUTOMATION_RUNBOOK.md`

The pipeline writes:
- JSON run log: `output/logs/weekly-pipeline-*.json`
- Markdown summary: `output/summaries/weekly-pipeline-*.md`
- Curated Discord drafts: `output/discord/latest.json` + `output/discord/*_latest.md`
- Discord channel coverage: `release-notes`, `build-in-public`, `weekly-review`, `product-lessons`, `feedback`

## Acquisition automation

Daily:

```bash
python3 scripts/run_acquisition_pipeline.py --mode daily --strict-quality
```

Weekly:

```bash
python3 scripts/run_acquisition_pipeline.py --mode weekly
```

Acquisition outputs:
- SQLite CRM: `output/acquisition/acquisition.sqlite3`
- Raw lead signals: `output/acquisition/raw/lead_signals_*.json`
- Lead shortlist: `output/acquisition/drafts/latest_lead_shortlist.md`
- Outreach drafts: `output/acquisition/drafts/latest_outreach.md`
- Acquisition quality report: `output/acquisition/quality_report.json`
- Pipeline logs: `output/acquisition/logs/acquisition-*.json`
- Pipeline summaries: `output/acquisition/summaries/acquisition-*.md`

Lead scoring tiers:
- `fit`: high-confidence prospect, drafted for manual approval
- `candidate`: near-threshold prospect, held for manual review (not drafted automatically)
- `not_fit`: archived for now

Safety defaults:
- private outreach is always saved as `needs_approval`
- no LinkedIn scraping
- no outbound sending in these scripts
- public publish queue requires `PUBLISH_PUBLIC=true` and quality pass
- Discord output is draft-only and requires manual posting.

Single command outputs (daily):
- JSON log: `output/acquisition/logs/acquisition-daily-*.json`
- Markdown summary: `output/acquisition/summaries/acquisition-daily-*.md`
- Lead shortlist: `output/acquisition/drafts/latest_lead_shortlist.md`
- Outreach drafts: `output/acquisition/drafts/latest_outreach.md`

## Newsletter generation

Weekly public-safe newsletter draft:

```bash
python3 scripts/generate_newsletter.py --period weekly --mode weekly-lessons --strict-safety --strict-taste
```

Custom range from selected source IDs:

```bash
python3 scripts/generate_newsletter.py \
  --period custom --from 2026-04-01 --to 2026-04-21 \
  --mode product-builder-notes \
  --source-ids thought-12,decision-7 \
  --strict-safety --strict-taste
```

What it does:
- reads selected source material (`thoughts`, `notes`, `decisions`, `priority-feedback`, `weekly-review`, `decision-replay`)
- supports `daily`, `weekly`, `monthly`, or `custom` date ranges
- supports source filtering by `--source-ids`, `--tags`, and `--keywords`
- classifies each source item (`private`, `sensitive`, `internal`, `public_safe`, `public_ready`) before generation
- redacts sensitive patterns (emails, phone numbers, long numbers, URLs, common secret token formats)
- blocks confidential indicators and marks unsafe drafts as `needs_review` in strict mode
- runs a strict taste gate (generic/repetitive/weak drafts become `needs_review`)
- updates local voice memory from approved writing only (`output/newsletters/voice_profile.json`)
- writes content-flywheel snippets (X, LinkedIn, blog outline, acquisition angle) inside the JSON log
- stores safety + redaction logs with source IDs for manual review
- writes Markdown + HTML + JSON metadata with safety + redaction + classification + taste reports
- archives only safe + taste-passing + `public_ready` drafts to `output/public_proof/newsletters/`

Outputs:
- `output/newsletters/drafts/newsletter-*.md` (or `rejected/` when blocked)
- `output/newsletters/drafts/newsletter-*.html`
- `output/newsletters/logs/newsletter-*.json`
- `output/newsletters/latest.json`
- `output/newsletters/voice_profile.json`
- `output/newsletters/memory.json`
- `output/public_proof/newsletters/newsletter-*.md` (only when archive rules pass)

## Notes

- `build_cortex_today.py` uses the latest `../growth_output/*/(ready_to_publish|pending_approval).json` as primary source.
- If growth output is missing, it attempts one fallback run of `../scripts/cortex_growth_loop.py`.
- `marketing_automation.py` generates drafts and artifacts only.
- `publish_outputs.py` is safe by default (`PUBLISH_DRY_RUN=true`), and updates content memory only when quality passes.
