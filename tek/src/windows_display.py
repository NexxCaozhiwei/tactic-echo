"""Windows DPI, virtual-desktop and foreground-window calibration helpers.

All functions are defensive and report capabilities rather than assuming that a
specific Windows compositor, monitor topology or window mode exists.  They are
used only for TEAP pixel sampling calibration; they do not send input.
"""
from __future__ import annotations

import ctypes
import os
from dataclasses import asdict, dataclass


SM_XVIRTUALSCREEN = 76
SM_YVIRTUALSCREEN = 77
SM_CXVIRTUALSCREEN = 78
SM_CYVIRTUALSCREEN = 79
MONITOR_DEFAULTTONEAREST = 2
GWL_STYLE = -16
WS_POPUP = 0x80000000


@dataclass(frozen=True)
class VirtualDesktopBounds:
    left: int = 0
    top: int = 0
    width: int = 0
    height: int = 0

    @property
    def right(self) -> int:
        return self.left + self.width

    @property
    def bottom(self) -> int:
        return self.top + self.height

    def to_dict(self) -> dict:
        return asdict(self) | {"right": self.right, "bottom": self.bottom}


@dataclass(frozen=True)
class DpiAwarenessResult:
    enabled: bool
    mode: str
    reason: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class WindowCalibration:
    hwnd: int = 0
    dpi: int | None = None
    window_mode: str = "unknown"
    window_rect: tuple[int, int, int, int] | None = None
    client_rect: tuple[int, int, int, int] | None = None
    client_origin: tuple[int, int] | None = None
    monitor_rect: tuple[int, int, int, int] | None = None
    virtual_desktop: VirtualDesktopBounds | None = None
    reason: str | None = None

    def to_dict(self) -> dict:
        data = asdict(self)
        if self.virtual_desktop is not None:
            data["virtual_desktop"] = self.virtual_desktop.to_dict()
        return data


class _RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long), ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


class _POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


class _MONITORINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", ctypes.c_ulong),
        ("rcMonitor", _RECT),
        ("rcWork", _RECT),
        ("dwFlags", ctypes.c_ulong),
    ]


def enable_per_monitor_dpi_awareness() -> DpiAwarenessResult:
    """Request Per-Monitor V2 awareness before Tk/Pillow create windows.

    The request is process-global and may legitimately fail when another
    bootstrapper has already chosen a DPI mode.  That is reported instead of
    being treated as a fatal TEK error.
    """
    if os.name != "nt":
        return DpiAwarenessResult(False, "unsupported", "windows_only")
    try:
        user32 = ctypes.windll.user32
        setter = getattr(user32, "SetProcessDpiAwarenessContext", None)
        if setter and setter(ctypes.c_void_p(-4)):  # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
            return DpiAwarenessResult(True, "per_monitor_v2")
        legacy = getattr(user32, "SetProcessDPIAware", None)
        if legacy and legacy():
            return DpiAwarenessResult(True, "system_aware_fallback")
        return DpiAwarenessResult(False, "unchanged", "dpi_context_not_changed")
    except Exception as error:
        return DpiAwarenessResult(False, "error", f"{type(error).__name__}:{error}")


def virtual_desktop_bounds() -> VirtualDesktopBounds:
    if os.name != "nt":
        return VirtualDesktopBounds()
    try:
        user32 = ctypes.windll.user32
        return VirtualDesktopBounds(
            left=int(user32.GetSystemMetrics(SM_XVIRTUALSCREEN)),
            top=int(user32.GetSystemMetrics(SM_YVIRTUALSCREEN)),
            width=int(user32.GetSystemMetrics(SM_CXVIRTUALSCREEN)),
            height=int(user32.GetSystemMetrics(SM_CYVIRTUALSCREEN)),
        )
    except Exception:
        return VirtualDesktopBounds()


def _rect_tuple(rect: _RECT) -> tuple[int, int, int, int]:
    return int(rect.left), int(rect.top), int(rect.right), int(rect.bottom)


