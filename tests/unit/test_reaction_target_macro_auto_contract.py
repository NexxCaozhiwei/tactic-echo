"""1.0.39 P2.2 contract: same-spell target-management macros are auto-eligible.

This remains mapping metadata only.  It must not add a dispatch path before P4.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def test_same_spell_target_switch_macro_is_macro_managed_auto_eligible() -> None:
    macro = (ADDON / "Actions" / "MacroSemantics.lua").read_text(encoding="utf-8")
    reaction = (ADDON / "Tactics" / "ReactionBindings.lua").read_text(encoding="utf-8")
    assert "macro_target_switch_fallback_auto" in macro
    assert "macroManagedTargetAuto" in macro
    assert 'autoRouteMode = "macro_managed_target"' in macro
    assert "macroManagedTarget = macroManagedTarget" in reaction
    assert "macroManagedTargetAuto = macroManagedTargetAuto" in reaction
    assert "targetSwitchAuto" in reaction


def test_p22_still_does_not_add_reaction_dispatch_runtime() -> None:
    reaction = (ADDON / "Tactics" / "ReactionBindings.lua").read_text(encoding="utf-8")
    # Metadata only. Runtime input and protocol integrations remain outside P2.2.
    for forbidden in ("TE.SignalFrame", "TE.SignalEncoder", "TE.AutoBurst", "SendInput(", "C_Timer.After("):
        assert forbidden not in reaction
    assert "BindingToken=" not in reaction
