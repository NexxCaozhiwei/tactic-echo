"""Contract for 1.0.39 P2: reaction binding/macro learning only."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_reaction_binding_inspector_is_loaded_after_shared_macro_dependencies() -> None:
    toc = read("!TacticEcho.toc")
    assert "Actions/MacroSemantics.lua" in toc
    assert "Actions/ActionBarBindingResolver.lua" in toc
    assert "Tactics/AbilityProfiles.lua" in toc
    assert "Tactics/ReactionBindings.lua" in toc
    assert toc.index("Actions/MacroSemantics.lua") < toc.index("Tactics/ReactionBindings.lua")
    assert toc.index("Actions/ActionBarBindingResolver.lua") < toc.index("Tactics/ReactionBindings.lua")
    assert toc.index("Tactics/AbilityProfiles.lua") < toc.index("Tactics/ReactionBindings.lua")


def test_macro_route_description_extends_existing_semantics_without_new_parser() -> None:
    macro = read("Actions/MacroSemantics.lua")
    for token in (
        "function MacroSemantics:DescribeSpellRoutes",
        "tokenMatchesSpell(action.token, spellID, spellName)",
        "out.routes",
        "macro_target_route_ambiguous",
        "macro_castsequence_route_opaque",
        "macro_target_switch_fallback_auto",
        "macroManagedTargetAuto",
        "autoRouteMode",
        "hasTargetMutation",
    ):
        assert token in macro


def test_control_catalogue_preserves_legacy_advisory_list_and_exposes_typed_roles() -> None:
    profiles = read("Tactics/AbilityProfiles.lua")
    for token in (
        "AbilityProfiles.controls = {",
        "AbilityProfiles.reactionControls = {",
        'role = "single"',
        'role = "aoe"',
        "function AbilityProfiles:GetReactionControls(classFile)",
        "self.controls[classFile]",
    ):
        assert token in profiles


def test_reaction_binding_inspector_is_read_only_and_future_route_gated() -> None:
    reaction = read("Tactics/ReactionBindings.lua")
    for token in (
        "TE.ReactionBindings = ReactionBindings",
        "TE.ActionBarBindingResolver",
        "TE.MacroSemantics",
        "function ReactionBindings:GetSnapshot(force)",
        "safeForFutureAuto",
        "macroManagedTarget",
        "details.macroManagedTargetAuto == true",
        'route ~= "cursor" or role == "aoe"',
        "Never creates a BindingToken",
    ):
        assert token in reaction
    # Runtime integration points must remain absent.  The module documents the
    # names of forbidden paths in comments, so this checks concrete API usage
    # rather than rejecting explanatory safety text.
    for forbidden in ("TE.SignalFrame", "TE.SignalEncoder", "TE.AutoBurst", "SendInput(", "C_Timer.After("):
        assert forbidden not in reaction
    # The safety comment must state the prohibition; no runtime token creation
    # helper is allowed in this module.
    assert "BindingToken=" not in reaction


def test_interrupt_control_page_has_three_explicit_tabs_and_p2_readouts() -> None:
    panel = read("UI/ControlPanel.lua")
    for token in (
        'createActionButton(pane, "打断设置"',
        'createActionButton(pane, "控制设置"',
        'createActionButton(pane, "样式设置"',
        'ControlPanel:SetInterruptSubpage("style")',
        'createReadout(pane, "interruptBindingState"',
        'createReadout(pane, "controlBindingState"',
        "buildInterruptStyleSettings(stylePane)",
        'ControlPanel:Show("interrupt", "style")',
    ):
        assert token in panel


def test_p2_mapping_still_does_not_modify_dispatch_or_burst_runtime_paths() -> None:
    # P3 may now consume the P2 mapping snapshot in TacticalAdvisors for
    # read-only highlights. The frozen transport/burst paths remain untouched.
    for relative in (
        "Tactics/AutoBurst.lua",
        "Signal/SignalFrame.lua",
        "Signal/SignalEncoder.lua",
    ):
        source = read(relative)
        assert "ReactionBindings" not in source, relative
        assert "autoReaction" not in source, relative
