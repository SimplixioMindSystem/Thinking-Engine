"""CocoIndex-backed incremental ingestion/enrichment storage for SimpliXio.

This module keeps ingestion concerns separated from ranking concerns.
It stores:
- raw_signals
- enriched_signals

Ranking and surfaced queues remain in SimpliXio (SignalMatcher/Engine).
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def _utc_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat()


def _sha256(payload: str) -> str:
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, sort_keys=True)


@dataclass
class RawUpsertResult:
    raw_signal_id: str
    changed: bool
    status: str
    payload_hash: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "raw_signal_id": self.raw_signal_id,
            "changed": self.changed,
            "status": self.status,
            "payload_hash": self.payload_hash,
        }


class CocoIndexSignalPipeline:
    """Small, inspectable CocoIndex-style pipeline with deterministic fallback.

    If the `cocoindex` package is available, we mark backend as cocoindex-backed.
    We keep SQLite storage for low operational overhead in this milestone.
    """

    PIPELINE_VERSION = "v1"

    def __init__(self, data_dir: Path):
        self.db_path = data_dir / "cocoindex_signals.sqlite3"
        self.backend = self._detect_backend()
        self._init_db()

    @staticmethod
    def _detect_backend() -> str:
        try:
            import cocoindex  # type: ignore # noqa: F401

            return "cocoindex"
        except Exception:
            return "fallback"

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS raw_signals (
                    id TEXT PRIMARY KEY,
                    source_type TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    captured_at TEXT NOT NULL,
                    raw_text TEXT NOT NULL,
                    normalised_text TEXT NOT NULL,
                    linked_project TEXT NOT NULL,
                    tags_json TEXT NOT NULL,
                    context_text TEXT NOT NULL,
                    payload_hash TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS enriched_signals (
                    id TEXT PRIMARY KEY,
                    raw_signal_id TEXT NOT NULL UNIQUE,
                    captured_at TEXT NOT NULL,
                    source_type TEXT NOT NULL,
                    raw_text TEXT NOT NULL,
                    normalised_text TEXT NOT NULL,
                    signal_type TEXT NOT NULL,
                    linked_project TEXT NOT NULL,
                    tags_json TEXT NOT NULL,
                    emotional_tone TEXT NOT NULL,
                    clarity_level REAL NOT NULL,
                    ambiguity_level REAL NOT NULL,
                    actionability REAL NOT NULL,
                    decision_readiness REAL NOT NULL,
                    recurrence_likelihood REAL NOT NULL,
                    sensitivity_level TEXT NOT NULL,
                    dependencies_json TEXT NOT NULL,
                    contradiction INTEGER NOT NULL,
                    trace_metadata_json TEXT NOT NULL,
                    enriched_hash TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_raw_source ON raw_signals(source_type, source_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_enriched_raw_signal_id ON enriched_signals(raw_signal_id)")

    @staticmethod
    def _raw_signal_id(event: dict[str, Any]) -> str:
        source_type = str(event.get("source", "")).strip().lower() or "capture"
        source_id = str(event.get("source_id", "")).strip()
        if source_id:
            return f"{source_type}:{source_id}"
        return str(event.get("id", "")).strip()

    @staticmethod
    def _normalise_text(text: str) -> str:
        return " ".join(str(text).strip().split())

    def upsert_raw_signal(self, event: dict[str, Any]) -> RawUpsertResult:
        raw_signal_id = self._raw_signal_id(event)
        captured_at = str(event.get("captured_at", "")).strip() or _utc_now()
        source_type = str(event.get("source", "")).strip() or "capture"
        source_id = str(event.get("source_id", "")).strip()
        raw_text = str(event.get("raw_text", "")).strip()
        normalised_text = self._normalise_text(raw_text)
        linked_project = str(event.get("project", "")).strip()
        context_text = str(event.get("context", "")).strip()
        tags = [str(tag).strip().lower() for tag in event.get("tags", []) if str(tag).strip()]
        payload_hash = _sha256(
            _json(
                {
                    "source_type": source_type,
                    "source_id": source_id,
                    "raw_text": raw_text,
                    "normalised_text": normalised_text,
                    "linked_project": linked_project,
                    "context_text": context_text,
                    "tags": tags,
                }
            )
        )
        now = _utc_now()

        with self._connect() as conn:
            existing = conn.execute(
                "SELECT payload_hash FROM raw_signals WHERE id = ?",
                (raw_signal_id,),
            ).fetchone()

            if existing is None:
                conn.execute(
                    """
                    INSERT INTO raw_signals (
                        id, source_type, source_id, captured_at, raw_text,
                        normalised_text, linked_project, tags_json, context_text,
                        payload_hash, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        raw_signal_id,
                        source_type,
                        source_id,
                        captured_at,
                        raw_text,
                        normalised_text,
                        linked_project,
                        _json(tags),
                        context_text,
                        payload_hash,
                        now,
                    ),
                )
                return RawUpsertResult(
                    raw_signal_id=raw_signal_id,
                    changed=True,
                    status="created",
                    payload_hash=payload_hash,
                )

            if str(existing["payload_hash"]) == payload_hash:
                conn.execute(
                    "UPDATE raw_signals SET updated_at = ? WHERE id = ?",
                    (now, raw_signal_id),
                )
                return RawUpsertResult(
                    raw_signal_id=raw_signal_id,
                    changed=False,
                    status="unchanged",
                    payload_hash=payload_hash,
                )

            conn.execute(
                """
                UPDATE raw_signals
                SET captured_at = ?, raw_text = ?, normalised_text = ?, linked_project = ?,
                    tags_json = ?, context_text = ?, payload_hash = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    captured_at,
                    raw_text,
                    normalised_text,
                    linked_project,
                    _json(tags),
                    context_text,
                    payload_hash,
                    now,
                    raw_signal_id,
                ),
            )
            return RawUpsertResult(
                raw_signal_id=raw_signal_id,
                changed=True,
                status="updated",
                payload_hash=payload_hash,
            )

    def get_enriched_signal(self, raw_signal_id: str) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM enriched_signals WHERE raw_signal_id = ?",
                (raw_signal_id,),
            ).fetchone()
        if row is None:
            return None
        data = dict(row)
        try:
            data["tags_json"] = json.loads(str(data.get("tags_json", "")) or "[]")
        except Exception:
            data["tags_json"] = []
        try:
            data["dependencies_json"] = json.loads(str(data.get("dependencies_json", "")) or "[]")
        except Exception:
            data["dependencies_json"] = []
        try:
            data["trace_metadata_json"] = json.loads(str(data.get("trace_metadata_json", "")) or "{}")
        except Exception:
            data["trace_metadata_json"] = {}
        return data

    def upsert_enriched_signal(
        self,
        *,
        raw_signal_id: str,
        enriched: dict[str, Any],
    ) -> dict[str, Any]:
        now = _utc_now()
        enriched_hash = _sha256(
            _json(
                {
                    "normalised_text": enriched.get("normalised_text", ""),
                    "signal_type": enriched.get("signal_type", ""),
                    "linked_project": enriched.get("linked_project", ""),
                    "tags": enriched.get("tags", []),
                    "emotional_tone": enriched.get("emotional_tone", ""),
                    "clarity_level": enriched.get("clarity_level", 0.0),
                    "ambiguity_level": enriched.get("ambiguity_level", 0.0),
                    "actionability": enriched.get("actionability", 0.0),
                    "decision_readiness": enriched.get("decision_readiness", 0.0),
                    "recurrence_likelihood": enriched.get("recurrence_likelihood", 0.0),
                    "sensitivity_level": enriched.get("sensitivity_level", "sensitive"),
                    "dependencies": enriched.get("dependencies", []),
                    "contradiction": bool(enriched.get("contradiction", False)),
                }
            )
        )

        trace_metadata = dict(enriched.get("trace_metadata", {}))
        trace_metadata.update(
            {
                "pipeline": "cocoindex_signals",
                "backend": self.backend,
                "pipeline_version": self.PIPELINE_VERSION,
                "raw_signal_id": raw_signal_id,
            }
        )

        record_id = str(enriched.get("id", "")).strip() or raw_signal_id

        with self._connect() as conn:
            existing = conn.execute(
                "SELECT id, enriched_hash FROM enriched_signals WHERE raw_signal_id = ?",
                (raw_signal_id,),
            ).fetchone()

            payload = (
                record_id,
                raw_signal_id,
                str(enriched.get("captured_at", "")).strip() or now,
                str(enriched.get("source_type", "")).strip() or "capture",
                str(enriched.get("raw_text", "")).strip(),
                str(enriched.get("normalised_text", "")).strip(),
                str(enriched.get("signal_type", "")).strip() or "thought",
                str(enriched.get("linked_project", "")).strip(),
                _json(enriched.get("tags", [])),
                str(enriched.get("emotional_tone", "")).strip() or "neutral",
                float(enriched.get("clarity_level", 0.0)),
                float(enriched.get("ambiguity_level", 0.0)),
                float(enriched.get("actionability", 0.0)),
                float(enriched.get("decision_readiness", 0.0)),
                float(enriched.get("recurrence_likelihood", 0.0)),
                str(enriched.get("sensitivity_level", "")).strip() or "sensitive",
                _json(enriched.get("dependencies", [])),
                1 if bool(enriched.get("contradiction", False)) else 0,
                _json(trace_metadata),
                enriched_hash,
                now,
            )

            if existing is None:
                conn.execute(
                    """
                    INSERT INTO enriched_signals (
                        id, raw_signal_id, captured_at, source_type, raw_text, normalised_text,
                        signal_type, linked_project, tags_json, emotional_tone, clarity_level,
                        ambiguity_level, actionability, decision_readiness, recurrence_likelihood,
                        sensitivity_level, dependencies_json, contradiction, trace_metadata_json,
                        enriched_hash, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    payload,
                )
                return {
                    "status": "created",
                    "changed": True,
                    "recomputed": True,
                    "enriched_hash": enriched_hash,
                    "trace_metadata": trace_metadata,
                }

            if str(existing["enriched_hash"]) == enriched_hash:
                conn.execute(
                    "UPDATE enriched_signals SET updated_at = ? WHERE raw_signal_id = ?",
                    (now, raw_signal_id),
                )
                return {
                    "status": "unchanged",
                    "changed": False,
                    "recomputed": False,
                    "enriched_hash": enriched_hash,
                    "trace_metadata": trace_metadata,
                }

            conn.execute(
                """
                UPDATE enriched_signals
                SET id = ?, captured_at = ?, source_type = ?, raw_text = ?, normalised_text = ?,
                    signal_type = ?, linked_project = ?, tags_json = ?, emotional_tone = ?,
                    clarity_level = ?, ambiguity_level = ?, actionability = ?, decision_readiness = ?,
                    recurrence_likelihood = ?, sensitivity_level = ?, dependencies_json = ?,
                    contradiction = ?, trace_metadata_json = ?, enriched_hash = ?, updated_at = ?
                WHERE raw_signal_id = ?
                """,
                (*payload[0:20], raw_signal_id),
            )
            return {
                "status": "updated",
                "changed": True,
                "recomputed": True,
                "enriched_hash": enriched_hash,
                "trace_metadata": trace_metadata,
            }

    def stats(self) -> dict[str, Any]:
        with self._connect() as conn:
            raw_count = int(conn.execute("SELECT COUNT(*) FROM raw_signals").fetchone()[0])
            enriched_count = int(conn.execute("SELECT COUNT(*) FROM enriched_signals").fetchone()[0])
        return {
            "backend": self.backend,
            "db_path": str(self.db_path),
            "raw_signals": raw_count,
            "enriched_signals": enriched_count,
            "pipeline_version": self.PIPELINE_VERSION,
        }
