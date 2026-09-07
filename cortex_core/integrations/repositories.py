"""Persistence for integration raw payloads, dedupe, and sync cursors."""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class IntegrationRepository:
    """Stores raw external payloads and lightweight sync state."""

    def __init__(self, data_dir: Path):
        self.root = data_dir / "integrations"
        self.raw_dir = self.root / "raw"
        self.state_path = self.root / "state.json"
        self.root.mkdir(parents=True, exist_ok=True)
        self.raw_dir.mkdir(parents=True, exist_ok=True)
        self._state = self._load_state()
        self._dirty = False

    def _load_state(self) -> dict[str, Any]:
        if self.state_path.exists():
            try:
                with open(self.state_path, encoding="utf-8") as fh:
                    loaded = json.load(fh)
                return {
                    "seen": dict(loaded.get("seen", {})),
                    "cursors": dict(loaded.get("cursors", {})),
                    "last_sync": dict(loaded.get("last_sync", {})),
                }
            except Exception:
                logging.getLogger(__name__).warning("Cannot read integration state; starting with empty sync metadata")
        return {"seen": {}, "cursors": {}, "last_sync": {}}

    def _seen_set(self, source: str) -> set[str]:
        return set(self._state.setdefault("seen", {}).setdefault(source, []))

    def has_seen(self, source: str, fingerprint: str) -> bool:
        if not fingerprint:
            return False
        return fingerprint in self._seen_set(source)

    def mark_seen(self, source: str, fingerprint: str) -> None:
        if not fingerprint:
            return
        seen = self._seen_set(source)
        seen.add(fingerprint)
        self._state.setdefault("seen", {})[source] = sorted(seen)
        self._dirty = True

    def append_raw(
        self,
        *,
        source: str,
        kind: str,
        external_id: str,
        fingerprint: str,
        payload: dict[str, Any],
    ) -> None:
        record = {
            "source": source,
            "kind": kind,
            "external_id": external_id,
            "fingerprint": fingerprint,
            "ingested_at": datetime.now(UTC).isoformat(),
            "payload": payload,
        }
        out_path = self.raw_dir / f"{source}.jsonl"
        with open(out_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=True))
            fh.write("\n")
        self.mark_seen(source, fingerprint)

    def get_cursor(self, source: str, key: str) -> str:
        return str(self._state.setdefault("cursors", {}).setdefault(source, {}).get(key, "")).strip()

    def set_cursor(self, source: str, key: str, value: str) -> None:
        value = str(value or "").strip()
        if not value:
            return
        self._state.setdefault("cursors", {}).setdefault(source, {})[key] = value
        self._dirty = True

    def mark_synced(self, source: str) -> None:
        self._state.setdefault("last_sync", {})[source] = datetime.now(UTC).isoformat()
        self._dirty = True

    def save(self) -> None:
        if not self._dirty:
            return
        self.root.mkdir(parents=True, exist_ok=True)
        with open(self.state_path, "w", encoding="utf-8") as fh:
            json.dump(self._state, fh, indent=2)
        self._dirty = False
