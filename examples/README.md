# SimpliXio Public-Safe Examples

These examples show how a developer tool can send signals into SimpliXio and receive the core output:

```text
scattered signals -> 3 priorities -> why -> action
```

They are intentionally small. SimpliXio is not being repositioned as a developer platform or SDK product. The examples exist to make the product credible to builders without exposing private app logic or private user data.

## Current Example

```bash
python3 examples/simplixio_signal_demo.py --dry-run
```

The dry run prints:
- sample public-safe captured signals
- the API calls an external tool would make
- a representative SimpliXio Today response with 3 priorities, why, and action

To run against a local SimpliXio API server:

```bash
.venv/bin/python -m cortex_core.api.server
python3 examples/simplixio_signal_demo.py --live --base-url http://127.0.0.1:8420
```

## Safety Rules

- Use public-safe sample data only.
- Do not include customer names, private emails, secrets, internal project names, or confidential notes.
- Do not publish raw captured thoughts.
- Public examples should show the shape of the workflow, not private context.

## What This Proves

- SimpliXio can ingest fragmented signals.
- The backend can normalize and rank those signals.
- The product output remains the same: 3 priorities, why they matter, and one next action.
