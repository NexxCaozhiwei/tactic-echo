"""Bounded asynchronous JSONL writer for TEK trace records.

Trace is diagnostic evidence, never a dispatch dependency.  The worker only
queues records; disk rotation, serialization and file contention are isolated
on this side thread.
"""
from __future__ import annotations

import logging
import threading
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path

from tek.src.engine import TraceRecord
from tek.src.trace import write_trace


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class _TraceJob:
    record: TraceRecord
    path: Path
    max_bytes: int
    backup_count: int
    include_diagnostics: bool
    priority: int


@dataclass(frozen=True)
class TraceWriterDiagnostics:
    submitted: int
    written: int
    failed: int
    dropped: int
    queued: int
    last_error: str | None
    worker_alive: bool

    def to_dict(self) -> dict:
        return {
            "submitted": self.submitted,
            "written": self.written,
            "failed": self.failed,
            "dropped": self.dropped,
            "queued": self.queued,
            "last_error": self.last_error,
            "worker_alive": self.worker_alive,
        }


class TraceWriter:
    """Write trace rows away from the TEAP sampling thread.

    High-priority records cover state changes, blocks and errors.  Aggregated
    normal success rows are low priority and are dropped first if the disk
    cannot keep up.  No writer error is ever propagated to the TEK worker.
    """

    def __init__(
        self,
        *,
        max_queue: int = 256,
        batch_size: int = 32,
        flush_interval_seconds: float = 0.25,
        clock=time.monotonic,
    ) -> None:
        self.max_queue = max(16, int(max_queue))
        self.batch_size = max(1, int(batch_size))
        self.flush_interval_seconds = max(0.01, float(flush_interval_seconds))
        self._clock = clock
        self._condition = threading.Condition(threading.RLock())
        self._queue: deque[_TraceJob] = deque()
        self._thread: threading.Thread | None = None
        self._stop = False
        self._writing = False
        self._submitted = 0
        self._written = 0
        self._failed = 0
        self._dropped = 0
        self._last_error: str | None = None
        self._last_error_log_at = 0.0

    def start(self) -> None:
        with self._condition:
            if self._thread and self._thread.is_alive():
                return
            self._stop = False
            self._thread = threading.Thread(target=self._run, name="TEKTraceWriter", daemon=True)
            self._thread.start()

    @staticmethod
    def _priority(record: TraceRecord) -> int:
        if record.dispatchError or record.reason in {"blocked", "manual_input_held", "frame_read_error"}:
            return 2
        if record.inputSent:
            return 0
        return 1

    def submit(
        self,
        record: TraceRecord,
        path: str | Path,
        *,
        max_bytes: int,
        backup_count: int,
        include_diagnostics: bool,
    ) -> bool:
        job = _TraceJob(
            record=record,
            path=Path(path),
            max_bytes=int(max_bytes),
            backup_count=int(backup_count),
            include_diagnostics=bool(include_diagnostics),
            priority=self._priority(record),
        )
        with self._condition:
            self._submitted += 1
            if len(self._queue) >= self.max_queue:
                if not self._make_room_for(job):
                    self._dropped += 1
                    return False
            self._queue.append(job)
            self._condition.notify_all()
            return True

    def _make_room_for(self, incoming: _TraceJob) -> bool:
        """Prefer preserving errors/state transitions over success summaries."""
        if incoming.priority <= 0:
            return False
        for index, queued in enumerate(self._queue):
            if queued.priority <= 0:
                del self._queue[index]
                self._dropped += 1
                return True
        if incoming.priority >= 2 and self._queue:
            self._queue.popleft()
            self._dropped += 1
            return True
        return False

    def flush(self, *, timeout_seconds: float = 1.0) -> bool:
        deadline = self._clock() + max(0.0, float(timeout_seconds))
        with self._condition:
            self._condition.notify_all()
            while self._queue or self._writing:
                remaining = deadline - self._clock()
                if remaining <= 0:
                    return False
                self._condition.wait(timeout=remaining)
            return self._last_error is None

    def stop(self, *, timeout_seconds: float = 1.0) -> None:
        self.flush(timeout_seconds=timeout_seconds)
        with self._condition:
            self._stop = True
            self._condition.notify_all()
            thread = self._thread
        if thread and thread.is_alive() and thread is not threading.current_thread():
            thread.join(timeout_seconds)
        with self._condition:
            self._thread = None

    def diagnostics(self) -> dict:
        with self._condition:
            return TraceWriterDiagnostics(
                submitted=self._submitted,
                written=self._written,
                failed=self._failed,
                dropped=self._dropped,
                queued=len(self._queue),
                last_error=self._last_error,
                worker_alive=bool(self._thread and self._thread.is_alive()),
            ).to_dict()

    def _run(self) -> None:
        while True:
            with self._condition:
                while not self._queue and not self._stop:
                    self._condition.wait(timeout=self.flush_interval_seconds)
                if self._stop and not self._queue:
                    return
                batch: list[_TraceJob] = []
                while self._queue and len(batch) < self.batch_size:
                    batch.append(self._queue.popleft())
                self._writing = True

            for job in batch:
                error_text = None
                try:
                    write_trace(
                        job.record,
                        job.path,
                        max_bytes=job.max_bytes,
                        backup_count=job.backup_count,
                        include_diagnostics=job.include_diagnostics,
                    )
                except Exception as error:  # trace is always side-channel only
                    error_text = f"{type(error).__name__}:{error}"

                now = self._clock()
                with self._condition:
                    if error_text is None:
                        self._written += 1
                    else:
                        self._failed += 1
                        self._last_error = error_text
                        if now - self._last_error_log_at >= 30.0:
                            LOGGER.warning("TEK trace writer deferred a record: %s", error_text)
                            self._last_error_log_at = now

            with self._condition:
                self._writing = False
                self._condition.notify_all()
