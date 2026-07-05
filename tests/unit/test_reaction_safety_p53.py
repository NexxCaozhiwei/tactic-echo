"""P5.6 safety gates for strict steel/unknown eligibility and interrupt cooldowns."""
from __future__ import annotations

import pytest

import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
AUTO = ADDON / "Tactics" / "AutoReaction.lua"
OBSERVATION = ADDON / "Tactics" / "ReactionObservation.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "reaction_safety_p53.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skip(reason='P5.7 intentionally hard-pauses automatic interrupt; historical candidate-dispatch contract is inactive.')
def test_scalar_native_steel_suspicion_stays_unknown_and_never_authorizes_reaction() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        GetTime = function() return 1 end
        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true, compatibilityActiveCast = false,
            targetOrder = {{ "target" }}, targetEnabled = {{ target = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        local route = {{ bindingReady = true, safeForFutureAuto = true, binding = "F", bindingToken = 133,
            route = "target", routeKind = "direct", autoRouteMode = "direct_actionbar", actionSlot = 1,
            actionBarStateTrusted = true }}
        _G.TacticEcho.ReactionBindings = {{ GetSnapshot = function() return {{ interrupt = {{{{ role = "interrupt", spellID = 147362, routes = {{ target = route }} }}}} }} end }}
        local observation
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return observation end }}
        dofile({str(AUTO)!r})
        observation = {{ observedAt = 1, sources = {{ target = {{ exists = true, hostile = true, alive = true, cast = {{
            active = true, continuity = "live", castSerial = 1, spellID = 147362, startTimeMS = 100, endTimeMS = 3000,
            kind = "cast", nativeInterruptibilityEvidence = "native_scalar_true_unverified:notInterruptible",
        }} }} }} }}
        local result = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if result.kind ~= "none" or result.reason ~= "interruptibility_unknown" then
            error("scalar_steel_bypassed:" .. tostring(result.kind) .. ":" .. tostring(result.reason))
        end
        '''
    )
    run_texlua(script)


@pytest.mark.skip(reason='P5.7 intentionally hard-pauses automatic interrupt; historical candidate-dispatch contract is inactive.')
def test_exact_macro_action_cooldown_releases_normal_sequence_and_never_offers_reaction() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        GetTime = function() return 1 end
        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true, compatibilityActiveCast = false,
            targetOrder = {{ "target" }}, targetEnabled = {{ target = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        local collectorOptions = nil
        _G.TacticEcho.IconState = {{ CollectCooldownOnly = function(_, spellID, options)
            collectorOptions = options
            return {{ cooldownKnown = true, cooldownActive = true, cooldownOnGCD = false,
                cooldownGcdAlias = false, cooldownSource = "actionbar_api",
                cooldownDirectActionBarEvidence = true }}
        end }}
        local route = {{ bindingReady = true, safeForFutureAuto = true, binding = "`", bindingToken = 20,
            route = "target", routeKind = "macro", autoRouteMode = "explicit_route", actionSlot = 60,
            actionBarStateTrusted = false, macroName = "反射", macroManagedTarget = false }}
        _G.TacticEcho.ReactionBindings = {{ GetSnapshot = function() return {{ interrupt = {{{{ role = "interrupt", spellID = 147362, routes = {{ target = route }} }}}} }} end }}
        local observation
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return observation end }}
        dofile({str(AUTO)!r})
        local function setCast(tick)
            observation = {{ observedAt = tick, sources = {{ target = {{ exists = true, hostile = true, alive = true, cast = {{
                active = true, continuity = "live", castSerial = 1, spellID = 147362, startTimeMS = 100, endTimeMS = 3000,
                kind = "cast", directInterruptibilityKnown = true,
                interruptibilitySource = "unit_api", interruptibleKnown = true,
                interruptible = true, nativeInterruptibilityEvidence = "native_showShield_config_true",
            }} }} }} }}
        end
        setCast(1); local blocked = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if blocked.kind ~= "none" or blocked.reason ~= "interrupt_action_cooldown"
            or blocked.cooldownActive ~= true or blocked.cooldownActionSlot ~= 60 then
            error("cooldown_not_blocked:" .. tostring(blocked.kind) .. ":" .. tostring(blocked.reason))
        end
        if not collectorOptions or collectorOptions.actionSlot ~= 60 or collectorOptions.directActionSlot ~= true
            or collectorOptions.actionBarStateTrusted ~= false
            or collectorOptions.exactActionCooldownVeto ~= true then
            error("exact_macro_slot_not_used")
        end
        _G.TacticEcho.IconState.CollectCooldownOnly = function(_, spellID, options)
            return {{ cooldownKnown = true, cooldownActive = false, cooldownOnGCD = false,
                cooldownGcdAlias = false, cooldownSource = "actionbar_api_ready" }}
        end
        setCast(2); local ready = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if ready.kind ~= "candidate" or ready.reason ~= "confirmed_interrupt_candidate"
            or ready.confirmationReason ~= "unit_api_confirmed" then
            error("ready_interrupt_not_restored:" .. tostring(ready.kind) .. ":" .. tostring(ready.reason))
        end
        '''
    )
    run_texlua(script)


