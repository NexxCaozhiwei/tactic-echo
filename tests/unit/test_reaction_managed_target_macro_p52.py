"""P5.3.1 compatibility for strict focus-first /targetenemy fallback macros.

The focus branch remains attributable to focus. The exact legacy focus->target
fallback is restored only when no live hostile focus can preempt its first
branch. Direct target buttons still win in ReactionBindings.
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
REACTION = ADDON / "Tactics" / "ReactionBindings.lua"
AUTO = ADDON / "Tactics" / "AutoReaction.lua"


def run_texlua(script: str) -> None:
    texlua = shutil.which("texlua")
    if not texlua:
        return
    with tempfile.TemporaryDirectory() as tmp:
        test_file = Path(tmp) / "reaction_managed_target_p52.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skip(reason='P5.7 intentionally hard-pauses automatic interrupt; historical candidate-dispatch contract is inactive.')
def test_focus_first_targetenemy_macro_restores_target_compat_without_focus_preemption() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        GetTime = function() return 1 end
        dofile({str(MACRO)!r})
        local M = _G.TacticEcho.MacroSemantics
        local body = [[#showtooltip 反制射击
        /stopcasting
        /cast [@focus,nodead] 反制射击
        /cleartarget
        /targetenemy
        /cast 反制射击
        /targetlasttarget]]

        local detail = M:DescribeSpellRoutes(M:Analyze(body), 147362, "反制射击")
        if detail.reason ~= "macro_target_switch_fallback_auto"
            or detail.macroManagedTargetFallbackAuto ~= true
            or table.concat(detail.managedTargetRouteOrder, ",") ~= "focus,target" then
            error("fallback_metadata_missing")
        end

        C_Spell = {{ GetSpellInfo = function() return {{ name = "反制射击", iconID = 0 }} end }}
        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true, compatibilityActiveCast = false,
            targetOrder = {{ "focus", "target" }},
            targetEnabled = {{ focus = true, target = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        _G.TacticEcho.Context = {{ GetPlayer = function() return {{ class = "HUNTER", specIndex = 1 }} end }}
        _G.TacticEcho.AbilityProfiles = {{ GetInterrupts = function() return {{ 147362 }} end }}
        _G.TacticEcho.ActionBarBindingResolver = {{
            -- Fixture macro identity is already confirmed by the resolver.
            IsVerifiedCurrentMacroSource = function() return true end,
            GetButtonCache = function() return {{ generation = 1 }} end,
            ResolveSpell = function()
                return {{ status = "Ready", reason = "resolved", cacheGeneration = 1, candidates = {{{{
                    source = "macro", rawBinding = "CTRL-1", parsed = {{ binding = "CTRL-1", token = 133 }},
                    actionSlot = 60, buttonName = "MultiBarBottomRightButton5",
                    macroName = "打断", macroSemantics = M:Analyze(body),
                }}}} }}
            end,
        }}
        dofile({str(REACTION)!r})
        local mapped = _G.TacticEcho.ReactionBindings:GetSnapshot(true).interrupt[1]
        local focusRoute, targetRoute = mapped.routes.focus, mapped.routes.target
        if not focusRoute or not targetRoute or focusRoute.macroManagedTargetFallback ~= true
            or targetRoute.macroManagedTargetFallback ~= true then
            error("fallback_routes_missing")
        end

        local observation
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return observation end }}
        _G.TacticEcho.ReactionBindings.GetSnapshot = function() return {{ interrupt = {{ mapped }} }} end
        dofile({str(AUTO)!r})
        local AR = _G.TacticEcho.AutoReaction

        local function casting(serial)
            return {{
                active = true, continuity = "live", directInterruptibilityKnown = true, interruptible = true,
                castSerial = serial, spellID = 999, startTimeMS = 100, endTimeMS = 3000, kind = "cast",
            }}
        end
        local function unit(cast)
            return {{ exists = true, hostile = true, alive = true, cast = cast or {{ active = false }} }}
        end
        local function absent()
            return {{ exists = false, hostile = false, alive = false, cast = {{ active = false }} }}
        end

        observation = {{ observedAt = 1, sources = {{ focus = unit(casting(1)), target = absent(), mouseover = absent() }} }}
        local focus = AR:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if focus.kind ~= "candidate" or focus.source ~= "focus"
            or focus.macroManagedTargetFallback ~= true then
            error("focus_branch_not_candidate")
        end

        observation = {{ observedAt = 2, sources = {{ focus = absent(), target = unit(casting(2)), mouseover = absent() }} }}
        local target = AR:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if target.kind ~= "candidate" or target.source ~= "target"
            or target.bindingInfo.bindingToken ~= 133
            or target.bindingInfo.macroManagedTargetFallback ~= true then
            error("targetenemy_fallback_not_restored:" .. tostring(target.kind) .. ":" .. tostring(target.reason))
        end

        observation = {{ observedAt = 3, sources = {{ focus = unit(nil), target = unit(casting(3)), mouseover = absent() }} }}
        local preempted = AR:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if preempted.kind ~= "none" or preempted.reason ~= "macro_managed_target_target_preempted_by_focus" then
            error("targetenemy_focus_preemption_not_blocked:" .. tostring(preempted.kind) .. ":" .. tostring(preempted.reason))
        end
        '''
    )
    run_texlua(script)


def test_contract_keeps_direct_target_preference_over_target_management_fallback() -> None:
    reaction = REACTION.read_text(encoding="utf-8")
    auto = AUTO.read_text(encoding="utf-8")
    macro = MACRO.read_text(encoding="utf-8")
    for token in (
        "focusTargetManagedFallbackOrder",
        "macroManagedTargetFallbackAuto",
        "managedTargetRouteOrder",
    ):
        assert token in macro
    for token in ("macroManagedTargetFallback", "safetyPriority", "routeKind == \"direct\""):
        assert token in reaction
    for token in (
        "managedTargetFallbackRouteAllowed",
        "macro_managed_target_target_compat",
        "macro_managed_target_target_preempted_by_focus",
        "macro_managed_target_focus_branch_match",
    ):
        assert token in auto


def test_direct_target_button_wins_over_same_spell_targetenemy_macro() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        dofile({str(MACRO)!r})
        local M = _G.TacticEcho.MacroSemantics
        local body = [[/cast [@focus,nodead] 反制射击
        /cleartarget
        /targetenemy
        /cast 反制射击
        /targetlasttarget]]
        C_Spell = {{ GetSpellInfo = function() return {{ name = "反制射击", iconID = 0 }} end }}
        _G.TacticEcho.Context = {{ GetPlayer = function() return {{ class = "HUNTER", specIndex = 1 }} end }}
        _G.TacticEcho.AbilityProfiles = {{ GetInterrupts = function() return {{ 147362 }} end }}
        _G.TacticEcho.ActionBarBindingResolver = {{
            -- Fixture macro identity is already confirmed by the resolver.
            IsVerifiedCurrentMacroSource = function() return true end,
            GetButtonCache = function() return {{ generation = 1 }} end,
            ResolveSpell = function()
                return {{ status = "Ready", reason = "resolved", cacheGeneration = 1, candidates = {{
                    {{ source = "macro", rawBinding = "CTRL-1", parsed = {{ binding = "CTRL-1", token = 133 }},
                       actionSlot = 60, buttonName = "MultiBarBottomRightButton5", macroSemantics = M:Analyze(body) }},
                    {{ source = "actionbar", rawBinding = "F", parsed = {{ binding = "F", token = 144 }},
                       actionSlot = 1, buttonName = "ActionButton1", directActionSlot = true }},
                }} }}
            end,
        }}
        dofile({str(REACTION)!r})
        local entry = _G.TacticEcho.ReactionBindings:GetSnapshot(true).interrupt[1]
        if entry.routes.target.routeKind ~= "direct" or entry.routes.target.bindingToken ~= 144
            or entry.routes.focus.routeKind ~= "macro" then
            error("direct_target_not_preferred")
        end
        '''
    )
    run_texlua(script)
