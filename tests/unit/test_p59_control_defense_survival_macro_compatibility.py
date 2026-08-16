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


def test_shared_macro_qualification_is_owned_by_resolver_and_autoburst() -> None:
    macro = MACRO.read_text(encoding="utf-8")
    resolver = RESOLVER.read_text(encoding="utf-8")
    auto = (ADDON / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
    advisors = ADVISORS.read_text(encoding="utf-8")
    assert "function MacroSemantics:MatchItem" in macro
    assert "function Resolver:IsVerifiedCurrentMacroSource" in resolver
    assert "function Resolver:IsAutoBurstMacroEligible" in resolver
    assert "resolver:IsAutoBurstMacroEligible(bindingInfo)" in auto
    assert "bindingToken = 0" in advisors
    assert "Tactics/AdvisoryPlanner.lua" not in toc

    for forbidden in (":Click(", "SetOverrideBinding", "EditMacro", "CreateMacro"):
        assert forbidden not in resolver
