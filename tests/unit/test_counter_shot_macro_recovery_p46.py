"""P4.6 regression: macro body recovery and SpellID-backed association.

The test models a client sequence where GetMacroInfo(actionInfoID) exposes a
macro name but not a body on the first read, GetActionText is empty, and the
requested spell's localized name is unavailable. The resolver must retry the
same numeric macro index, rather than use its visible name as an identity key,
and match its /cast token through a read-only token -> SpellID lookup.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
MACRO = ADDON / "Actions" / "MacroSemantics.lua"
RESOLVER = ADDON / "Actions" / "ActionBarBindingResolver.lua"


def test_counter_shot_macro_recovers_when_name_api_is_unavailable() -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return

    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{
            RegisterEventsSafe = function() end,
        }}
        _G.NUM_ACTIONBAR_BUTTONS = 12
        _G.C_Spell = {{
            GetSpellInfo = function(value)
                if value == "反制射击" then return {{ spellID = 147362 }} end
                -- Deliberately do not materialize a localized name for the
                -- requested numeric SpellID.  The macro token lookup must be
                -- sufficient by itself.
                if value == 147362 then return {{ spellID = 147362 }} end
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
            if slot == 1 then return "macro", 121, nil, nil end
            return nil
        end
        _G.GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then return "F" end
            return nil
        end
        _G.GetActionText = function() return nil end
        _G.GetMacroSpell = function() return nil end
        _G.GetNumMacros = function() error("P5 must not enumerate macros by name") end
        local macroInfoCalls = 0
        _G.GetMacroInfo = function(index)
            if index == 121 then
                macroInfoCalls = macroInfoCalls + 1
                if macroInfoCalls == 1 then return "反制回退", 1, nil end
                return "反制回退", 1, [[#showtooltip
        /stopcasting
        /cast [@focus,nodead] 反制射击
        /cleartarget
        /targetenemy
        /cast 反制射击
        /targetlasttarget]]
            end
            return nil
        end
        _G.CreateFrame = function()
            return {{ SetScript = function() end }}
        end
        _G.GetTime = function() return 1 end

        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})
        local resolver = _G.TacticEcho.ActionBarBindingResolver
        local result = resolver:ResolveSpell(147362)
        if result.status ~= "Ready" then error("status:" .. tostring(result.status) .. ":" .. tostring(result.reason)) end
        if result.source ~= "macro" then error("source:" .. tostring(result.source)) end
        if result.macroAssociation ~= "macro_body_single_spell" then
            error("association:" .. tostring(result.macroAssociation))
        end
        if result.binding ~= "F" or tonumber(result.bindingToken) <= 0 then
            error("binding:" .. tostring(result.binding) .. ":" .. tostring(result.bindingToken))
        end
        local candidate = result.candidates and result.candidates[1] or {{}}
        if candidate.macroDiagnostic == nil
            or candidate.macroDiagnostic.macroIdentitySource ~= "action_info_macro_index"
            or candidate.macroDiagnostic.macroIdentityVerified ~= true
            or tonumber(candidate.macroDiagnostic.actionInfoMacroIndex) ~= 121
            or tonumber(candidate.macroDiagnostic.actionInfoIdReadAttempts) ~= 2
            or candidate.macroDiagnostic.lookupByActionInfoName == true then
            error("action_info_index_recovery_missing")
        end
        '''
    )
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "counter_shot_recovery.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr
