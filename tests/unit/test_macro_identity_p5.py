# P5 macro identity regressions.
#
# P5 requires a visible macro button to recover its body only through the
# numeric macro index returned by GetActionInfo. Duplicate Chinese/English
# names may exist in account and character macro scopes and must never be used
# to select a body.
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
        test_file = Path(tmp) / "macro_identity_p5.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def _preamble() -> str:
    return f'''\
        _G.TacticEcho = {{ RegisterEventsSafe = function() end }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == "反制射击" or value == 147362 then return {{ spellID = 147362, name = "反制射击" }} end
                if value == "奥术射击" or value == 3044 then return {{ spellID = 3044, name = "奥术射击" }} end
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
        _G.GetActionInfo = function(slot) if slot == 1 then return "macro", 121, nil, nil end return nil end
        _G.GetBindingKey = function(command) if command == "ACTIONBUTTON1" then return "F" end return nil end
        _G.GetActionText = function() return "打断" end
        _G.GetMacroSpell = function() return nil end
        _G.CreateFrame = function() return {{ SetScript = function() end }} end
        _G.GetTime = function() return 1 end
        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})
    '''


def test_duplicate_chinese_macro_name_recovers_only_action_info_index() -> None:
    script = textwrap.dedent(
        _preamble()
        + r'''
        local calls121, stringLookup, enumLookup = 0, 0, 0
        _G.GetNumMacros = function() enumLookup = enumLookup + 1; return 1, 1 end
        _G.GetMacroInfo = function(index)
            if type(index) ~= "number" then stringLookup = stringLookup + 1; return "打断", 1, [[/cast 奥术射击]] end
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
        if diag.lookupSource ~= "action_info_id_retry" or diag.macroIdentityVerified ~= true
            or diag.macroIdentitySource ~= "action_info_id" or diag.actionInfoMacroIndex ~= 121
            or diag.actionInfoIdReadAttempts ~= 2 then
            error("identity_diag_missing")
        end
        if stringLookup ~= 0 or enumLookup ~= 0 then
            error("name_recovery_used:" .. tostring(stringLookup) .. ":" .. tostring(enumLookup))
        end
        '''
    )
    _run_lua(script)


def test_duplicate_name_with_no_index_body_fails_closed() -> None:
    script = textwrap.dedent(
        _preamble()
        + r'''
        local stringLookup, enumLookup = 0, 0
        _G.GetNumMacros = function() enumLookup = enumLookup + 1; return 1, 1 end
        _G.GetMacroInfo = function(index)
            if type(index) ~= "number" then stringLookup = stringLookup + 1; return "打断", 1, [[/cast 反制射击]] end
            if index == 1 then return "打断", 1, [[/cast 反制射击]] end
            if index == 121 then return "打断", 1, nil end
            return nil
        end
        local result = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(147362)
        if result.status == "Ready" or result.bindingToken ~= 0 then
            error("duplicate_name_fail_open")
        end
        if result.reason ~= "macro_body_unavailable" then
            error("reason:" .. tostring(result.reason))
        end
        if stringLookup ~= 0 or enumLookup ~= 0 then
            error("name_recovery_used:" .. tostring(stringLookup) .. ":" .. tostring(enumLookup))
        end
        local diag = result.macroDiagnostics and result.macroDiagnostics[1] or {}
        if diag.actionInfoMacroIndex ~= 121 or diag.macroIdentityVerified == true
            or diag.failureReason ~= "macro_body_unavailable" then
            error("fail_closed_diag_missing:" .. tostring(diag.failureReason))
        end
        '''
    )
    _run_lua(script)
