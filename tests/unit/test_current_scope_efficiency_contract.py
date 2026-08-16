from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(rel: str) -> str:
    return (ADDON / rel).read_text(encoding="utf-8")


def test_signal_history_is_semantically_coalesced_below_transport_rate() -> None:
    signal = read("Signal/SignalFrame.lua")
    assert "SIGNAL_HISTORY_HEARTBEAT_SECONDS = 0.50" in signal
    assert "sameRememberedState(sequenceState, lastRememberedSequenceState)" in signal
    assert "index ~= DISPATCH_ATTEMPT_STATE_INDEX" in signal
    assert "remember(encoded, message.unresolvedReason or reason, message._sequenceState, now)" in signal
    assert "store.bySequence[" not in signal


def test_auto_burst_progress_logs_are_coalesced_before_record_allocation() -> None:
    burst = read("Tactics/AutoBurst.lua")
    assert "PROGRESS_LOG_HEARTBEAT_SECONDS = 0.50" in burst
    assert 'shouldLogProgress(self, "window_queue_delivery_continues")' in burst
    assert 'shouldLogProgress(self, "step_dispatch_phase_wait")' in burst
    assert 'shouldLogProgress(self, "step_wait_confirm_gcd_locked")' in burst
    assert 'shouldLogProgress(self, "step_failure_retry_wait_ready_now")' in burst
    priority = burst[burst.index("local PRIORITY_LOG_EVENTS"):burst.index("local QUIET_DECISION_REASONS")]
    assert "window_queue_delivery_continues" not in priority
    assert "gcd_locked_delivery_continues" not in priority


def test_tactical_advisors_normalizes_tactical_and_hud_config_once() -> None:
    advisors = read("Tactics/TacticalAdvisors.lua")
    assert "local function ensureConfig()" in advisors
    assert "local _, settings, hud = TE.Config.Normalize:All()" in advisors
    assert "local settings, hud = ensureConfig()" in advisors
    assert "local function ensureSettings()" not in advisors
    assert "local function ensureHudSettings()" not in advisors


def test_current_hud_path_contains_no_retired_planners_or_duplicate_burst_views() -> None:
    advisors = read("Tactics/TacticalAdvisors.lua")
    panel = read("UI/ControlPanel.lua")
    burst = read("Tactics/AutoBurst.lua")
    for retired in (
        "buildInterrupt", "buildReactionReadOnly", "applyReactionReadOnly",
        "ReactionBindings", "ReactionObservation", "buildPreview",
    ):
        assert retired not in advisors
    for retired in (
        "reactionBindingSnapshot", "formatInterruptBindingState",
        "formatControlBindingState", "formatReactionDiagnostics",
    ):
        assert retired not in panel
    for duplicate in ("out.window", "out.followups", "followups = {}"):
        assert duplicate not in burst


def test_current_autoburst_hud_files_have_no_orphan_local_helpers() -> None:
    for relative in (
        "Tactics/AutoBurst.lua",
        "Tactics/BurstPlanner.lua",
        "Tactics/TacticalAdvisors.lua",
        "UI/ControlPanel.lua",
    ):
        text = read(relative)
        names = re.findall(r"(?m)^local function\s+([A-Za-z_][A-Za-z0-9_]*)", text)
        orphaned = [name for name in names if len(re.findall(rf"\b{re.escape(name)}\b", text)) <= 1]
        assert orphaned == [], f"{relative}: orphaned local helpers {orphaned}"
