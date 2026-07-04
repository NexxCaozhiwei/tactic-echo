"""1.0.42 P4.5: guarded support for one strict interrupt priority macro.

The macro itself remains Blizzard-owned.  These checks prove that the parser
recognizes only the exact mouseover -> focus -> target cascade and that P4
refuses a source whenever an earlier macro branch would capture the key.
"""
from __future__ import annotations

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
        test_file = Path(tmp) / "reaction_priority_macro.lua"
        test_file.write_text(script, encoding="utf-8")
        result = subprocess.run([texlua, str(test_file)], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr


def test_priority_macro_contract_preserves_single_transport_and_no_macro_rewrite() -> None:
    macro = MACRO.read_text(encoding="utf-8")
    reaction = REACTION.read_text(encoding="utf-8")
    auto = AUTO.read_text(encoding="utf-8")

    for token in (
        "macro_priority_chain_auto",
        "macro_conditional_chain_opaque",
        "strictPriorityRouteChain",
        'PRIORITY_ROUTE_ORDER = { "mouseover", "focus", "target" }',
        "conditionBlocks",
    ):
        assert token in macro
    for token in ("macroPriorityChain", "priorityRouteOrder", "macroPriorityChainAuto"):
        assert token in reaction
    for token in (
        "priorityMacroRouteAllowed",
        "macro_priority_preempted_by_",
        "macro_priority_chain_metadata_invalid",
        "macroBranchUnitEligible",
    ):
        assert token in auto

    for source in (macro, reaction, auto):
        for forbidden in ("SetBinding", "SaveBindings", "CreateMacro", "EditMacro", "SendInput(", "TE.SignalEncoder"):
            assert forbidden not in source


def test_canonical_priority_macro_is_recognized_but_partial_or_modified_cascades_stay_manual() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        dofile({str(MACRO)!r})
        local M = _G.TacticEcho.MacroSemantics

        local canonical = [[#showtooltip 迎头痛击
        /stopcasting
        /cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 迎头痛击]]
        local detail = M:DescribeSpellRoutes(M:Analyze(canonical), 106839, "迎头痛击")
        if detail.reason ~= "macro_priority_chain_auto"
            or detail.autoRouteMode ~= "macro_priority_chain"
            or detail.macroPriorityChainAuto ~= true
            or table.concat(detail.routes, ",") ~= "mouseover,focus,target"
            or table.concat(detail.priorityRouteOrder, ",") ~= "mouseover,focus,target" then
            error("canonical_not_recognized")
        end

        local partial = [[/cast [@mouseover,harm,nodead][@focus,harm,nodead] 迎头痛击]]
        local partialDetail = M:DescribeSpellRoutes(M:Analyze(partial), 106839, "迎头痛击")
        if partialDetail.reason ~= "macro_conditional_chain_opaque"
            or partialDetail.autoRouteMode ~= nil
            or partialDetail.singleRoute == true then
            error("partial_cascade_promoted")
        end

        local modified = [[/cast [@mouseover,harm,nodead][@focus,harm,nodead][combat,harm,nodead] 迎头痛击]]
        local modifiedDetail = M:DescribeSpellRoutes(M:Analyze(modified), 106839, "迎头痛击")
        if modifiedDetail.reason ~= "macro_conditional_chain_opaque"
            or modifiedDetail.macroPriorityChainAuto == true then
            error("modified_cascade_promoted")
        end
        '''
    )
    run_texlua(script)


def test_reaction_binding_registry_marks_all_canonical_routes_and_p4_fails_closed_on_preemption() -> None:
    script = textwrap.dedent(
        f'''\
        _G.TacticEcho = {{}}
        TacticEchoDB = {{}}
        GetTime = function() return 1 end
        dofile({str(MACRO)!r})
        local M = _G.TacticEcho.MacroSemantics
        local body = [[#showtooltip 迎头痛击
        /stopcasting
        /cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 迎头痛击]]

        C_Spell = {{ GetSpellInfo = function(spellID) return {{ name = "迎头痛击", iconID = 0 }} end }}
        local tactics = {{ autoReaction = {{ interrupt = {{
            enabled = true,
            targetOrder = {{ "focus", "target", "mouseover" }},
            targetEnabled = {{ focus = true, target = true, mouseover = true }},
        }} }} }}
        _G.TacticEcho.Config = {{ Normalize = {{ All = function() return {{}}, tactics end }} }}
        _G.TacticEcho.Context = {{ GetPlayer = function() return {{ class = "DRUID", specIndex = 1 }} end }}
        _G.TacticEcho.AbilityProfiles = {{ GetInterrupts = function() return {{ 106839 }} end }}
        _G.TacticEcho.ActionBarBindingResolver = {{
            GetButtonCache = function() return {{ generation = 1 }} end,
            ResolveSpell = function(_, spellID)
                return {{
                    status = "Ready", reason = "resolved", cacheGeneration = 1,
                    candidates = {{{{
                        source = "macro", rawBinding = "CTRL-1",
                        parsed = {{ binding = "CTRL-1", token = 133 }},
                        actionSlot = 60, buttonName = "MultiBarBottomRightButton5",
                        macroName = "interrupt_priority", macroSemantics = M:Analyze(body),
                    }}}},
                }}
            end,
        }}
        dofile({str(REACTION)!r})
        local mapped = _G.TacticEcho.ReactionBindings:GetSnapshot(true).interrupt[1]
        if mapped.status ~= "ready" or mapped.macroRouteReason ~= "macro_priority_chain_auto"
            or mapped.macroPriorityChainAuto ~= true then
            error("priority_mapping_not_ready")
        end
        for _, routeName in ipairs({{ "mouseover", "focus", "target" }}) do
            local route = mapped.routes[routeName]
            if not route or route.safeForFutureAuto ~= true
                or route.macroPriorityChain ~= true
                or table.concat(route.priorityRouteOrder, ",") ~= "mouseover,focus,target" then
                error("route_missing:" .. routeName)
            end
        end

        local currentObservation
        _G.TacticEcho.ReactionObservation = {{ Sample = function() return currentObservation end }}
        _G.TacticEcho.ReactionBindings.GetSnapshot = function() return {{ interrupt = {{ mapped }} }} end
        dofile({str(AUTO)!r})
        local AR = _G.TacticEcho.AutoReaction

        local function unit(active, serial)
            return {{
                exists = true, hostile = true, alive = true,
                cast = {{
                    active = active == true, continuity = "live", directInterruptibilityKnown = true,
                    interruptible = true, castSerial = serial or 1, spellID = 12345,
                    startTimeMS = 100, endTimeMS = 3000, kind = "cast",
                }},
            }}
        end
        local function absent()
            return {{ exists = false, hostile = false, alive = false, cast = {{ active = false }} }}
        end

        -- A focus cast must not use the integrated macro while a live hostile
        -- mouseover exists: Blizzard would take the first macro branch instead.
        currentObservation = {{ observedAt = 1, sources = {{
            mouseover = unit(false, 1), focus = unit(true, 2), target = absent(),
        }} }}
        local blocked = AR:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if blocked.kind ~= "none" or blocked.reason ~= "macro_priority_preempted_by_mouseover" then
            error("focus_preemption_not_blocked:" .. tostring(blocked.kind) .. ":" .. tostring(blocked.reason))
        end

        -- Once mouseover is no longer a matching hostile unit, focus is the
        -- actual macro branch and can be delivered through the existing route.
        currentObservation = {{ observedAt = 2, sources = {{
            mouseover = absent(), focus = unit(true, 3), target = absent(),
        }} }}
        local focusCandidate = AR:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if focusCandidate.kind ~= "candidate" or focusCandidate.source ~= "focus"
            or focusCandidate.macroPriorityChain ~= true
            or focusCandidate.bindingInfo.bindingToken ~= 133 then
            error("focus_candidate_missing")
        end

        -- Target becomes eligible only when both macro-priority sources are
        -- absent.  This avoids falsely claiming that the macro can inspect casts.
        tactics.autoReaction.interrupt.targetOrder = {{ "target", "focus", "mouseover" }}
        currentObservation = {{ observedAt = 3, sources = {{
            mouseover = absent(), focus = absent(), target = unit(true, 4),
        }} }}
        local targetCandidate = AR:Evaluate({{ inCombat = true, intentState = "armed", effectiveState = "armed" }})
        if targetCandidate.kind ~= "candidate" or targetCandidate.source ~= "target"
            or targetCandidate.macroPriorityChain ~= true then
            error("target_candidate_missing")
        end
        '''
    )
    run_texlua(script)
