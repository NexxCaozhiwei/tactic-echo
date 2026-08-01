from __future__ import annotations

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
    assert 'shouldLogProgress(self, "gcd_locked_delivery_continues")' in burst
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
