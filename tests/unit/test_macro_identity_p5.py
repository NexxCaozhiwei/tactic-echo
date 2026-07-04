# P5.1 macro identity regressions.
#
# Retail may expose a macro action through its represented SpellID rather than
# the numeric macro-list index. Macro name recovery therefore must be bounded
# and semantic: exact visible macro label + represented spell + parsed body,
# and it must fail closed when more than one macro survives that join.
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


def _run_lua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "macro_identity_p51.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def _preamble(action_info_id: int) -> str:
    return f'''\
        _G.TacticEcho = {{ RegisterEventsSafe = function() end }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.MAX_ACCOUNT_MACROS = 120
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == "反制射击" or value == 147362 then return {{ spellID = 147362, name = "反制射击" }} end
                if value == "奥术射击" or value == 3044 then return {{ spellID = 3044, name = "奥术射击" }} end
                if value == "心灵冰冻" or value == 47528 then return {{ spellID = 47528, name = "心灵冰冻" }} end
                return nil
            end,
        }}
        _G.ActionButton1 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return 1 end end,
            GetCenter = function() return 100, 100 end,
        }}
        _G.GetActionBarPage = function() return 1 end
        _G.GetBonusBarOffset = function() return 0 end
        _G.GetActionInfo = function(slot)
            if slot == 1 then return "macro", {action_info_id}, nil, nil end
            return nil
        end
        _G.GetBindingKey = function(command) if command == "ACTIONBUTTON1" then return "F" end return nil end
        _G.GetActionText = function() return "打断" end
        _G.CreateFrame = function() return {{ SetScript = function() end }} end
        _G.GetTime = function() return 1 end
        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})
    '''


def test_numeric_action_info_macro_index_remains_exact_identity() -> None:
    script = textwrap.dedent(
        _preamble(121)
        + r'''
        _G.GetNumMacros = function() return 1, 1 end
        _G.GetMacroSpell = function(index)
            if index == 121 then return "反制射击", nil, 147362 end
            return nil
        end
        local calls121 = 0
        _G.GetMacroInfo = function(index)
            if index == 1 then return "打断", 1, [[/cast 奥术射击]] end
            if index == 121 then
                calls121 = calls121 + 1
                if calls121 == 1 then return "打断", 1, nil end
                return "打断", 1, [[#showtooltip
/stopcasting
/cast [@focus,nodead] 反制射击
/cleartarget
/targetenemy
/cast 反制射击
/targetlasttarget]]
            end
            return nil
        end
        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(147362)
        if result.status ~= "Ready" or result.macroID ~= 121 then
            error("wrong_result:" .. tostring(result.status) .. ":" .. tostring(result.macroID))
        end
        local diag = result.candidates[1].macroDiagnostic or {}
        if diag.lookupSource ~= "action_info_macro_index_retry"
            or diag.macroIdentitySource ~= "action_info_macro_index"
            or diag.macroIdentityVerified ~= true
            or diag.actionInfoLooksLikeMacroIndex ~= true then
            error("numeric_identity_diag_missing")
        end
        '''
    )
    _run_lua(script)


def test_represented_spell_id_recovers_unique_same_name_candidate() -> None:
    script = textwrap.dedent(
        _preamble(147362)
        + r'''
        _G.GetNumMacros = function() return 2, 1 end
        _G.GetMacroSpell = function(index)
            if index == 1 then return "奥术射击", nil, 3044 end
            if index == 2 then return "反制射击", nil, 147362 end
            if index == 121 then return "心灵冰冻", nil, 47528 end
            return nil
        end
        _G.GetMacroInfo = function(index)
            if index == 1 then return "打断", 1, [[/cast 奥术射击]] end
            if index == 2 then return "打断", 1, [[#showtooltip
/stopcasting
/cast [@focus,nodead] 反制射击
/cleartarget
/targetenemy
/cast 反制射击
/targetlasttarget]] end
            if index == 121 then return "打断", 1, [[/cast 心灵冰冻]] end
            return nil
        end
        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(147362)
        if result.status ~= "Ready" or result.macroID ~= 2 then
            error("wrong_result:" .. tostring(result.status) .. ":" .. tostring(result.macroID) .. ":" .. tostring(result.reason))
        end
        local diag = result.candidates[1].macroDiagnostic or {}
        if diag.lookupSource ~= "action_text_unique_spell_semantic"
            or diag.macroIdentitySource ~= "action_text_unique_spell_semantic"
            or diag.macroIdentityVerified ~= true
            or diag.actionInfoLooksLikeMacroIndex == true
            or diag.representedSpellID ~= 147362
            or diag.semanticCandidateCount ~= 1
            or diag.actionTextCandidateCount ~= 3 then
            error("represented_spell_identity_diag_missing")
        end
        '''
    )
    _run_lua(script)


def test_same_name_same_spell_candidates_fail_closed() -> None:
    script = textwrap.dedent(
        _preamble(147362)
        + r'''
        _G.GetNumMacros = function() return 2, 0 end
        _G.GetMacroSpell = function(index)
            if index == 1 or index == 2 then return "反制射击", nil, 147362 end
            return nil
        end
        _G.GetMacroInfo = function(index)
            if index == 1 then return "打断", 1, [[/cast [@focus,nodead] 反制射击]] end
            if index == 2 then return "打断", 1, [[/cast 反制射击]] end
            return nil
        end
        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(147362)
        if result.status == "Ready" or result.bindingToken ~= 0 then
            error("ambiguous_same_name_fail_open")
        end
        local diag = result.macroDiagnostics and result.macroDiagnostics[1] or {}
        if diag.identityFailureReason ~= "macro_semantic_identity_ambiguous" then
            error("ambiguity_diag_missing:" .. tostring(diag.identityFailureReason))
        end
        '''
    )
    _run_lua(script)
