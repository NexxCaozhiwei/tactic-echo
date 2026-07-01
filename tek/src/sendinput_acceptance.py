"""Explicit, non-game SendInput acceptance harness for the TEK.exe build.

This module is intentionally separate from normal TEK dispatch.  It can only
send one tester-selected supported key to a foreground *non-WoW* process after
an exact confirmation phrase.  The documented PowerShell gate launches
Notepad, asks the tester to visually confirm the character, and preserves a
JSON evidence record under %LOCALAPPDATA%\\TacticEcho\\diagnostics.
"""
from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

from tek.src.input_planner import InputPlanError, plan_binding
from tek.src.windows_foreground import ForegroundWindow, WindowsForegroundDetector
from tek.src.windows_sendinput import WindowsSendInputDispatcher

ACCEPTANCE_CONFIRMATION = "I_UNDERSTAND_TEK_SENDS_A_TEST_KEY"
BLOCKED_GAME_PROCESS_NAMES = {"wow.exe", "world of warcraft.exe", "wowclassic.exe", "wow_b.exe"}


@dataclass(frozen=True)
class SendInputAcceptanceResult:
    ok: bool
    reason: str
    expected_process: str
    actual_process: str | None = None
    hwnd: int = 0
    binding: str | None = None
    events_sent: int = 0
    backend: str | None = None
    created_at: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _basename(value: str) -> str:
    return value.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1].casefold()


def run_sendinput_acceptance(
    *,
    confirmation: str,
    expected_process: str = "notepad.exe",
    binding: str = "Q",
    foreground_detector=None,
    dispatcher=None,
) -> SendInputAcceptanceResult:
    expected = _basename(expected_process)
    if expected in BLOCKED_GAME_PROCESS_NAMES or "warcraft" in expected or expected.startswith("wow"):
        return SendInputAcceptanceResult(False, "acceptance_target_game_forbidden", expected, created_at=_now())
    if confirmation != ACCEPTANCE_CONFIRMATION:
        return SendInputAcceptanceResult(False, "acceptance_confirmation_required", expected, created_at=_now())
    if os.name != "nt":
        return SendInputAcceptanceResult(False, "windows_only", expected, created_at=_now())
    try:
        detector = foreground_detector or WindowsForegroundDetector((expected,))
        window: ForegroundWindow = detector.current()
    except Exception as error:
        return SendInputAcceptanceResult(False, f"foreground_lookup_failed:{type(error).__name__}", expected, created_at=_now())
    actual = (window.process_name or "").casefold()
    if not window.hwnd:
        return SendInputAcceptanceResult(False, "acceptance_foreground_missing", expected, actual or None, created_at=_now())
    if actual != expected:
        return SendInputAcceptanceResult(False, "acceptance_foreground_target_mismatch", expected, actual or None, hwnd=window.hwnd, created_at=_now())
    try:
        plan = plan_binding(binding)
    except InputPlanError as error:
        return SendInputAcceptanceResult(False, f"acceptance_binding_invalid:{error}", expected, actual, hwnd=window.hwnd, binding=binding, created_at=_now())
    try:
        result = (dispatcher or WindowsSendInputDispatcher()).dispatch(plan)
    except Exception as error:
        return SendInputAcceptanceResult(False, f"acceptance_dispatch_setup_failed:{type(error).__name__}", expected, actual, hwnd=window.hwnd, binding=plan.binding, created_at=_now())
    return SendInputAcceptanceResult(
        ok=result.sent,
        reason=result.reason,
        expected_process=expected,
        actual_process=actual,
        hwnd=window.hwnd,
        binding=plan.binding,
        events_sent=result.events_sent,
        backend=result.backend,
        created_at=_now(),
    )


def write_acceptance_evidence(result: SendInputAcceptanceResult, directory: str | Path) -> Path:
    import json

    target_dir = Path(directory)
    target_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    target = target_dir / f"tek-sendinput-acceptance-{stamp}.json"
    target.write_text(json.dumps(result.to_dict(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return target
