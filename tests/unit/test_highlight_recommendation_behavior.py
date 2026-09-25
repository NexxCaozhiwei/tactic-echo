"""Runtime coverage for highlighted recommendation selection and arbitration."""
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
lupa = pytest.importorskip("lupa", reason="Lupa is needed for AddOn Lua behavior tests")
LuaRuntime = lupa.LuaRuntime


def test_highlight_selection_is_opt_in_ordered_and_readiness_gated():
    lua = LuaRuntime(unpack_returned_tuples=True)
    module = (ROOT / "addon" / "!TacticEcho" / "Tactics" / "HighlightRecommendation.lua").as_posix()
    lua.execute(r'''
        _G.overlays = { [101] = true, [202] = true }
        _G.cooldowns = {
            [101] = { cooldownKnown = true, cooldownActive = false },
            [202] = { cooldownKnown = true, cooldownActive = false },
        }
        _G.usability = { [101] = { true, false }, [202] = { true, false } }
        _G.issecretvalue = function(value) return value == "secret" end
        _G.C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return overlays[id] end }
        local te = { Context = {}, BurstProfiles = {}, ActionBarBindingResolver = {}, RuntimeSnapshot = {}, GCDGate = {} }
        _G.TacticEcho = te
        TacticEchoDB = { settings = { highlightRecommendationEnabled = false }, tactics = {} }
        function te.Context:GetPlayer() return { class = "MAGE", specIndex = 1 } end
        function te.BurstProfiles:SpecKey(class, spec) return class .. "_" .. spec end
        local entries = {
            { source = "spell", spellID = 101, visualOrder = 2 },
            { source = "spell", spellID = 202, visualOrder = 1 },
        }
        function te.ActionBarBindingResolver:GetButtonCache() return { entries = entries } end
        function te.ActionBarBindingResolver:ResolveSpell(id)
            return { status = "Ready", bindingToken = id, source = "spell" }
        end
        function te.RuntimeSnapshot:ResolveSpell(_, id)
            return te.ActionBarBindingResolver:ResolveSpell(id)
        end
        function te.RuntimeSnapshot:CollectSpellCooldown(_, id) return cooldowns[id] end
        function te.RuntimeSnapshot:GetSpellUsability(_, id)
            local state = usability[id]
            if not state then return nil, nil end
            return state[1], state[2]
        end
        function te.GCDGate:BeginCycle() return {} end
        function te.GCDGate:Classify() return "READY_NOW" end
    ''')
    lua.execute(f'dofile([[{module}]])')
    results = lua.execute(r'''
        local highlight = TacticEcho.HighlightRecommendation
        local choice, audit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local disabled = choice == nil and audit.reason == "highlight_disabled"
        highlight:SetEnabled(true)
        choice, audit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local first = choice and choice.spellID
        overlays[101], overlays[202] = false, false
        local noOverlay, noOverlayAudit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local falseIsKnown = noOverlay == nil and noOverlayAudit.reason == "highlight_none_ready"
            and noOverlayAudit.unknownCount == 0
        overlays[101], overlays[202] = true, true
        usability[202] = { false, true }
        local resourceFallback, resourceAudit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local nextHighlight = resourceFallback and resourceFallback.spellID == 101
            and resourceAudit.resourceBlockedCount == 1
        usability[101] = { false, true }
        local noResourceChoice, noResourceAudit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local officialFallback = noResourceChoice == nil
            and noResourceAudit.reason == "highlight_insufficient_resource"
            and noResourceAudit.resourceBlockedCount == 2
        usability[101], usability[202] = { false, false }, { false, false }
        local unusableChoice, unusableAudit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local genericFallback = unusableChoice == nil and unusableAudit.reason == "highlight_unusable"
            and unusableAudit.unusableCount == 2
        usability[101], usability[202] = {}, {}
        local unknownChoice, unknownAudit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local unknownFallback = unknownChoice == nil and unknownAudit.reason == "highlight_usability_unknown"
            and unknownAudit.usabilityUnknownCount == 2
        usability[101], usability[202] = { true, false }, { true, false }
        highlight:SetSpellEnabled(202, false)
        choice = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        local afterDisable = choice and choice.spellID
        cooldowns[101] = { cooldownKnown = true, cooldownActive = true, cooldownOnGCD = false }
        choice, audit = highlight:Evaluate(TacticEcho.Context:GetPlayer(), {}, {})
        return disabled, first, falseIsKnown, nextHighlight, officialFallback,
            genericFallback, unknownFallback,
            afterDisable, choice == nil, audit.reason,
            highlight:IsSpellEnabled(202), TacticEchoDB.tactics.highlightRecommendationProfiles.MAGE_1 ~= nil
    ''')
    assert results == (True, 202, True, True, True, True, True, 101, True,
                       "highlight_none_ready", False, True)


