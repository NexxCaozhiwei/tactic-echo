from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path

from tek.runtime.runtime_status import TEKStatusSnapshot
from tek.runtime.status_mapper import is_snapshot_stale, stale_snapshot


class StatusStore:
    """Best-effort, atomic status-file persistence.

    ``tek-status.json`` is a tray/UI mirror, never an input-safety dependency.
    A transient antivirus, explorer preview, or second reader lock must not be
    allowed to stop the TEK worker.  Writes therefore use a process/sequence
    unique temporary filename, bounded retry, and return ``False`` on failure
    instead of propagating file-system errors into the sampling loop.
    """

    _RETRY_DELAYS_SECONDS = (0.02, 0.05, 0.10)
    _STALE_TEMP_MAX_AGE_SECONDS = 24 * 60 * 60

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._write_lock = threading.RLock()
        self._temp_sequence = 0
        self._last_error: str | None = None
        self._failed_writes = 0
        self._successful_writes = 0
        self._cleanup_stale_temp_files()

    @property
    def last_error(self) -> str | None:
        with self._write_lock:
            return self._last_error

    def diagnostics(self) -> dict:
        with self._write_lock:
            return {
                "successful_writes": self._successful_writes,
                "failed_writes": self._failed_writes,
                "last_error": self._last_error,
            }

    def write(self, snapshot: TEKStatusSnapshot) -> bool:
        """Persist a lightweight status mirror without letting I/O kill TEK.

        The method is intentionally synchronous only for the dedicated status
        publisher.  The TEK sampling/dispatch worker queues updates to that
        publisher and never calls this method directly.
        """
        payload = snapshot.to_runtime_dict() if hasattr(snapshot, "to_runtime_dict") else snapshot.to_dict()
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"

        with self._write_lock:
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
            except OSError as error:
                self._record_failure(error)
                return False

            last_error: OSError | None = None
            for attempt in range(len(self._RETRY_DELAYS_SECONDS) + 1):
                temp_path = self._next_temp_path()
                try:
                    with temp_path.open("w", encoding="utf-8", newline="\n") as file:
                        file.write(encoded)
                        file.flush()
                    os.replace(temp_path, self.path)
                except OSError as error:
                    last_error = error
                    try:
                        temp_path.unlink(missing_ok=True)
                    except OSError:
                        pass
                    if attempt < len(self._RETRY_DELAYS_SECONDS):
                        time.sleep(self._RETRY_DELAYS_SECONDS[attempt])
                    continue

                self._successful_writes += 1
                self._last_error = None
                return True

            self._record_failure(last_error or OSError("status_write_failed"))
            return False

    def read(self, *, stale_after_seconds: float | None = None) -> TEKStatusSnapshot | None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            snapshot = TEKStatusSnapshot.from_dict(data)
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            return None
        if stale_after_seconds is not None and is_snapshot_stale(snapshot, max_age_seconds=stale_after_seconds):
            return stale_snapshot(snapshot)
        return snapshot

    def _next_temp_path(self) -> Path:
        self._temp_sequence += 1
        name = f"{self.path.name}.{os.getpid()}.{threading.get_ident()}.{self._temp_sequence}.tmp"
        return self.path.with_name(name)

    def _record_failure(self, error: OSError) -> None:
        self._failed_writes += 1
        self._last_error = f"{type(error).__name__}:{error}"

    def _cleanup_stale_temp_files(self) -> None:
        try:
            parent = self.path.parent
            if not parent.exists():
                return
            cutoff = time.time() - self._STALE_TEMP_MAX_AGE_SECONDS
            candidates = list(parent.glob(f"{self.path.name}.*.tmp"))
            # Remove the fixed legacy temporary name only when stale; it was
            # used before 0.9.9 and can otherwise survive a forced shutdown.
            candidates.append(self.path.with_suffix(self.path.suffix + ".tmp"))
            for candidate in candidates:
                try:
                    if candidate.exists() and candidate.stat().st_mtime < cutoff:
                        candidate.unlink(missing_ok=True)
                except OSError:
                    continue
        except OSError:
            return
