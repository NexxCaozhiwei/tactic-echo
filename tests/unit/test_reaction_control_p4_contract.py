"""1.0.51 P5.6: API/event-confirmed eligibility with P4.3 transport."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_p4_auto_reaction_is_loaded_after_p2_mapping_p3_observation_and_event_cache() -> None:
    toc = read("!TacticEcho.toc")
    assert "Tactics/ReactionObservation.lua" in toc
    assert "Tactics/ReactionInterruptEvents.lua" in toc
    assert "Tactics/AutoReaction.lua" in toc
    assert toc.index("Tactics/ReactionBindings.lua") < toc.index("Tactics/ReactionObservation.lua")
    assert toc.index("Tactics/ReactionObservation.lua") < toc.index("Tactics/ReactionInterruptEvents.lua")
    assert toc.index("Tactics/ReactionInterruptEvents.lua") < toc.index("Tactics/AutoReaction.lua")


def test_p56_requires_api_or_positive_event_and_preserves_p43_transport_after_confirmation() -> None:
    source = read("Tactics/AutoReaction.lua")
    for token in (
        "TE.AutoReaction = AutoReaction",
        "confirmedInterruptible",
        "eligibleInterrupt",
        "HARD_INTERRUPTIBILITY_VETO",
        "unit_api_confirmed",
        "unit_api_not_interruptible",
        "unit_event_interruptible_confirmed",
        "unit_event_not_interruptible",
        "native_visible_shield",
        "interruptibility_unknown",
        "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "notInterruptible=false",
        "directInterruptibilityKnown",
        "native_visible_shield",
        "reactionCooldownGate",
        "interrupt_action_cooldown",
        "native_visual_settling",
        "deliveryStable = true",
        "safeForFutureAuto ~= true",
        "macroManagedTarget",
        'kind = "candidate"',
        "TacticEchoDB.autoReactionRuntime",
    ):
        assert token in source
    for forbidden in (
        "probeEligibleInterrupt",
        "probe_active_cast_ignore_steel",
        "CreateFrame(",
        ":RegisterEvent(",
        "SendInput(",
        "TE.SignalEncoder",
        "single_control",
        "aoe_control",
    ):
        assert forbidden not in source


def test_p4_4_native_visual_path_reads_real_shield_widgets_and_ignores_template_flags() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    auto = read("Tactics/AutoReaction.lua")

    for token in (
        "SHIELD_FIELD_NAMES",
        "SHIELD_GLOBAL_SUFFIXES",
        "nativeShieldShown",
        "native_visible_shield:",
        "native_visible_no_shield:",
        "native_showShield_config_true",
        "native_showShield_config_false",
        "native_bar_type_unverified:",
        "nativeShieldSource",
        "appendSemanticShieldWidgets",
        "GetChildren",
        "GetRegions",
        "directInterruptibilityKnown",
        "nativeInterruptibilityKnown",
    ):
        assert token in observer
    assert 'return false, "native_bar_type_interruptible"' not in observer
    assert 'return false, "native_showShield_false"' not in observer
    assert "showShield` template flag is never evidence" in auto


def test_p4_4_event_tracker_preserves_start_identity_when_status_events_omit_it() -> None:
    tracker = read("Tactics/ReactionInterruptEvents.lua")
    auto = read("Tactics/AutoReaction.lua")
    for token in (
        "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_INTERRUPTED",
        "PLAYER_TARGET_CHANGED",
        "EVIDENCE_TTL_SECONDS",
        "castGUID",
        "Preserve",
        "if readableSpellID ~= nil then record.spellID = readableSpellID end",
        'touchSource(source, "pending", event, castGUID, spellID, true)',
        'touchSource(source, "interruptible", event, castGUID, spellID, false)',
    ):
        assert token in tracker
    for token in (
        "eventInterruptibility",
        "ReactionInterruptEvents",
        "unit_event_spell_mismatch",
        "eventEvidence",
    ):
        assert token in auto
    for forbidden in ("SendInput(", "TE.SignalEncoder", "CreateBinding", "SetBinding", "SaveBindings"):
        assert forbidden not in tracker


def test_p4_keeps_p3_observation_read_only_and_reports_visual_diagnostics() -> None:
    observer = read("Tactics/ReactionObservation.lua")
    panel = read("UI/ControlPanel.lua")
    advisors = read("Tactics/TacticalAdvisors.lua")
    for forbidden in ("CreateFrame(", ":RegisterEvent(", "SendInput(", "TE.SignalFrame", "TE.SignalEncoder"):
        assert forbidden not in observer
    for token in ("P5.6 remains automatic-interrupt-only", "P4.3-proven", "Single control and AOE control remain display-only"):
        assert token in read("Tactics/AutoReaction.lua")
    for token in ("自动打断（已暂停）", "自动打断（当前不可用）", "暂停边界：自动打断不扫描目标优先级", "UnitCastingInfo / UnitChannelInfo"):
        assert token in panel
    assert "targetNativeShieldSource" in advisors


def test_p4_4_uses_existing_signal_transport_and_burst_owns_live_plan_priority() -> None:
    signal = read("Signal/SignalFrame.lua")
    assert "TE.AutoReaction.Evaluate" in signal
    assert "autoBurstSnapshot" in signal
    assert 'dispatchOrigin = "reaction"' in signal
    assert "reactionHoldObservation" in signal
    assert "autoBurstSnapshot = autoBurstSnapshot" in signal
    block = signal[signal.index("-- P4 automatic interrupts"):signal.index("-- P5.8 has no out-of-combat Burst transport exception")]
    for forbidden in ("AutoBurst:Abort", "AutoBurst.Abort", "AutoBurst:Evaluate", "AutoBurst.Evaluate"):
        assert forbidden not in block


def test_p4_transport_origin_uses_reserved_bit_6_and_parser_rejects_conflict() -> None:
    encoder = read("Signal/SignalEncoder.lua")
    assert 'dispatchOrigin ~= "burst" and dispatchOrigin ~= "reaction"' in encoder
    assert 'if dispatchOrigin == "reaction" then flags = flags + 64 end' in encoder
    teap = (ROOT / "tek" / "src" / "teap.py").read_text(encoding="utf-8")
    for token in ("reaction_dispatch", "flags & 0x40", "dispatch_origin_conflict", '"reaction"'):
        assert token in teap


def test_p4_3_delivery_fix_remains_in_place_and_tek_dedupes_stable_candidates() -> None:
    auto = read("Tactics/AutoReaction.lua")
    signal = read("Signal/SignalFrame.lua")
    gate = (ROOT / "tek" / "src" / "safety_gate.py").read_text(encoding="utf-8")
    for token in (
        "Keep the same candidate visible until the observed cast disappears",
        "deliveryStable = true",
        "confirmed_interrupt_candidate",
        "interruptibility_unknown",
    ):
        assert token in auto
    for token in (
        "stableReactionCandidate",
        "reactionDeliveryStable",
        "and stableReactionCandidate ~= true",
    ):
        assert token in signal
    for token in (
        "last_reaction_dispatch_sequence",
        "reaction_candidate_already_dispatched",
        "if sent and getattr(frame, \"dispatch_origin\", \"official\") == \"reaction\"",
    ):
        assert token in gate
