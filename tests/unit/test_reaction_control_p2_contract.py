"""Contract for the narrowed runtime scope: reaction P2 is retired."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_reaction_binding_runtime_is_not_loaded() -> None:
    toc = read("!TacticEcho.toc")
    assert "Actions/MacroSemantics.lua" in toc
    assert "Actions/ActionBarBindingResolver.lua" in toc
    assert "Tactics/AbilityProfiles.lua" in toc
    assert "Tactics/ReactionBindings.lua" not in toc


def test_shared_macro_semantics_remain_available_for_primary_and_autoburst() -> None:
    macro = read("Actions/MacroSemantics.lua")
    for token in (
        "function MacroSemantics:DescribeSpellRoutes",
        "macro_castsequence_route_opaque",
        "macroManagedTargetAuto",
        "autoRouteMode",
    ):
        assert token in macro


def test_control_settings_page_is_not_in_navigation_scope() -> None:
    panel = read("UI/ControlPanel.lua")
    assert "PAGE_META.control" not in panel
    assert "BUILDERS.interrupt = nil" in panel
    assert "LEGACY_PAGE_ALIAS.control = \"hud\"" in panel


def test_retired_reaction_mapping_does_not_modify_dispatch_or_burst_runtime_paths() -> None:
    for relative in (
        "Tactics/AutoBurst.lua",
        "Signal/SignalFrame.lua",
        "Signal/SignalEncoder.lua",
    ):
        source = read(relative)
        assert "ReactionBindings" not in source, relative
