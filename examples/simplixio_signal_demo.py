#!/usr/bin/env python3
"""Public-safe SimpliXio API demo.

This script demonstrates the developer-facing loop without exposing private data:
capture signals -> request today's output -> show 3 priorities, why, action.

Default mode is dry-run so it is safe to run from a public repo.
Use --live only against a local SimpliXio API server you control.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True)
class DemoSignal:
    text: str
    source: str
    source_id: str
    context: str
    project: str
    tags: list[str]
    signal_type_hint: str


DEMO_SIGNALS: list[DemoSignal] = [
    DemoSignal(
        text="Onboarding still takes too long before the user sees the 3 priorities.",
        source="public_demo",
        source_id="demo-onboarding-clarity",
        context="App Store review prep",
        project="SimpliXio",
        tags=["onboarding", "clarity", "conversion"],
        signal_type_hint="tension",
    ),
    DemoSignal(
        text="The macOS app should make Weekly Review feel like a calm workbench, not a dashboard.",
        source="public_demo",
        source_id="demo-macos-review",
        context="macOS design pass",
        project="SimpliXio",
        tags=["macos", "weekly-review", "ux"],
        signal_type_hint="decision",
    ),
    DemoSignal(
        text="Public proof should come from release notes, Decision Replay, and safe weekly lessons.",
        source="public_demo",
        source_id="demo-proof-loop",
        context="Developer credibility layer",
        project="SimpliXio",
        tags=["proof", "trust", "github"],
        signal_type_hint="idea",
    ),
]


DRY_RUN_TODAY: dict[str, Any] = {
    "priorities": [
        {
            "rank": 1,
            "title": "Shorten onboarding to show value faster",
            "why": "The strongest repeated signal is that users need to see 3 priorities before learning more concepts.",
            "action": "Make the first screen show capture, 3 priorities, why, and one next action.",
        },
        {
            "rank": 2,
            "title": "Keep macOS as the calm review workbench",
            "why": "The macOS surface can carry deeper review without making iPhone feel like a backlog.",
            "action": "Group Weekly Review, Decision Replay, and patterns behind clear sections.",
        },
        {
            "rank": 3,
            "title": "Turn proof into public-safe examples",
            "why": "Builder trust improves when examples show real product shape without leaking private context.",
            "action": "Publish sanitized release notes, demo signals, and a small GitHub example.",
        },
    ],
    "ignored_signals": [
        "Broad SDK roadmap",
        "Unverified traction claims",
        "Generic AI productivity copy",
    ],
}


def request_json(method: str, url: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(url=url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Request failed for {url}: {exc}") from exc


def print_priority_output(today: dict[str, Any]) -> None:
    priorities = today.get("priorities") or []
    print("\nSimpliXio Today")
    print("----------------")
    for item in priorities[:3]:
        print(f"{item.get('rank', '-')}. {item.get('title', 'Untitled priority')}")
        print(f"   Why: {item.get('why', 'No explanation provided.')}")
        print(f"   Action: {item.get('action', 'Choose the next concrete step.')}")

    ignored = today.get("ignored_signals") or []
    if ignored:
        print("\nIgnored")
        for item in ignored[:5]:
            print(f"- {item}")


def run_dry_run() -> int:
    print("Dry run: public-safe signals that an external tool could send to SimpliXio.\n")
    for signal in DEMO_SIGNALS:
        payload = asdict(signal)
        print("POST /context/signals/capture")
        print(json.dumps(payload, indent=2))
        print()

    print("GET /sync/today")
    print_priority_output(DRY_RUN_TODAY)
    return 0


def run_live(base_url: str) -> int:
    base = base_url.rstrip("/")
    for signal in DEMO_SIGNALS:
        payload = asdict(signal)
        result = request_json("POST", f"{base}/context/signals/capture", payload)
        print(f"Captured {result.get('id', signal.source_id)}")

    today = request_json("GET", f"{base}/sync/today")
    print_priority_output(today)
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a public-safe SimpliXio signal demo.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Print public-safe sample calls without network access.")
    mode.add_argument("--live", action="store_true", help="Send sample signals to a local SimpliXio API server.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8420", help="Local SimpliXio API base URL.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if args.live:
        return run_live(args.base_url)
    return run_dry_run()


if __name__ == "__main__":
    raise SystemExit(main())
