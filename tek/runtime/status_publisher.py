from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass

from tek.runtime.runtime_status import TEKStatusSnapshot
from tek.runtime.status_store import StatusStore


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class StatusPublisherDiagnostics:
    submitted: int
    published: int
    failed: int
    coalesced: int
    last_error: str | None
    worker_alive: bool

    def to_dict(self) -> dict:
        return {
            "submitted": self.submitted,
            "published": self.published,
            "failed": self.failed,
            "coalesced": self.coalesced,
            "last_error": self.last_error,
            "worker_alive": self.worker_alive,
        }


def _snapshot_signature(snapshot: TEKStatusSnapshot) -> tuple:
    """Disk-publish fields that represent lifecycle or safety-state changes.

    Action code, binding, dispatch result and reason strings can change every
    active frame. They remain in the in-memory UI snapshot but must not force
    disk I/O. The publisher writes these stable snapshots on a one-second
    heartbeat when no key state changed.
    """
    return (
        snapshot.process_state,
        snapshot.safety_state,
        snapshot.mode,
        snapshot.signal_found,
        snapshot.wow_foreground,
        snapshot.error_message,
        snapshot.worker_alive,
        snapshot.last_protocol_version,
        snapshot.last_dispatch_origin,
        snapshot.last_in_combat,
        snapshot.monitor_flags,
    )


class StatusPublisher:
    """Coalesce status updates and publish them off the TEK sampling thread.

    Status changes are queued immediately; stable snapshots are persisted at a
    bounded rate.  Failed mirror writes are recorded and retried later, but
    never propagated to the dispatch worker.
    """

    def __init__(
        self,
        store: StatusStore,
        *,
        stable_interval_seconds: float = 1.0,
        retry_interval_seconds: float = 1.0,
        clock=time.monotonic,
    ) -> None:
        self.store = store
        self.stable_interval_seconds = max(0.05, float(stable_interval_seconds))
        self.retry_interval_seconds = max(0.10, float(retry_interval_seconds))
        self._clock = clock
        self._condition = threading.Condition(threading.RLock())
        self._thread: threading.Thread | None = None
        self._stop = False
        self._pending: TEKStatusSnapshot | None = None
        self._pending_signature: tuple | None = None
        self._urgent = False
        self._writing = False
        self._last_signature: tuple | None = None
        self._last_published_at: float | None = None
        self._next_retry_at = 0.0
        self._submitted = 0
        self._published = 0
        self._failed = 0
        self._coalesced = 0
        self._last_error: str | None = None
        self._last_error_log_at = 0.0

    def start(self) -> None:
        with self._condition:
            if self._thread and self._thread.is_alive():
                return
            self._stop = False
            self._thread = threading.Thread(target=self._run, name="TEKStatusPublisher", daemon=True)
            self._thread.start()

    def submit(self, snapshot: TEKStatusSnapshot, *, urgent: bool = False) -> None:
        signature = _snapshot_signature(snapshot)
        with self._condition:
            self._submitted += 1
            if self._pending is not None:
                self._coalesced += 1
            self._pending = snapshot
            self._pending_signature = signature
            if urgent or signature != self._last_signature:
                self._urgent = True
            self._condition.notify_all()

    def flush(self, *, timeout_seconds: float = 1.0) -> bool:
        deadline = self._clock() + max(0.0, timeout_seconds)
        with self._condition:
            if self._pending is not None:
                self._urgent = True
                self._condition.notify_all()
            while self._pending is not None or self._writing:
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
            return StatusPublisherDiagnostics(
                submitted=self._submitted,
                published=self._published,
                failed=self._failed,
                coalesced=self._coalesced,
                last_error=self._last_error,
                worker_alive=bool(self._thread and self._thread.is_alive()),
            ).to_dict()

    def _run(self) -> None:
        while True:
            with self._condition:
                while self._pending is None and not self._stop:
                    self._condition.wait()
                if self._stop and self._pending is None:
                    return

                now = self._clock()
                if not self._stop and now < self._next_retry_at:
                    self._condition.wait(timeout=self._next_retry_at - now)
                    continue

                signature = self._pending_signature
                state_changed = signature != self._last_signature
                due = (
                    self._urgent
                    or state_changed
                    or self._last_published_at is None
                    or (now - self._last_published_at) >= self.stable_interval_seconds
                )
                if not due:
                    wait_for = self.stable_interval_seconds - (now - self._last_published_at)
                    self._condition.wait(timeout=max(0.01, wait_for))
                    continue

                snapshot = self._pending
                self._pending = None
                self._pending_signature = None
                self._urgent = False
                self._writing = True

            write_error = None
            try:
                ok = bool(self.store.write(snapshot))
            except Exception as error:
                # The status mirror is presentation-only. Even an unexpected
                # serializer/store implementation failure must not kill this
                # publisher thread or ever reach the TEK dispatch worker.
                ok = False
                write_error = f"{type(error).__name__}:{error}"
            now = self._clock()
            with self._condition:
                self._writing = False
                if ok:
                    self._published += 1
                    self._last_signature = _snapshot_signature(snapshot)
                    self._last_published_at = now
                    self._last_error = None
                    self._next_retry_at = 0.0
                else:
                    self._failed += 1
                    self._last_error = write_error or getattr(self.store, "last_error", None) or "status_publish_failed"
                    self._next_retry_at = now + self.retry_interval_seconds
                    # Preserve the latest unsaved state. If a newer update
                    # arrived while writing, it already lives in _pending.
                    if self._pending is None and not self._stop:
                        self._pending = snapshot
                        self._pending_signature = _snapshot_signature(snapshot)
                    if now - self._last_error_log_at >= 30.0:
                        LOGGER.warning("TEK status publish deferred: %s", self._last_error)
                        self._last_error_log_at = now
                self._condition.notify_all()
