from __future__ import annotations

import json
import time
from dataclasses import asdict, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from tek.src.engine import TraceRecord


DEFAULT_TRACE_MAX_BYTES = 10_000_000
DEFAULT_TRACE_BACKUP_COUNT = 3
DEFAULT_IDLE_HEARTBEAT_SECONDS = 5.0
# Successful dispatches are aggregated by default. A half-second bucket retains
# throughput/action evidence without a JSONL write for every 50 ms frame.
DEFAULT_ACTIVE_HEARTBEAT_SECONDS = 0.5


_NORMAL_DIAGNOSTIC_KEYS = {
    "physical_input_pause",
    "manual_held",
    "manual_reason",
    "wow_foreground",
    "foreground_reason",
    "input_sent_summary",
}


def _normal_diagnostics(diagnostics: dict | None) -> dict | None:
    """Keep normal trace rows small while preserving gate-relevant hints."""
    if not diagnostics:
        return None
    compact = {key: diagnostics[key] for key in _NORMAL_DIAGNOSTIC_KEYS if key in diagnostics}
    return compact or None


def trace_to_dict(record: TraceRecord, *, include_diagnostics: bool = True) -> dict:
    data = asdict(record)
    if not include_diagnostics:
        diagnostics = _normal_diagnostics(record.diagnostics)
        if diagnostics is None:
            data.pop("diagnostics", None)
        else:
            data["diagnostics"] = diagnostics
    data["schemaVersion"] = 1
    data["component"] = "TEK"
    if record.inputSent:
        data["eventType"] = "input_sent"
    elif record.dispatchAttempted:
        data["eventType"] = "input_dispatch"
    else:
        data["eventType"] = "input_blocked"
    data["observedAt"] = datetime.now(timezone.utc).isoformat()
    return data


def trace_signature(record: TraceRecord, *, full_debug: bool = True) -> tuple[Any, ...]:
    """Return a stable state signature.

    Full-debug mode preserves historical per-action trace behavior. Normal mode
    intentionally excludes successful action/binding churn; those events are
    emitted as bounded summaries by ``TraceSampler``.
    """
    diagnostics = record.diagnostics or {}
    common = (
        record.accepted,
        record.reason,
        record.state,
        record.tekState,
        record.gatePassed,
        record.dispatchAttempted,
        record.inputSent,
        record.dispatchError,
        diagnostics.get("physical_input_pause"),
        diagnostics.get("manual_held"),
        diagnostics.get("manual_reason"),
        diagnostics.get("wow_foreground"),
        diagnostics.get("foreground_reason"),
    )
    if full_debug:
        return common + (record.action_code, record.action_id, record.binding)
    return common