def test_observer_probes_named_or_atlased_shield_children_without_trusting_showshield() -> None:
    source = OBSERVATION.read_text(encoding="utf-8")
    for token in (
        "safeMethodList",
        "GetChildren",
        "GetRegions",
        "shieldIdentifier",
        "appendSemanticShieldWidgets",
        "native_showShield_config_true",
    ):
        assert token in source


@pytest.mark.skip(reason='P5.7 intentionally hard-pauses automatic interrupt; historical candidate-dispatch contract is inactive.')
def test_exact_legacy_target_fallback_requires_no_focus_preemption_and_opaque_mutation_stays_closed() -> None:
    """P5.3.1 restores only the explicit focus->target compatibility shape."""
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        GetTime = function() return 1 end
        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true, compatibilityActiveCast = false,
            targetOrder = {{ "target" }}, targetEnabled = {{ target = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        local route = {{ bindingReady = true, safeForFutureAuto = true, binding = "F", bindingToken = 133,
            route = "target", routeKind = "macro", autoRouteMode = "macro_managed_target", actionSlot = 60,
            macroManagedTarget = true, macroManagedTargetFallback = true,
            managedTargetRouteOrder = {{ "focus", "target" }} }}
        _G.TacticEcho.ReactionBindings = {{ GetSnapshot = function() return {{ interrupt = {{{{ role = "interrupt", spellID = 147362, routes = {{ target = route }} }}}} }} end }}
        local target = {{ exists = true, hostile = true, alive = true, cast = {{ active = true, continuity = "live",
            directInterruptibilityKnown = true, interruptible = true, castSerial = 1, spellID = 147362,
            startTimeMS = 100, endTimeMS = 3000, kind = "cast" }} }}
        local absent = {{ exists = false, hostile = false, alive = false, cast = {{ active = false }} }}
        local focus = absent
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return {{ observedAt = 1, sources = {{ target = target, focus = focus, mouseover = absent }} }} end }}
        dofile({str(AUTO)!r})
        local restored = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if restored.kind ~= "candidate" or restored.reason ~= "confirmed_interrupt_candidate" then
            error("legacy_target_fallback_not_restored:" .. tostring(restored.kind) .. ":" .. tostring(restored.reason))
        end

        focus = {{ exists = true, hostile = true, alive = true, cast = {{ active = false }} }}
        local preempted = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if preempted.kind ~= "none" or preempted.reason ~= "macro_managed_target_target_preempted_by_focus" then
            error("focus_preemption_not_blocked:" .. tostring(preempted.kind) .. ":" .. tostring(preempted.reason))
        end

        focus = absent
        route.macroManagedTargetFallback = false
        route.managedTargetRouteOrder = {{}}
        local opaque = _G.TacticEcho.AutoReaction:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if opaque.kind ~= "none" or opaque.reason ~= "macro_managed_target_target_unverifiable" then
            error("opaque_mutation_target_bypassed:" .. tostring(opaque.kind) .. ":" .. tostring(opaque.reason))
        end
        '''
    )
    run_texlua(script)
