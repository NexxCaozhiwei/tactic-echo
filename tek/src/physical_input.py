"""Manual-input ownership and Windows physical-input monitoring for TEK.

The gate is deliberately fail-safe:

* a non-exempt physical keyboard key *owns* input until it is released;
* after the final release, TEK waits according to the selected recovery policy
  and then observes the required number of new TEAP freshness frames;
* a replay guard prevents the last automatically dispatched token from being
  immediately re-sent while the game state is still catching up;
* injected SendInput events are ignored by the hook so TEK never yields to
  itself; and
* real Windows SendInput is blocked unless the required low-level keyboard hook is healthy.

Mouse input is intentionally ignored in full by the user-approved policy.
"""
from __future__ import annotations

import ctypes
import os
import threading
import time
from dataclasses import dataclass
from typing import Callable

from tek.src.keyboard_whitelist import KeyboardInterventionWhitelist

DEFAULT_RECOVERY_SECONDS = 0.030
MANUAL_PRIORITY_POLICIES = {
    # "balanced" is the product default: manual keys yield immediately, then
    # recover after a short 30 ms release delay plus two 50 ms TEAP freshness
    # frames. The replay guard only covers the same action/token pair.
    "aggressive": {"recovery_seconds": 0.000, "freshness_frames": 1, "replay_guard_seconds": 0.100},
    "balanced": {"recovery_seconds": 0.030, "freshness_frames": 2, "replay_guard_seconds": 0.150},
    "manual_first": {"recovery_seconds": 0.250, "freshness_frames": 2, "replay_guard_seconds": 0.500},
}
# Kept for compatibility with prior tests/settings imports.
MANUAL_PRIORITY_PROFILES = {key: value["recovery_seconds"] for key, value in MANUAL_PRIORITY_POLICIES.items()}

LLKHF_INJECTED = 0x00000010
LLMHF_INJECTED = 0x00000001

WH_KEYBOARD_LL = 13
WH_MOUSE_LL = 14
HC_ACTION = 0
WM_QUIT = 0x0012
WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_SYSKEYDOWN = 0x0104
WM_SYSKEYUP = 0x0105
WM_LBUTTONDOWN = 0x0201
WM_LBUTTONUP = 0x0202
WM_RBUTTONDOWN = 0x0204
WM_RBUTTONUP = 0x0205
WM_MBUTTONDOWN = 0x0207
WM_MBUTTONUP = 0x0208
WM_MOUSEWHEEL = 0x020A
WM_XBUTTONDOWN = 0x020B
WM_XBUTTONUP = 0x020C
WM_MOUSEHWHEEL = 0x020E

VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12
VK_LSHIFT = 0xA0
VK_RSHIFT = 0xA1
VK_LCONTROL = 0xA2
VK_RCONTROL = 0xA3
VK_LMENU = 0xA4
VK_RMENU = 0xA5

_MODIFIER_VKS = {
    VK_SHIFT: "SHIFT", VK_LSHIFT: "SHIFT", VK_RSHIFT: "SHIFT",
    VK_CONTROL: "CTRL", VK_LCONTROL: "CTRL", VK_RCONTROL: "CTRL",
    VK_MENU: "ALT", VK_LMENU: "ALT", VK_RMENU: "ALT",
}
_MODIFIER_HOLD_NAMES = {
    VK_SHIFT: "SHIFT", VK_LSHIFT: "LSHIFT", VK_RSHIFT: "RSHIFT",
    VK_CONTROL: "CTRL", VK_LCONTROL: "LCTRL", VK_RCONTROL: "RCTRL",
    VK_MENU: "ALT", VK_LMENU: "LALT", VK_RMENU: "RALT",
}

_SPECIAL_VK_NAMES = {
    0x08: "BACKSPACE", 0x09: "TAB", 0x0D: "ENTER", 0x1B: "ESC",
    0x20: "SPACE", 0x21: "PAGEUP", 0x22: "PAGEDOWN", 0x23: "END",
    0x24: "HOME", 0x25: "LEFT", 0x26: "UP", 0x27: "RIGHT", 0x28: "DOWN",
    0x2D: "INSERT", 0x2E: "DELETE", 0x70: "F1", 0x71: "F2", 0x72: "F3", 0x73: "F4",
    0xC0: "`", 0xBF: "/",
}


@dataclass(frozen=True)
class ManualPriorityPolicy:
    name: str
    recovery_seconds: float
    freshness_frames: int
    replay_guard_seconds: float


