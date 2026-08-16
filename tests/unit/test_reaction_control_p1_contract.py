"""Contract for 1.0.39 P1: UI/config only, no reaction dispatch yet."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_reaction_defaults_are_hard_suspended_and_keep_target_order() -> None:
    defaults = read("Config/Defaults.lua")
    for token in (
        "autoReaction = {",
        "schema = 2",
        "interrupt = {",
        "control = {",
        "enabled = false",
        "suspended = true",
        'suspensionReason = "auto_interrupt_suspended"',
        "aoeEnabled = false",
        'targetOrder = { "target", "focus", "mouseover" }',
        "targetEnabled = { target = true, focus = false, mouseover = false }",
    ):
        assert token in defaults


def test_reaction_normalizer_owns_stable_source_contract() -> None:
    normalizer = read("Config/Normalize.lua")
    for token in (
        "local REACTION_TARGET_SOURCES",
        "local function normalizeReactionTargetOrder",
        "local function normalizeReactionTargetEnabled",
        "local function normalizeAutoReaction",
        "normalizeAutoReaction(tactics, defaults)",
        "tactics.autoReaction = reaction",
    ):
        assert token in normalizer


def test_interrupt_and_control_subpages_are_retired_from_navigation() -> None:
    panel = read("UI/ControlPanel.lua")
    assert 'interrupt = "hud"' in panel
    assert 'control = "hud"' in panel
    for token in ("SetInterruptSubpage", "buildInterruptSettings", "buildControlSettings", "createReactionTargetPriorityEditor"):
        assert token not in panel


def test_p1_does_not_touch_input_or_burst_runtime_paths() -> None:
    # P3 may read autoReaction in TacticalAdvisors for display-only source
    # ordering. The frozen burst and transport paths remain untouched.
    for relative in (
        "Tactics/AutoBurst.lua",
        "Signal/SignalFrame.lua",
        "Signal/SignalEncoder.lua",
    ):
        assert "autoReaction" not in read(relative), relative
