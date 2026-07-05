"""P5.4: restore the P4.3 interrupt transport from the actual visible actionbar.

Retail can expose a macro action as its represented spell ID while withholding
both a usable macro index and the macro body.  The current visible button and
its real binding remain authoritative for target-only transport; no macro-list
name lookup or branch inference is used.
"""
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
        test_file = Path(tmp) / "reaction_p54_route_reanchor.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skip(reason='P5.7 intentionally hard-pauses automatic interrupt; historical candidate-dispatch contract is inactive.')
def test_actual_actionbar_represented_interrupt_spell_restores_target_transport_and_keeps_cd_steel_gates() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        NUM_ACTIONBAR_BUTTONS = 1
        local timeNow = 1
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
        GetActionInfo = function(slot)
            if slot == 1 then return "macro", 147362, nil, nil end
            return nil
        end
        GetActionText = function() return nil end
        -- The client only exposes a label when queried by the represented ID,
        -- not a macro body or valid macro-list index.
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
            or candidate.source ~= "macro"
            or candidate.macroAssociation ~= "action_info_represented_spell"
            or candidate.macroOpaqueRepresentedSpell ~= true
            or candidate.parsed.binding ~= "F" then
            error("represented_action_not_resolved:" .. tostring(resolved.status)
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
            or route.autoRouteMode ~= "action_info_represented_spell_compat"
            or route.bindingToken ~= 4
            or route.macroOpaqueRepresentedSpell ~= true
            or mapped.routes.focus ~= nil or mapped.routes.mouseover ~= nil then
            error("represented_route_not_target_only")
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
        local eventStatus = "pending"
        _G.TacticEcho.ReactionInterruptEvents = {{ GetEvidence = function()
            return {{ active = eventStatus ~= "unavailable", status = eventStatus, age = 0.05,
                reason = "unit_event_" .. tostring(eventStatus) }}
        end }}
        local observation
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return observation end }}
        _G.TacticEcho.ReactionBindings.GetSnapshot = function() return {{ interrupt = {{ mapped }} }} end
        dofile({str(AUTO)!r})

        local function setCast(observedAt, serial)
            observation = {{ observedAt = observedAt, sources = {{ target = {{
                exists = true, hostile = true, alive = true,
                cast = {{ active = true, continuity = "live", castSerial = serial or 1,
                    spellID = 900001, startTimeMS = 100, endTimeMS = 3000, kind = "cast",
                    directInterruptibilityKnown = true, interruptibilitySource = "unit_api",
                    interruptibleKnown = true, interruptible = true,
                    nativeInterruptibilityEvidence = "native_showShield_config_true" }},
            }} }} }}
        end
        local function evaluate() return _G.TacticEcho.AutoReaction:Evaluate({{
            inCombat = true, intentState = "armed", effectiveState = "armed",
        }}) end

        -- A confirmed UnitCastingInfo false reaches the exact action-button
        -- cooldown gate immediately; opaque-cast compatibility timing is gone.
        setCast(1.00, 1); local cd = evaluate()
        if cd.kind ~= "none" or cd.reason ~= "interrupt_action_cooldown"
            or cd.bindingToken ~= nil or cd.cooldownActionSlot ~= 1 then
            error("exact_action_cd_not_blocked:" .. tostring(cd.kind) .. ":" .. tostring(cd.reason))
        end
        if not seenOptions or seenOptions.actionSlot ~= 1 or seenOptions.exactActionCooldownVeto ~= true then
            error("exact_action_cd_options_missing")
        end

        -- A ready actionbar button immediately restores the P4.3 delivery path.
        cooldownActive = false
        setCast(1.10, 1); local ready = evaluate()
        if ready.kind ~= "candidate" or ready.dispatchOrigin ~= "reaction"
            or ready.bindingInfo.bindingToken ~= 4
            or ready.routeMode ~= "action_info_represented_spell_compat"
            or ready.macroOpaqueRepresentedSpell ~= true
            or ready.reason ~= "confirmed_interrupt_candidate" then
            error("p43_transport_not_restored:" .. tostring(ready.kind) .. ":" .. tostring(ready.reason))
        end

        -- A later explicit steel event still wins over the compatibility route
        -- before any candidate is emitted for the new cast identity.
        eventStatus = "not_interruptible"
        cooldownActive = false
        setCast(2.00, 2); local steel = evaluate()
        if steel.kind ~= "none" or steel.reason ~= "unit_event_not_interruptible" then
            error("steel_event_bypassed:" .. tostring(steel.kind) .. ":" .. tostring(steel.reason))
        end
        '''
    )
    run_texlua(script)


def test_p54_contract_anchors_to_actual_actionbar_identity_without_macro_name_recovery() -> None:
    resolver = RESOLVER.read_text(encoding="utf-8")
    reaction = REACTION.read_text(encoding="utf-8")
    auto = AUTO.read_text(encoding="utf-8")
    for token in (
        "action_info_represented_spell",
        "macroOpaqueRepresentedSpell",
        "macroRepresentedSpellID",
        "action_info_represented_spell_compat",
    ):
        assert token in resolver or token in reaction
    for token in (
        "interruptibility_unknown",
        "unit_api_confirmed",
        "unit_event_not_interruptible",
        "reactionCooldownGate",
        "interrupt_action_cooldown",
    ):
        assert token in auto
    # The P5 identity repair remains: target transport must not fall back to
    # grabbing a macro body solely by a duplicate macro name.
    assert "lookupMacroByName" not in resolver
