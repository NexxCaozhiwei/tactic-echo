"""P5.11: every macro consumer uses one current-action-bar identity policy."""
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
AUTOBURST = ADDON / "Tactics" / "AutoBurst.lua"
REACTION = ADDON / "Tactics" / "ReactionBindings.lua"
ADVISORS = ADDON / "Tactics" / "TacticalAdvisors.lua"
PLANNER = ADDON / "Tactics" / "AdvisoryPlanner.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "p511_shared_macro_policy.lua"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(path)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_all_macro_consumers_delegate_to_canonical_current_actionbar_policy() -> None:
    resolver = RESOLVER.read_text(encoding="utf-8")
    autoburst = AUTOBURST.read_text(encoding="utf-8")
    reaction = REACTION.read_text(encoding="utf-8")
    advisors = ADVISORS.read_text(encoding="utf-8")
    planner = PLANNER.read_text(encoding="utf-8")

    assert "function Resolver:IsVerifiedCurrentMacroSource(value, association)" in resolver
    assert "function Resolver:IsAutoBurstMacroEligible(value)" in resolver
    assert "macroDiagnosticRelatesToRequestedSpell(entry, spellID, spellName)" in resolver
    assert "unrelated buttons such as a BUTTON3 mount macro" in resolver
    assert "resolver:IsAutoBurstMacroEligible(bindingInfo)" in autoburst
    assert "opaque action-info compatibility" in autoburst
    assert "resolver:IsVerifiedCurrentMacroSource(candidate, candidate.macroAssociation) == true" in reaction
    assert "addOpaqueActionSpellMacroRoute(routes, candidate, spellID)" in reaction
    assert "resolver:IsVerifiedCurrentMacroSource(info, info.macroAssociation)" in advisors
    assert "resolver:IsVerifiedCurrentMacroSource(resolved, resolved.macroAssociation)" in planner


def test_verified_cursor_control_and_use_item_macro_share_manual_identity_contract() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{ RegisterEventsSafe = function() end }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.MAX_ACCOUNT_MACROS = 120
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == 187650 or value == "冰冻陷阱" then
                    return {{ spellID = 187650, name = "冰冻陷阱" }}
                end
                return nil
            end,
        }}
        _G.C_Item = {{
            GetItemInfo = function(value)
                if value == 5512 then return {{ itemName = "治疗石" }} end
                return nil
            end,
        }}
        _G.ActionButton1 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return 1 end end,
            GetCenter = function() return 100, 100 end,
        }}
        _G.ActionButton2 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return 2 end end,
            GetCenter = function() return 200, 100 end,
        }}
        _G.GetActionBarPage = function() return 1 end
        _G.GetBonusBarOffset = function() return 0 end
        _G.GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then return "CTRL-1" end
            if command == "ACTIONBUTTON2" then return "CTRL-2" end
            return nil
        end
        _G.CreateFrame = function() return {{ SetScript = function() end }} end
        _G.GetTime = function() return 1 end
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 1, nil, nil end
            if slot == 2 then return "macro", 2, nil, nil end
            return nil
        end
        _G.GetActionText = function(slot)
            if slot == 1 then return "冰冻陷阱" end
            if slot == 2 then return "治疗石" end
            return nil
        end
        _G.GetMacroInfo = function(index)
            if index == 1 then return "猎人鼠标陷阱", 1, [[#showtooltip 冰冻陷阱
/cast [@cursor] 冰冻陷阱]] end
            if index == 2 then return "治疗石宏", 1, [[#showtooltip 治疗石
/use item:5512]] end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 then return "冰冻陷阱", nil, 187650 end
            return nil, nil, nil
        end
        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})

        local resolver = _G.TacticEcho.ActionBarBindingResolver
        local trap = resolver:ResolveSpell(187650)
        if trap.status ~= "Ready" or trap.source ~= "macro" or trap.binding ~= "CTRL+1"
            or trap.macroID ~= 1 or tostring(trap.macroAssociation):find("macro_body_", 1, true) ~= 1 then
            error("verified_cursor_trap_not_ready:" .. tostring(trap.status) .. ":" .. tostring(trap.binding))
        end
        if resolver:IsVerifiedCurrentMacroSource(trap, trap.macroAssociation) ~= true then
            error("verified_cursor_trap_not_manual_source")
        end

        local stone = resolver:ResolveItem(5512)
        if stone.status ~= "Ready" or stone.source ~= "macro" or stone.binding ~= "CTRL+2"
            or stone.macroID ~= 2 or tostring(stone.macroAssociation):find("macro_item_", 1, true) ~= 1 then
            error("verified_use_item_not_ready:" .. tostring(stone.status) .. ":" .. tostring(stone.binding)
                .. ":" .. tostring(stone.macroAssociation))
        end
        if resolver:IsVerifiedCurrentMacroSource(stone, stone.macroAssociation) ~= true then
            error("verified_use_item_not_manual_source")
        end

        local opaque = {{
            source = "macro",
            macroAssociation = "action_info_represented_spell",
            macroOpaqueRepresentedSpell = true,
            macroDiagnostic = {{ macroIdentityVerified = false }},
        }}
        if resolver:IsVerifiedCurrentMacroSource(opaque, opaque.macroAssociation) == true then
            error("opaque_macro_admitted_as_manual")
        end
        if resolver:IsAutoBurstMacroEligible(opaque) == true then
            error("opaque_macro_admitted_to_burst")
        end
        '''
    )
    run_texlua(script)