@dataclass(frozen=True)
class PhysicalInputSnapshot:
    active: bool
    manual_held: bool
    remaining_ms: int
    last_kind: str | None
    observed_events: int
    ignored_injected_events: int
    recovery_ms: int
    manual_epoch: int
    phase: str
    held_inputs: tuple[str, ...]
    required_freshness_frames: int
    observed_freshness_frames: int
    replay_guard_ms: int
    replay_guard_active: bool
    teap_manual_hold: bool


def policy_for(
    profile: str | None,
    *,
    custom_recovery_seconds: float | None = None,
    custom_freshness_frames: int | None = None,
    custom_replay_guard_seconds: float | None = None,
) -> ManualPriorityPolicy:
    name = str(profile or "balanced").strip().lower()
    if name == "custom":
        return ManualPriorityPolicy(
            name="custom",
            recovery_seconds=max(0.0, min(1.500, float(custom_recovery_seconds if custom_recovery_seconds is not None else 0.030))),
            freshness_frames=max(1, min(2, int(custom_freshness_frames if custom_freshness_frames is not None else 2))),
            replay_guard_seconds=max(0.0, min(1.500, float(custom_replay_guard_seconds if custom_replay_guard_seconds is not None else 0.150))),
        )
    data = MANUAL_PRIORITY_POLICIES.get(name, MANUAL_PRIORITY_POLICIES["balanced"])
    return ManualPriorityPolicy(
        name=name if name in MANUAL_PRIORITY_POLICIES else "balanced",
        recovery_seconds=float(data["recovery_seconds"]),
        freshness_frames=int(data["freshness_frames"]),
        replay_guard_seconds=float(data["replay_guard_seconds"]),
    )


