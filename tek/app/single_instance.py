from __future__ import annotations

import hashlib
import os
import threading
from pathlib import Path


class SingleInstance:
    """Cross-process TEK singleton with an in-process guard for deterministic tests.

    On Windows a named mutex is authoritative. On POSIX development hosts an
    advisory flock is used. The file remains useful for diagnostics and for
    stale-file recovery, but file presence alone never blocks a fresh launch.
    """

    _held_paths: set[str] = set()
    _registry_lock = threading.Lock()

    def __init__(self, lock_path: str | Path):
        self.lock_path = Path(lock_path)
        self._fd: int | None = None
        self._mutex_handle = None
        self._registered_path: str | None = None

    def acquire(self) -> bool:
        normalized = str(self.lock_path.resolve())
        with self._registry_lock:
            if normalized in self._held_paths:
                return False

        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        if os.name == "nt":
            if not self._acquire_windows_mutex(normalized):
                return False
        else:
            if not self._acquire_posix_lock():
                return False

        with self._registry_lock:
            if normalized in self._held_paths:
                self._release_os_lock()
                return False
            self._held_paths.add(normalized)
            self._registered_path = normalized

        try:
            self.lock_path.write_text(str(os.getpid()), encoding="ascii")
        except OSError:
            # The actual mutex/file lock remains valid even if diagnostics fail.
            pass
        return True

    def _acquire_windows_mutex(self, normalized: str) -> bool:
        import ctypes

        name = "Local\\TacticEcho-" + hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:24]
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.CreateMutexW(None, False, name)
        if not handle:
            return False
        ERROR_ALREADY_EXISTS = 183
        if kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
            kernel32.CloseHandle(handle)
            return False
        self._mutex_handle = handle
        return True

    def _acquire_posix_lock(self) -> bool:
        try:
            import fcntl

            self._fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except (ImportError, OSError):
            if self._fd is not None:
                try:
                    os.close(self._fd)
                except OSError:
                    pass
                self._fd = None
            return False

    def release(self) -> None:
        self._release_os_lock()
        if self._registered_path:
            with self._registry_lock:
                self._held_paths.discard(self._registered_path)
            self._registered_path = None
        try:
            self.lock_path.unlink()
        except OSError:
            pass

    def _release_os_lock(self) -> None:
        if self._mutex_handle is not None:
            try:
                import ctypes

                ctypes.windll.kernel32.ReleaseMutex(self._mutex_handle)
                ctypes.windll.kernel32.CloseHandle(self._mutex_handle)
            except Exception:
                pass
            self._mutex_handle = None
        if self._fd is not None:
            try:
                import fcntl

                fcntl.flock(self._fd, fcntl.LOCK_UN)
            except (ImportError, OSError):
                pass
            try:
                os.close(self._fd)
            except OSError:
                pass
            self._fd = None
