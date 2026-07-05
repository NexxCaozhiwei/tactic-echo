"""P5.11 hunter-control macro identity and request-scoped diagnostics."""
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
PROFILES = ADDON / "Tactics" / "AbilityProfiles.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "p511_hunter_control.lua"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(path)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def preamble() -> str:
    return f'''\
        _G.TacticEcho = {{ RegisterEventsSafe = function() end }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.MAX_ACCOUNT_MACROS = 120
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == "冰冻陷阱" or value == 187650 then
                    return {{ spellID = 187650, name = "冰冻陷阱" }}
                end
                if value == "威慑" or value == 186265 then
                    return {{ spellID = 186265, name = "威慑" }}
                end
                return nil
            end,
        }}
        local action1, action2 = 1, 2
        _G.ActionButton1 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return action1 end end,
            GetCenter = function() return 100, 100 end,
        }}
        _G.ActionButton2 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return action2 end end,
            GetCenter = function() return 200, 100 end,
        }}
        _G.GetActionBarPage = function() return 1 end
        _G.GetBonusBarOffset = function() return 0 end
        _G.GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then return "CTRL-1" end
            if command == "ACTIONBUTTON2" then return "BUTTON3" end
            return nil
        end
        _G.CreateFrame = function() return {{ SetScript = function() end }} end
        _G.GetTime = function() return 1 end
        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})
    '''


def test_current_macro_index_accepts_spell_display_text_without_scanning_other_index() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 1, nil, nil end
            if slot == 2 then return "macro", 2, nil, nil end
            return nil
        end
        _G.GetActionText = function(slot)
            if slot == 1 then return "冰冻陷阱" end
            if slot == 2 then return "坐骑" end
            return nil
        end
        local readOtherIndex = false
        _G.ActionButton2.IsShown = function() return false end
        _G.ActionButton2.IsVisible = function() return false end
        _G.GetMacroInfo = function(index)
            if index == 1 then return "陷阱鼠标宏", 1, [[#showtooltip 冰冻陷阱
/cast [@cursor] 冰冻陷阱]] end
            if index == 2 then
                readOtherIndex = true
                return "坐骑", 1, [[/cast 雄壮远足牦牛]]
            end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status ~= "Ready" or result.source ~= "macro"
            or result.buttonName ~= "ActionButton1" or result.actionSlot ~= 1
            or result.binding ~= "CTRL+1" or result.macroID ~= 1 then
            error("indexed_trap_not_bound:" .. tostring(result.status) .. ":"
                .. tostring(result.buttonName) .. ":" .. tostring(result.binding))
        end
        local diag = result.macroDiagnostic or {{}}
        if diag.macroIdentitySource ~= "action_info_macro_index"
            or diag.directIndexActionTextDiffers ~= true
            or diag.directIndexActionText ~= "冰冻陷阱"
            or diag.directIndexMacroName ~= "陷阱鼠标宏" then
            error("indexed_display_text_not_diagnostic:" .. tostring(diag.macroIdentitySource)
                .. ":" .. tostring(diag.directIndexActionTextDiffers))
        end
        if readOtherIndex then error("indexed_macro_scanned_other_macro") end
        '''
    )
    run_texlua(script)


def test_represented_spell_display_recovers_unique_different_named_macro() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 1, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 187650, nil, nil end
            return nil
        end
        _G.GetActionText = function(slot)
            if slot == 1 then return "冰冻陷阱" end
            return nil
        end
        _G.GetMacroInfo = function(index)
            -- Retail does not expose a usable macro-name handle here.
            if index == 1 then return "陷阱鼠标宏", 1, [[#showtooltip
/cast [@cursor] 冰冻陷阱]] end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status ~= "Ready" or result.buttonName ~= "ActionButton1"
            or result.actionSlot ~= 1 or result.binding ~= "CTRL+1" or result.macroID ~= 1 then
            error("represented_spell_display_not_bound:" .. tostring(result.status)
                .. ":" .. tostring(result.buttonName) .. ":" .. tostring(result.binding))
        end
        local diag = result.macroDiagnostic or {{}}
        if diag.macroIdentityVerified ~= true
            or diag.semanticNameSource ~= "action_text_represented_spell"
            or diag.semanticLookupName ~= "冰冻陷阱"
            or diag.semanticResolvedMacroName ~= "陷阱鼠标宏"
            or diag.lookupSource ~= "action_text_represented_spell_unique_semantic" then
            error("represented_spell_display_identity_missing:" .. tostring(diag.semanticNameSource)
                .. ":" .. tostring(diag.lookupSource))
        end
        '''
    )
    run_texlua(script)


def test_represented_spell_display_multiple_bodies_fails_closed() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 187650, nil, nil end
            return nil
        end
        _G.GetActionText = function(slot)
            if slot == 1 then return "冰冻陷阱" end
            return nil
        end
        _G.GetMacroInfo = function(index)
            if index == 1 then return "陷阱宏A", 1, [[/cast [@cursor] 冰冻陷阱]] end
            if index == 2 then return "陷阱宏B", 1, [[/cast 冰冻陷阱]] end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 or index == 2 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status == "Ready" or result.bindingToken ~= 0 then
            error("represented_spell_display_ambiguity_fail_open:" .. tostring(result.status))
        end
        local diag = result.macroDiagnostics and result.macroDiagnostics[1] or {{}}
        if diag.identityFailureReason ~= "macro_semantic_identity_ambiguous"
            or diag.semanticCandidateIndexes == nil
            or diag.semanticCandidateIndexes[1] ~= 1
            or diag.semanticCandidateIndexes[2] ~= 2 then
            error("represented_spell_display_ambiguity_missing:" .. tostring(diag.identityFailureReason))
        end
        '''
    )
    run_texlua(script)


def test_unrelated_mount_macro_is_not_control_diagnostic() -> None:
    script = textwrap.dedent(
        preamble()
        + r'''
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", 187650, nil, nil end
            if slot == 2 then return "macro", 2, nil, nil end
            return nil
        end
        _G.GetActionText = function(slot)
            if slot == 1 then return "冰冻陷阱宏" end
            if slot == 2 then return "坐骑" end
            return nil
        end
        _G.GetMacroInfo = function(index)
            if index == 1 then return "冰冻陷阱宏", 1, [[/cast 威慑]] end
            if index == 2 then return "坐骑", 1, [[/cast 雄壮远足牦牛]] end
            return nil
        end
        _G.GetMacroSpell = function(index)
            if index == 1 then return "冰冻陷阱", nil, 187650 end
            return nil
        end

        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(187650)
        if result.status == "Ready" then error("wrong_body_should_not_bind") end
        local diags = result.macroDiagnostics or {{}}
        if #diags ~= 1 or diags[1].buttonName ~= "ActionButton1"
            or diags[1].rawBinding ~= "CTRL-1" then
            error("unrelated_mount_leaked_into_control_diag:" .. tostring(#diags)
                .. ":" .. tostring(diags[1] and diags[1].buttonName))
        end
        '''
    )
    run_texlua(script)


def test_hunter_control_profile_uses_visible_action_spell_id() -> None:
    text = PROFILES.read_text(encoding="utf-8")
    assert "HUNTER = { 19577, 187650 }" in text
    assert '{ spellID = 19577, role = "single", roleLabel = "单体控制" }' in text
    assert "{ spellID = 24394, role = \"single\", roleLabel = \"单体控制\" }" not in text
