"""P5.9: control/defense/survival macro compatibility stays manual and fail-closed."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
MACRO = ADDON / "Actions" / "MacroSemantics.lua"
RESOLVER = ADDON / "Actions" / "ActionBarBindingResolver.lua"
ADVISORS = ADDON / "Tactics" / "TacticalAdvisors.lua"
PLANNER = ADDON / "Tactics" / "AdvisoryPlanner.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "p59_macro_compatibility.lua"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(path)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_existing_use_macros_match_item_id_link_name_branches_and_castsequence() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        _G.C_Item = {{
            GetItemInfoInstant = function(token)
                if token == "治疗石" then return 5512 end
                if token == "治疗药水" then return 171267 end
                return nil
            end,
        }}
        dofile({str(MACRO)!r})
        local M = _G.TacticEcho.MacroSemantics

        local function expect(body, itemID, itemName, wanted, wantedKind)
            local semantics = M:Analyze(body)
            local matched, kind = M:MatchItem(semantics, itemID, itemName, "broad")
            if matched ~= wanted or kind ~= wantedKind then
                error("unexpected:" .. tostring(matched) .. ":" .. tostring(kind))
            end
            return semantics
        end

        local direct = expect("/stopcasting\\n/use [@player] item:5512", 5512, "治疗石", true, "macro_item_single")
        if M:Summary(direct).resolvedItemTokenCount ~= 1 then error("item_id_not_recorded") end
        expect("/use [mod:shift] 5512; [nomod] 治疗药水", 5512, "治疗石", true, "macro_item_broad_multi_item")
        expect("/castsequence reset=combat item:5512, 治疗药水", 5512, "治疗石", true, "macro_item_broad_castsequence")
        expect("/use 治疗药水", 5512, "治疗石", false, "macro_item_not_referenced")
        '''
    )
    run_texlua(script)


def test_control_defense_and_survival_keep_visible_macro_sources_manual_only() -> None:
    macro = MACRO.read_text(encoding="utf-8")
    resolver = RESOLVER.read_text(encoding="utf-8")
    advisors = ADVISORS.read_text(encoding="utf-8")
    planner = PLANNER.read_text(encoding="utf-8")

    # Item resolution now follows the same read-only semantic association model
    # as spell resolution, but the manual target still points to the existing
    # button rather than fabricating an item action or hotkey.
    assert "function MacroSemantics:MatchItem" in macro
    assert "local function macroItemCandidateMatches" in resolver
    assert 'TE.MacroSemantics:MatchItem(semantics, itemID, itemName, "broad")' in resolver
    assert "function Resolver:ResolveItem(itemID)" in resolver
    assert "function Resolver:ResolveManualItem(itemID)" in resolver
    assert "return manualTargetFromResult(result, reason)" in resolver

    # A reliable visible macro with no usable keyboard BindingToken may still be
    # rendered and physically clicked from HUD. The presentation wrapper fixes
    # its token at zero, so it cannot create a new automatic dispatch channel.
    for layer, helper in ((advisors, "actionbarPresentationSource"), (planner, "presentationBinding")):
        assert f"local function {helper}" in layer
        assert "bindingToken = 0" in layer
        assert "manualActionSource = true" in layer
        assert "advisoryOnlyBinding = true" in layer
    assert "return actionbarPresentationSource(info)" in advisors
    assert "return presentationBinding(resolved)" in planner
    assert "local source = presentationBinding(resolved)" in planner

    # Macro-backed action slots retain their verified action-bar cooldown identity
    # for display instead of being silently downgraded merely because they are macros.
    assert "actionBarStateTrusted = binding and binding.actionBarStateTrusted == true or false" in advisors
    assert "actionBarStateTrusted = binding and binding.actionBarStateTrusted == true or false" in planner
    assert "actionBarStateTrusted = binding.actionBarStateTrusted == true" in planner

    for forbidden in (":Click(", "SetOverrideBinding", "EditMacro", "CreateMacro"):
        assert forbidden not in resolver
