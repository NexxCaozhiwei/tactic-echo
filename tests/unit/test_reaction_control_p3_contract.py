"""1.0.39 P3: read-only cast observation and single-priority HUD highlights."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_p3_observer_is_loaded_and_uses_protocol_monitor_cadence() -> None:
    toc = read("!TacticEcho.toc")
    assert "Tactics/ReactionObservation.lua" in toc
    assert toc.index("Tactics/ReactionBindings.lua") < toc.index("Tactics/ReactionObservation.lua")

    observer = read("Tactics/ReactionObservation.lua")
    monitor = read("Tactics/ProtocolMonitor.lua")
    for token in (
        "TE.ReactionObservation = ReactionObservation",
        'target = readUnit("target", "target")',
        'focus = readUnit("focus", "focus")',
        'mouseover = readUnit("mouseover", "mouseover")',
        "C_NamePlate.GetNamePlates",
        "AOE_CONTROL_THRESHOLD = 4",
        "CONTROL_EXCLUDED_CLASSIFICATIONS",
        "UnitClassification",
        "UnitIsBossMob",
        "cast.interruptibleKnown == true",
        "cast.interruptible == false",
    ):
        assert token in observer
    assert "readReactionObservation()" in monitor
    assert "reaction = type(state.reaction)" in monitor


def test_p3_fails_closed_for_control_target_eligibility() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    for token in (
        "hostile == true",
        "alive == true",
        "isPlayer == true or (isPlayer == false and bossLike ~= true and classification ~= nil)",
        "elite = true",
        "rareelite = true",
        "worldboss = true",
        "unitLevel == -1",
    ):
        assert token in observer


def test_p3_priority_is_interrupt_then_aoe_then_single_control() -> None:
    advisors = read("Tactics/TacticalAdvisors.lua")
    assert "out.selected = out.interrupt or out.aoe or out.control" in advisors
    assert "reactionRoute(bindingSnapshot, \"control\", \"aoe\", \"cursor\", true)" in advisors
    assert "reactionHighlight = false" in advisors
    assert "applyReactionReadOnly(reaction, interrupt, advisory)" in advisors
    assert "reaction = reaction" in advisors


def test_p3_preserves_read_only_transport_boundary() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    advisors = read("Tactics/TacticalAdvisors.lua")
    # Observation module has no independent event/update/input path.
    for forbidden in ("CreateFrame(", ":RegisterEvent(", "TE.SignalFrame", "TE.SignalEncoder", "SendInput(", "C_Timer.After("):
        assert forbidden not in observer
    # P3 never exposes an input-capable HUD binding, despite inspecting a real
    # action-bar route for display/highlight purposes.
    assert "bindingToken = 0" in advisors
    assert "dispatchAllowed = false" in advisors
    for frozen in ("Tactics/AutoBurst.lua", "Signal/SignalFrame.lua", "Signal/SignalEncoder.lua"):
        text = read(frozen)
        assert "ReactionObservation" not in text
        assert "buildReactionReadOnly" not in text


def test_p3_hud_sanitizes_and_explains_reaction_highlight() -> None:
    model = read("UI/TacticalHudModel.lua")
    styles = read("UI/TacticalHudStyles.lua")
    icon = read("UI/TacticalIconButton.lua")
    for token in (
        '"reactionHighlight"',
        '"reactionObservedTarget"',
        '"reactionAoe"',
        "reactionKind",
        "reactionQualifyingCount",
    ):
        assert token in model
    assert "item.reactionHighlight ~= false" in styles
    assert "P3 反应候选：" in icon
    assert "P3 仅高亮，不自动按键" in icon


def test_p32_cast_presence_uses_api_result_arity_without_spell_text() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    assert "local function packReturns(...)" in observer
    assert "apiRecordPresent(ok, arity, 9)" in observer
    assert "apiRecordPresent(ok, arity, 8)" in observer
    assert "packReturns(UnitCastingInfo(unit))" in observer
    assert "packReturns(UnitChannelInfo(unit))" in observer
    # The observer must not keep raw cast names in its snapshots.
    assert "spell name is deliberately never retained" in observer


def test_p31_highlight_can_exercise_read_only_cast_observation_without_p2_route() -> None:
    advisors = read("Tactics/TacticalAdvisors.lua")
    assert "local function reactionFallbackItem(classFile, reactionKind, candidate)" in advisors
    assert 'reactionFallbackItem(classFile, "interrupt", { source = source })' in advisors
    assert "reactionRouteAvailable = false" in advisors
    assert "bindingToken = 0" in advisors
    assert "P4 must not treat it as an executable route" in advisors


def test_p32_reconciles_target_monitor_and_keeps_profile_fallback_when_p2_cache_is_missing() -> None:
    advisors = read("Tactics/TacticalAdvisors.lua")
    panel = read("UI/ControlPanel.lua")
    for token in (
        "local function withTargetMonitorFallback",
        "protocol_monitor_target_fallback",
        "local function reactionObservationDiagnostics",
        "mappings = mappings or { interrupt = {}, control = {}",
        "out.diagnostics = reactionObservationDiagnostics",
    ):
        assert token in advisors
    assert "local function formatReactionDiagnostics(reaction)" in panel
    assert "P3 目标观测：" in panel

def test_p33_native_castbar_fallback_stays_read_only_and_exposes_diagnostics() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    monitor = read("Tactics/ProtocolMonitor.lua")
    advisors = read("Tactics/TacticalAdvisors.lua")
    panel = read("UI/ControlPanel.lua")

    for token in (
        "local function readNativeCastbarRecord",
        'safeObjectField(_G, "TargetFrameSpellBar")',
        'safeObjectField(_G, "FocusFrameSpellBar")',
        "C_NamePlate.GetNamePlateForUnit",
        "native_castbar:",
        "showShield",
        "BorderShield",
        "nativeShieldShown",
        "GetIsInterruptible",
        "barType",
        "nativeCastbar = nativeRecord ~= nil",
        "nativeBarSource",
    ):
        assert token in observer
    # Native UI state is a polling fallback only; P3 must retain the prior
    # no-event/no-input boundary.
    for forbidden in ("CreateFrame(", ":RegisterEvent(", "SendInput(", "TE.SignalFrame", "TE.SignalEncoder"):
        assert forbidden not in observer

    for token in (
        "local function packReturns(...)",
        "castRecordPresent(ok, arity, 9)",
        "castRecordPresent(ok, arity, 8)",
        "reconcileTargetFromReactionObservation",
    ):
        assert token in monitor
    assert "targetNativeCastbar = cast.nativeCastbar == true" in advisors
    assert "interrupt_unverified" in advisors
    assert "reactionAutoEligible = false" in advisors
    assert "reactionProbeOnly = true" in advisors
    assert "原生施法条=" in panel



def test_p34_native_scalar_true_is_unverified_but_visible_shield_is_hard_steel() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    for token in (
        "local function nativeNotInterruptible(frame, globalPrefix)",
        "native_visible_shield:",
        "native_visible_no_shield:",
        "native_scalar_true_unverified:",
        "native_method_uninterruptible_unverified:",
        "nativeSteelConfirmed",
        "nativeShieldKnown",
        "nativeShieldVisible",
        "local hiddenField = nil",
        "if shown == true then return true, candidate.label end",
        "scalar-only `true`",
    ):
        assert token in observer
    # P3.4 must no longer return a hard true from a scalar-only native value.
    assert 'if value == true then return nil, "native_scalar_true_unverified:" .. field' in observer
    assert "if shownShield == true then\n        return true" in observer


def test_p34_transient_cast_gap_hold_is_read_only_unverified() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    advisors = read("Tactics/TacticalAdvisors.lua")
    panel = read("UI/ControlPanel.lua")
    for token in (
        "TRANSIENT_CAST_GAP_SECONDS = 0.22",
        "local function stabilizeCastPresence",
        "transient_native_castbar_gap",
        "transient_gap_unverified",
        'continuity = "transient_gap_hold"',
        "cast = stabilizeCastPresence(source, readCast(unit))",
    ):
        assert token in observer
    assert "targetNativeInterruptibilityEvidence" in advisors
    assert "targetCastContinuity" in advisors
    assert "钢条证据=" in panel
    assert "连续性=" in panel
    # P3 remains visual-only despite the continuity bridge.
    for forbidden in ("CreateFrame(", ":RegisterEvent(", "SendInput(", "TE.SignalFrame", "TE.SignalEncoder"):
        assert forbidden not in observer
