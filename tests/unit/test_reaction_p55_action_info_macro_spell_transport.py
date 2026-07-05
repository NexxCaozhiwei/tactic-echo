# P5.5 test: exact opaque macro action spell identity.
from __future__ import annotations

import pytest

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
MACRO = ADDON / "Actions" / "MacroSemantics.lua"
RESOLVER = ADDON / "Actions" / "ActionBarBindingResolver.lua"
REACTION = ADDON / "Tactics" / "ReactionBindings.lua"
AUTO = ADDON / "Tactics" / "AutoReaction.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "reaction_p55_macro_spell.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skip(reason='P5.7 intentionally hard-pauses automatic interrupt; historical candidate-dispatch contract is inactive.')
def test_opaque_action_info_macro_spell_registers_target_transport_and_obeys_cd() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        NUM_ACTIONBAR_BUTTONS = 1
        local timeNow = 1.0
        GetTime = function() return timeNow end
        _G.TacticEcho.RegisterEventsSafe = function() end
        CreateFrame = function()
            return {{ RegisterEvent = function() end, SetScript = function() end }}
        end
        C_Spell = {{ GetSpellInfo = function(spellID)
            return {{ name = spellID == 147362 and "反制射击" or tostring(spellID), iconID = 1 }}
        end }}
        GetActionBarPage = function() return 1 end
        GetBonusBarOffset = function() return 0 end
        GetShapeshiftForm = function() return 0 end
        -- Exact current-client shape: macro action and macro-spell identity
        -- identify Counter Shot, but no usable macro index/body exists.
        GetActionInfo = function(slot)
            if slot == 1 then return "macro", 147362, nil, 147362 end
            return nil
        end
        GetActionText = function() return nil end
        GetMacroInfo = function(index)
            if index == 147362 then return "反射", nil, nil end
            if index == 1 then return "其它宏", nil, "/cast 1" end
            return nil, nil, nil
        end
        GetNumMacros = function() return 1, 0 end
        GetMacroSpell = function() return nil, nil, nil end
        GetBindingKey = function(command)
            if command == "ACTIONBUTTON1" then return "F" end
            return nil, nil
        end
        _G.ActionButton1 = {{
            IsShown = function() return true end,
            IsVisible = function() return true end,
            GetAttribute = function(_, key) if key == "action" then return 1 end end,
            GetCenter = function() return 100, 100 end,
        }}

        dofile({str(MACRO)!r})
        dofile({str(RESOLVER)!r})
        local resolved = _G.TacticEcho.ActionBarBindingResolver:ResolveSpell(147362)
        local candidate = resolved.candidates and resolved.candidates[1]
        if resolved.status ~= "Ready" or not candidate
            or candidate.macroAssociation ~= "action_info_macro_spell"
            or candidate.macroOpaqueRepresentedSpell == true
            or candidate.matchedSpellID ~= 147362 then
            error("macro_spell_identity_not_resolved:" .. tostring(resolved.status)
                .. ":" .. tostring(candidate and candidate.macroAssociation))
        end

        _G.TacticEcho.Context = {{ GetPlayer = function() return {{ class = "HUNTER", specIndex = 1 }} end }}
        _G.TacticEcho.AbilityProfiles = {{
            GetInterrupts = function() return {{ 147362 }} end,
            GetReactionControls = function() return {{}} end,
        }}
        dofile({str(REACTION)!r})
        local mapped = _G.TacticEcho.ReactionBindings:GetSnapshot(true).interrupt[1]
        local route = mapped and mapped.routes and mapped.routes.target
        if not route or route.safeForFutureAuto ~= true
            or route.autoRouteMode ~= "action_info_macro_spell_compat"
            or route.bindingToken ~= 4
            or route.macroOpaqueRepresentedSpell ~= true
            or mapped.routes.focus ~= nil or mapped.routes.mouseover ~= nil then
            error("macro_spell_route_not_target_only")
        end

        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true, compatibilityActiveCast = false,
            targetOrder = {{ "target" }}, targetEnabled = {{ target = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        local cooldownActive = true
        local seenOptions = nil
        _G.TacticEcho.IconState = {{ CollectCooldownOnly = function(_, spellID, options)
            seenOptions = options
            return {{ cooldownKnown = true, cooldownActive = cooldownActive,
                cooldownOnGCD = false, cooldownGcdAlias = false,
                cooldownSource = "exact_actionbar", cooldownExactActionVetoEvidence = true }}
        end }}
        _G.TacticEcho.ReactionInterruptEvents = {{ GetEvidence = function()
            return {{ active = true, status = "pending", age = 0.05, reason = "unit_event_pending" }}
        end }}
        local observation
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return observation end }}
        _G.TacticEcho.ReactionBindings.GetSnapshot = function() return {{ interrupt = {{ mapped }} }} end
        dofile({str(AUTO)!r})

        local function setCast(observedAt)
            timeNow = observedAt
            observation = {{ observedAt = observedAt, sources = {{ target = {{
                exists = true, hostile = true, alive = true,
                cast = {{ active = true, continuity = "live", castSerial = 1,
                    spellID = 900001, startTimeMS = 100, endTimeMS = 3000, kind = "cast",
                    directInterruptibilityKnown = true, interruptibilitySource = "unit_api",
                    interruptibleKnown = true, interruptible = true,
                    nativeInterruptibilityEvidence = "native_showShield_config_true" }},
            }} }} }}
        end
        local function evaluate() return _G.TacticEcho.AutoReaction:Evaluate({{
            inCombat = true, intentState = "armed", effectiveState = "armed",
        }}) end

        setCast(1.00); local cd = evaluate()
        if cd.kind ~= "none" or cd.reason ~= "interrupt_action_cooldown"
            or cd.cooldownActionSlot ~= 1 then
            error("macro_spell_cd_not_blocked:" .. tostring(cd.kind) .. ":" .. tostring(cd.reason))
        end
        if not seenOptions or seenOptions.actionSlot ~= 1 or seenOptions.exactActionCooldownVeto ~= true then
            error("macro_spell_exact_slot_missing")
        end

        cooldownActive = false
        setCast(1.10); local ready = evaluate()
        if ready.kind ~= "candidate" or ready.dispatchOrigin ~= "reaction"
            or ready.routeMode ~= "action_info_macro_spell_compat"
            or ready.bindingInfo.bindingToken ~= 4
            or ready.macroOpaqueRepresentedSpell ~= true
            or ready.reason ~= "confirmed_interrupt_candidate" then
            error("macro_spell_p43_transport_not_restored:" .. tostring(ready.kind) .. ":" .. tostring(ready.reason))
        end
        '''
    )
    run_texlua(script)


def test_p55_accepts_both_exact_action_info_spell_forms_without_macro_name_recovery() -> None:
    reaction = REACTION.read_text(encoding="utf-8")
    for token in (
        "OPAQUE_ACTION_SPELL_ASSOCIATIONS",
        "action_info_represented_spell",
        "action_info_macro_spell",
        "opaqueActionSpellBodyUnavailable",
        "action_info_macro_spell_compat",
    ):
        assert token in reaction
    resolver = RESOLVER.read_text(encoding="utf-8")
    assert "lookupMacroByName" not in resolver