class TraceSampler:
    """Persist transitions and bounded heartbeats without per-frame JSONL I/O.

    Normal mode aggregates ``input_sent`` entries into a short bucket containing
    a count and the most recent action/binding. ``full_debug=True`` restores the
    previous event-by-event behavior for focused troubleshooting.
    """

    def __init__(
        self,
        *,
        idle_heartbeat_seconds: float = DEFAULT_IDLE_HEARTBEAT_SECONDS,
        active_heartbeat_seconds: float = DEFAULT_ACTIVE_HEARTBEAT_SECONDS,
        full_debug: bool = False,
        clock=time.monotonic,
    ) -> None:
        self.idle_heartbeat_seconds = max(0.05, float(idle_heartbeat_seconds))
        self.active_heartbeat_seconds = max(0.05, float(active_heartbeat_seconds))
        self.full_debug = bool(full_debug)
        self._clock = clock
        self._last_signature: tuple[Any, ...] | None = None
        self._last_written_at: float | None = None
        self._pending_input_count = 0
        self._pending_input_first_at: float | None = None
        self._pending_input_record: TraceRecord | None = None

    def should_write(self, record: TraceRecord) -> bool:
        """Compatibility predicate used by legacy tests/callers.

        New worker code should call ``records_to_write`` to receive the actual
        aggregate record. The predicate still advances sampler state exactly as
        a normal write decision would.
        """
        return bool(self.records_to_write(record))

    def records_to_write(self, record: TraceRecord) -> tuple[TraceRecord, ...]:
        if self.full_debug:
            return (record,) if self._should_write_full(record) else ()

        if record.inputSent:
            return self._collect_success(record)

        rows: list[TraceRecord] = []
        summary = self._flush_success()
        if summary is not None:
            rows.append(summary)
        if self._should_write_non_success(record):
            rows.append(record)
        return tuple(rows)

    def _should_write_full(self, record: TraceRecord) -> bool:
        now = self._clock()
        signature = trace_signature(record, full_debug=True)
        changed = signature != self._last_signature
        active = bool(record.inputSent or record.dispatchAttempted)
        interval = self.active_heartbeat_seconds if active else self.idle_heartbeat_seconds
        due = self._last_written_at is None or (now - self._last_written_at) >= interval
        if changed or due:
            self._last_signature = signature
            self._last_written_at = now
            return True
        return False

    def _should_write_non_success(self, record: TraceRecord) -> bool:
        now = self._clock()
        signature = trace_signature(record, full_debug=False)
        changed = signature != self._last_signature
        active = bool(record.dispatchAttempted)
        interval = self.active_heartbeat_seconds if active else self.idle_heartbeat_seconds
        due = self._last_written_at is None or (now - self._last_written_at) >= interval
        if changed or due:
            self._last_signature = signature
            self._last_written_at = now
            return True
        return False

    def _collect_success(self, record: TraceRecord) -> tuple[TraceRecord, ...]:
        now = self._clock()
        if self._pending_input_count == 0:
            self._pending_input_first_at = now
        self._pending_input_count += 1
        self._pending_input_record = record
        # Persist the first successful dispatch immediately so a fresh trace
        # shows that the session became active; later successes coalesce into
        # one bucket per active heartbeat interval.
        if self._last_written_at is None or (now - self._last_written_at) >= self.active_heartbeat_seconds:
            summary = self._flush_success(now=now)
            return (summary,) if summary is not None else ()
        return ()

    def _flush_success(self, *, now: float | None = None) -> TraceRecord | None:
        record = self._pending_input_record
        count = self._pending_input_count
        if record is None or count <= 0:
            return None
        observed = self._clock() if now is None else now
        first = self._pending_input_first_at if self._pending_input_first_at is not None else observed
        diagnostics = dict(record.diagnostics or {})
        diagnostics["input_sent_summary"] = {
            "count": count,
            "window_ms": max(0, int(round((observed - first) * 1000))),
            "last_action_code": record.action_code,
            "last_action_id": record.action_id,
            "last_binding": record.binding,
        }
        summary = replace(record, diagnostics=diagnostics)
        self._pending_input_count = 0
        self._pending_input_first_at = None
        self._pending_input_record = None
        self._last_signature = trace_signature(summary, full_debug=False)
        self._last_written_at = observed
        return summary


def _rotate_trace_files(target: Path, backup_count: int) -> None:
    if backup_count <= 0:
        target.unlink(missing_ok=True)
        return
    oldest = target.with_suffix(target.suffix + f".{backup_count}")
    oldest.unlink(missing_ok=True)
    for index in range(backup_count - 1, 0, -1):
        source = target.with_suffix(target.suffix + f".{index}")
        destination = target.with_suffix(target.suffix + f".{index + 1}")
        if source.exists():
            source.replace(destination)
    target.replace(target.with_suffix(target.suffix + ".1"))


def write_trace(
    record: TraceRecord,
    path: str | Path,
    *,
    max_bytes: int | None = None,
    backup_count: int = 1,
    include_diagnostics: bool = True,
) -> dict:
    data = trace_to_dict(record, include_diagnostics=include_diagnostics)
    encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    if max_bytes is not None and target.exists() and target.stat().st_size + len(encoded.encode("utf-8")) > max_bytes:
        _rotate_trace_files(target, backup_count)
    with target.open("a", encoding="utf-8") as file:
        file.write(encoded)
    return data


def render_trace(record: TraceRecord) -> str:
    return json.dumps(trace_to_dict(record), ensure_ascii=False, indent=2)