def test_skill_toggle_requires_a_resolved_specialization_profile():
    lua = LuaRuntime(unpack_returned_tuples=True)
    module = (ROOT / "addon" / "!TacticEcho" / "Tactics" / "HighlightRecommendation.lua").as_posix()
    lua.execute(r'''
        local te = { Context = {}, BurstProfiles = {} }
        _G.TacticEcho = te
        function te.Context:GetPlayer() return { class = "MAGE" } end
        function te.BurstProfiles:SpecKey(class, spec) return spec and (class .. "_" .. spec) or nil end
        TacticEchoDB = { tactics = { highlightRecommendationProfiles = {} } }
    ''')
    lua.execute(f'dofile([[{module}]])')
    result = lua.execute(r'''
        local ok, reason = TacticEcho.HighlightRecommendation:SetSpellEnabled(123, false)
        return ok, reason, TacticEcho.HighlightRecommendation:IsSpellEnabled(123)
    ''')
    assert result == (False, "specialization_unavailable", True)


def test_highlight_does_not_trigger_special_mode_and_auto_injection_keeps_priority():
    lua = LuaRuntime(unpack_returned_tuples=True)
    module = (ROOT / "addon" / "!TacticEcho" / "Signal" / "SignalFrame.lua").as_posix()
    lua.execute(r'''
        _G.GetTime = function() return 10 end
        _G.CreateFrame = function()
            return setmetatable({ CreateTexture = CreateFrame }, { __index = function() return function() end end })
        end
        local te = {
            Context = {}, RecommendationAdapter = {}, ActionRegistry = {},
            ActionBarBindingResolver = {}, RuntimeSnapshot = {}, ManualActionPriority = {},
        }
        _G.TacticEcho = te
        function te:RegisterEventSafe() end
        function te:RegisterEventsSafe() end
        function te.Context:GetPlayer() return { inCombat = true, class = "MAGE", specIndex = 1 } end
        function te.Context:GetRevision() return 1 end
        function te.RecommendationAdapter:ReadOfficial() return { spellID = 100 } end
        function te.ActionRegistry:ResolveRecommendation() return { actionCode = 1, actionId = 1 } end
        local binding = { status = "Ready", bindingToken = 7, source = "spell" }
        function te.ActionBarBindingResolver:BeginResolveCycle() return {} end
        function te.ActionBarBindingResolver:ResolveSpell() return binding end
        function te.RuntimeSnapshot:Begin() return {} end
        function te.ManualActionPriority:GetActive() return { active = false } end
        _G.burst = { kind = "none", dispatchOrigin = "official" }
        te.AutoBurst = { Evaluate = function() return burst end }
        _G.specialCalls = 0
        te.SpecialMode = {
            Select = function() specialCalls = specialCalls + 1; return { spellID = 200 } end,
            CanDispatch = function() return true end,
        }
        te.HighlightRecommendation = {
            Evaluate = function()
                return { spellID = 300, bindingInfo = binding, reason = "highlight_dispatch" },
                    { reason = "highlight_selected" }
            end,
        }
        TacticEchoDB = { settings = { specialModeEnabled = true, sessionPolicy = "manual_keep" }, tactics = {} }
    ''')
    lua.execute(f'dofile([[{module}]])')
    results = lua.execute(r'''
        local signal = TacticEcho.SignalFrame
        signal.Refresh = function() end
        signal:SetState("armed")
        -- Production AutoBurst returns kind="none" when it has no candidate.
        -- Highlight must still be allowed to select the ordinary action.
        local highlighted = signal:BuildBusinessMessage("test", 100, "ok")
        local specialAfterHighlight = specialCalls
        TacticEcho.HighlightRecommendation.Evaluate = function()
            return nil, { reason = "highlight_insufficient_resource", resourceBlockedCount = 1 }
        end
        local official = signal:BuildBusinessMessage("test", 100, "ok")
        local specialAfterOfficial = specialCalls
        burst = { kind = "candidate", dispatchSpellID = 400,
            bindingInfo = { status = "Ready", bindingToken = 9, source = "spell" } }
        TacticEcho.HighlightRecommendation.Evaluate = function() error("must not run while AutoInjection owns") end
        local injected = signal:BuildBusinessMessage("test", 100, "ok")
        return highlighted.dispatchSpellID, highlighted.recommendationSource, specialAfterHighlight,
            official.dispatchSpellID, official.recommendationSource, specialAfterOfficial,
            injected.dispatchSpellID, injected.recommendationSource, specialCalls
    ''')
    assert results == (300, "highlight", 0, 200, "official", 1, 400, "auto_injection", 1)
