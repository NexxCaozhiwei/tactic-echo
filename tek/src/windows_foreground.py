import ctypes
import time
from dataclasses import dataclass

from tek.src.safety_gate import ForegroundSnapshot


def _basename(path: str | None) -> str | None:
    if not path:
        return None
    normalized = path.replace('\\', '/').rstrip('/')
    return normalized.rsplit('/', 1)[-1] or None


@dataclass(frozen=True)
class ForegroundWindow:
    hwnd: int
    title: str
    process_id: int
    process_name: str | None = None
    executable_path: str | None = None

    def to_dict(self) -> dict:
        return {
            'hwnd': self.hwnd,
            'title': self.title,
            'process_id': self.process_id,
            'process_name': self.process_name,
            'executable_path': self.executable_path,
        }


class WindowsForegroundDetector:
    """Foreground verifier with a bounded process-identity cache.

    TEK keeps both the pre-read and pre-dispatch foreground checks.  Those checks
    still retrieve the live HWND/PID on every tick; only expensive OpenProcess +
    executable-path lookup is cached while that identity remains unchanged.
    """

    def __init__(
        self,
        allowed_process_names: tuple[str, ...] = ('wow.exe', 'world of warcraft.exe'),
        *,
        process_cache_seconds: float = 0.75,
        title_cache_seconds: float = 0.50,
        clock=time.monotonic,
    ):
        self.user32 = ctypes.windll.user32
        self.kernel32 = ctypes.windll.kernel32
        self.allowed_process_names = {name.strip().lower() for name in allowed_process_names if name and name.strip()}
        self.process_cache_seconds = max(0.10, float(process_cache_seconds))
        self.title_cache_seconds = max(0.10, float(title_cache_seconds))
        self._clock = clock
        self._identity_cache: dict[tuple[int, int], tuple[float, str | None, str | None]] = {}
        self._title_cache: dict[int, tuple[float, str]] = {}

    def current(self) -> ForegroundWindow:
        hwnd = int(self.user32.GetForegroundWindow() or 0)
        if not hwnd:
            return ForegroundWindow(hwnd=0, title='', process_id=0)
        process_id = ctypes.c_ulong()
        self.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
        pid = int(process_id.value or 0)
        path, name = self._process_identity(hwnd, pid)
        return ForegroundWindow(
            hwnd=hwnd,
            title=self._window_title_cached(hwnd),
            process_id=pid,
            process_name=name,
            executable_path=path,
        )

    def snapshot(self) -> ForegroundSnapshot:
        try:
            window = self.current()
            common = dict(
                hwnd=window.hwnd,
                process_id=window.process_id,
                title=window.title,
                process_name=window.process_name,
                executable_path=window.executable_path,
            )
            if not window.hwnd:
                return ForegroundSnapshot(ok=False, reason='window_handle_invalid', **common)
            if not window.process_id:
                return ForegroundSnapshot(ok=False, reason='window_process_mismatch', **common)
            process_name = (window.process_name or '').casefold()
            title = (window.title or '').casefold()
            title_matches = 'world of warcraft' in title or '魔兽世界' in title
            process_matches = process_name in self.allowed_process_names
            if not process_matches:
                reason = 'foreground_not_game' if title_matches else 'window_process_mismatch'
                return ForegroundSnapshot(ok=False, reason=reason, **common)
            return ForegroundSnapshot(ok=True, reason='foreground_ok', **common)
        except Exception as error:
            return ForegroundSnapshot(ok=False, reason=f'foreground_check_error:{type(error).__name__}:{error}')

    def is_wow_foreground(self) -> bool:
        return self.snapshot().ok

    def light_snapshot(self, expected: ForegroundSnapshot | None = None) -> ForegroundSnapshot:
        """Cheap pre-dispatch continuity check using only HWND and PID.

        The read-side ``snapshot`` has already performed the full executable
        identity verification. Immediately before dispatch TEK only needs to
        prove that the foreground target did not change; re-querying title and
        process path every 50 ms adds work without strengthening that check.
        """
        try:
            hwnd = int(self.user32.GetForegroundWindow() or 0)
            if not hwnd:
                return ForegroundSnapshot(ok=False, reason="window_handle_invalid", hwnd=0, process_id=0)
            process_id = ctypes.c_ulong()
            self.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
            pid = int(process_id.value or 0)
            if not pid:
                return ForegroundSnapshot(ok=False, reason="window_process_mismatch", hwnd=hwnd, process_id=0)
            if expected is not None:
                if hwnd != expected.hwnd or pid != expected.process_id:
                    return ForegroundSnapshot(
                        ok=False,
                        reason="foreground_changed_before_dispatch",
                        hwnd=hwnd,
                        process_id=pid,
                    )
                return ForegroundSnapshot(
                    ok=True,
                    reason="foreground_ok",
                    hwnd=hwnd,
                    process_id=pid,
                    title=expected.title,
                    process_name=expected.process_name,
                    executable_path=expected.executable_path,
                )
            # Generic callers without a prior full snapshot retain fail-closed
            # behavior rather than treating an arbitrary HWND/PID as WoW.
            return ForegroundSnapshot(ok=False, reason="foreground_recheck_missing_baseline", hwnd=hwnd, process_id=pid)
        except Exception as error:
            return ForegroundSnapshot(ok=False, reason=f"foreground_check_error:{type(error).__name__}:{error}")

    def _process_identity(self, hwnd: int, process_id: int) -> tuple[str | None, str | None]:
        if not process_id:
            return None, None
        cache = getattr(self, '_identity_cache', None)
        if cache is None:
            cache = {}
            self._identity_cache = cache
        ttl = max(0.10, float(getattr(self, 'process_cache_seconds', 0.75)))
        clock = getattr(self, '_clock', time.monotonic)
        now = clock()
        key = (int(hwnd), int(process_id))
        cached = cache.get(key)
        if cached and cached[0] > now:
            return cached[1], cached[2]

        path = self._process_path(process_id)
        name = _basename(path)
        # Only retain the active identity; this bounds memory across app/window
        # switches while preserving both safety checks' live HWND/PID observation.
        cache.clear()
        cache[key] = (now + ttl, path, name)
        return path, name

    def _window_title_cached(self, hwnd: int) -> str:
        """Return a short-lived title cache for a stable foreground HWND.

        The live HWND/PID checks remain uncached.  Window text is only useful
        for diagnostics and process/title mismatch wording, so re-reading it
        twenty times per second provides no additional dispatch safety.
        """
        cache = getattr(self, "_title_cache", None)
        if cache is None:
            cache = {}
            self._title_cache = cache
        clock = getattr(self, "_clock", time.monotonic)
        ttl = max(0.10, float(getattr(self, "title_cache_seconds", 0.50)))
        now = clock()
        cached = cache.get(int(hwnd))
        if cached and cached[0] > now:
            return cached[1]
        title = self._window_title(hwnd)
        # Keep only the current foreground identity; bounded memory matters
        # more than retaining titles for inactive windows.
        cache.clear()
        cache[int(hwnd)] = (now + ttl, title)
        return title

    def _window_title(self, hwnd: int) -> str:
        length = int(self.user32.GetWindowTextLengthW(hwnd) or 0)
        buffer = ctypes.create_unicode_buffer(length + 1)
        self.user32.GetWindowTextW(hwnd, buffer, length + 1)
        return buffer.value

    def _process_path(self, process_id: int) -> str | None:
        if not process_id:
            return None
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = self.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, process_id)
        if not handle:
            return None
        try:
            query = getattr(self.kernel32, 'QueryFullProcessImageNameW', None)
            if query:
                size = ctypes.c_ulong(32768)
                buffer = ctypes.create_unicode_buffer(size.value)
                try:
                    if query(handle, 0, buffer, ctypes.byref(size)):
                        return buffer.value
                except Exception:
                    pass
            # Fallback covers systems/processes where QueryFullProcessImageNameW is unavailable/denied.
            try:
                psapi = ctypes.WinDLL('psapi')
                get_image = psapi.GetProcessImageFileNameW
                buffer = ctypes.create_unicode_buffer(32768)
                if get_image(handle, buffer, len(buffer)):
                    return buffer.value
            except Exception:
                pass
            return None
        finally:
            self.kernel32.CloseHandle(handle)