class PhysicalInputPause:
    """Thread-safe manual-input ownership state machine.

    The class keeps its historical name to avoid an unnecessary public API
    break, but it no longer represents a one-shot timer.  Keyboard keydown
    enters a held ownership state; the final keyup starts the recovery phase.
    """

    DISPATCHABLE = "DISPATCHABLE"
    MANUAL_HELD = "MANUAL_HELD"
    RELEASE_DELAY = "RELEASE_DELAY"
    WAIT_FRESHNESS = "WAIT_FRESHNESS"
    REPLAY_GUARD = "REPLAY_GUARD"

    def __init__(
        self,
        *,
        recovery_seconds: float = DEFAULT_RECOVERY_SECONDS,
        profile: str | None = None,
        custom_freshness_frames: int | None = None,
        custom_replay_guard_seconds: float | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        policy = policy_for(
            profile,
            custom_recovery_seconds=recovery_seconds if profile == "custom" else None,
            custom_freshness_frames=custom_freshness_frames,
            custom_replay_guard_seconds=custom_replay_guard_seconds,
        )
        # Legacy direct recovery_seconds callers remain valid when profile is not
        # supplied.  They receive balanced freshness/replay semantics.
        if profile is None:
            policy = ManualPriorityPolicy(
                name="legacy",
                recovery_seconds=max(0.0, min(1.500, float(recovery_seconds))),
                freshness_frames=1,
                replay_guard_seconds=0.150,
            )
        self.policy = policy
        self.profile = policy.name
        self.recovery_seconds = policy.recovery_seconds
        self._clock = clock
        self._lock = threading.RLock()
        self._held_inputs: set[str] = set()
        self._teap_manual_hold = False
        self._phase = self.DISPATCHABLE
        self._release_deadline: float | None = None
        self._last_kind: str | None = None
        self._observed_events = 0
        self._ignored_injected_events = 0
        self._manual_epoch = 0
        self._last_observed_freshness: int | None = None
        self._freshness_baseline: int | None = None
        self._observed_freshness_frames = 0
        self._last_auto_token: int | None = None
        self._last_auto_sequence: int | None = None
        self._replay_token: int | None = None
        self._replay_sequence: int | None = None
        self._replay_deadline: float | None = None

    @property
    def manual_epoch(self) -> int:
        with self._lock:
            return self._manual_epoch

    def epoch(self) -> int:
        return self.manual_epoch

    def note_auto_dispatch(self, binding_token: int | None, action_sequence: int | None) -> None:
        with self._lock:
            self._last_auto_token = int(binding_token) if binding_token else None
            self._last_auto_sequence = int(action_sequence) if action_sequence is not None else None

    def begin_manual_hold(self, kind: str, *, injected: bool = False, now: float | None = None) -> bool:
        timestamp = self._clock() if now is None else float(now)
        identifier = str(kind or "keyboard")
        with self._lock:
            if injected:
                self._ignored_injected_events += 1
                return False
            if identifier in self._held_inputs:
                return False
            was_active = self._has_owner_locked()
            self._held_inputs.add(identifier)
            self._last_kind = identifier
            self._observed_events += 1
            self._manual_epoch += 1
            self._release_deadline = None
            self._observed_freshness_frames = 0
            if not was_active:
                self._arm_replay_guard_locked(timestamp)
            self._phase = self.MANUAL_HELD
            return True

    def end_manual_hold(self, kind: str, *, injected: bool = False, now: float | None = None) -> bool:
        timestamp = self._clock() if now is None else float(now)
        identifier = str(kind or "keyboard")
        with self._lock:
            if injected:
                self._ignored_injected_events += 1
                return False
            if identifier not in self._held_inputs:
                return False
            self._held_inputs.remove(identifier)
            self._last_kind = identifier
            self._observed_events += 1
            if not self._has_owner_locked():
                self._begin_release_locked(timestamp)
            return True

    def observe(self, kind: str, *, injected: bool = False, now: float | None = None) -> bool:
        """Compatibility helper for a momentary manual pulse.

        Production keyboard input uses explicit down/up methods.  This helper
        models a pulse as immediate down then up, useful for tests or callers
        that have no release event.
        """
        timestamp = self._clock() if now is None else float(now)
        if not self.begin_manual_hold(kind, injected=injected, now=timestamp):
            return False
        self.end_manual_hold(kind, injected=injected, now=timestamp)
        return True

    def begin_teap_manual_hold(self, *, now: float | None = None) -> bool:
        timestamp = self._clock() if now is None else float(now)
        with self._lock:
            if self._teap_manual_hold:
                return False
            was_active = self._has_owner_locked()
            self._teap_manual_hold = True
            self._last_kind = "teap_manual_hold"
            self._observed_events += 1
            self._manual_epoch += 1
            self._release_deadline = None
            self._observed_freshness_frames = 0
            if not was_active:
                self._arm_replay_guard_locked(timestamp)
            self._phase = self.MANUAL_HELD
            return True

    def end_teap_manual_hold(self, *, now: float | None = None) -> bool:
        timestamp = self._clock() if now is None else float(now)
        with self._lock:
            if not self._teap_manual_hold:
                return False
            self._teap_manual_hold = False
            self._last_kind = "teap_manual_hold_release"
            self._observed_events += 1
            if not self._has_owner_locked():
                self._begin_release_locked(timestamp)
            return True

    def observe_teap_state(self, state: str, *, now: float | None = None) -> None:
        if str(state or "").lower() == "manual_hold":
            self.begin_teap_manual_hold(now=now)
        else:
            self.end_teap_manual_hold(now=now)

    def observe_freshness(self, freshness: int | None, *, now: float | None = None) -> None:
        if freshness is None:
            return
        timestamp = self._clock() if now is None else float(now)
        value = int(freshness) % 65536
        with self._lock:
            self._advance_locked(timestamp)
            previous = self._last_observed_freshness
            self._last_observed_freshness = value
            if self._phase != self.WAIT_FRESHNESS:
                return
            baseline = self._freshness_baseline
            if baseline is None:
                self._freshness_baseline = value
                return
            if previous == value or not self._is_newer(value, baseline):
                return
            self._freshness_baseline = value
            self._observed_freshness_frames += 1
            if self._observed_freshness_frames >= self.policy.freshness_frames:
                self._phase = self.REPLAY_GUARD if self._replay_guard_is_active_locked(timestamp) else self.DISPATCHABLE

    def dispatch_block_reason(
        self,
        *,
        binding_token: int | None = None,
        action_sequence: int | None = None,
        now: float | None = None,
    ) -> str | None:
        timestamp = self._clock() if now is None else float(now)
        with self._lock:
            self._advance_locked(timestamp)
            if self._held_inputs:
                return "manual_input_held"
            if self._teap_manual_hold:
                return "teap_manual_hold"
            if self._phase == self.RELEASE_DELAY:
                return "manual_release_delay"
            if self._phase == self.WAIT_FRESHNESS:
                return "manual_wait_freshness"
            if self._phase == self.REPLAY_GUARD:
                if self._replay_deadline is not None and timestamp >= self._replay_deadline:
                    self._clear_replay_guard_locked()
                    self._phase = self.DISPATCHABLE
                    return None
                token = int(binding_token) if binding_token else None
                sequence = int(action_sequence) if action_sequence is not None else None
                # A changed official recommendation/action sequence is a
                # meaningful game-state transition and may dispatch normally.
                if token != self._replay_token or sequence != self._replay_sequence:
                    self._clear_replay_guard_locked()
                    self._phase = self.DISPATCHABLE
                    return None
                return "manual_replay_guard"
            return None

    def is_paused(self, *, now: float | None = None) -> bool:
        """Return whether manual ownership currently blocks dispatch without mutation.

        ``dispatch_block_reason`` is the state-machine advancement point: it may
        expire or clear a replay guard after inspecting a concrete TEAP
        recommendation.  UI/diagnostic callers often only need a read-only
        answer, so this method must never advance phases or clear any guard.
        """

        timestamp = self._clock() if now is None else float(now)
        with self._lock:
            if self._held_inputs or self._teap_manual_hold:
                return True
            if self._phase == self.RELEASE_DELAY:
                return self._release_deadline is None or timestamp < self._release_deadline
            if self._phase == self.WAIT_FRESHNESS:
                return True
            if self._phase == self.REPLAY_GUARD:
                # Do not clear an elapsed replay guard here. The next explicit
                # dispatch decision advances state and owns that transition.
                return self._replay_deadline is None or timestamp < self._replay_deadline
            return False

    def remaining_seconds(self, *, now: float | None = None) -> float:
        timestamp = self._clock() if now is None else float(now)
        with self._lock:
            self._advance_locked(timestamp)
            if self._held_inputs or self._teap_manual_hold:
                return self.policy.recovery_seconds
            if self._phase == self.RELEASE_DELAY and self._release_deadline is not None:
                return max(0.0, self._release_deadline - timestamp)
            return 0.0

    def snapshot(self, *, now: float | None = None) -> PhysicalInputSnapshot:
        timestamp = self._clock() if now is None else float(now)
        with self._lock:
            self._advance_locked(timestamp)
            remaining = self.remaining_seconds(now=timestamp)
            replay_ms = 0
            if self._replay_deadline is not None:
                replay_ms = int(round(max(0.0, self._replay_deadline - timestamp) * 1000))
            manual_held = bool(self._held_inputs or self._teap_manual_hold)
            return PhysicalInputSnapshot(
                active=self._phase != self.DISPATCHABLE,
                manual_held=manual_held,
                remaining_ms=int(round(remaining * 1000)),
                last_kind=self._last_kind,
                observed_events=self._observed_events,
                ignored_injected_events=self._ignored_injected_events,
                recovery_ms=int(round(self.policy.recovery_seconds * 1000)),
                manual_epoch=self._manual_epoch,
                phase=self._phase,
                held_inputs=tuple(sorted(self._held_inputs)),
                required_freshness_frames=self.policy.freshness_frames,
                observed_freshness_frames=self._observed_freshness_frames,
                replay_guard_ms=replay_ms,
                replay_guard_active=self._phase == self.REPLAY_GUARD and replay_ms > 0,
                teap_manual_hold=self._teap_manual_hold,
            )

    def diagnostics(self, *, now: float | None = None) -> dict:
        return self.snapshot(now=now).__dict__.copy()

    def reset_recovery_gate(self) -> None:
        """Clear only post-release recovery state for explicit ErrorLocked recovery.

        Real keys still held, and addon-originated ``manual_hold``, continue to
        own input.  The epoch is incremented so no in-flight dispatch can cross
        the explicit recovery boundary.
        """

        with self._lock:
            self._manual_epoch += 1
            self._release_deadline = None
            self._freshness_baseline = self._last_observed_freshness
            self._observed_freshness_frames = 0
            self._clear_replay_guard_locked()
            self._phase = self.MANUAL_HELD if self._has_owner_locked() else self.DISPATCHABLE

    def _has_owner_locked(self) -> bool:
        return bool(self._held_inputs or self._teap_manual_hold)

    def _begin_release_locked(self, timestamp: float) -> None:
        self._release_deadline = timestamp + self.policy.recovery_seconds
        self._freshness_baseline = self._last_observed_freshness
        self._observed_freshness_frames = 0
        self._phase = self.RELEASE_DELAY

    def _arm_replay_guard_locked(self, timestamp: float) -> None:
        self._replay_token = self._last_auto_token
        self._replay_sequence = self._last_auto_sequence
        if self._replay_token and self._replay_sequence is not None and self.policy.replay_guard_seconds > 0:
            self._replay_deadline = timestamp + self.policy.replay_guard_seconds
        else:
            self._replay_deadline = None

    def _replay_guard_is_active_locked(self, timestamp: float) -> bool:
        return bool(self._replay_deadline is not None and timestamp < self._replay_deadline and self._replay_token)

    def _clear_replay_guard_locked(self) -> None:
        self._replay_token = None
        self._replay_sequence = None
        self._replay_deadline = None

    def _advance_locked(self, timestamp: float) -> None:
        if self._has_owner_locked():
            self._phase = self.MANUAL_HELD
            return
        if self._phase == self.RELEASE_DELAY and self._release_deadline is not None and timestamp >= self._release_deadline:
            self._phase = self.WAIT_FRESHNESS
            self._freshness_baseline = self._last_observed_freshness
            self._observed_freshness_frames = 0
        if self._phase == self.REPLAY_GUARD and self._replay_deadline is not None and timestamp >= self._replay_deadline:
            self._clear_replay_guard_locked()
            self._phase = self.DISPATCHABLE

    @staticmethod
    def _is_newer(current: int, previous: int) -> bool:
        delta = (int(current) - int(previous)) % 65536
        return 0 < delta <= 32768


# ctypes aliases are explicit so the ABI is stable in packaged Windows builds.
#
# The hook code deliberately declares every Win32 function used below.  ctypes'
# default function signatures return ``c_int``; on 64-bit Windows that truncates
# HINSTANCE/HHOOK handles and can make SetWindowsHookExW fail even when the
# desktop permits a low-level keyboard hook.
DWORD = ctypes.c_uint32
ULONG_PTR = ctypes.c_size_t
LONG = ctypes.c_int32
LRESULT = ctypes.c_ssize_t
HHOOK = ctypes.c_void_p
HINSTANCE = ctypes.c_void_p
BOOL = ctypes.c_int
UINT = ctypes.c_uint


class POINT(ctypes.Structure):
    _fields_ = [("x", LONG), ("y", LONG)]


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [("vkCode", DWORD), ("scanCode", DWORD), ("flags", DWORD), ("time", DWORD), ("dwExtraInfo", ULONG_PTR)]


class MSLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [("pt", POINT), ("mouseData", DWORD), ("flags", DWORD), ("time", DWORD), ("dwExtraInfo", ULONG_PTR)]


class MSG(ctypes.Structure):
    _fields_ = [("hwnd", ctypes.c_void_p), ("message", UINT), ("wParam", ULONG_PTR), ("lParam", ctypes.c_ssize_t), ("time", DWORD), ("pt", POINT), ("lPrivate", DWORD)]


_HOOKPROC = getattr(ctypes, "WINFUNCTYPE", ctypes.CFUNCTYPE)(LRESULT, ctypes.c_int, ULONG_PTR, ctypes.c_ssize_t)


class _WindowsHookApi:
    """Typed Win32 API surface used by :class:`WindowsPhysicalInputMonitor`.

    The object is created only inside a Windows hook thread.  Keeping it small
    makes hook startup deterministic and exposes a native error code whenever
    Windows refuses the installation.
    """

    def __init__(self) -> None:
        if not hasattr(ctypes, "WinDLL"):
            raise RuntimeError("ctypes_windll_unavailable")
        self.user32 = ctypes.WinDLL("user32", use_last_error=True)
        self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

        self.kernel32.GetCurrentThreadId.argtypes = []
        self.kernel32.GetCurrentThreadId.restype = DWORD
        self.kernel32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
        self.kernel32.GetModuleHandleW.restype = HINSTANCE
        self.kernel32.GetLastError.argtypes = []
        self.kernel32.GetLastError.restype = DWORD

        self.user32.SetWindowsHookExW.argtypes = [ctypes.c_int, _HOOKPROC, HINSTANCE, DWORD]
        self.user32.SetWindowsHookExW.restype = HHOOK
        self.user32.UnhookWindowsHookEx.argtypes = [HHOOK]
        self.user32.UnhookWindowsHookEx.restype = BOOL
        self.user32.CallNextHookEx.argtypes = [HHOOK, ctypes.c_int, ULONG_PTR, ctypes.c_ssize_t]
        self.user32.CallNextHookEx.restype = LRESULT
        self.user32.GetMessageW.argtypes = [ctypes.POINTER(MSG), ctypes.c_void_p, UINT, UINT]
        self.user32.GetMessageW.restype = ctypes.c_int
        self.user32.TranslateMessage.argtypes = [ctypes.POINTER(MSG)]
        self.user32.TranslateMessage.restype = BOOL
        self.user32.DispatchMessageW.argtypes = [ctypes.POINTER(MSG)]
        self.user32.DispatchMessageW.restype = LRESULT
        self.user32.PostThreadMessageW.argtypes = [DWORD, UINT, ULONG_PTR, ctypes.c_ssize_t]
        self.user32.PostThreadMessageW.restype = BOOL

    def last_error(self) -> int:
        return int(ctypes.get_last_error() or self.kernel32.GetLastError() or 0)


class WindowsPhysicalInputMonitor:
    """Low-level keyboard monitor with fail-closed health reporting.

    The approved manual-ownership policy intentionally ignores every mouse
    input.  A mouse hook therefore provides no safety signal and must not be a
    prerequisite for real SendInput.  Keyboard-hook health is the one required
    runtime dependency; when it is unavailable the engine still fail-closes.
    """

    def __init__(
        self,
        pause: PhysicalInputPause,
        *,
        intervention_whitelist: KeyboardInterventionWhitelist | None = None,
        platform_name: str | None = None,
        native_api_factory: Callable[[], _WindowsHookApi] | None = None,
    ) -> None:
        self.pause = pause
        # Runtime policy is TEK-local. WoW binding caches are intentionally not consulted.
        # No refresh_if_changed call is needed: this whitelist is immutable for one UI-linked session.
        self.intervention_whitelist = intervention_whitelist or KeyboardInterventionWhitelist()
        self.platform_name = platform_name or os.name
        self._native_api_factory = native_api_factory or _WindowsHookApi
        self._stop = threading.Event()
        self._ready_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._thread_id: int | None = None
        self._keyboard_hook_handle = None
        self._keyboard_proc = None
        self._last_error: str | None = None
        self._started = False
        # A stop timeout is not equivalent to a stopped hook.  Keep this flag
        # until the hook thread has actually exited so a second monitor is never
        # started while the first one can still receive physical key events.
        self._stopping = False
        self._lock = threading.RLock()
        self._pressed_modifiers: set[str] = set()
        self._manual_by_vk: dict[int, str] = {}
        self._active_keyboard_vks: set[int] = set()
        self._last_physical_key: str | None = None
        self._last_physical_key_classification: str | None = None
        self._native_api: _WindowsHookApi | None = None
        self._hook_module_mode: str | None = None
        self._hook_native_error: int | None = None

    @staticmethod
    def keyboard_is_injected(flags: int) -> bool:
        return bool(int(flags) & LLKHF_INJECTED)

    @staticmethod
    def mouse_is_injected(flags: int) -> bool:
        return bool(int(flags) & LLMHF_INJECTED)

    def observe_keyboard(self, *, flags: int = 0, vk_code: int | None = None, message: int = WM_KEYDOWN) -> bool:
        """Compatibility wrapper plus physical keyboard classification."""
        if self.keyboard_is_injected(flags):
            self.pause.observe("keyboard", injected=True)
            return False
        if vk_code is None:
            return self.pause.observe("keyboard", injected=False)
        return self.observe_keyboard_event(vk_code=int(vk_code), message=message, flags=flags)

    def observe_keyboard_event(self, *, vk_code: int, message: int, flags: int = 0) -> bool:
        if self.keyboard_is_injected(flags):
            self.pause.observe("keyboard", injected=True)
            return False
        with self._lock:
            if message in {WM_KEYDOWN, WM_SYSKEYDOWN}:
                if vk_code in self._active_keyboard_vks:
                    return False
                self._active_keyboard_vks.add(vk_code)
                modifier = _MODIFIER_VKS.get(vk_code)
                if modifier:
                    self._pressed_modifiers.add(modifier)
                    binding = _MODIFIER_HOLD_NAMES.get(vk_code, modifier)
                else:
                    binding = self._binding_for_vk(vk_code)
                self._last_physical_key = binding
                if self.intervention_whitelist.is_exempt_vk(vk_code):
                    self._last_physical_key_classification = "dispatch_exempt"
                    return False
                self._last_physical_key_classification = "manual_takeover"
                self._manual_by_vk[vk_code] = binding
                return self.pause.begin_manual_hold(binding)
            if message in {WM_KEYUP, WM_SYSKEYUP}:
                self._active_keyboard_vks.discard(vk_code)
                binding = self._manual_by_vk.pop(vk_code, None)
                if binding:
                    self._last_physical_key = binding
                    self._last_physical_key_classification = "manual_release"
                modifier = _MODIFIER_VKS.get(vk_code)
                if modifier:
                    self._pressed_modifiers.discard(modifier)
                # KEYUP only releases an existing hold; it never starts or
                # extends a new manual-priority window.
                return self.pause.end_manual_hold(binding) if binding else False
        return False

    # All mouse input is intentionally ignored by the approved policy.
    def observe_mouse_button(self, *, flags: int = 0) -> bool:
        return False

    def observe_mouse_middle_down(self, *, flags: int = 0) -> bool:
        return False

    def observe_mouse_middle_up(self, *, flags: int = 0) -> bool:
        return False

    def observe_mouse_wheel(self, *, flags: int = 0) -> bool:
        return False

    def start(self) -> bool:
        if self.platform_name != "nt":
            self._last_error = "physical_input_hook_unsupported_platform"
            self._ready_event.set()
            return False
        with self._lock:
            if self._stopping:
                # A hook that has not confirmed its exit must never be replaced
                # by another hook thread.  That would create duplicate physical
                # input observers and can incorrectly extend manual ownership.
                if self._thread and self._thread.is_alive():
                    return False
                self._finalize_stopped_locked()
            if self._thread and self._thread.is_alive():
                return True
            self._stop.clear()
            self._ready_event.clear()
            self._last_error = None
            self._hook_native_error = None
            self._hook_module_mode = None
            self._thread = threading.Thread(target=self._run, name="TEKPhysicalInputHook", daemon=True)
            self._thread.start()
            return True

    def wait_until_ready(self, *, timeout_seconds: float = 1.0) -> bool:
        self._ready_event.wait(max(0.0, float(timeout_seconds)))
        return self.is_healthy()

    def stop(self, *, timeout_seconds: float = 1.0) -> bool:
        """Request shutdown and return only after the hook actually exits.

        ``False`` means the monitor remains in ``physical_input_hook_stopping``
        state.  Callers must retain this monitor and block any new UI-linked
        start until the old low-level hook has confirmed its exit.
        """

        with self._lock:
            thread = self._thread
            if not thread or not thread.is_alive():
                self._finalize_stopped_locked()
                return True
            self._stopping = True
            self._stop.set()
            thread_id = self._thread_id
            api = self._native_api
        if self.platform_name == "nt" and thread_id and api is not None:
            try:
                api.user32.PostThreadMessageW(DWORD(thread_id), WM_QUIT, 0, 0)
            except Exception:
                pass
        if thread is not threading.current_thread():
            thread.join(max(0.0, float(timeout_seconds)))
        if thread.is_alive():
            with self._lock:
                self._stopping = True
                self._ready_event.set()
            return False
        with self._lock:
            self._finalize_stopped_locked(expected_thread=thread)
        return True

    def is_stopping(self) -> bool:
        with self._lock:
            return bool(self._stopping and self._thread and self._thread.is_alive())

    def health_reason(self) -> str | None:
        with self._lock:
            if self.platform_name != "nt":
                return self._last_error or "physical_input_hook_unsupported_platform"
            if self._stopping:
                return "physical_input_hook_stopping"
            if self._last_error:
                return self._last_error
            if not self._ready_event.is_set():
                return "physical_input_hook_not_ready"
            # Mouse hook is intentionally not installed: all mouse input is
            # ignored, so keyboard capture is the complete required monitor.
            if not self._started or not self._keyboard_hook_handle:
                return "physical_input_hook_not_ready"
            if not self._thread or not self._thread.is_alive():
                return "physical_input_hook_thread_stopped"
            return None

    def is_healthy(self) -> bool:
        return self.health_reason() is None

    def diagnostics(self) -> dict:
        data = self.pause.diagnostics()
        whitelist = self.intervention_whitelist.diagnostics()
        data.update(
            {
                "hook_platform": self.platform_name,
                "hook_started": self._started,
                "hook_ready": self._ready_event.is_set(),
                "hook_healthy": self.is_healthy(),
                "hook_health_reason": self.health_reason(),
                "hook_error": self._last_error,
                "hook_native_error": self._hook_native_error,
                "hook_thread_alive": bool(self._thread and self._thread.is_alive()),
                "hook_stopping": self._stopping,
                "keyboard_hook_required": True,
                "keyboard_hook_installed": bool(self._keyboard_hook_handle),
                "hook_module_mode": self._hook_module_mode,
                "mouse_hook_required": False,
                "mouse_hook_status": "disabled_by_input_policy",
                "intervention_whitelist": whitelist,
                "last_physical_key": self._last_physical_key,
                "last_physical_key_classification": self._last_physical_key_classification,
            }
        )
        return data

    def _binding_for_vk(self, vk_code: int) -> str:
        key = _vk_to_key(vk_code)
        modifiers = set(self._pressed_modifiers)
        # This label is diagnostics-only.  Runtime exemption is determined by
        # the TEK-local whitelist from the raw main-key virtual key code.
        return "+".join([*(name for name in ("CTRL", "ALT", "SHIFT") if name in modifiers), key])

    def _finalize_stopped_locked(self, *, expected_thread=None) -> None:
        if expected_thread is not None and self._thread is not None and self._thread is not expected_thread:
            return
        self._thread = None
        self._thread_id = None
        self._keyboard_hook_handle = None
        self._keyboard_proc = None
        self._native_api = None
        self._started = False
        self._stopping = False
        self._ready_event.set()

    def _install_keyboard_hook(self, api: _WindowsHookApi) -> tuple[object | None, str | None, int]:
        """Install the only required low-level hook with a safe fallback.

        A correctly typed current-module handle is preferred.  Some packaged
        Python hosts expose a NULL/unsuitable module handle to this API even
        though low-level hooks are delivered back to the installing process;
        retrying with NULL provides a documented process-local fallback without
        weakening the fail-closed health gate.
        """
        module = api.kernel32.GetModuleHandleW(None)
        attempts: list[tuple[object | None, str]] = []
        if module:
            attempts.append((module, "current_module"))
        attempts.append((None, "null_module"))
        seen: set[int] = set()
        last_error = 0
        for hmodule, mode in attempts:
            identity = int(getattr(hmodule, "value", hmodule) or 0) if hmodule else 0
            if identity in seen:
                continue
            seen.add(identity)
            try:
                ctypes.set_last_error(0)
            except Exception:
                pass
            handle = api.user32.SetWindowsHookExW(WH_KEYBOARD_LL, self._keyboard_proc, hmodule, 0)
            if handle:
                return handle, mode, 0
            last_error = api.last_error()
        return None, None, int(last_error or 0)

    def _run(self) -> None:
        keyboard_handle = None
        api: _WindowsHookApi | None = None
        try:
            api = self._native_api_factory()
            self._native_api = api
            self._thread_id = int(api.kernel32.GetCurrentThreadId())
            self._keyboard_proc = _HOOKPROC(self._keyboard_callback)
            keyboard_handle, module_mode, error_code = self._install_keyboard_hook(api)
            if not keyboard_handle:
                self._hook_native_error = error_code or None
                suffix = f":winerror_{error_code}" if error_code else ""
                self._last_error = f"physical_input_hook_install_failed{suffix}"
                self._ready_event.set()
                return
            self._keyboard_hook_handle = keyboard_handle
            self._hook_module_mode = module_mode
            self._started = True
            self._ready_event.set()
            message = MSG()
            while not self._stop.is_set():
                result = api.user32.GetMessageW(ctypes.byref(message), None, 0, 0)
                if result <= 0 or message.message == WM_QUIT:
                    break
                api.user32.TranslateMessage(ctypes.byref(message))
                api.user32.DispatchMessageW(ctypes.byref(message))
            if not self._stop.is_set() and not self._last_error:
                self._last_error = "physical_input_hook_thread_stopped"
        except Exception as error:
            self._last_error = f"physical_input_hook_exception:{type(error).__name__}:{error}"
        finally:
            self._ready_event.set()
            try:
                if api is not None and keyboard_handle:
                    api.user32.UnhookWindowsHookEx(keyboard_handle)
            except Exception:
                pass
            with self._lock:
                self._finalize_stopped_locked(expected_thread=threading.current_thread())

    def _keyboard_callback(self, code: int, message: int, lparam: int) -> int:
        try:
            if code == HC_ACTION and message in {WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP}:
                event = ctypes.cast(lparam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                self.observe_keyboard_event(vk_code=int(event.vkCode), message=int(message), flags=int(event.flags))
        except Exception:
            # Input observation must never interfere with the system input path.
            pass
        return self._call_next(code, message, lparam)

    def _call_next(self, code: int, message: int, lparam: int) -> int:
        try:
            api = self._native_api
            if api is None:
                return 0
            return int(api.user32.CallNextHookEx(self._keyboard_hook_handle, code, message, lparam))
        except Exception:
            return 0


def _vk_to_key(vk_code: int) -> str:
    if 0x30 <= vk_code <= 0x39:
        return chr(vk_code)
    if 0x41 <= vk_code <= 0x5A:
        return chr(vk_code)
    if 0x60 <= vk_code <= 0x69:
        return f"NUMPAD{vk_code - 0x60}"
    return _SPECIAL_VK_NAMES.get(vk_code, f"VK_{vk_code:02X}")