def inspect_window_calibration(hwnd: int | None = None) -> WindowCalibration:
    desktop = virtual_desktop_bounds()
    if os.name != "nt":
        return WindowCalibration(virtual_desktop=desktop, reason="windows_only")
    try:
        user32 = ctypes.windll.user32
        hwnd = int(hwnd or user32.GetForegroundWindow() or 0)
        if not hwnd:
            return WindowCalibration(virtual_desktop=desktop, reason="foreground_window_missing")
        window = _RECT()
        client = _RECT()
        if not user32.GetWindowRect(hwnd, ctypes.byref(window)):
            return WindowCalibration(hwnd=hwnd, virtual_desktop=desktop, reason="GetWindowRect_failed")
        if not user32.GetClientRect(hwnd, ctypes.byref(client)):
            return WindowCalibration(hwnd=hwnd, window_rect=_rect_tuple(window), virtual_desktop=desktop, reason="GetClientRect_failed")
        client_origin = _POINT(0, 0)
        user32.ClientToScreen(hwnd, ctypes.byref(client_origin))
        dpi = None
        get_dpi = getattr(user32, "GetDpiForWindow", None)
        if get_dpi:
            reported = int(get_dpi(hwnd) or 0)
            dpi = reported or None
        monitor_rect = None
        monitor = user32.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)
        if monitor:
            info = _MONITORINFO()
            info.cbSize = ctypes.sizeof(_MONITORINFO)
            if user32.GetMonitorInfoW(monitor, ctypes.byref(info)):
                monitor_rect = _rect_tuple(info.rcMonitor)
        style = int(user32.GetWindowLongW(hwnd, GWL_STYLE))
        window_rect = _rect_tuple(window)
        if monitor_rect and window_rect == monitor_rect:
            mode = "borderless_or_fullscreen"
        elif style & WS_POPUP:
            mode = "borderless"
        else:
            mode = "windowed"
        return WindowCalibration(
            hwnd=hwnd,
            dpi=dpi,
            window_mode=mode,
            window_rect=window_rect,
            client_rect=_rect_tuple(client),
            client_origin=(int(client_origin.x), int(client_origin.y)),
            monitor_rect=monitor_rect,
            virtual_desktop=desktop,
        )
    except Exception as error:
        return WindowCalibration(hwnd=int(hwnd or 0), virtual_desktop=desktop, reason=f"{type(error).__name__}:{error}")


def inspect_client_geometry(hwnd: int | None = None) -> WindowCalibration:
    """Read only the client rectangle and its screen origin.

    This is the hot-path counterpart to :func:`inspect_window_calibration`.
    It deliberately avoids monitor lookup, DPI lookup, window-style lookup and
    virtual-desktop metrics.  Normal TEAP sampling needs current client bounds
    every tick; expensive display metadata is refreshed on a slower cadence.
    """
    if os.name != "nt":
        return WindowCalibration(reason="windows_only")
    try:
        user32 = ctypes.windll.user32
        hwnd = int(hwnd or user32.GetForegroundWindow() or 0)
        if not hwnd:
            return WindowCalibration(reason="foreground_window_missing")
        client = _RECT()
        if not user32.GetClientRect(hwnd, ctypes.byref(client)):
            return WindowCalibration(hwnd=hwnd, reason="GetClientRect_failed")
        client_origin = _POINT(0, 0)
        if not user32.ClientToScreen(hwnd, ctypes.byref(client_origin)):
            return WindowCalibration(hwnd=hwnd, client_rect=_rect_tuple(client), reason="ClientToScreen_failed")
        return WindowCalibration(
            hwnd=hwnd,
            client_rect=_rect_tuple(client),
            client_origin=(int(client_origin.x), int(client_origin.y)),
        )
    except Exception as error:
        return WindowCalibration(hwnd=int(hwnd or 0), reason=f"{type(error).__name__}:{error}")


def client_capture_bounds(calibration: WindowCalibration):
    """Return a screen-global client rectangle suitable for Pillow capture.

    ``GetClientRect`` is client-local while ``ClientToScreen`` supplies the
    screen-global origin. Returning a plain tuple avoids a dependency from this
    low-level Windows module back into the sampler module.
    """
    if not calibration:
        return None
    client_origin = getattr(calibration, "client_origin", None)
    client_rect = getattr(calibration, "client_rect", None)
    if not client_origin or not client_rect:
        return None
    left_local, top_local, right_local, bottom_local = client_rect
    width = int(right_local) - int(left_local)
    height = int(bottom_local) - int(top_local)
    if width <= 0 or height <= 0:
        return None
    origin_x, origin_y = client_origin
    left = int(origin_x) + int(left_local)
    top = int(origin_y) + int(top_local)
    return left, top, left + width, top + height
