#!/usr/bin/env python3
"""Generate current-version App Store assets with strict screenshot hygiene.

Why this exists:
- Prevent uploading stale/outdated screenshots.
- Ensure canonical listing files per device folder.
- Keep output deterministic for App Store review submissions.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "CortexOSApp"
MARKETING_ROOT = APP_ROOT / "store_assets" / "marketing"
STORE_ASSETS_ROOT = APP_ROOT / "store_assets"
RAW_ROOT = APP_ROOT / "screenshot_results"
PROJECT_YML = APP_ROOT / "project.yml"

# Canonical listing sets (single narrative per device class)
CANONICAL_FILES: dict[str, list[str]] = {
    "iPhone_6.9": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "iPhone_6.7": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "iPhone_6.5": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "iPhone_5.5": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "iPad_13": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "iPad_12.9": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "Mac": [
        "01_focus.png", "02_weekly_review.png", "03_decision_replay.png",
        "04_memory.png", "05_decisions.png", "06_settings.png",
    ],
}

RAW_REQUIRED: dict[str, list[str]] = {
    "iphone_raw": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "ipad_raw": ["01_focus.png", "02_decide.png", "03_capture.png", "04_settings.png"],
    "mac_raw": [
        "01_focus.png", "02_weekly_review.png", "03_decision_replay.png",
        "04_memory.png", "05_decisions.png", "06_settings.png",
    ],
}


def selected_devices() -> dict[str, list[str]]:
    raw_value = os.getenv("STORE_ASSET_DEVICES", "").strip()
    if not raw_value:
        return CANONICAL_FILES

    requested = {item.strip() for item in raw_value.split(",") if item.strip()}
    unknown = sorted(requested.difference(CANONICAL_FILES))
    if unknown:
        raise RuntimeError(f"Unknown STORE_ASSET_DEVICES value(s): {', '.join(unknown)}")
    return {device: files for device, files in CANONICAL_FILES.items() if device in requested}


def required_raw_folders(devices: dict[str, list[str]]) -> dict[str, list[str]]:
    required: dict[str, list[str]] = {}
    for device in devices:
        if device.startswith("iPhone"):
            required["iphone_raw"] = RAW_REQUIRED["iphone_raw"]
        elif device.startswith("iPad"):
            required["ipad_raw"] = RAW_REQUIRED["ipad_raw"]
        elif device == "Mac":
            required["mac_raw"] = RAW_REQUIRED["mac_raw"]
    return required


def read_marketing_version() -> str:
    if not PROJECT_YML.exists():
        return "unknown"
    text = PROJECT_YML.read_text(encoding="utf-8")
    match = re.search(r"MARKETING_VERSION:\s*\"?([0-9]+\.[0-9]+\.[0-9]+)\"?", text)
    return match.group(1) if match else "unknown"


def ensure_fresh_raw_captures(devices: dict[str, list[str]]) -> None:
    max_age_hours = float(os.getenv("SCREENSHOT_MAX_AGE_HOURS", "168"))  # 7 days default
    max_age_seconds = max_age_hours * 3600.0
    allow_stale = os.getenv("ALLOW_STALE_SCREENSHOTS", "0").strip().lower() in {"1", "true", "yes"}
    now = time.time()

    missing: list[str] = []
    stale: list[str] = []

    for raw_folder, required_files in required_raw_folders(devices).items():
        folder = RAW_ROOT / raw_folder
        for name in required_files:
            path = folder / name
            if not path.exists():
                missing.append(str(path))
                continue
            age = now - path.stat().st_mtime
            if age > max_age_seconds:
                stale.append(f"{path} ({int(age // 3600)}h old)")

    if missing or stale:
        lines = ["Refusing to generate submission assets from stale/missing raw captures."]
        if missing:
            lines.append("Missing raw captures:")
            lines.extend([f"- {item}" for item in missing])
        if stale:
            lines.append(f"Stale raw captures (>{int(max_age_hours)}h):")
            lines.extend([f"- {item}" for item in stale])
        lines.append("Re-run UI screenshot capture tests, then regenerate store assets.")
        if allow_stale:
            print("⚠️  ALLOW_STALE_SCREENSHOTS enabled; continuing despite validation warnings.")
            print("\n".join(lines))
        else:
            raise RuntimeError("\n".join(lines))


def run_generator(devices: dict[str, list[str]]) -> None:
    venv_python = ROOT / ".venv" / "bin" / "python"
    python_bin = str(venv_python) if venv_python.exists() else sys.executable
    cmd = [python_bin, str(ROOT / "scripts" / "generate_marketing_screenshots.py")]

    env = os.environ.copy()
    # Strict mode: never reuse old listing assets as raw fallback.
    env["ALLOW_SCREENSHOT_FALLBACK"] = "0"
    env["STORE_ASSET_DEVICES"] = ",".join(devices)

    result = subprocess.run(cmd, cwd=ROOT, env=env, check=False)  # noqa: S603
    if result.returncode != 0:
        raise RuntimeError("Marketing screenshot generator failed")


def sync_canonical_files(device: str, names: list[str]) -> int:
    src_dir = MARKETING_ROOT / device
    dst_dir = STORE_ASSETS_ROOT / device
    if not src_dir.exists():
        raise RuntimeError(f"Missing generated marketing folder: {src_dir}")

    dst_dir.mkdir(parents=True, exist_ok=True)
    for existing in dst_dir.glob("*.png"):
        existing.unlink()

    copied = 0
    for name in names:
        src = src_dir / name
        if not src.exists():
            raise RuntimeError(f"Missing expected screenshot: {src}")
        shutil.copy2(src, dst_dir / name)
        copied += 1
    return copied


def write_manifest(copied: dict[str, int]) -> None:
    manifest = {
        "generated_at_epoch": int(time.time()),
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "app_marketing_version": read_marketing_version(),
        "strict_raw_fallback_disabled": True,
        "max_raw_age_hours": float(os.getenv("SCREENSHOT_MAX_AGE_HOURS", "168")),
        "devices": copied,
    }
    out = STORE_ASSETS_ROOT / "submission_manifest.json"
    out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main() -> None:
    devices = selected_devices()
    ensure_fresh_raw_captures(devices)
    run_generator(devices)

    copied: dict[str, int] = {}
    for device, files in devices.items():
        copied[device] = sync_canonical_files(device, files)

    write_manifest(copied)

    print("Generated strict App Store submission assets:")
    for device, count in copied.items():
        print(f"- {device}: {count} file(s)")
    print(f"- manifest: {STORE_ASSETS_ROOT / 'submission_manifest.json'}")


if __name__ == "__main__":
    main()
