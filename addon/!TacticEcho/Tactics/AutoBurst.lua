-- Controlled AutoBurst dispatcher candidate builder.
--
-- Dispatchable Burst candidates deliberately use the same fresh-frame / global
-- TEK rate-limit behavior as ordinary official recommendations. Every fresh
-- dispatchable frame receives a new TEAP sequence; confirmation gates plan
-- progression, not physical re-offer frequency.
--
-- This module is intentionally not a second input path.  It can only return a
-- single, already-resolved action-bar candidate to SignalFrame; SignalFrame
-- still owns BindingToken → TEAP and TEK remains the only Windows input path.
--
-- AutoBurst builds one explicit, specialization-scoped ordered sequence. The
-- official recommendation remains the sole window anchor; optional steps may
-- be up to three profile injection skills plus explicit 13/14 trinket slots.
-- Each step still resolves through the existing visible default action bar and
-- the ordinary TEAP/TEK gate. Potions and arbitrary inventory remain excluded.
local TE = _G.TacticEcho

local AutoBurst = {
    schema = 2,
    nextPlanId = 1,
    plan = nil,
    requireWindowDeparture = false,
    lockedWindowSpellID = nil,
    -- A completed pre-combat bridge still owns its official window until it
    -- departs.  This marker makes that terminal hold observable without
    -- reopening ordinary out-of-combat dispatch.
    preCombatBridgeDepartureLock = false,
    -- A world/zone transition invalidates any implicit out-of-combat opener
    -- authority.  The normal in-combat path is unaffected; this fence only
    -- blocks the narrow pre-combat bridge until a real combat epoch begins or
    -- the user explicitly presses the existing Run control again.
    preCombatBridgeWorldFence = false,
    preCombatBridgeAuthorizationRequiresHandoff = false,
    worldTransitionEpoch = 0,
    lastWorldTransition = nil,
    lastOfficialSpellID = nil,
    lastIntentState = nil,
    armedEpoch = 0,
    firstHealthyFramePending = false,
    windowGeneration = 0,
    consumedWindowGeneration = 0,
    activePlanGeneration = nil,
    departureLockGeneration = nil,
    currentWindowSpellID = nil,
    eventPauseUntil = 0,
    eventPauseReason = nil,
    deadPaused = false,
    vehiclePaused = false,
    -- Official-window edges are scoped to the current combat epoch.  A
    -- recommendation can already be visible before combat begins; retaining
    -- that out-of-combat spell ID would incorrectly suppress the first valid
    -- window of the next encounter.
    combatEpoch = 0,
    lastDecision = nil,
    lastDecisionSignature = nil,
    lastDecisionLoggedAt = 0,
    lastFault = nil,
    -- Last direct player spell-success event observed while a Phase-1 plan was
    -- active. This scalar audit record never decides whether a plan starts.
    lastSpellcastSuccess = nil,
    lastConfirmationSource = nil,
    lastAbortReason = nil,
    lastWindowRejectReason = nil,
    -- Last logical candidate offered to SignalFrame. It contains no macro body,
    -- raw cooldown value or player-identifying data; it only makes the next
    -- diagnostic bundle show whether Burst ever reached TEAP.
    lastCandidate = nil,
    -- A compact scalar-only observation is exported with /temapping so a test
    -- can distinguish "injection was skipped as GCD" from "binding/token was
    -- missing" without persisting macro bodies or resolver internals.
    lastStepObservation = nil,
    -- Re-arming after a runtime pause starts a new observation epoch only when
    -- no active plan or departure lock owns the current official window. This
    -- closes the stale-same-window edge case without permitting a consumed
    -- window to be reacquired midway through its departure lock.
    lastArmedRebase = nil,
    -- A pre-window capture owns a configured front-injection window before
    -- its fully bound plan is available. It is an observation-only handoff
    -- barrier: the official window token must never leak through while the
    -- AddOn is deciding or rebuilding the Burst sequence.
    preWindowCapture = nil,
    nextPreWindowCaptureId = 1,
    -- Diagnostic-only result of the latest build-time optional-step eligibility scan.
    -- `lastInjectionPreflight` remains as a compact compatibility alias for
    -- existing mapping exports; the richer record is sequence-scoped.
    lastInjectionPreflight = nil,
    lastSequencePreflight = nil,
}
TE.AutoBurst = AutoBurst

local MAX_LOGS = 180
local MAX_PRIORITY_LOGS = 64
-- These intervals are diagnostic milestones only. They never terminate a
-- healthy AutoBurst step. A valid, bound and latched action continues to
-- re-offer through the normal TEK global rate limiter until exact success, a
-- rule-approved own-CD skip, or a hard safety invalidation.
local STEP_CONFIRM_SECONDS = 2.20
-- First recovery milestone for a pre-window trinket. After this point the plan
-- stays in persistent recovery and continues to watch the exact slot+ItemID
-- cooldown for delayed or manual use; this is not a terminal recovery deadline.
local INVENTORY_RECOVERY_SECONDS = 3.50
-- Revalidation heartbeat. UNKNOWN/conflicting API samples are held and re-read
-- indefinitely while the official window remains active; this value only limits
-- diagnostic event frequency.
local STEP_REVALIDATE_SECONDS = 2.20
-- A front/simple injection may be skipped only after two independently sampled
-- live API snapshots agree that the exact requested spell is on its own CD.
-- The delay deliberately forces the second sample onto a later SignalFrame tick
-- rather than accepting two reads from the same transient client response.
local PRE_INJECTION_COOLDOWN_CONFIRM_SAMPLES = 2
local PRE_INJECTION_COOLDOWN_CONFIRM_INTERVAL_SECONDS = 0.06
-- A paused -> armed pre-window handoff is a transport ownership transition, not
-- a gameplay/GCD delay. Require four *fresh TEAP observation frames* before
-- exposing the injection token. This is deliberately frame-counted rather than
-- timer/sleep based: SignalFrame owns the transport cadence and every hold
-- advances TEK's freshness barrier. Four frames cover the normal 50 ms reader
-- cadence plus a missed paint/read without creating a Burst-only input policy.
local PRE_WINDOW_HANDOFF_MIN_HOLD_FRAMES = 4
-- A logical Burst candidate stays visible until the specific step is confirmed,
-- rule-skipped for a verified own cooldown, its official window departs before
-- dispatch, or an explicit hard invalidation occurs. Fresh armed frames may
-- re-offer it; TEK's global limiter bounds physical input.
local DECISION_LOG_MIN_SECONDS = 0.35
local QUIET_DECISION_LOG_MIN_SECONDS = 15.00

local PRIORITY_LOG_EVENTS = {
    combat_epoch_started = true,
    precombat_burst_bridge_started = true,
    precombat_burst_bridge_combat_entered = true,
    world_transition_precombat_fenced = true,
    precombat_bridge_reauthorized = true,
    world_transition_fence_cleared_by_combat = true,
    armed_epoch_started = true,
    armed_window_observation_rebased = true,
    pre_window_capture_started = true,
    pre_window_capture_handoff_barrier = true,
    pre_window_capture_handoff_ready = true,
    pre_window_capture_revalidating = true,
    pre_window_capture_released = true,
    window_departed = true,
    plan_created = true,
    injection_preflight_selected = true,
    injection_preflight_no_eligible = true,
    sequence_preflight_selected = true,
    sequence_preflight_no_eligible = true,
    plan_released_injection_unavailable = true,
    plan_rejected = true,
    plan_gate_window_official_cooldown_conflict = true,
    window_official_cooldown_revalidate = true,
    window_official_cooldown_resolved = true,
    plan_aborted = true,
    hard_abort = true,
    step_revalidate_started = true,
    step_revalidate_persistent = true,
    step_confirmation_grace_elapsed = true,
    plan_released_window_departed_before_window_dispatch = true,
    window_skipped_own_cooldown = true,
    pre_injection_cooldown_sample = true,
    pre_injection_cooldown_rejected = true,
    pre_injection_cooldown_confirmed = true,
    injection_skipped = true,
    sequence_optional_step_skipped = true,
    step_dispatched = true,
    step_confirmed = true,
    window_queue_delivery_continues = true,
    gcd_locked_delivery_continues = true,
    inventory_recovery_started = true,
    inventory_recovery_completed = true,
    soft_pause_clock_extended = true,
    plan_completed = true,
    evaluate_fault = true,
}

local QUIET_DECISION_REASONS = {
    auto_run_not_armed = true,
    out_of_combat = true,
    world_transition_precombat_fenced = true,
    official_not_window = true,
    window_edge_missing = true,
    await_window_departure = true,
}

local function number(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local resolved = tonumber(value)
        if type(resolved) ~= "number" then return nil end
        local plain = resolved + 0
        if plain < -math.huge or plain > math.huge then return nil end
        return plain
    end)
    return ok and result or nil
end

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and (number(value) or 0) or 0
end

local function positiveSpellID(value)
    value = number(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function positiveItemID(value)
    value = number(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function inventorySlot(value)
    value = number(value)
    value = value and math.floor(value) or nil
    return (value == 13 or value == 14) and value or nil
end

local function stepKind(step)
    return type(step) == "table" and step.kind == "inventory" and "inventory" or "spell"
end

local function isWindowStep(step)
    return type(step) == "table" and (step.category == "window" or step.role == "window")
end

local function isOptionalStep(step)
    return type(step) == "table" and step.optional == true and not isWindowStep(step)
end

local function stepAuditID(step)
    if stepKind(step) == "inventory" then return positiveItemID(step and (step.expectedItemID or step.itemID)) end
    return positiveSpellID(step and step.spellID)
end

local function stepIdentity(step, bindingInfo)
    if stepKind(step) == "inventory" then
        local slot = inventorySlot(step and step.inventorySlot)
        local itemID = positiveItemID(step and step.expectedItemID)
            or positiveItemID(bindingInfo and (bindingInfo.itemID or bindingInfo.expectedItemID))
        if not slot or not itemID then return nil end
        return "inventory:" .. tostring(slot) .. ":item:" .. tostring(itemID)
    end
    local spellID = positiveSpellID(step and step.spellID)
    return spellID and ("spell:" .. tostring(spellID)) or nil
end

local function shallowCopy(value)
    local out = {}
    for key, item in pairs(type(value) == "table" and value or {}) do
        if type(item) ~= "table" then out[key] = item end
    end
    return out
end

local function ensureStore()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.autoBurst = type(TacticEchoDB.autoBurst) == "table" and TacticEchoDB.autoBurst or {}
    TacticEchoDB.autoBurst.events = type(TacticEchoDB.autoBurst.events) == "table" and TacticEchoDB.autoBurst.events or {}
    -- Keep lifecycle-critical observations in an independent scalar-only ring.
    -- Repeated idle decisions must not evict the exact plan/skip evidence needed
    -- for a field-test diagnostic export.
    TacticEchoDB.autoBurst.priorityEvents = type(TacticEchoDB.autoBurst.priorityEvents) == "table" and TacticEchoDB.autoBurst.priorityEvents or {}
    return TacticEchoDB.autoBurst
end

local function tactics()
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, value = TE.Config.Normalize:All()
        if type(value) == "table" then return value end
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    return TacticEchoDB.tactics
end

local function log(self, event, fields)
    local settings = tactics()
    if settings.autoBurstDebug ~= true and event == "phase" then return end
    local store = ensureStore()
    local record = {
        schema = 1,
        component = "AutoBurst",
        event = event,
        elapsed = now(),
        planId = self.plan and self.plan.id or (fields and fields.planId),
        ruleId = self.plan and self.plan.rule and self.plan.rule.id or (fields and fields.ruleId),
    }
    for key, value in pairs(fields or {}) do record[key] = value end
    store.lastEvent = record
    store.events[#store.events + 1] = record
    while #store.events > MAX_LOGS do table.remove(store.events, 1) end
    if PRIORITY_LOG_EVENTS[event] == true then
        store.priorityEvents[#store.priorityEvents + 1] = shallowCopy(record)
        while #store.priorityEvents > MAX_PRIORITY_LOGS do table.remove(store.priorityEvents, 1) end
    end
end

local function isInCombat(runtime)
    if type(runtime) == "table" and runtime.inCombat ~= nil then return runtime.inCombat == true end
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- The normal session policy remains authoritative for ordinary out-of-combat
-- recommendations.  A pre-combat bridge is a deliberately narrow exception:
-- it exists only while the player has explicitly armed TE, the runtime is
-- paused solely by the default out-of-combat policy, and the declared rule is
-- a configured front-injection window.  Manual hold, text input, cast locks,
-- death, vehicle and close-out-of-combat never qualify.
local function runtimeAllowsPreCombatBridge(runtime)
    if type(runtime) ~= "table" or runtime.intentState ~= "armed" then return false end
    local effective = runtime.effectiveState
    if effective == "armed" then return true end
    return effective == "paused" and runtime.runtimeReason == "out_of_combat_policy_pause"
end

local function hasPreCombatBridgeOwner(self)
    local plan = self and self.plan
    if type(plan) == "table" and plan.preCombatBridge == true then return true end
    local capture = self and self.preWindowCapture
    if type(capture) == "table" and capture.preCombatBridge == true then return true end
    return false
end

local function canStartPreCombatBridge(self, rule, officialSpellID, runtime)
    -- A zone/world transition keeps the visible session semantics intact, but
    -- revokes only the implicit pre-combat exception.  Without this fence an
    -- old armed intent can see a post-load official window and immediately
    -- dispatch trinkets/skills while the player is still out of combat.
    if self and self.preCombatBridgeWorldFence == true then return false end
    return runtimeAllowsPreCombatBridge(runtime)
        and type(rule) == "table"
        and rule.requiresPreWindowCapture == true
        and officialSpellID ~= nil
        and officialSpellID == rule.windowSpellID
end

local function isDead()
    return type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") == true
end

local function recordDecision(self, phase, reason, fields)
    fields = type(fields) == "table" and fields or {}
    local record = {
        schema = 1,
        component = "AutoBurst",
        phase = phase,
        reason = reason,
        elapsed = now(),
        planId = self.plan and self.plan.id or fields.planId,
        officialSpellID = positiveSpellID(fields.officialSpellID),
        windowSpellID = positiveSpellID(fields.windowSpellID),
        injectionSpellID = positiveSpellID(fields.injectionSpellID),
        ruleSource = fields.ruleSource,
        ruleId = self.plan and self.plan.rule and self.plan.rule.id or fields.ruleId,
        state = self.plan and self.plan.state or fields.state,
        armedEpoch = self.armedEpoch or 0,
        firstHealthyFramePending = self.firstHealthyFramePending == true,
        windowGeneration = self.windowGeneration or 0,
        consumedWindowGeneration = self.consumedWindowGeneration or 0,
        activePlanGeneration = self.activePlanGeneration,
        departureLockGeneration = self.departureLockGeneration,
    }
    self.lastDecision = record
    if phase == "armed" and reason then
        self.lastWindowRejectReason = tostring(reason)
    elseif phase == "plan_created" then
        self.lastWindowRejectReason = nil
    end
    local signature = table.concat({
        tostring(phase), tostring(reason), tostring(record.planId or 0),
        tostring(record.officialSpellID or 0), tostring(record.windowSpellID or 0),
        tostring(record.injectionSpellID or 0), tostring(record.ruleSource or ""),
        tostring(record.state or ""),
    }, ":")
    local t = record.elapsed or 0
    -- Idle/non-window status is useful as the current decision, but writing it
    -- every SignalFrame used to overwrite the causative plan/step events before
    -- a diagnostic was exported. Keep a long heartbeat only for these quiet
    -- reasons; lifecycle events retain the normal bounded cadence.
    local minInterval = QUIET_DECISION_REASONS[reason] == true
        and QUIET_DECISION_LOG_MIN_SECONDS or DECISION_LOG_MIN_SECONDS
    if signature ~= self.lastDecisionSignature or t - (self.lastDecisionLoggedAt or 0) >= minInterval then
        self.lastDecisionSignature = signature
        self.lastDecisionLoggedAt = t
        log(self, "decision", record)
    end
    return record
end

function AutoBurst:ReportFault(reason)
    self.lastFault = {
        schema = 1,
        component = "AutoBurst",
        reason = tostring(reason or "unknown"),
        elapsed = now(),
        planId = self.plan and self.plan.id or nil,
    }
    log(self, "evaluate_fault", { reason = self.lastFault.reason })
end

-- A cast event may report an override/replacement SpellID even though the
-- currently visible default action-bar slot was resolved from the declared
-- Phase-1 SpellID. Accept only the exact current step or the resolver-provided
-- requested/matched/equivalent IDs for that same waiting step; unrelated manual
-- casts remain unable to advance a plan.
local function spellcastMatchesCurrentStep(step, observedSpellID, bindingInfo)
    if stepKind(step) == "inventory" then return false, nil end
    observedSpellID = positiveSpellID(observedSpellID)
    if not observedSpellID then return false, nil end
    local expected = positiveSpellID(step and step.spellID)
    if expected and observedSpellID == expected then return true, "exact" end
    bindingInfo = type(bindingInfo) == "table" and bindingInfo or {}
    if observedSpellID == positiveSpellID(bindingInfo.requestedSpellID) then return true, "requested" end
    if observedSpellID == positiveSpellID(bindingInfo.matchedSpellID) then return true, "matched" end
    for _, equivalentSpellID in pairs(type(bindingInfo.equivalentSpellIDs) == "table" and bindingInfo.equivalentSpellIDs or {}) do
        if observedSpellID == positiveSpellID(equivalentSpellID) then return true, "equivalent" end
    end
    return false, nil
end

-- This is a confirmation-only event path. It does not influence trigger timing
-- and never reads Buffs, resources, targets or raw cooldown values. The event
-- can satisfy only the current Phase-1 step already waiting for confirmation.
function AutoBurst:RecordSpellcastSucceeded(spellID)
    spellID = positiveSpellID(spellID)
    if not spellID then return false end
    local t = now()

    local plan = self.plan
    if not (plan and plan.state == "WAIT_CONFIRM" and type(plan.wait) == "table") then return false end
    local step = plan.steps and plan.steps[plan.stepIndex] or nil
    local bindingInfo = plan.wait.offerSample and plan.wait.offerSample.bindingInfo or nil
    local matches, matchKind = spellcastMatchesCurrentStep(step, spellID, bindingInfo)
    if matches ~= true then return false end
    if t < (number(plan.wait.dispatchedAt) or 0) then return false end

    -- Persist only a matching current-step receipt, never unrelated manual
    -- casts. This keeps mapping export diagnostic-only and unambiguous.
    self.lastSpellcastSuccess = { spellID = spellID, elapsed = t, planId = plan.id, matchKind = matchKind }
    plan.wait.spellcastSucceededSpellID = spellID
    plan.wait.spellcastSucceededAt = t
    plan.wait.spellcastSucceededMatchKind = matchKind
    log(self, "step_spellcast_succeeded", {
        role = step.role,
        spellID = spellID,
        expectedSpellID = positiveSpellID(step and step.spellID),
        matchKind = matchKind,
        currentStep = plan.stepIndex,
        dispatchAttempt = plan.wait.dispatchAttempt,
    })
    return true
end

local function profileRule(context)
    local settings = tactics()
    local mode = settings.autoBurstMode == "focused" and "focused" or "simple"
    if not (TE.BurstProfiles and type(TE.BurstProfiles.GetAutoBurstSequence) == "function") then
        return nil, "burst_sequence_profiles_unavailable"
    end
    local sequence, profileKey, reason, profile = TE.BurstProfiles:GetAutoBurstSequence(context)
    if not sequence or not profile then return nil, reason or "burst_sequence_unavailable" end
    if profile.enabled == false then return nil, "burst_profile_disabled" end

    local windowSpellID = positiveSpellID(sequence.windowSpellID)
    if not windowSpellID then return nil, "burst_sequence_window_missing" end

    local steps, firstOptionalSpellID, optionalCount = {}, nil, 0
    for _, entry in ipairs(sequence.entries or {}) do
        if entry.enabled ~= false then
            local step
            if entry.category == "window" then
                step = {
                    key = "window", role = "window", category = "window", kind = "spell",
                    spellID = windowSpellID, optional = false,
                }
            elseif entry.category == "trinket" then
                local slot = inventorySlot(entry.inventorySlot)
                if slot then
                    step = {
                        key = entry.key, role = entry.role or ("trinket_" .. tostring(slot)), category = "trinket",
                        kind = "inventory", inventorySlot = slot, optional = true,
                        offGCDExplicit = entry.offGCDExplicit == true,
                    }
                end
            else
                local spellID = positiveSpellID(entry.spellID)
                if spellID then
                    step = {
                        key = entry.key, role = entry.role or "injection", category = "injection",
                        kind = "spell", spellID = spellID, optional = true,
                    }
                    firstOptionalSpellID = firstOptionalSpellID or spellID
                end
            end
            if step then
                steps[#steps + 1] = step
                if isOptionalStep(step) then optionalCount = optionalCount + 1 end
            end
        end
    end

    -- A window by itself is deliberately left to the ordinary official path.
    -- AutoBurst only claims it when at least one enabled optional action remains
    -- in the current specialization sequence.
    if optionalCount <= 0 then return nil, "burst_sequence_no_enabled_optional_steps" end
    local firstStep = steps[1]
    if not firstStep or (not isWindowStep(steps[1]) and not isOptionalStep(steps[1])) then
        return nil, "burst_sequence_invalid_steps"
    end
    local requiresPreWindowCapture = not isWindowStep(firstStep)
    local direction = requiresPreWindowCapture and "pre" or "window_first"
    return {
        id = tostring(profileKey) .. ":sequence:" .. tostring(sequence.signature or "default"),
        profileKey = profileKey,
        source = "profile_sequence",
        windowSpellID = windowSpellID,
        injectionSpellID = firstOptionalSpellID,
        injectionKind = "sequence",
        steps = steps,
        optionalStepCount = optionalCount,
        requiresPreWindowCapture = requiresPreWindowCapture,
        direction = direction,
        mode = mode,
        sequenceSignature = sequence.signature,
    }, nil
end

-- A macro remains the player's own visible action-bar button. Broad macro
-- support accepts a resolver-proven association (API or parsed body) without
-- TE attempting to evaluate a condition or execute a macro branch itself.
local function macroAllowed(bindingInfo)
    if not bindingInfo or bindingInfo.source ~= "macro" then return true, nil end
    if bindingInfo.macroAutoBurstEligible == true then return true, nil end
    local association = tostring(bindingInfo.macroAssociation or "")
    if association == "action_info_macro_spell" or association == "GetMacroSpell"
        or association == "GetMacroSpell(actionInfoId)" then
        return true, nil
    end
    local semantics = bindingInfo.macroSemantics
    if type(semantics) == "table" and semantics.broadReferenceEligible == true and association:find("macro_body_", 1, true) == 1 then
        return true, nil
    end
    return false, "macro_spell_not_associated"
end

local function resolveStepBinding(step)
    local resolver = TE.ActionBarBindingResolver
    if not resolver then return nil, "BLOCKED", "binding_resolver_unavailable" end
    local bindingInfo, reason
    if stepKind(step) == "inventory" then
        if type(resolver.ResolveInventorySlot) ~= "function" then
            return nil, "BLOCKED", "inventory_binding_resolver_unavailable"
        end
        local slot = inventorySlot(step.inventorySlot)
        if not slot then return nil, "BLOCKED", "inventory_slot_invalid" end
        local ok
        ok, bindingInfo, reason = pcall(resolver.ResolveInventorySlot, resolver, slot, step.expectedItemID)
        if not ok or type(bindingInfo) ~= "table" then return nil, "BLOCKED", "inventory_binding_resolver_failed" end
        if not positiveItemID(bindingInfo.itemID or bindingInfo.expectedItemID) then
            return bindingInfo, "BLOCKED", reason or "inventory_item_missing"
        end
    else
        if type(resolver.ResolveSpell) ~= "function" then
            return nil, "BLOCKED", "binding_resolver_unavailable"
        end
        local ok
        ok, bindingInfo, reason = pcall(resolver.ResolveSpell, resolver, step.spellID)
        if not ok or type(bindingInfo) ~= "table" then return nil, "BLOCKED", "binding_resolver_failed" end
    end
    local special = bindingInfo.specialActionBar
    if special and special.active == true then return bindingInfo, "PAUSED", special.reason or "special_actionbar" end
    if bindingInfo.status ~= "Ready" or (number(bindingInfo.bindingToken) or 0) <= 0 then
        return bindingInfo, "BLOCKED", reason or bindingInfo.reason or bindingInfo.status or "binding_not_ready"
    end
    local macroReady, macroReason = macroAllowed(bindingInfo)
    if not macroReady then return bindingInfo, "BLOCKED", macroReason or "macro_not_associated" end
    return bindingInfo, nil, nil
end

local function collectCooldownState(step, cycle, bindingInfo)
    if not TE.IconState then
        return nil, "cooldown_only_sampler_unavailable"
    end
    bindingInfo = type(bindingInfo) == "table" and bindingInfo or {}
    local options = {
        gcdSnapshot = type(cycle) == "table" and cycle.gcdSnapshot or nil,
        liveCooldown = true,
        actionSlot = bindingInfo.actionSlot or bindingInfo.slot,
        directActionSlot = bindingInfo.directActionSlot == true,
        actionBarStateTrusted = bindingInfo.actionBarStateTrusted == true,
        matchedSpellID = bindingInfo.matchedSpellID,
        requestedSpellID = bindingInfo.requestedSpellID,
        equivalentSpellIDs = bindingInfo.equivalentSpellIDs,
    }
    if stepKind(step) == "inventory" then
        if type(TE.IconState.CollectInventoryCooldownOnly) ~= "function" then
            return nil, "inventory_cooldown_sampler_unavailable"
        end
        local ok, state = pcall(TE.IconState.CollectInventoryCooldownOnly, TE.IconState,
            step.inventorySlot, step.expectedItemID or bindingInfo.itemID, options)
        if not ok then return nil, "inventory_cooldown_state_failed" end
        if type(state) ~= "table" then return nil, "inventory_cooldown_state_invalid" end
        return state, nil
    end
    if type(TE.IconState.CollectCooldownOnly) ~= "function" then
        return nil, "cooldown_only_sampler_unavailable"
    end
    local ok, state = pcall(TE.IconState.CollectCooldownOnly, TE.IconState, step.spellID, options)
    if not ok then return nil, "cooldown_only_state_failed" end
    if type(state) ~= "table" then return nil, "cooldown_only_state_invalid" end
    return state, nil
end

local function ownReadyState(iconState)
    if type(iconState) ~= "table" then return "UNKNOWN", "icon_state_missing" end
    local charges, maximum = number(iconState.charges), number(iconState.maxCharges)
    if maximum and maximum > 1 then
        if charges == nil then return "UNKNOWN", "charge_state_unknown" end
        if charges <= 0 then return "COOLDOWN", "no_available_charge" end
        return "OWN_READY", nil
    end

    -- Modern Retail can protect raw start/duration values while preserving
    -- public activity/GCD booleans. Protected numerics therefore do not by
    -- themselves mean UNKNOWN; the timing adapter provides only safe booleans.
    if iconState.cooldownKnown ~= true then
        -- Retail may expose isActive while hiding both the numeric cooldown and
        -- the isOnGCD provenance.  `active=true` alone cannot safely mean an
        -- own cooldown: it can be the shared GCD. Treat that case as UNKNOWN so
        -- a front plan holds/revalidates rather than skipping its injection.
        if iconState.cooldownPublicActiveKnown == true then
            if iconState.cooldownPublicActive == false then
                return "OWN_READY", "spell_ready_public"
            end
            if iconState.cooldownPublicActive == true then
                if iconState.cooldownPublicOnGCDKnown == true then
                    if iconState.cooldownPublicOnGCD == true then
                        return "OWN_READY", "spell_ready_public_on_gcd"
                    end
                    return "COOLDOWN", "spell_cooldown_active_public"
                end
                return "UNKNOWN", "cooldown_active_origin_unknown"
            end
        end
        return "UNKNOWN", iconState.cooldownUnknownReason or "cooldown_unknown"
    end
    if iconState.cooldownActive == true and iconState.cooldownOnGCD ~= true and iconState.cooldownGcdAlias ~= true then
        return "COOLDOWN", "spell_cooldown_active"
    end
    return "OWN_READY", nil
end

-- A COOLDOWN phase by itself is insufficient to skip a simple injection
-- (front or post). The evidence must come from a fresh spell API read for the
-- exact rule ActionRef,
-- be non-GCD, have a stable visible default-action-bar binding (direct skill
-- or resolver-associated user macro), and not be in post-cast tracker
-- confirmation. This function intentionally returns only
-- scalar diagnostics; it does not read usability, resources, targets or auras.
local function explicitOwnCooldownEvidence(step, sample)
    step = type(step) == "table" and step or {}
    sample = type(sample) == "table" and sample or {}
    local icon = type(sample.iconState) == "table" and sample.iconState or {}
    local binding = type(sample.bindingInfo) == "table" and sample.bindingInfo or {}
    if sample.phase ~= "COOLDOWN" then return false, "phase_not_cooldown" end
    local expectedIdentity = stepIdentity(step, binding)
    if not expectedIdentity then return false, "step_identity_invalid" end
    if icon.cooldownLiveRead ~= true then return false, "cooldown_not_live" end
    if icon.cooldownKnown ~= true then return false, "cooldown_not_confirmed" end
    if icon.cooldownActive ~= true then return false, "cooldown_not_active" end
    if icon.cooldownOnGCD == true or icon.cooldownGcdAlias == true then return false, "cooldown_is_gcd" end
    if icon.cooldownConfirmationPending == true then return false, "cooldown_confirmation_pending" end
    if icon.cooldownIdentityKey ~= expectedIdentity then return false, "cooldown_identity_mismatch" end
    if binding.actionBarStateTrusted ~= true or (number(binding.actionSlot or binding.slot) or 0) <= 0 then
        return false, "binding_action_slot_untrusted"
    end
    if binding.source == "macro" and binding.macroAutoBurstEligible ~= true then
        return false, "macro_binding_untrusted"
    end
    if stepKind(step) == "inventory" then
        local slot = inventorySlot(step.inventorySlot)
        -- Before a plan exists the trinket step has no locked ItemID yet.  The
        -- resolver sample is the authoritative current-slot identity for that
        -- first CD certificate; createPlan then freezes it into the plan.
        local itemID = positiveItemID(step.expectedItemID)
            or positiveItemID(binding.itemID or binding.expectedItemID)
        if slot ~= inventorySlot(binding.inventorySlot) then return false, "binding_inventory_slot_mismatch" end
        if not itemID then return false, "binding_inventory_item_missing" end
        if itemID ~= positiveItemID(binding.itemID or binding.expectedItemID) then return false, "binding_inventory_item_mismatch" end
        if type(icon.cooldownSource) ~= "string" or icon.cooldownSource:find("inventory", 1, true) ~= 1 then
            return false, "inventory_cooldown_source_untrusted"
        end
    else
        local spellID = positiveSpellID(step.spellID)
        if not spellID then return false, "step_spell_invalid" end
        local cooldownSource = icon.cooldownSource
        if cooldownSource ~= "spell_api" and cooldownSource ~= "actionbar_api"
            and cooldownSource ~= "actionbar_duration" then
            return false, "cooldown_source_untrusted"
        end
        -- Direct action-bar evidence is accepted only for the exact,
        -- resolver-trusted default button TEK will press.  `actionbar_api`
        -- carries explicit public booleans; `actionbar_duration` is the narrow
        -- compatibility classification produced inside IconState when that same
        -- button exposes an ordinary long (> shared-GCD envelope) cooldown but
        -- omits the booleans.  Neither route accepts icon grayness, HUD
        -- DurationObjects, macros or generic action-bar guesses.
        if cooldownSource == "actionbar_api" or cooldownSource == "actionbar_duration" then
            if icon.cooldownDirectActionBarEvidence ~= true then
                return false, "actionbar_cooldown_evidence_missing"
            end
            if cooldownSource == "actionbar_duration" and icon.cooldownActionBarDurationOwnEvidence ~= true then
                return false, "actionbar_duration_evidence_missing"
            end
            if binding.directActionSlot ~= true or binding.actionBarStateTrusted ~= true then
                return false, "actionbar_binding_untrusted"
            end
        end
        local bindingSpellID = positiveSpellID(binding.requestedSpellID) or positiveSpellID(binding.spellID)
        if bindingSpellID ~= spellID then return false, "binding_requested_spell_mismatch" end
    end
    return true, "confirmed_own_cooldown_evidence", expectedIdentity, number(binding.bindingToken)
end

local sequenceFor
local rememberStepObservation

-- A missing/opaque cooldown value is not a proven own cooldown. Once the
-- ActionRef has already passed the binding gate, keep the action eligible for
-- the normal shared-rate delivery path whenever GCDGate can still provide a
-- public phase. This makes AutoBurst match ordinary official recommendations:
-- an uncertain cooldown read never silently turns a valid queued action into
-- an observation-only stall. The uncertainty remains strictly non-confirming
-- and non-skip-eligible; only a later exact own-CD/charge/spellcast proof can
-- advance or rule-skip the logical step.
local function mayDeliverWithUnknownCooldown(iconState)
    if type(iconState) ~= "table" then return false end
    if iconState.cooldownKnown == true then return false end
    if iconState.inventoryEquipmentChanged == true then return false end
    return true
end

local function classifyDispatchPhase(step, cycle, bindingInfo, iconState, reason, cooldownUncertain)
    -- Off-GCD is opt-in only and only exposed for the explicit configured
    -- trinket injection. It is never inferred from a cooldown, tooltip or
    -- item category.
    if stepKind(step) == "inventory" and step.offGCDExplicit == true then
        return {
            phase = "READY_NOW",
            reason = "inventory_off_gcd_explicit",
            bindingInfo = bindingInfo,
            iconState = iconState,
            cooldownUncertain = cooldownUncertain == true,
        }
    end
    if not (TE.GCDGate and type(TE.GCDGate.Classify) == "function") then
        return {
            phase = "UNKNOWN",
            reason = "gcd_gate_unavailable",
            bindingInfo = bindingInfo,
            iconState = iconState,
            cooldownUncertain = cooldownUncertain == true,
        }
    end
    local phase, phaseReason = TE.GCDGate:Classify(cycle)
    return {
        phase = phase,
        reason = cooldownUncertain == true
            and ("cooldown_unknown_delivery:" .. tostring(reason or phaseReason or "unknown"))
            or phaseReason,
        bindingInfo = bindingInfo,
        iconState = iconState,
        cooldownUncertain = cooldownUncertain == true,
    }
end

local function stepSample(step, cycle)
    local bindingInfo, bindingState, bindingReason = resolveStepBinding(step)
    if bindingState then return { phase = bindingState, reason = bindingReason, bindingInfo = bindingInfo } end
    local iconState, iconReason = collectCooldownState(step, cycle, bindingInfo)
    if iconState and iconState.inventoryEquipmentChanged == true then
        return { phase = "BLOCKED", reason = iconState.cooldownUnknownReason or "inventory_equipment_changed", bindingInfo = bindingInfo, iconState = iconState }
    end
    local ownState, ownReason = ownReadyState(iconState)
    if ownState == "UNKNOWN" and mayDeliverWithUnknownCooldown(iconState) then
        return classifyDispatchPhase(step, cycle, bindingInfo, iconState, ownReason or iconReason, true)
    end
    if ownState ~= "OWN_READY" then
        return { phase = ownState, reason = ownReason or iconReason, bindingInfo = bindingInfo, iconState = iconState }
    end
    return classifyDispatchPhase(step, cycle, bindingInfo, iconState, nil, false)
end

local function validateRuleBindings(self, rule)
    for _, step in ipairs(sequenceFor(rule)) do
        local bindingInfo, bindingState, bindingReason = resolveStepBinding(step)
        if bindingState then
            rememberStepObservation(self, nil, step, { phase = bindingState, reason = bindingReason, bindingInfo = bindingInfo }, "plan_gate_binding")
            return false, step, bindingState, bindingReason
        end
        if stepKind(step) == "inventory" and not positiveItemID(bindingInfo.itemID or bindingInfo.expectedItemID) then
            rememberStepObservation(self, nil, step, { phase = "BLOCKED", reason = "inventory_item_missing", bindingInfo = bindingInfo }, "plan_gate_binding")
            return false, step, "BLOCKED", "inventory_item_missing"
        end
    end
    return true, nil, nil, nil
end

local function confirmationBaseline(sample)
    local icon = sample and sample.iconState or {}
    return {
        cooldownKnown = icon.cooldownKnown == true,
        cooldownActive = icon.cooldownActive == true and icon.cooldownOnGCD ~= true and icon.cooldownGcdAlias ~= true,
        charges = number(icon.charges),
        maxCharges = number(icon.maxCharges),
        bindingToken = sample and sample.bindingInfo and number(sample.bindingInfo.bindingToken) or nil,
    }
end

local function confirmed(sample, baseline)
    local icon = sample and sample.iconState or {}
    baseline = type(baseline) == "table" and baseline or {}
    local charges, maximum = number(icon.charges), number(icon.maxCharges)
    if baseline.maxCharges and baseline.maxCharges > 1 and maximum and maximum > 1
        and baseline.charges and charges and charges < baseline.charges then
        return true, "charge_decreased"
    end
    if icon.cooldownKnown == true and icon.cooldownActive == true and icon.cooldownOnGCD ~= true
        and icon.cooldownGcdAlias ~= true and baseline.cooldownActive ~= true then
        return true, "action_cooldown_started"
    end
    -- No generic global-GCD action-bar marker is accepted as proof.  The first
    -- phase requires a skill-specific CD or charge change; rules without one
    -- fail closed rather than confusing GCD shading with successful casting.
    return false, nil
end

local function spellcastEventConfirmed(plan, step)
    local wait = plan and plan.wait
    if type(wait) ~= "table" or type(step) ~= "table" then return false, nil end
    local eventSpellID = positiveSpellID(wait.spellcastSucceededSpellID)
    local matches, matchKind = spellcastMatchesCurrentStep(step, eventSpellID, wait.offerSample and wait.offerSample.bindingInfo)
    if matches then
        return true, "unit_spellcast_succeeded_" .. tostring(wait.spellcastSucceededMatchKind or matchKind or "exact")
    end
    return false, nil
end

sequenceFor = function(rule)
    local out = {}
    for _, source in ipairs(type(rule) == "table" and rule.steps or {}) do
        local step = {}
        for key, value in pairs(source) do step[key] = value end
        out[#out + 1] = step
    end
    return out
end

rememberStepObservation = function(self, plan, step, sample, stage)
    sample = type(sample) == "table" and sample or {}
    local binding = type(sample.bindingInfo) == "table" and sample.bindingInfo or {}
    local icon = type(sample.iconState) == "table" and sample.iconState or {}
    local observation = {
        schema = 1,
        stage = stage,
        elapsed = now(),
        planId = plan and plan.id or nil,
        role = step and step.role or nil,
        actionKind = stepKind(step),
        spellID = stepKind(step) == "spell" and positiveSpellID(step and step.spellID) or nil,
        inventorySlot = stepKind(step) == "inventory" and inventorySlot(step and step.inventorySlot) or nil,
        itemID = stepKind(step) == "inventory" and positiveItemID(step and step.expectedItemID) or nil,
        phase = sample.phase,
        reason = sample.reason,
        bindingStatus = binding.status,
        bindingReason = binding.reason,
        bindingToken = number(binding.bindingToken),
        binding = binding.binding or binding.rawBinding,
        matchedSpellID = positiveSpellID(binding.matchedSpellID),
        cooldownKnown = icon.cooldownKnown == true,
        cooldownActive = icon.cooldownActive == true,
        cooldownOnGCD = icon.cooldownOnGCD == true,
        cooldownPublicActiveKnown = icon.cooldownPublicActiveKnown == true,
        cooldownPublicActive = icon.cooldownPublicActive,
        cooldownPublicOnGCDKnown = icon.cooldownPublicOnGCDKnown == true,
        cooldownPublicOnGCD = icon.cooldownPublicOnGCD,
        cooldownGcdAlias = icon.cooldownGcdAlias == true,
        cooldownLiveRead = icon.cooldownLiveRead == true,
        cooldownSource = icon.cooldownSource,
        cooldownDirectActionBarEvidence = icon.cooldownDirectActionBarEvidence == true,
        cooldownDirectActionBarReadyEvidence = icon.cooldownDirectActionBarReadyEvidence == true,
        cooldownActionBarPublicActiveKnown = icon.cooldownActionBarPublicActiveKnown == true,
        cooldownActionBarPublicActive = icon.cooldownActionBarPublicActive,
        cooldownActionBarPublicOnGCDKnown = icon.cooldownActionBarPublicOnGCDKnown == true,
        cooldownActionBarPublicOnGCD = icon.cooldownActionBarPublicOnGCD,
        cooldownActionBarDurationKnown = icon.cooldownActionBarDurationKnown == true,
        cooldownActionBarDurationOwnEvidence = icon.cooldownActionBarDurationOwnEvidence == true,
        cooldownActionBarNumericReady = icon.cooldownActionBarNumericReady == true,
        cooldownIdentityKey = icon.cooldownIdentityKey,
        cooldownConfirmationPending = icon.cooldownConfirmationPending == true,
        cooldownUnknownReason = icon.cooldownUnknownReason,
        cooldownRequestedActionSlot = number(icon.cooldownRequestedActionSlot),
        cooldownActionBarStateTrusted = icon.cooldownActionBarStateTrusted == true,
        chargeCount = number(icon.charges),
        chargeMaximum = number(icon.maxCharges),
        dispatchAttempt = plan and number(plan.dispatchAttempt) or nil,
        waitDispatchAttempt = plan and plan.wait and number(plan.wait.dispatchAttempt) or nil,
        waitInputPhase = plan and plan.wait and plan.wait.phase or nil,
    }
    self.lastStepObservation = observation
    return observation
end

local function candidateResult(self, plan, step, sample)
    local offeredAt = now()
    plan.candidateOfferCount = (plan.candidateOfferCount or 0) + 1
    plan.candidateFirstOfferedAt = plan.candidateFirstOfferedAt or offeredAt
    plan.candidateLastOfferedAt = offeredAt
    self.lastCandidate = {
        schema = 1,
        elapsed = offeredAt,
        planId = plan.id,
        windowGeneration = plan.windowGeneration,
        role = step.role,
        actionKind = stepKind(step),
        spellID = stepKind(step) == "spell" and positiveSpellID(step.spellID) or nil,
        inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
        itemID = stepKind(step) == "inventory" and positiveItemID(step.expectedItemID or (sample and sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
        bindingToken = sample and sample.bindingInfo and number(sample.bindingInfo.bindingToken) or nil,
        binding = sample and sample.bindingInfo and (sample.bindingInfo.binding or sample.bindingInfo.rawBinding) or nil,
        dispatchAttempt = plan.wait and plan.wait.dispatchAttempt or 0,
        inputPhase = plan.wait and plan.wait.phase or (sample and sample.phase),
        cooldownUncertain = sample and sample.cooldownUncertain == true,
        offerCount = plan.candidateOfferCount,
    }
    return {
        kind = "candidate",
        dispatchOrigin = "burst",
        dispatchSpellID = stepKind(step) == "spell" and step.spellID or nil,
        dispatchActionKind = stepKind(step),
        dispatchInventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
        dispatchItemID = stepKind(step) == "inventory" and positiveItemID(step.expectedItemID or (sample and sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
        officialSpellID = plan.officialSpellID,
        bindingInfo = sample.bindingInfo,
        planId = plan.id,
        windowGeneration = plan.windowGeneration,
        ruleId = plan.rule.id,
        ruleSource = plan.rule.source,
        direction = plan.rule.direction,
        mode = plan.rule.mode,
        stepRole = step.role,
        -- This increments only when the state machine moves to a new logical
        -- step. The same candidate remains visible on every fresh armed frame;
        -- TEK deliberately applies the same configured global rate limiter to Burst
        -- and official candidates rather than a Burst-only one-shot dedupe.
        dispatchAttempt = plan.wait and plan.wait.dispatchAttempt or 0,
        recoveryActive = plan.wait and plan.wait.inventoryRecoveryActive == true,
        cooldownUncertain = sample and sample.cooldownUncertain == true,
        -- This is diagnostic metadata only. SignalFrame uses it to preserve an
        -- armed TEAP envelope for this already-authorized bridge candidate;
        -- TEK still receives the ordinary inCombat=false flag and every normal
        -- protocol/foreground/manual/freshness gate.
        preCombatBridge = plan.preCombatBridge == true,
    }
end

local function holdResult(plan, reason, options)
    options = type(options) == "table" and options or {}
    return {
        kind = "hold",
        dispatchOrigin = "burst",
        -- A hold is an authenticated, non-dispatchable transport frame.  It is
        -- not the user-facing paused state: SignalFrame encodes it as an
        -- observation-only armed frame so an internal GCD/confirmation wait
        -- cannot feed back into AutoBurst as runtime.effectiveState="paused".
        observationOnly = true,
        officialSpellID = plan and plan.officialSpellID or nil,
        planId = plan and plan.id or nil,
        ruleId = plan and plan.rule and plan.rule.id or nil,
        reason = reason,
        preCombatBridge = (plan and plan.preCombatBridge == true) or options.preCombatBridge == true,
    }
end

local function noneResult()
    return { kind = "none", dispatchOrigin = "official" }
end

-- Front-injection ownership exists one layer earlier than a fully created plan.
-- When the official recommendation exactly matches a declared pre-window, this
-- capture emits an authenticated observation frame rather than allowing the
-- ordinary official recommendation to escape while bindings/cooldown snapshots
-- settle. The capture is short-lived and only survives while the same official
-- window remains visible; it never fabricates a Burst sequence after the window
-- has departed.
local function preWindowCaptureHold(capture, reason)
    return {
        kind = "hold",
        dispatchOrigin = "burst",
        observationOnly = true,
        officialSpellID = capture and capture.officialSpellID or nil,
        planId = nil,
        captureId = capture and capture.id or nil,
        windowGeneration = capture and capture.windowGeneration or nil,
        ruleId = capture and capture.rule and capture.rule.id or nil,
        ruleSource = capture and capture.rule and capture.rule.source or nil,
        direction = capture and capture.rule and capture.rule.direction or nil,
        mode = capture and capture.rule and capture.rule.mode or nil,
        reason = reason or (capture and capture.reason) or "pre_window_capture",
        preCombatBridge = capture and capture.preCombatBridge == true,
    }
end

local function beginPreWindowCapture(self, rule, officialSpellID, windowGeneration, reason, handoffBarrierRequired, preCombatBridge)
    local existing = self and self.preWindowCapture
    if type(existing) == "table"
        and existing.rule and existing.rule.id == rule.id
        and existing.officialSpellID == officialSpellID
        and number(existing.windowGeneration) == number(windowGeneration) then
        if preCombatBridge == true then existing.preCombatBridge = true end
        return existing, false
    end
    -- A manual re-arm after a world transition is still a pre-combat bridge,
    -- but it starts from a potentially stale screen reader frame.  Require the
    -- same four fresh observation frames before exposing any optional-step
    -- token, even when the logical intent remained armed across the map load.
    local requiresHandoff = handoffBarrierRequired == true
        or (preCombatBridge == true and self.preCombatBridgeAuthorizationRequiresHandoff == true)
    local capture = {
        schema = 1,
        id = self.nextPreWindowCaptureId or 1,
        rule = rule,
        officialSpellID = officialSpellID,
        windowGeneration = number(windowGeneration) or number(self.windowGeneration) or 0,
        armedEpoch = self.armedEpoch or 0,
        createdAt = now(),
        reason = reason or "pre_window_capture",
        preCombatBridge = preCombatBridge == true,
        preCombatBridgeEnteredCombat = false,
        -- Preserve the legacy boolean for mapping compatibility. The actual
        -- handoff contract is frame-counted, because a single event refresh can
        -- be far shorter than one TEK sampling period.
        handoffBarrierRequiredFrames = requiresHandoff and PRE_WINDOW_HANDOFF_MIN_HOLD_FRAMES or 0,
        handoffBarrierRemainingFrames = requiresHandoff and PRE_WINDOW_HANDOFF_MIN_HOLD_FRAMES or 0,
        handoffBarrierPublishedFrames = 0,
        handoffBarrierPending = requiresHandoff,
        retryCount = 0,
        lastRetryReason = nil,
    }
    self.nextPreWindowCaptureId = capture.id + 1
    self.preWindowCapture = capture
    if capture.preCombatBridge == true and self.preCombatBridgeAuthorizationRequiresHandoff == true then
        self.preCombatBridgeAuthorizationRequiresHandoff = false
    end
    log(self, "pre_window_capture_started", {
        captureId = capture.id,
        ruleId = rule.id,
        ruleSource = rule.source,
        officialSpellID = officialSpellID,
        windowSpellID = rule.windowSpellID,
        windowGeneration = capture.windowGeneration,
        armedEpoch = capture.armedEpoch,
        reason = capture.reason,
        preCombatBridge = capture.preCombatBridge == true,
    })
    if capture.preCombatBridge == true then
        log(self, "precombat_burst_bridge_started", {
            captureId = capture.id,
            ruleId = rule.id,
            ruleSource = rule.source,
            officialSpellID = officialSpellID,
            windowSpellID = rule.windowSpellID,
            windowGeneration = capture.windowGeneration,
            armedEpoch = capture.armedEpoch,
            reason = capture.reason,
        })
    end
    return capture, true
end

local function handoffBarrierRemaining(owner)
    if type(owner) ~= "table" then return 0 end
    return math.max(0, math.floor(number(owner.handoffBarrierRemainingFrames) or 0))
end

local function resetHandoffBarrier(owner, requiredFrames)
    if type(owner) ~= "table" then return end
    local required = math.max(0, math.floor(number(requiredFrames) or 0))
    owner.handoffBarrierRequiredFrames = required
    owner.handoffBarrierRemainingFrames = required
    owner.handoffBarrierPublishedFrames = 0
    owner.handoffBarrierPending = required > 0
end

-- SignalFrame may Refresh several times inside one visual/sampling period due
-- to state and game events. Count only its scheduled transport tick for the
-- cross-process handoff. Direct unit callers omit this field and are treated as
-- one fresh tick per Evaluate call.
local function isTransportHandoffTick(runtime)
    return type(runtime) ~= "table" or runtime.transportHandoffTick ~= false
end

local function consumeHandoffBarrierFrame(owner)
    local remaining = handoffBarrierRemaining(owner)
    if remaining <= 0 then
        if type(owner) == "table" then owner.handoffBarrierPending = false end
        return false, 0, math.max(0, math.floor(number(owner and owner.handoffBarrierPublishedFrames) or 0))
    end
    remaining = remaining - 1
    owner.handoffBarrierRemainingFrames = remaining
    owner.handoffBarrierPublishedFrames = math.max(0, math.floor(number(owner.handoffBarrierPublishedFrames) or 0)) + 1
    owner.handoffBarrierPending = remaining > 0
    return true, remaining, owner.handoffBarrierPublishedFrames
end

local function copyHandoffBarrier(source, target)
    if type(target) ~= "table" then return end
    target.handoffBarrierRequiredFrames = math.max(0, math.floor(number(source and source.handoffBarrierRequiredFrames) or 0))
    target.handoffBarrierRemainingFrames = handoffBarrierRemaining(source)
    target.handoffBarrierPublishedFrames = math.max(0, math.floor(number(source and source.handoffBarrierPublishedFrames) or 0))
    target.handoffBarrierPending = target.handoffBarrierRemainingFrames > 0
end

local function handoffBarrierLogFields(owner, fields)
    fields = type(fields) == "table" and fields or {}
    fields.holdFramesRequired = math.max(0, math.floor(number(owner and owner.handoffBarrierRequiredFrames) or 0))
    fields.holdFrame = math.max(0, math.floor(number(owner and owner.handoffBarrierPublishedFrames) or 0))
    fields.holdFramesRemaining = handoffBarrierRemaining(owner)
    return fields
end

local function releasePreWindowCapture(self, reason, fields)
    local capture = self and self.preWindowCapture
    if type(capture) ~= "table" then return end
    fields = type(fields) == "table" and fields or {}
    log(self, "pre_window_capture_released", {
        captureId = capture.id,
        ruleId = capture.rule and capture.rule.id or nil,
        officialSpellID = capture.officialSpellID,
        windowSpellID = capture.rule and capture.rule.windowSpellID or nil,
        windowGeneration = capture.windowGeneration,
        armedEpoch = capture.armedEpoch,
        retryCount = capture.retryCount or 0,
        reason = reason or "pre_window_capture_released",
        detail = fields.detail,
    })
    self.preWindowCapture = nil
end

local function continuePreWindowCapture(self, capture, reason, fields, runtime)
    if type(capture) ~= "table" then return noneResult() end
    fields = type(fields) == "table" and fields or {}
    capture.retryCount = (number(capture.retryCount) or 0) + 1
    local hadHandoffBarrier = handoffBarrierRemaining(capture) > 0
    local handoffBarrier = false
    if hadHandoffBarrier and isTransportHandoffTick(runtime) then
        handoffBarrier = consumeHandoffBarrierFrame(capture)
    end
    local priorReason = capture.lastRetryReason
    capture.lastRetryReason = reason
    if handoffBarrier then
        log(self, "pre_window_capture_handoff_barrier", handoffBarrierLogFields(capture, {
            captureId = capture.id,
            ruleId = capture.rule and capture.rule.id or nil,
            officialSpellID = capture.officialSpellID,
            windowSpellID = capture.rule and capture.rule.windowSpellID or nil,
            windowGeneration = capture.windowGeneration,
            armedEpoch = capture.armedEpoch,
            reason = reason or "pre_window_handoff",
            phase = "capture",
        }))
        if handoffBarrierRemaining(capture) == 0 then
            log(self, "pre_window_capture_handoff_ready", handoffBarrierLogFields(capture, {
                captureId = capture.id,
                ruleId = capture.rule and capture.rule.id or nil,
                officialSpellID = capture.officialSpellID,
                windowGeneration = capture.windowGeneration,
                armedEpoch = capture.armedEpoch,
                phase = "capture",
            }))
        end
    elseif not hadHandoffBarrier and priorReason ~= reason then
        log(self, "pre_window_capture_revalidating", {
            captureId = capture.id,
            ruleId = capture.rule and capture.rule.id or nil,
            officialSpellID = capture.officialSpellID,
            windowSpellID = capture.rule and capture.rule.windowSpellID or nil,
            windowGeneration = capture.windowGeneration,
            retryCount = capture.retryCount,
            reason = reason or "pre_window_capture_revalidate",
            detail = fields.detail,
        })
    end
    return preWindowCaptureHold(capture, hadHandoffBarrier and "pre_window_capture_handoff_barrier" or reason)
end

local function lockWindowDeparture(self, plan)
    if not (self and plan and plan.rule) then return end
    local generation = number(plan.windowGeneration) or number(self.windowGeneration)
    self.lockedWindowSpellID = plan.rule.windowSpellID
    self.requireWindowDeparture = true
    self.preCombatBridgeDepartureLock = plan.preCombatBridge == true
    self.departureLockGeneration = generation
    if generation then self.consumedWindowGeneration = generation end
    self.activePlanGeneration = nil
end

-- A pre-window capture has no plan yet, but it still owns the official window
-- token. If evaluation faults during that ownership interval, fail closed until
-- the official recommendation leaves rather than exposing the captured window
-- through the ordinary recommendation path on the next frame.
local function lockPreWindowCaptureDeparture(self, capture)
    if not (self and type(capture) == "table" and type(capture.rule) == "table") then return end
    local generation = number(capture.windowGeneration) or number(self.windowGeneration)
    self.lockedWindowSpellID = capture.rule.windowSpellID or capture.officialSpellID
    self.requireWindowDeparture = self.lockedWindowSpellID ~= nil
    self.preCombatBridgeDepartureLock = capture.preCombatBridge == true
    self.departureLockGeneration = generation
    if generation then self.consumedWindowGeneration = generation end
    self.activePlanGeneration = nil
    log(self, "pre_window_capture_departure_locked", {
        captureId = capture.id,
        ruleId = capture.rule.id,
        officialSpellID = capture.officialSpellID,
        windowSpellID = capture.rule.windowSpellID,
        windowGeneration = generation,
        reason = "capture_evaluator_fault",
    })
end

local function observeWindowFrame(self, officialSpellID, rule, previousOfficialSpellID, firstHealthyFramePending)
    if not officialSpellID or officialSpellID ~= rule.windowSpellID then
        if self.currentWindowSpellID and officialSpellID ~= self.currentWindowSpellID then
            self.currentWindowSpellID = nil
        end
        return false, "official_not_window"
    end

    local edgeEntry = previousOfficialSpellID ~= officialSpellID
    if edgeEntry then
        self.windowGeneration = (self.windowGeneration or 0) + 1
        self.currentWindowSpellID = officialSpellID
        return true, "official_window_edge"
    end

    if firstHealthyFramePending == true then
        if self.currentWindowSpellID ~= officialSpellID or (self.windowGeneration or 0) <= 0 then
            self.windowGeneration = (self.windowGeneration or 0) + 1
            self.currentWindowSpellID = officialSpellID
        end
        local generation = self.windowGeneration or 0
        if generation ~= (self.consumedWindowGeneration or 0)
            and generation ~= (self.departureLockGeneration or 0) then
            return true, "first_healthy_window"
        end
    end

    return false, "window_edge_missing"
end

-- A completed window must not be re-sent while the official recommendation
-- still displays that same stale window skill.  The departure lock therefore
-- creates an observation-only frame until the official recommendation leaves
-- the window.  SignalFrame carries a separate display-only official binding in
-- that frame, so the primary HUD never turns into “无绑定” and TEK never gets a
-- second window key to send.
local function terminalResult(self, reason, fields)
    fields = type(fields) == "table" and fields or {}
    fields.reason = reason or fields.reason or "burst_terminal"
    if self.requireWindowDeparture then
        recordDecision(self, "hold", fields.reason, fields)
        return holdResult(nil, "burst_await_window_departure", {
            preCombatBridge = self.preCombatBridgeDepartureLock == true,
        })
    end
    recordDecision(self, "released", fields.reason, fields)
    return noneResult()
end

-- Once a plan has been created, its declared steps are latched to that
-- generation. The official recommendation is the creation anchor, not a
-- per-frame cancellation signal: the assisted queue can rotate while the
-- first Burst action is still waiting on GCD/cast acceptance. Releasing here
-- would strand a successfully confirmed injection and reproduce the observed
-- ``trinket succeeded → window never sent`` failure. We therefore record the
-- departure once for diagnosis but keep the plan active until a real step
-- outcome (confirmation, verified own-CD rule disposition, or hard gate).
local function observeLatchedPlanOfficialDeparture(self, plan, officialSpellID, reason)
    if not (self and plan and plan.rule) then return false end
    if officialSpellID == plan.rule.windowSpellID then return false end
    if plan.officialDepartureObserved == true then return false end
    plan.officialDepartureObserved = true
    plan.officialDepartureObservedAt = now()
    log(self, "official_window_departed_plan_latched", {
        planId = plan.id,
        currentStep = plan.stepIndex,
        officialSpellID = officialSpellID,
        windowSpellID = plan.rule.windowSpellID,
        windowDispatchAttempted = plan.windowDispatchAttempted == true,
        reason = reason or "official_window_departed",
    })
    return false
end

local function revalidateUnknownStep(self, plan, step, sample, reason)
    local t = now()
    local identity = stepIdentity(step, sample and sample.bindingInfo)
    local current = plan.revalidate
    if type(current) ~= "table" or current.stepIndex ~= plan.stepIndex or current.identity ~= identity then
        current = {
            stepIndex = plan.stepIndex,
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
            itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample and sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
            identity = identity,
            startedAt = t,
            nextHeartbeatAt = t + STEP_REVALIDATE_SECONDS,
            lastReason = reason,
        }
        plan.revalidate = current
        log(self, "step_revalidate_started", {
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
            itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample and sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
            reason = reason,
            currentStep = plan.stepIndex,
            persistent = true,
        })
    elseif t >= (number(current.nextHeartbeatAt) or t) then
        current.nextHeartbeatAt = t + STEP_REVALIDATE_SECONDS
        current.lastReason = reason
        log(self, "step_revalidate_persistent", {
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
            itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample and sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
            reason = reason,
            currentStep = plan.stepIndex,
            elapsed = math.max(0, t - (number(current.startedAt) or t)),
        })
    end
    -- No deadline-based abort here. Unknown or conflicting public cooldown
    -- data never authorizes a token, but it also must not consume a valid
    -- official window and leave the main recommendation path locked.
    return holdResult(plan, "burst_step_revalidate")
end

-- A cooldown flag that cannot yet pass the exact own-CD certificate is treated
-- as delivery uncertainty, not as a terminal stall. Reclassify it through the
-- same public GCD gate used by ordinary recommendations; when that gate exposes
-- READY/QUEUE/GCD_LOCKED, keep publishing fresh armed candidates at the shared
-- TEK cadence. A later exact two-sample certificate may still rule-skip the
-- optional simple injection or finish the window without dispatching it.
local function reofferUnconfirmedCooldown(self, plan, step, cycle, sample, reason)
    sample = type(sample) == "table" and sample or {}
    local offer = classifyDispatchPhase(
        step,
        cycle,
        sample.bindingInfo,
        sample.iconState,
        reason or sample.reason or "cooldown_unconfirmed",
        true
    )
    rememberStepObservation(self, plan, step, offer, "cooldown_unconfirmed_delivery")
    if offer.phase == "READY_NOW" or offer.phase == "QUEUE_WINDOW" or offer.phase == "GCD_LOCKED" then
        return candidateResult(self, plan, step, offer)
    end
    return revalidateUnknownStep(self, plan, step, offer,
        "cooldown_unconfirmed_" .. tostring(offer.reason or reason or "unknown"))
end

local function confirmPreInjectionOwnCooldown(self, plan, step, sample)
    -- Legacy diagnostic field names retain the "preInjection" prefix for
    -- SavedVariables compatibility. The same exact two-sample certificate is
    -- now used by simple post injection as well; `direction` disambiguates it.
    local direction = plan and plan.rule and plan.rule.direction or "pre"
    local t = now()
    local eligible, reason, identityKey, bindingToken = explicitOwnCooldownEvidence(step, sample)
    local confirmation = type(plan.preInjectionCooldownConfirmation) == "table"
        and plan.preInjectionCooldownConfirmation or nil

    if eligible ~= true then
        plan.preInjectionSkipAllowed = false
        plan.preInjectionRequired = true
        plan.preInjectionSkipStatus = "cooldown_unconfirmed"
        if confirmation then
            log(self, "pre_injection_cooldown_rejected", {
                role = step.role,
                actionKind = stepKind(step),
                spellID = stepKind(step) == "spell" and step.spellID or nil,
                inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
                itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
                reason = reason,
                direction = direction,
                confirmations = number(confirmation.count) or 0,
                currentStep = plan.stepIndex,
            })
        end
        plan.preInjectionCooldownConfirmation = nil
        return "revalidate", reason
    end

    if not confirmation then
        confirmation = {
            count = 1,
            firstObservedAt = t,
            nextProbeAt = t + PRE_INJECTION_COOLDOWN_CONFIRM_INTERVAL_SECONDS,
            identityKey = identityKey,
            bindingToken = bindingToken,
        }
        plan.preInjectionCooldownConfirmation = confirmation
        plan.preInjectionSkipAllowed = false
        plan.preInjectionRequired = true
        plan.preInjectionSkipStatus = "confirming_own_cooldown"
        log(self, "pre_injection_cooldown_sample", {
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
            itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
            reason = reason,
            direction = direction,
            confirmations = confirmation.count,
            cooldownIdentityKey = identityKey,
            cooldownSource = type(sample.iconState) == "table" and sample.iconState.cooldownSource or nil,
            cooldownDirectActionBarEvidence = type(sample.iconState) == "table" and sample.iconState.cooldownDirectActionBarEvidence == true,
            currentStep = plan.stepIndex,
        })
        return "hold", "pre_injection_cooldown_confirming"
    end

    if t < (number(confirmation.nextProbeAt) or t) then
        return "hold", "pre_injection_cooldown_confirming"
    end

    if confirmation.identityKey ~= identityKey or confirmation.bindingToken ~= bindingToken then
        plan.preInjectionSkipAllowed = false
        plan.preInjectionRequired = true
        plan.preInjectionSkipStatus = "cooldown_identity_changed"
        plan.preInjectionCooldownConfirmation = nil
        log(self, "pre_injection_cooldown_rejected", {
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
            itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
            reason = "cooldown_identity_changed",
            direction = direction,
            currentStep = plan.stepIndex,
        })
        return "revalidate", "cooldown_identity_changed"
    end

    confirmation.count = (number(confirmation.count) or 0) + 1
    confirmation.nextProbeAt = t + PRE_INJECTION_COOLDOWN_CONFIRM_INTERVAL_SECONDS
    if confirmation.count >= PRE_INJECTION_COOLDOWN_CONFIRM_SAMPLES then
        plan.preInjectionSkipAllowed = true
        plan.preInjectionRequired = false
        plan.preInjectionSkipStatus = "confirmed_own_cooldown"
        log(self, "pre_injection_cooldown_confirmed", {
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
            itemID = stepKind(step) == "inventory" and (step.expectedItemID or (sample.bindingInfo and sample.bindingInfo.itemID)) or nil,
            reason = "confirmed_own_cooldown",
            direction = direction,
            confirmations = confirmation.count,
            cooldownIdentityKey = identityKey,
            cooldownSource = type(sample.iconState) == "table" and sample.iconState.cooldownSource or nil,
            cooldownDirectActionBarEvidence = type(sample.iconState) == "table" and sample.iconState.cooldownDirectActionBarEvidence == true,
            currentStep = plan.stepIndex,
        })
        return "skip", "confirmed_own_cooldown"
    end

    plan.preInjectionSkipStatus = "confirming_own_cooldown"
    return "hold", "pre_injection_cooldown_confirming"
end


-- A window may legitimately enter its own cooldown outside this plan (manual
-- key press, external macro or a prior action). Treat that as a rule-level
-- disposition only after two live, exact, non-GCD samples. A single short
-- public/API disagreement remains a revalidation state and never terminates
-- the latched plan.
local function confirmWindowOwnCooldown(self, plan, step, sample)
    local t = now()
    local eligible, reason, identityKey, bindingToken = explicitOwnCooldownEvidence(step, sample)
    local confirmation = type(plan.windowCooldownConfirmation) == "table"
        and plan.windowCooldownConfirmation or nil

    if eligible ~= true then
        if confirmation then
            log(self, "window_own_cooldown_rejected", {
                role = step.role,
                spellID = step.spellID,
                reason = reason,
                confirmations = number(confirmation.count) or 0,
                currentStep = plan.stepIndex,
            })
        end
        plan.windowCooldownConfirmation = nil
        return "revalidate", reason
    end

    if not confirmation then
        confirmation = {
            count = 1,
            firstObservedAt = t,
            nextProbeAt = t + PRE_INJECTION_COOLDOWN_CONFIRM_INTERVAL_SECONDS,
            identityKey = identityKey,
            bindingToken = bindingToken,
        }
        plan.windowCooldownConfirmation = confirmation
        log(self, "window_own_cooldown_sample", {
            role = step.role,
            spellID = step.spellID,
            reason = reason,
            confirmations = confirmation.count,
            cooldownIdentityKey = identityKey,
            currentStep = plan.stepIndex,
        })
        return "hold", "window_own_cooldown_confirming"
    end

    if t < (number(confirmation.nextProbeAt) or t) then
        return "hold", "window_own_cooldown_confirming"
    end

    if confirmation.identityKey ~= identityKey or confirmation.bindingToken ~= bindingToken then
        log(self, "window_own_cooldown_rejected", {
            role = step.role,
            spellID = step.spellID,
            reason = "cooldown_identity_changed",
            currentStep = plan.stepIndex,
        })
        plan.windowCooldownConfirmation = nil
        return "revalidate", "cooldown_identity_changed"
    end

    confirmation.count = (number(confirmation.count) or 0) + 1
    confirmation.nextProbeAt = t + PRE_INJECTION_COOLDOWN_CONFIRM_INTERVAL_SECONDS
    if confirmation.count >= PRE_INJECTION_COOLDOWN_CONFIRM_SAMPLES then
        log(self, "window_own_cooldown_confirmed", {
            role = step.role,
            spellID = step.spellID,
            reason = "confirmed_own_cooldown",
            confirmations = confirmation.count,
            cooldownIdentityKey = identityKey,
            currentStep = plan.stepIndex,
        })
        return "skip", "confirmed_own_cooldown"
    end
    return "hold", "window_own_cooldown_confirming"
end

function AutoBurst:Abort(reason, hard)
    self.lastAbortReason = tostring(reason or "unknown")
    local capture = self.preWindowCapture
    -- A capture has not yet created a sequence, but it still owns the front
    -- window against ordinary fallback. An evaluator fault is therefore a
    -- fail-closed terminal event for the captured window: keep an explicit
    -- departure lock before releasing transient capture state.
    if not self.plan and tostring(reason or "") == "evaluator_fault" and type(capture) == "table" then
        lockPreWindowCaptureDeparture(self, capture)
    end
    releasePreWindowCapture(self, "abort:" .. tostring(reason or "unknown"))
    if self.plan then
        log(self, hard and "hard_abort" or "plan_aborted", { reason = reason, currentStep = self.plan.stepIndex })
        -- A created Burst plan owns its official window through terminal state.
        -- It must never fail open to the ordinary recommendation after UNKNOWN,
        -- confirmation timeout or a rejected candidate; a new plan requires the
        -- official recommendation to leave the window and re-enter.
        lockWindowDeparture(self, self.plan)
    end
    self.plan = nil
end

-- A world transition is not a combat transition.  Any official recommendation
-- visible while loading or immediately after the map settles is advisory only:
-- it must never inherit the old armed intent as authority for a pre-combat
-- Burst bridge.  Clear all transient window ownership without creating a
-- departure lock, then wait for a real combat epoch or an explicit existing
-- Run action before another bridge can begin.
function AutoBurst:ActivateWorldTransitionFence(reason)
    self.worldTransitionEpoch = (self.worldTransitionEpoch or 0) + 1
    self.preCombatBridgeWorldFence = true
    self.preCombatBridgeAuthorizationRequiresHandoff = false

    releasePreWindowCapture(self, "world_transition:" .. tostring(reason or "unknown"))
    self.plan = nil
    self.requireWindowDeparture = false
    self.lockedWindowSpellID = nil
    self.preCombatBridgeDepartureLock = false
    self.departureLockGeneration = nil
    self.activePlanGeneration = nil
    self.currentWindowSpellID = nil
    self.lastOfficialSpellID = nil
    self.firstHealthyFramePending = true
    self.eventPauseUntil = 0
    self.eventPauseReason = nil
    self.lastWorldTransition = {
        schema = 1,
        elapsed = now(),
        reason = tostring(reason or "unknown"),
        epoch = self.worldTransitionEpoch,
    }
    log(self, "world_transition_precombat_fenced", {
        reason = self.lastWorldTransition.reason,
        worldTransitionEpoch = self.worldTransitionEpoch,
    })
end

-- SignalFrame calls this only from the existing explicit SetState("armed")
-- control.  It does not change user-visible state labels or enable ordinary
-- out-of-combat dispatch; it merely authorizes the already-designed opener
-- bridge after a map transition and forces a fresh four-frame handoff.
function AutoBurst:AuthorizePreCombatBridge(reason)
    local wasFenced = self.preCombatBridgeWorldFence == true
    self.preCombatBridgeWorldFence = false
    self.preCombatBridgeAuthorizationRequiresHandoff = true
    if wasFenced then
        self.firstHealthyFramePending = true
        self.lastOfficialSpellID = nil
        self.currentWindowSpellID = nil
        self.activePlanGeneration = nil
        log(self, "precombat_bridge_reauthorized", {
            reason = tostring(reason or "manual_arm"),
            worldTransitionEpoch = self.worldTransitionEpoch or 0,
        })
    end
    return wasFenced
end

-- Begin a new encounter-scoped official-window epoch.  This deliberately
-- clears only stale AutoBurst edge/lock memory; it does not fabricate a
-- candidate or bypass the normal in-combat, armed, rule, binding, TEAP or TEK
-- gates.  On the next healthy in-combat frame, a currently recommended window
-- is therefore treated as the first recommendation edge of this combat.
function AutoBurst:BeginCombatEpoch(reason)
    self.combatEpoch = (self.combatEpoch or 0) + 1
    if self.preCombatBridgeWorldFence == true then
        -- Actual combat is the other legitimate opener authorization path.
        -- It restores normal in-combat AutoBurst immediately, without creating
        -- or replaying any out-of-combat plan from the map transition.
        self.preCombatBridgeWorldFence = false
        self.preCombatBridgeAuthorizationRequiresHandoff = false
        log(self, "world_transition_fence_cleared_by_combat", {
            reason = reason or "combat_started",
            combatEpoch = self.combatEpoch,
            worldTransitionEpoch = self.worldTransitionEpoch or 0,
        })
    end
    local plan = self.plan
    local capture = self.preWindowCapture
    local bridgePlan = type(plan) == "table" and plan.preCombatBridge == true
    local bridgeCapture = type(capture) == "table" and capture.preCombatBridge == true

    -- A front-injection opener may itself cross PLAYER_REGEN_DISABLED. Do not
    -- clear its capture, plan, window generation or handoff budget on that
    -- event: the bridge is the only explicit owner allowed to cross this
    -- boundary. Every non-bridge encounter still receives the historical clean
    -- combat epoch reset below.
    if bridgePlan or bridgeCapture then
        if bridgePlan then
            plan.preCombatBridgeEnteredCombat = true
            plan.combatEpoch = self.combatEpoch
        end
        if bridgeCapture then
            capture.preCombatBridgeEnteredCombat = true
            capture.combatEpoch = self.combatEpoch
        end
        self.eventPauseUntil = 0
        self.eventPauseReason = nil
        log(self, "precombat_burst_bridge_combat_entered", {
            reason = reason or "combat_started",
            combatEpoch = self.combatEpoch,
            planId = bridgePlan and plan.id or nil,
            captureId = bridgeCapture and capture.id or nil,
            windowGeneration = bridgePlan and plan.windowGeneration or (bridgeCapture and capture.windowGeneration or nil),
        })
        return true
    end

    releasePreWindowCapture(self, "combat_epoch:" .. tostring(reason or "combat_started"))
    self.plan = nil
    self.requireWindowDeparture = false
    self.lockedWindowSpellID = nil
    self.preCombatBridgeDepartureLock = false
    self.departureLockGeneration = nil
    self.activePlanGeneration = nil
    self.currentWindowSpellID = nil
    self.lastOfficialSpellID = nil
    self.firstHealthyFramePending = true
    self.eventPauseUntil = 0
    self.eventPauseReason = nil
    log(self, "combat_epoch_started", {
        reason = reason or "combat_started",
        combatEpoch = self.combatEpoch,
    })
    return false
end

local function isRecoverableInventoryInjection(plan, step)
    return type(plan) == "table"
        and type(step) == "table"
        and isOptionalStep(step)
        and stepKind(step) == "inventory"
        and plan.rule and plan.rule.requiresPreWindowCapture == true
        and plan.windowDispatchAttempted ~= true
end

local function extendDeadline(value, delta)
    value = number(value)
    delta = number(delta) or 0
    if not value or delta <= 0 then return value end
    return value + delta
end

function AutoBurst:SoftPause(reason)
    if not self.plan then return end
    if self.plan.state ~= "SOFT_PAUSED" then
        self.plan.pauseStartedAt = now()
        self.plan.state = "SOFT_PAUSED"
        self.plan.pauseReason = reason
        local step = self.plan.steps and self.plan.steps[self.plan.stepIndex] or nil
        if self.plan.wait and isRecoverableInventoryInjection(self.plan, step) then
            -- The next healthy frame keeps looking for the locked slot's own
            -- cooldown. This accepts a manual supplemental use without ever
            -- treating generic GCD, icon grayness or a Buff as success.
            self.plan.wait.inventoryRecoveryEligible = true
        end
        log(self, "soft_paused", {
            reason = reason,
            currentStep = self.plan.stepIndex,
            recoveryEligible = self.plan.wait and self.plan.wait.inventoryRecoveryEligible == true,
        })
    elseif self.plan.pauseReason ~= reason then
        self.plan.pauseReason = reason
    end
end

function AutoBurst:ResumeIfPossible()
    if not self.plan or self.plan.state ~= "SOFT_PAUSED" then return end
    local plan = self.plan
    local resumedAt = now()
    local pausedAt = number(plan.pauseStartedAt) or resumedAt
    local pauseSeconds = math.max(0, resumedAt - pausedAt)
    -- A non-dispatchable runtime state must not consume a confirmation,
    -- revalidation or recovery interval. This makes cast/channel/empower and
    -- manual-pause behavior match the ordinary fresh-frame scheduler.
    plan.deadlineAt = extendDeadline(plan.deadlineAt, pauseSeconds)
    if type(plan.wait) == "table" then
        plan.wait.deadlineAt = extendDeadline(plan.wait.deadlineAt, pauseSeconds)
        plan.wait.inventoryRecoveryDeadlineAt = extendDeadline(plan.wait.inventoryRecoveryDeadlineAt, pauseSeconds)
    end
    if type(plan.revalidate) == "table" then
        plan.revalidate.deadlineAt = extendDeadline(plan.revalidate.deadlineAt, pauseSeconds)
    end
    plan.pauseStartedAt = nil
    plan.state = plan.wait and "WAIT_CONFIRM" or "PENDING"
    local priorReason = plan.pauseReason
    plan.pauseReason = nil
    log(self, "soft_pause_clock_extended", {
        reason = priorReason,
        pauseSeconds = pauseSeconds,
        currentStep = plan.stepIndex,
    })
    log(self, "soft_resumed", {
        currentStep = plan.stepIndex,
        pauseSeconds = pauseSeconds,
        recoveryEligible = plan.wait and plan.wait.inventoryRecoveryEligible == true,
    })
end

local function isRuntimePaused(self, runtime, allowPreCombatBridge)
    if self.deadPaused then return true, "player_dead" end
    if self.vehiclePaused then return true, "vehicle_active" end
    local t = now()
    if self.eventPauseUntil and t < self.eventPauseUntil then return true, self.eventPauseReason or "event_revalidation" end
    local effective = runtime and runtime.effectiveState
    if effective and effective ~= "armed" then
        -- Do not turn the default out-of-combat display pause into a global
        -- input permission. Only the already-qualified, front-injection bridge
        -- may continue its own capture/plan through this one internal state.
        if allowPreCombatBridge == true
            and effective == "paused"
            and runtime and runtime.runtimeReason == "out_of_combat_policy_pause" then
            return false, nil
        end
        return true, runtime.runtimeReason or ("runtime_" .. tostring(effective))
    end
    return false, nil
end

local function observeWindowQueueDelivery(plan, step, sample)
    if not (plan and plan.wait and isWindowStep(step)) then return false end
    if plan.wait.phase ~= "QUEUE_WINDOW" or not (sample and sample.phase == "READY_NOW") then return false end
    if plan.wait.queueDeliveryContinuesLogged == true then return false end
    plan.wait.queueDeliveryContinuesLogged = true
    return true
end

local function startInventoryRecovery(self, plan, step, reason)
    local wait = plan and plan.wait
    if not (wait and isRecoverableInventoryInjection(plan, step)) then return false end
    local t = now()
    if wait.inventoryRecoveryActive == true then
        return true
    end
    wait.inventoryRecoveryActive = true
    wait.inventoryRecoveryPersistent = true
    wait.inventoryRecoveryStartedAt = t
    -- Retain the legacy field only as a first-observation milestone. It is not
    -- consulted as a deadline and never ends the sequence.
    wait.inventoryRecoveryDeadlineAt = t + INVENTORY_RECOVERY_SECONDS
    wait.inventoryRecoveryReason = reason
    log(self, "inventory_recovery_started", {
        role = step.role,
        inventorySlot = inventorySlot(step.inventorySlot),
        itemID = positiveItemID(step.expectedItemID),
        reason = reason,
        currentStep = plan.stepIndex,
        recoverySeconds = INVENTORY_RECOVERY_SECONDS,
        persistent = true,
    })
    -- Keep the original baseline. A delayed slot refresh or a player-manual
    -- supplemental `/use 13|14` produces the exact non-GCD own-CD transition
    -- required by confirmed(sample, baseline), then advances to the window.
    return true
end

local function skipOptionalStep(self, plan, step, reason)
    if not (plan and isOptionalStep(step)) then return holdResult(plan, "sequence_optional_step_invalid") end
    log(self, "sequence_optional_step_skipped", {
        role = step.role, key = step.key, category = step.category,
        actionKind = stepKind(step),
        spellID = stepKind(step) == "spell" and positiveSpellID(step.spellID) or nil,
        inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
        itemID = stepKind(step) == "inventory" and positiveItemID(step.expectedItemID) or nil,
        reason = reason, currentStep = plan.stepIndex,
    })
    -- Retain the legacy diagnostic event name for existing mapping readers.
    log(self, "injection_skipped", {
        phase = reason, reason = reason, currentStep = plan.stepIndex,
        preInjectionSkipStatus = plan.preInjectionSkipStatus,
        cooldownConfirmations = type(plan.preInjectionCooldownConfirmation) == "table"
            and number(plan.preInjectionCooldownConfirmation.count) or nil,
    })
    plan.revalidate = nil
    plan.candidateOfferCount = 0
    plan.candidateFirstOfferedAt = nil
    plan.candidateLastOfferedAt = nil
    plan.stepIndex = plan.stepIndex + 1
    if plan.stepIndex > #plan.steps then
        log(self, "plan_completed", { reason = reason })
        lockWindowDeparture(self, plan)
        self.plan = nil
        return terminalResult(self, reason, {
            windowSpellID = plan.rule.windowSpellID,
            injectionSpellID = plan.rule.injectionSpellID,
            ruleSource = plan.rule.source,
            ruleId = plan.rule.id,
        })
    end
    return holdResult(plan, "burst_next_step_pending")
end

-- An official window observed on its own non-GCD cooldown before AutoBurst
-- has ever sent it is a rule-level skip, not a confirmation failure. In post
-- mode this must end the plan without attempting the post-window injection.
local function completePlanForWindowOwnCooldown(self, plan, reason)
    log(self, "window_skipped_own_cooldown", {
        planId = plan.id,
        currentStep = plan.stepIndex,
        direction = plan.rule.direction,
        reason = reason or "window_own_cooldown_observed",
    })
    log(self, "plan_completed", { reason = reason or "window_own_cooldown_observed" })
    lockWindowDeparture(self, plan)
    self.plan = nil
    return terminalResult(self, reason or "window_own_cooldown_observed", {
        windowSpellID = plan.rule.windowSpellID,
        injectionSpellID = plan.rule.injectionSpellID,
        ruleSource = plan.rule.source,
        ruleId = plan.rule.id,
    })
end

local function finishStep(self, plan, source)
    local step = plan.steps[plan.stepIndex]
    self.lastConfirmationSource = source
    plan.completed[#plan.completed + 1] = step.role
    plan.wait = nil
    plan.revalidate = nil
    plan.candidateOfferCount = 0
    plan.candidateFirstOfferedAt = nil
    plan.candidateLastOfferedAt = nil
    plan.stepIndex = plan.stepIndex + 1
    plan.state = "PENDING"
    log(self, "step_confirmed", {
        role = step.role,
        actionKind = stepKind(step),
        spellID = stepKind(step) == "spell" and step.spellID or nil,
        inventorySlot = stepKind(step) == "inventory" and step.inventorySlot or nil,
        itemID = stepKind(step) == "inventory" and step.expectedItemID or nil,
        confirmation = source,
        currentStep = plan.stepIndex - 1,
    })
    if plan.stepIndex > #plan.steps then
        log(self, "plan_completed", { reason = "all_steps_confirmed" })
        lockWindowDeparture(self, plan)
        self.plan = nil
        return terminalResult(self, "all_steps_confirmed", {
            windowSpellID = plan.rule.windowSpellID,
            injectionSpellID = plan.rule.injectionSpellID,
            ruleSource = plan.rule.source,
            ruleId = plan.rule.id,
        })
    end
    return nil
end

-- A plan may react to an optional sequence step becoming unavailable after
-- preflight but before confirmation. Simple mode skips only that optional step;
-- focused mode terminates the all-or-nothing sequence.
-- It intentionally does not use failure events as evidence and never locks the
-- window departure: SignalFrame may continue the official window normally.
local function releasePlanForInjectionUnavailable(self, plan, step, sample, reason)
    if not (self and self.plan == plan and isOptionalStep(step)) then return nil end
    local phase = type(sample) == "table" and sample.phase or nil
    local why = reason or (type(sample) == "table" and sample.reason) or "optional_step_unavailable"
    self.lastSequencePreflight = {
        status = "runtime_optional_unavailable", elapsed = now(), ruleId = plan.rule and plan.rule.id or nil,
        phase = phase, reason = why, key = step.key, role = step.role,
        spellID = stepKind(step) == "spell" and positiveSpellID(step.spellID) or nil,
        inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
        dispatchAttempt = plan.dispatchAttempt or 0,
        cooldownUncertain = type(sample) == "table" and sample.cooldownUncertain == true or false,
    }
    self.lastInjectionPreflight = self.lastSequencePreflight
    if plan.rule and plan.rule.mode == "simple" then
        return skipOptionalStep(self, plan, step, why)
    end
    self.lastAbortReason = "focused_optional_step_unavailable"
    local windowAlreadyDispatched = plan.windowDispatchAttempted == true
    log(self, "plan_aborted", {
        reason = "focused_optional_step_unavailable", detail = why, currentStep = plan.stepIndex,
        role = step.role, key = step.key, phase = phase,
        windowAlreadyDispatched = windowAlreadyDispatched,
    })
    -- Focused mode is all-or-nothing at plan build time.  A later runtime
    -- drift is still fail-safe, but it must not consume an untouched official
    -- window merely because an optional step became opaque after preflight.
    -- Once the window itself has been offered, retain the ordinary departure
    -- lock; before that point release it to the official recommendation.
    if windowAlreadyDispatched then lockWindowDeparture(self, plan) end
    self.activePlanGeneration = nil
    self.plan = nil
    return terminalResult(self, "focused_optional_step_unavailable", {
        windowSpellID = plan.rule and plan.rule.windowSpellID or nil,
        ruleSource = plan.rule and plan.rule.source or nil,
        ruleId = plan.rule and plan.rule.id or nil,
        officialWindowReleased = not windowAlreadyDispatched,
    })
end

local function createPlan(self, rule, officialSpellID, creation)
    creation = type(creation) == "table" and creation or {}
    local t = now()
    local steps = sequenceFor(rule)
    -- The configured slot is not enough: lock the currently equipped ItemID
    -- before the plan exists.  A later gear change or macro/button mismatch
    -- fails closed rather than continuing to press `/use 13` for a new trinket.
    for _, step in ipairs(steps) do
        if stepKind(step) == "inventory" then
            local bindingInfo, bindingState, bindingReason = resolveStepBinding(step)
            if bindingState then return nil, bindingReason or bindingState end
            local itemID = positiveItemID(bindingInfo and (bindingInfo.itemID or bindingInfo.expectedItemID))
            if not itemID then return nil, "inventory_item_missing" end
            step.expectedItemID = itemID
        end
    end
    local sequenceKeys = {}
    for _, step in ipairs(steps) do sequenceKeys[#sequenceKeys + 1] = step.key or step.role end
    local plan = {
        id = self.nextPlanId,
        rule = rule,
        officialSpellID = officialSpellID,
        windowGeneration = number(creation.windowGeneration) or number(self.windowGeneration) or 0,
        armedEpoch = self.armedEpoch or 0,
        -- The bridge origin is frozen with the plan. It is not inferred from
        -- later combat state, so an in-combat plan can never become eligible
        -- for out-of-combat dispatch merely because combat ended.
        preCombatBridge = creation.preCombatBridge == true,
        preCombatBridgeEnteredCombat = false,
        createdAt = t,
        -- No outer plan timeout: valid dispatchable steps persist until an
        -- explicit terminal fact occurs. This field remains nil for legacy
        -- diagnostics / pause extension compatibility only.
        deadlineAt = nil,
        steps = steps,
        stepIndex = 1,
        state = "PENDING",
        completed = {},
        windowDispatchAttempted = false,
        dispatchAttempt = 0,
        pauseStartedAt = nil,
        wait = nil,
        revalidate = nil,
        candidateOfferCount = 0,
        candidateFirstOfferedAt = nil,
        candidateLastOfferedAt = nil,
        initialWindowPhase = creation.initialWindowPhase,
        initialWindowReason = creation.initialWindowReason,
        windowAvailabilityConflict = creation.windowAvailabilityConflict == true,
        windowAvailabilityConflictReason = creation.windowAvailabilityConflictReason,
        windowAvailabilityConflictResolvedAt = nil,
        windowAvailabilityConflictLogged = false,
        windowCooldownConfirmation = nil,
        officialDepartureObserved = false,
        officialDepartureObservedAt = nil,
        preInjectionRequired = creation.preInjectionRequired == true,
        preInjectionSkipAllowed = false,
        preInjectionSkipStatus = creation.preInjectionSkipStatus or "not_applicable",
        preInjectionCooldownConfirmation = creation.preInjectionCooldownConfirmation,
        initialInjectionPhase = creation.initialInjectionPhase,
        initialInjectionReason = creation.initialInjectionReason,
        injectionPreflight = shallowCopy(creation.injectionPreflight),
        -- Keep the exact creation-time ordered preflight with the plan.  This
        -- is diagnostic only; runtime revalidation still reads every optional
        -- step live before it can be dispatched.
        sequencePreflight = shallowCopy(creation.sequencePreflight),
        sequenceLength = #steps,
        sequenceKeys = table.concat(sequenceKeys, ">"),
        -- Handoff is transport-only. It never advances a logical step and does
        -- not reset confirmation/skip evidence once injection begins.
        handoffBarrierRequiredFrames = math.max(0, math.floor(number(creation.handoffBarrierRequiredFrames) or 0)),
        handoffBarrierRemainingFrames = math.max(0, math.floor(number(creation.handoffBarrierRemainingFrames) or 0)),
        handoffBarrierPublishedFrames = math.max(0, math.floor(number(creation.handoffBarrierPublishedFrames) or 0)),
        handoffBarrierPending = math.max(0, math.floor(number(creation.handoffBarrierRemainingFrames) or 0)) > 0,
    }
    self.nextPlanId = self.nextPlanId + 1
    self.plan = plan
    self.activePlanGeneration = plan.windowGeneration
    self.lastAbortReason = nil
    self.lastConfirmationSource = nil
    self.lastWindowRejectReason = nil
    log(self, "plan_created", {
        direction = rule.direction, mode = rule.mode, officialSpellID = officialSpellID,
        injectionKind = rule.injectionKind or "spell", injectionTrinketSlot = rule.injectionTrinketSlot,
        injectionItemID = plan.steps[1] and stepKind(plan.steps[1]) == "inventory" and plan.steps[1].expectedItemID or nil,
        sequenceLength = #plan.steps,
        sequenceKeys = plan.sequenceKeys,
        preCombatBridge = plan.preCombatBridge == true,
        windowAvailabilityConflict = plan.windowAvailabilityConflict == true,
        windowAvailabilityConflictReason = plan.windowAvailabilityConflictReason,
    })
    return plan, nil
end

local function isDispatchablePhase(phase)
    return phase == "READY_NOW" or phase == "QUEUE_WINDOW" or phase == "GCD_LOCKED"
end

-- Optional-step selection happens before a Burst plan claims the official
-- window. A selected step must have a current binding and a positive own-ready
-- cooldown result. Shared GCD (READY/QUEUE/GCD_LOCKED) remains eligible; own
-- CD, opaque/UNKNOWN cooldown and invalid equipment/binding are excluded.
-- Simple mode removes each excluded optional step. Focused mode refuses the
-- whole sequence when any enabled optional step is not eligible.
local function selectedRuleForSequence(rule, selectedSteps)
    local selected = {}
    for key, value in pairs(rule or {}) do selected[key] = value end
    selected.steps = selectedSteps
    selected.optionalStepCount = 0
    selected.injectionSpellID = nil
    for _, step in ipairs(selectedSteps or {}) do
        if isOptionalStep(step) then
            selected.optionalStepCount = selected.optionalStepCount + 1
            if not selected.injectionSpellID and stepKind(step) == "spell" then
                selected.injectionSpellID = positiveSpellID(step.spellID)
            end
        end
    end
    selected.requiresPreWindowCapture = selectedSteps[1] and not isWindowStep(selectedSteps[1]) or false
    selected.direction = selected.requiresPreWindowCapture and "pre" or "window_first"
    return selected
end

local function preflightSequence(self, rule, cycle)
    local selected, excluded = {}, {}
    local configuredOptional, selectedOptional = 0, 0
    for index, step in ipairs(sequenceFor(rule)) do
        if isWindowStep(step) then
            selected[#selected + 1] = step
        elseif isOptionalStep(step) then
            configuredOptional = configuredOptional + 1
            local sample = stepSample(step, cycle)
            rememberStepObservation(self, nil, step, sample, "plan_gate_sequence_preflight")
            local phase = sample and sample.phase or "UNKNOWN"
            local eligible = isDispatchablePhase(phase) and sample.cooldownUncertain ~= true
            if eligible then
                selected[#selected + 1] = step
                selectedOptional = selectedOptional + 1
            else
                excluded[#excluded + 1] = {
                    index = index, key = step.key, role = step.role, category = step.category,
                    phase = phase, reason = sample and sample.reason or "sample_missing",
                    cooldownUncertain = sample and sample.cooldownUncertain == true or false,
                    spellID = stepKind(step) == "spell" and positiveSpellID(step.spellID) or nil,
                    inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
                }
            end
        end
    end

    local firstExcluded = excluded[1] or {}
    local status = "selected"
    local reason
    if configuredOptional <= 0 then
        status, reason = "none_ready", "sequence_no_optional_steps"
    elseif selectedOptional <= 0 then
        status, reason = "none_ready", "sequence_no_eligible_optional_steps"
    elseif rule.mode == "focused" and #excluded > 0 then
        status, reason = "none_ready", "focused_optional_step_unavailable"
    end
    local diagnostic = {
        status = status, reason = reason, ruleId = rule and rule.id or nil, elapsed = now(),
        configuredOptionalCount = configuredOptional, selectedOptionalCount = selectedOptional,
        excluded = excluded, excludedCount = #excluded,
        firstExcludedPhase = firstExcluded.phase, firstExcludedReason = firstExcluded.reason,
        firstExcludedCooldownUncertain = firstExcluded.cooldownUncertain == true,
        firstExcludedSpellID = firstExcluded.spellID, firstExcludedInventorySlot = firstExcluded.inventorySlot,
        selectedKeys = {},
    }
    for _, step in ipairs(selected) do diagnostic.selectedKeys[#diagnostic.selectedKeys + 1] = step.key or step.role end
    local excludedKeys = {}
    for _, entry in ipairs(excluded) do excludedKeys[#excludedKeys + 1] = entry.key or entry.role end
    -- Mapping export intentionally keeps diagnostics scalar-only. Preserve the
    -- resolved order in compact text so the saved trace can show exactly which
    -- steps survived CD/GCD preflight without serializing raw binding objects.
    diagnostic.selectedOrder = table.concat(diagnostic.selectedKeys, ">")
    diagnostic.excludedOrder = table.concat(excludedKeys, ">")
    self.lastSequencePreflight = diagnostic
    self.lastInjectionPreflight = diagnostic

    if status ~= "selected" then
        log(self, "sequence_preflight_no_eligible", {
            ruleId = rule and rule.id or nil, reason = reason,
            configuredOptionalCount = configuredOptional, selectedOptionalCount = selectedOptional,
            excludedCount = #excluded, firstExcludedPhase = firstExcluded.phase,
            firstExcludedKey = firstExcluded.key, firstExcludedRole = firstExcluded.role,
            firstExcludedReason = firstExcluded.reason,
            firstExcludedSpellID = firstExcluded.spellID,
            firstExcludedInventorySlot = firstExcluded.inventorySlot,
            selectedOrder = diagnostic.selectedOrder, excludedOrder = diagnostic.excludedOrder,
        })
        -- Keep the legacy event name in diagnostics for existing importers.
        log(self, "injection_preflight_no_eligible", {
            ruleId = rule and rule.id or nil, excludedCount = #excluded,
            firstExcludedPhase = firstExcluded.phase, firstExcludedKey = firstExcluded.key,
            firstExcludedReason = firstExcluded.reason, reason = reason,
            selectedOrder = diagnostic.selectedOrder, excludedOrder = diagnostic.excludedOrder,
        })
        return nil, diagnostic
    end

    local selectedRule = selectedRuleForSequence(rule, selected)
    diagnostic.ruleId = selectedRule.id
    diagnostic.requiresPreWindowCapture = selectedRule.requiresPreWindowCapture == true
    log(self, "sequence_preflight_selected", {
        ruleId = selectedRule.id, selectedOptionalCount = selectedOptional,
        excludedCount = #excluded, requiresPreWindowCapture = selectedRule.requiresPreWindowCapture == true,
        selectedOrder = diagnostic.selectedOrder, excludedOrder = diagnostic.excludedOrder,
        firstExcludedKey = firstExcluded.key, firstExcludedRole = firstExcluded.role,
        firstExcludedReason = firstExcluded.reason,
    })
    log(self, "injection_preflight_selected", {
        ruleId = selectedRule.id, selectedOptionalCount = selectedOptional,
        excludedCount = #excluded, selectedOrder = diagnostic.selectedOrder,
        excludedOrder = diagnostic.excludedOrder,
    })
    return selectedRule, diagnostic
end

-- The official recommendation is an independent, read-only window anchor.  A
-- transient cooldown sample that conflicts with that exact official window must
-- not throw away the only edge before a front injection can be attempted.  The
-- conflict is *not* treated as ready: the plan retains ownership and later
-- revalidates the window before it can publish the window BindingToken.
local function isOfficialWindowAvailabilityConflict(sample)
    return type(sample) == "table" and (sample.phase == "COOLDOWN" or sample.phase == "UNKNOWN")
end

local function canCreateFocused(rule, cycle, windowSample)
    for _, step in ipairs(sequenceFor(rule)) do
        local sample = isWindowStep(step) and windowSample or stepSample(step, cycle)
        if isWindowStep(step) and isOfficialWindowAvailabilityConflict(sample) then
            -- The actual candidate is withheld until later readiness is proven.
        elseif not isDispatchablePhase(sample and sample.phase) then
            return false, sample and sample.phase or "UNKNOWN", sample and sample.reason or "focused_step_sample_missing"
        end
    end
    return true, nil, nil
end

function AutoBurst:Evaluate(official, runtime)
    runtime = type(runtime) == "table" and runtime or {}
    local settings = tactics()
    local officialSpellID = official and positiveSpellID(official.spellID) or nil
    local previousOfficialSpellID = self.lastOfficialSpellID
    local intentState = runtime.intentState
    local enteredArmed = intentState == "armed" and self.lastIntentState ~= "armed"
    -- A nil prior state is startup observation, not a paused -> armed restart.
    -- The cross-process handoff barrier is required only after TEK/AddOn have
    -- already observed a real non-armed epoch that may have left a visible
    -- official-window frame on screen.
    local rearmedFromNonArmed = enteredArmed and self.lastIntentState ~= nil

    if enteredArmed then
        self.armedEpoch = (self.armedEpoch or 0) + 1
        self.firstHealthyFramePending = true
        -- A pending front-window capture must create a fresh observation
        -- barrier for each explicit paused -> armed epoch. The following
        -- dispatchable frame is therefore guaranteed to be newer than an
        -- authenticated no-token handoff frame.
        if rearmedFromNonArmed and type(self.preWindowCapture) == "table" then
            resetHandoffBarrier(self.preWindowCapture, PRE_WINDOW_HANDOFF_MIN_HOLD_FRAMES)
            self.preWindowCapture.armedEpoch = self.armedEpoch
        end
        log(self, "armed_epoch_started", {
            armedEpoch = self.armedEpoch,
            officialSpellID = officialSpellID,
        })

        -- While paused, official recommendation updates continue for HUD/TEAP
        -- display. If the first armed frame is already the same visible window,
        -- that inherited `lastOfficialSpellID/currentWindowSpellID` must not
        -- suppress the new armed epoch. Rebase only when no plan/departure lock
        -- owns the old generation; a consumed window remains non-reacquirable.
        if not self.plan and self.requireWindowDeparture ~= true then
            local priorOfficialSpellID = self.lastOfficialSpellID
            local priorWindowSpellID = self.currentWindowSpellID
            local priorWindowGeneration = self.windowGeneration or 0
            self.lastOfficialSpellID = nil
            self.currentWindowSpellID = nil
            self.activePlanGeneration = nil
            previousOfficialSpellID = nil
            self.lastArmedRebase = {
                schema = 1,
                elapsed = now(),
                armedEpoch = self.armedEpoch,
                officialSpellID = officialSpellID,
                priorOfficialSpellID = priorOfficialSpellID,
                priorWindowSpellID = priorWindowSpellID,
                priorWindowGeneration = priorWindowGeneration,
                reason = "paused_to_armed_observation_rebase",
            }
            log(self, "armed_window_observation_rebased", self.lastArmedRebase)
        end
    end

    if self.lastOfficialSpellID ~= officialSpellID then
        self.lastOfficialSpellID = officialSpellID
        if self.requireWindowDeparture and officialSpellID ~= self.lockedWindowSpellID then
            log(self, "window_departed", { spellID = self.lockedWindowSpellID })
            self.requireWindowDeparture = false
            self.lockedWindowSpellID = nil
            self.preCombatBridgeDepartureLock = false
            self.departureLockGeneration = nil
        end
        if self.currentWindowSpellID and officialSpellID ~= self.currentWindowSpellID then
            self.currentWindowSpellID = nil
        end
    end

    self.lastIntentState = intentState

    if settings.autoBurstEnabled ~= true then
        if self.plan or self.preWindowCapture then self:Abort("auto_burst_disabled", false) end
        recordDecision(self, "idle", "auto_burst_disabled", { officialSpellID = officialSpellID })
        return noneResult()
    end
    -- The existing SignalFrame armed intent is the independent “自动运行”
    -- gate.  AutoBurst cannot start merely because its own checkbox is on.
    if runtime.intentState ~= "armed" then
        if self.plan then self:SoftPause("auto_run_not_armed") end
        recordDecision(self, self.plan and "paused" or "idle", "auto_run_not_armed", { officialSpellID = officialSpellID })
        return self.plan and holdResult(self.plan, "auto_run_not_armed") or noneResult()
    end

    local context = runtime.context or (TE.Context and TE.Context:GetPlayer()) or {}
    local rule, ruleReason = profileRule(context)
    if not rule then
        if self.plan or self.preWindowCapture then self:Abort(ruleReason, false) end
        recordDecision(self, "idle", ruleReason or "rule_unavailable", { officialSpellID = officialSpellID })
        return noneResult()
    end

    if self.plan and self.plan.rule.id ~= rule.id then
        self:Abort("rule_changed", false)
        return terminalResult(self, "rule_changed", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
    end

    local inCombat = isInCombat(runtime)
    local worldTransitionPreCombatFence = self.preCombatBridgeWorldFence == true
    local preCombatBridge = not inCombat and not worldTransitionPreCombatFence and (
        hasPreCombatBridgeOwner(self)
        or self.preCombatBridgeDepartureLock == true
        or canStartPreCombatBridge(self, rule, officialSpellID, runtime)
    )
    if not inCombat and not preCombatBridge then
        if worldTransitionPreCombatFence then
            -- A transition event normally clears this state first.  Preserve a
            -- fail-closed fallback for an event/refresh race without installing
            -- an ordinary departure lock against the next legitimate opener.
            if self.plan or self.preWindowCapture then
                self:ActivateWorldTransitionFence("evaluate_fence")
            end
            recordDecision(self, "idle", "world_transition_precombat_fenced", {
                officialSpellID = officialSpellID,
                worldTransitionEpoch = self.worldTransitionEpoch or 0,
            })
            return noneResult()
        end
        self:Abort("out_of_combat", true)
        recordDecision(self, "idle", "out_of_combat", { officialSpellID = officialSpellID })
        return noneResult()
    end

    local paused, pauseReason = isRuntimePaused(self, runtime, preCombatBridge)
    if paused then
        self:SoftPause(pauseReason)
        recordDecision(self, self.plan and "paused" or "idle", pauseReason or "runtime_paused", { officialSpellID = officialSpellID })
        return self.plan and holdResult(self.plan, pauseReason) or noneResult()
    end

    local firstHealthyFramePending = self.firstHealthyFramePending == true
    self.firstHealthyFramePending = false

    -- A completed/aborted plan must not reacquire the same still-visible window
    -- recommendation.  This internal suppression is evaluated only after the
    -- real auto-run and runtime gates, so Start/Pause always retains its normal
    -- meaning and cannot be masked by an old burst lock.
    if self.requireWindowDeparture and officialSpellID == self.lockedWindowSpellID then
        -- Do not re-send a just-consumed window while the official API still
        -- presents its old recommendation. This is observation-only; the HUD
        -- receives the official display binding from SignalFrame.
        recordDecision(self, "hold", "await_window_departure", { officialSpellID = officialSpellID, windowSpellID = self.lockedWindowSpellID })
        return holdResult(nil, "burst_await_window_departure", {
            preCombatBridge = self.preCombatBridgeDepartureLock == true,
        })
    end

    -- Resolve a pending pre-window capture before constructing the next plan.
    -- It exists only to prevent a configured front window from falling through
    -- to ordinary official dispatch while bindings or public samples settle.
    local capture = self.preWindowCapture
    if type(capture) == "table" then
        if not capture.rule or capture.rule.id ~= rule.id then
            releasePreWindowCapture(self, "rule_changed_before_plan")
            capture = nil
        elseif capture.officialSpellID ~= rule.windowSpellID then
            releasePreWindowCapture(self, "capture_window_rule_mismatch")
            capture = nil
        elseif officialSpellID ~= capture.officialSpellID then
            -- Capture is intentionally not a hidden plan. If the official
            -- anchor leaves before a real plan exists, release ownership and
            -- let the new ordinary recommendation proceed normally.
            releasePreWindowCapture(self, "official_window_departed_before_plan")
            capture = nil
        end
    end

    local cycle = TE.GCDGate and TE.GCDGate:BeginCycle(runtime.primary) or { phase = "UNKNOWN" }
    if not self.plan then
        if not officialSpellID or officialSpellID ~= rule.windowSpellID then
            if capture then
                releasePreWindowCapture(self, "official_not_window")
                capture = nil
            end
            self.lastWindowRejectReason = "official_not_window"
            recordDecision(self, "armed", "official_not_window", {
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
            })
            return noneResult()
        end

        -- A window plan is generation-triggered. A capture keeps its existing
        -- generation while bindings / snapshots settle; otherwise a real edge
        -- or first healthy armed frame creates the next generation.
        local windowEntry, windowReason
        if capture then
            windowEntry = true
            windowReason = "pre_window_capture_revalidate"
            self.currentWindowSpellID = officialSpellID
            if number(capture.windowGeneration) and number(capture.windowGeneration) > 0 then
                self.windowGeneration = number(capture.windowGeneration)
            end
        else
            windowEntry, windowReason = observeWindowFrame(self, officialSpellID, rule, previousOfficialSpellID, firstHealthyFramePending)
        end
        if not windowEntry and not capture and rule.requiresPreWindowCapture == true
            and officialSpellID == rule.windowSpellID and self.requireWindowDeparture ~= true then
            -- The official window can already be visible when the first armed
            -- observation arrives (for example after a pause or during a Boss
            -- pull). Preserve the verified recovery behavior: claim only an
            -- observation-only capture here; real optional-step eligibility is
            -- still decided by preflight below before any plan is created.
            self.windowGeneration = (self.windowGeneration or 0) + 1
            capture = beginPreWindowCapture(
                self, rule, officialSpellID, self.windowGeneration,
                "pre_window_capture_recover:window_edge_missing", rearmedFromNonArmed, preCombatBridge
            )
            windowEntry = true
            windowReason = "pre_window_capture_recover:window_edge_missing"
        end
        if not windowEntry then
            self.lastWindowRejectReason = windowReason or "window_edge_missing"
            recordDecision(self, "armed", windowReason or "window_edge_missing", {
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
            })
            return noneResult()
        end

        -- Build the *actual* sequence only after the window is observed. This
        -- preflight is intentionally earlier than plan creation: optional steps
        -- already on own CD, unknown, unbound or equipment-mismatched never enter
        -- the plan, so no later retry loop can trap the window behind them.
        local selectedRule, sequencePreflight = preflightSequence(self, rule, cycle)
        if not selectedRule then
            self.lastWindowRejectReason = "burst_sequence_preflight_unavailable"
            recordDecision(self, "armed", "burst_sequence_preflight_unavailable", {
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
                excludedCount = sequencePreflight and sequencePreflight.excludedCount or 0,
            })
            if capture then releasePreWindowCapture(self, "sequence_preflight_unavailable") end
            return noneResult()
        end
        rule = selectedRule

        -- A pre-combat bridge is deliberately limited to sequences that really
        -- have an optional step before the official window after preflight.
        if not inCombat and rule.requiresPreWindowCapture ~= true then
            if capture then releasePreWindowCapture(self, "precombat_sequence_window_first") end
            self.lastWindowRejectReason = "precombat_sequence_window_first"
            return noneResult()
        end

        if rule.requiresPreWindowCapture == true and not capture then
            capture = beginPreWindowCapture(
                self, rule, officialSpellID, self.windowGeneration,
                windowReason or "official_window_edge", rearmedFromNonArmed, preCombatBridge
            )
        elseif capture and rule.requiresPreWindowCapture ~= true then
            -- A previously captured front step may have been excluded by the
            -- current CD preflight, leaving window-first ordering. Do not retain
            -- an unnecessary handoff barrier in that case.
            releasePreWindowCapture(self, "sequence_window_first_after_preflight")
            capture = nil
        end

        local creation = {
            windowGeneration = self.windowGeneration,
            preCombatBridge = (capture and capture.preCombatBridge == true) or (preCombatBridge == true and rule.requiresPreWindowCapture == true),
            injectionPreflight = shallowCopy(self.lastInjectionPreflight),
            sequencePreflight = shallowCopy(self.lastSequencePreflight),
            preInjectionRequired = rule.requiresPreWindowCapture == true,
            preInjectionSkipAllowed = false,
            preInjectionSkipStatus = "sequence_preflight_ready",
            preInjectionCooldownConfirmation = nil,
        }
        if capture then copyHandoffBarrier(capture, creation) end

        local bindingsReady, blockedStep, bindingPhase, bindingReason = validateRuleBindings(self, rule)
        if not bindingsReady then
            log(self, "plan_rejected", {
                reason = bindingReason or bindingPhase, role = blockedStep and blockedStep.role,
                mode = rule.mode,
            })
            recordDecision(self, "armed", "burst_binding_not_ready", {
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
            })
            if capture then
                return continuePreWindowCapture(self, capture, "pre_window_capture_binding_pending", { detail = bindingReason or bindingPhase }, runtime)
            end
            return noneResult()
        end

        local windowStep = { key = "window", role = "window", category = "window", kind = "spell", spellID = rule.windowSpellID }
        local windowSample = stepSample(windowStep, cycle)
        rememberStepObservation(self, nil, windowStep, windowSample, "plan_gate_window")
        creation.initialWindowPhase = windowSample.phase
        creation.initialWindowReason = windowSample.reason
        creation.windowAvailabilityConflict = isOfficialWindowAvailabilityConflict(windowSample)
        creation.windowAvailabilityConflictReason = creation.windowAvailabilityConflict
            and ("official_window_" .. tostring(windowSample.phase):lower() .. "_conflict") or nil

        if creation.windowAvailabilityConflict then
            log(self, "plan_gate_window_official_cooldown_conflict", {
                phase = windowSample.phase, reason = windowSample.reason, mode = rule.mode,
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
            })
        elseif not isDispatchablePhase(windowSample.phase) then
            log(self, "plan_rejected", { reason = windowSample.reason or windowSample.phase, mode = rule.mode })
            recordDecision(self, "armed", "burst_window_not_ready", {
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
            })
            if capture then
                return continuePreWindowCapture(self, capture, "pre_window_capture_window_pending", { detail = windowSample.reason or windowSample.phase }, runtime)
            end
            return noneResult()
        end

        local createdPlan, createReason = createPlan(self, rule, officialSpellID, creation)
        if not createdPlan then
            log(self, "plan_rejected", { reason = createReason or "plan_create_failed", role = "sequence", actionKind = "ordered" })
            recordDecision(self, "armed", "burst_plan_create_failed", {
                officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
            })
            if capture then
                return continuePreWindowCapture(self, capture, "pre_window_capture_plan_pending", { detail = createReason or "plan_create_failed" }, runtime)
            end
            return noneResult()
        end
        if capture then releasePreWindowCapture(self, "plan_created", { detail = "plan:" .. tostring(createdPlan.id) }) end
        recordDecision(self, "plan_created", windowReason or "official_window_edge", {
            officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID,
            injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id,
        })
    end

    local plan = self.plan
    if not plan then return noneResult() end
    -- Complete a multi-frame ownership epoch before publishing injection. The
    -- delay is expressed solely as authenticated fresh TEAP observation frames;
    -- no gameplay/GCD timer or Burst-specific dispatch cadence is introduced.
    local hadHandoffBarrier = handoffBarrierRemaining(plan) > 0
    local handoffBarrier = false
    if hadHandoffBarrier and isTransportHandoffTick(runtime) then
        handoffBarrier = consumeHandoffBarrierFrame(plan)
    end
    if hadHandoffBarrier then
        if handoffBarrier then
            log(self, "pre_window_capture_handoff_barrier", handoffBarrierLogFields(plan, {
                planId = plan.id,
                ruleId = plan.rule and plan.rule.id or nil,
                officialSpellID = plan.officialSpellID,
                windowSpellID = plan.rule and plan.rule.windowSpellID or nil,
                windowGeneration = plan.windowGeneration,
                armedEpoch = plan.armedEpoch,
                reason = "plan_ready_before_injection_dispatch",
                phase = "plan",
            }))
            if handoffBarrierRemaining(plan) == 0 then
                log(self, "pre_window_capture_handoff_ready", handoffBarrierLogFields(plan, {
                    planId = plan.id,
                    ruleId = plan.rule and plan.rule.id or nil,
                    officialSpellID = plan.officialSpellID,
                    windowGeneration = plan.windowGeneration,
                    armedEpoch = plan.armedEpoch,
                    phase = "plan",
                }))
            end
        end
        recordDecision(self, "hold", "pre_window_capture_handoff_barrier", {
            officialSpellID = officialSpellID,
            windowSpellID = plan.rule and plan.rule.windowSpellID or nil,
            injectionSpellID = plan.rule and plan.rule.injectionSpellID or nil,
            ruleSource = plan.rule and plan.rule.source or nil,
            ruleId = plan.rule and plan.rule.id or nil,
            state = plan.state,
        })
        return holdResult(plan, "pre_window_capture_handoff_barrier")
    end
    -- Resume before evaluating a live plan so a non-dispatchable pause
    -- preserves the confirmation/recovery diagnostic clocks and the first
    -- healthy frame can continue the same logical step.
    if plan.state == "SOFT_PAUSED" then
        self:ResumeIfPossible()
        plan = self.plan
        if not plan then return noneResult() end
    end
    -- There is deliberately no outer plan timeout. A healthy, latched step
    -- persists under the shared TEK rate limiter until an explicit result.

    observeLatchedPlanOfficialDeparture(self, plan, officialSpellID, "official_window_departed")

    local step = plan.steps[plan.stepIndex]
    if not step then
        self:Abort("step_missing", false)
        return terminalResult(self, "step_missing", { officialSpellID = officialSpellID })
    end

    if plan.state == "WAIT_CONFIRM" and plan.wait then
        local eventSuccess, eventSource = spellcastEventConfirmed(plan, step)
        if eventSuccess then
            local result = finishStep(self, plan, eventSource)
            if result then return result end
            -- The event may arrive after SignalFrame's earlier listener refresh.
            -- Re-enter once with the next declared step so injection confirmation
            -- does not leave the window card waiting for an unrelated 200ms tick.
            return self:Evaluate(official, runtime)
        end

        observeLatchedPlanOfficialDeparture(self, plan, officialSpellID, "official_window_departed_while_waiting")
        local sample = stepSample(step, cycle)
        rememberStepObservation(self, plan, step, sample, "wait_confirm")
        local success, source = confirmed(sample, plan.wait.baseline)
        if success then
            if plan.wait and plan.wait.inventoryRecoveryActive == true then
                source = "inventory_recovery_" .. tostring(source or "confirmed")
                log(self, "inventory_recovery_completed", {
                    role = step.role,
                    inventorySlot = inventorySlot(step.inventorySlot),
                    itemID = positiveItemID(step.expectedItemID),
                    confirmation = source,
                    currentStep = plan.stepIndex,
                })
            end
            local result = finishStep(self, plan, source)
            if result then return result end
            return self:Evaluate(official, runtime)
        end
        if observeWindowQueueDelivery(plan, step, sample) then
            log(self, "window_queue_delivery_continues", {
                role = step.role,
                spellID = step.spellID,
                currentStep = plan.stepIndex,
                dispatchAttempt = plan.wait and plan.wait.dispatchAttempt,
                waitPhase = plan.wait and plan.wait.phase,
                observedPhase = sample.phase,
            })
        end
        if sample.phase == "PAUSED" then
            self:SoftPause(sample.reason or "step_paused")
            return holdResult(plan, sample.reason or "step_paused")
        end
        if sample.phase == "BLOCKED" or sample.phase == "UNUSABLE" then
            self:Abort(sample.reason or sample.phase, false)
            return terminalResult(self, "burst_wait_confirmation_invalidated", { officialSpellID = officialSpellID, abortReason = sample.reason or sample.phase })
        end
        if isOptionalStep(step) and (sample.phase == "COOLDOWN" or sample.cooldownUncertain == true or sample.phase == "UNKNOWN") then
            return releasePlanForInjectionUnavailable(self, plan, step, sample,
                "injection_unavailable_while_waiting:" .. tostring(sample.reason or sample.phase))
        end
        -- Confirmation grace is diagnostic only. Once it elapses, a pre-window
        -- trinket enters persistent recovery; all other valid steps continue to
        -- re-offer at the normal global dispatch cadence. No retry count, 2.2s
        -- wait, 3.5s recovery or outer plan budget may abort a healthy step.
        if plan.wait.confirmationGraceElapsed ~= true
            and now() >= (number(plan.wait.deadlineAt) or math.huge) then
            plan.wait.confirmationGraceElapsed = true
            log(self, "step_confirmation_grace_elapsed", {
                role = step.role,
                actionKind = stepKind(step),
                spellID = stepKind(step) == "spell" and step.spellID or nil,
                inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
                itemID = stepKind(step) == "inventory" and positiveItemID(step.expectedItemID) or nil,
                currentStep = plan.stepIndex,
                persistent = true,
            })
            startInventoryRecovery(self, plan, step, "confirmation_grace_elapsed")
        end
        if isDispatchablePhase(sample.phase) then
            -- Always use the latest sample. A stale offer sample can retain an
            -- old GCD/slot state and is the source of false retry stalls.
            plan.wait.offerSample = sample
            plan.wait.phase = sample.phase
            return candidateResult(self, plan, step, sample)
        end
        return revalidateUnknownStep(self, plan, step, sample,
            "wait_confirm_" .. tostring(sample.phase):lower() .. ":" .. tostring(sample.reason or "unknown"))
    end

    local sample = stepSample(step, cycle)
    rememberStepObservation(self, plan, step, sample, "step_pending")
    if sample.phase == "PAUSED" then
        self:SoftPause(sample.reason or "step_paused")
        return holdResult(plan, sample.reason or "step_paused")
    end
    if isOptionalStep(step) and (sample.phase == "COOLDOWN" or sample.cooldownUncertain == true or sample.phase == "UNKNOWN") then
        return releasePlanForInjectionUnavailable(self, plan, step, sample,
            "injection_unavailable_before_dispatch:" .. tostring(sample.reason or sample.phase))
    end
    if sample.phase == "GCD_LOCKED" then
        -- Match the ordinary official-recommendation scheduler: an action that
        -- is otherwise ready remains a dispatchable armed candidate during the
        -- public GCD. Fresh TEAP frames may therefore reach TEK at the shared
        -- configured rate, allowing the game to accept/queue the binding when
        -- its normal queue window opens. This is not a confirmation shortcut:
        -- the plan still advances only after exact current-step evidence.
        log(self, "gcd_locked_delivery_continues", {
            role = step.role,
            actionKind = stepKind(step),
            spellID = stepKind(step) == "spell" and step.spellID or nil,
            inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
            currentStep = plan.stepIndex,
        })
    end
    if isWindowStep(step) and plan.windowAvailabilityConflict == true
        and isOfficialWindowAvailabilityConflict(sample) then
        if plan.windowAvailabilityConflictLogged ~= true then
            plan.windowAvailabilityConflictLogged = true
            log(self, "window_official_cooldown_revalidate", {
                phase = sample.phase,
                reason = sample.reason,
                currentStep = plan.stepIndex,
                officialSpellID = officialSpellID,
                windowSpellID = plan.rule.windowSpellID,
                persistent = true,
            })
        end
        -- Continue into the normal COOLDOWN / UNKNOWN handling. COOLDOWN is
        -- allowed to end only after the two-sample exact own-CD certificate;
        -- UNKNOWN remains a non-terminal revalidation state.
    end

    if isWindowStep(step) and plan.windowAvailabilityConflict == true and isDispatchablePhase(sample.phase) then
        plan.windowAvailabilityConflict = false
        plan.windowAvailabilityConflictResolvedAt = now()
        log(self, "window_official_cooldown_resolved", {
            phase = sample.phase,
            reason = sample.reason,
            currentStep = plan.stepIndex,
            officialSpellID = officialSpellID,
            windowSpellID = plan.rule.windowSpellID,
        })
    end

    if sample.phase == "COOLDOWN" then
        if isOptionalStep(step) then
            return releasePlanForInjectionUnavailable(self, plan, step, sample,
                "optional_step_own_cooldown:" .. tostring(sample.reason or sample.phase))
        end
        if isWindowStep(step) and plan.windowDispatchAttempted ~= true then
            local disposition, cooldownReason = confirmWindowOwnCooldown(self, plan, step, sample)
            if disposition == "skip" then
                return completePlanForWindowOwnCooldown(self, plan, cooldownReason or "confirmed_own_cooldown")
            end
            if disposition == "hold" then
                return holdResult(plan, cooldownReason or "window_own_cooldown_confirming")
            end
            return reofferUnconfirmedCooldown(self, plan, step, cycle, sample,
                "window_own_cooldown_unconfirmed:" .. tostring(cooldownReason or sample.reason or sample.phase))
        end
        return reofferUnconfirmedCooldown(self, plan, step, cycle, sample,
            "step_cooldown_unconfirmed:" .. tostring(sample.reason or sample.phase))
    end
    if sample.phase == "UNKNOWN" then
        -- UNKNOWN is not cooldown. It is never a simple-mode skip certificate,
        -- including post injection. Keep sequence ownership and re-sample
        -- persistently; when GCDGate has a public phase, stepSample above
        -- keeps publishing a normal shared-rate candidate instead.
        return revalidateUnknownStep(self, plan, step, sample, "step_unknown:" .. tostring(sample.reason or "unknown"))
    end
    if sample.phase == "UNUSABLE" or sample.phase == "BLOCKED" then
        self:Abort(sample.reason or sample.phase, false)
        return terminalResult(self, "burst_step_blocked", { officialSpellID = officialSpellID, abortReason = sample.reason or sample.phase })
    end
    if sample.phase ~= "READY_NOW" and sample.phase ~= "QUEUE_WINDOW" and sample.phase ~= "GCD_LOCKED" then
        self:Abort("invalid_step_phase:" .. tostring(sample.phase), false)
        return terminalResult(self, "burst_invalid_step_phase", { officialSpellID = officialSpellID, abortReason = sample.phase })
    end

    local dispatchedAt = now()
    plan.revalidate = nil
    plan.candidateOfferCount = 0
    plan.candidateFirstOfferedAt = nil
    plan.candidateLastOfferedAt = nil
    plan.dispatchAttempt = (plan.dispatchAttempt or 0) + 1
    if isWindowStep(step) then plan.windowDispatchAttempted = true end
    plan.state = "WAIT_CONFIRM"
    plan.wait = {
        baseline = confirmationBaseline(sample),
        dispatchedAt = dispatchedAt,
        deadlineAt = dispatchedAt + STEP_CONFIRM_SECONDS,
        offerSample = sample,
        phase = sample.phase,
        dispatchAttempt = plan.dispatchAttempt,
        expectedSpellID = stepKind(step) == "spell" and step.spellID or nil,
        expectedActionKind = stepKind(step),
        expectedInventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
        expectedItemID = stepKind(step) == "inventory" and positiveItemID(step.expectedItemID) or nil,
        spellcastSucceededSpellID = nil,
        spellcastSucceededAt = nil,
        spellcastSucceededMatchKind = nil,
        inventoryRecoveryEligible = false,
        inventoryRecoveryActive = false,
        inventoryRecoveryPersistent = false,
        inventoryRecoveryStartedAt = nil,
        inventoryRecoveryDeadlineAt = nil,
        inventoryRecoveryReason = nil,
        confirmationGraceElapsed = false,
        queueDeliveryContinuesLogged = false,
    }
    log(self, "step_dispatched", {
        role = step.role,
        actionKind = stepKind(step),
        spellID = stepKind(step) == "spell" and step.spellID or nil,
        inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
        itemID = stepKind(step) == "inventory" and positiveItemID(step.expectedItemID) or nil,
        inputPhase = sample.phase,
        dispatchAttempt = plan.dispatchAttempt,
        currentStep = plan.stepIndex,
    })
    recordDecision(self, "candidate", "step_dispatched", {
        officialSpellID = officialSpellID,
        windowSpellID = plan.rule.windowSpellID,
        injectionSpellID = plan.rule.injectionSpellID,
        ruleSource = plan.rule.source,
        ruleId = plan.rule.id,
        state = plan.state,
    })
    return candidateResult(self, plan, step, sample)
end

function AutoBurst:GetSnapshot()
    local plan = self.plan
    local capture = self.preWindowCapture
    local captureActive = type(capture) == "table"
    if not plan then
        return {
            schema = 1,
            active = false,
            requireWindowDeparture = self.requireWindowDeparture == true,
            lockedWindowSpellID = self.lockedWindowSpellID,
            preCombatBridgeDepartureLock = self.preCombatBridgeDepartureLock == true,
            preCombatBridgeWorldFence = self.preCombatBridgeWorldFence == true,
            preCombatBridgeAuthorizationRequiresHandoff = self.preCombatBridgeAuthorizationRequiresHandoff == true,
            worldTransitionEpoch = self.worldTransitionEpoch or 0,
            lastWorldTransition = shallowCopy(self.lastWorldTransition),
            combatEpoch = self.combatEpoch or 0,
            armedEpoch = self.armedEpoch or 0,
            firstHealthyFramePending = self.firstHealthyFramePending == true,
            windowGeneration = self.windowGeneration or 0,
            consumedWindowGeneration = self.consumedWindowGeneration or 0,
            activePlanGeneration = self.activePlanGeneration,
            departureLockGeneration = self.departureLockGeneration,
            currentWindowSpellID = self.currentWindowSpellID,
            preWindowCaptureActive = captureActive,
            preWindowCaptureId = captureActive and number(capture.id) or nil,
            preWindowCaptureRuleId = captureActive and capture.rule and capture.rule.id or nil,
            preWindowCaptureOfficialSpellID = captureActive and positiveSpellID(capture.officialSpellID) or nil,
            preWindowCaptureWindowGeneration = captureActive and number(capture.windowGeneration) or nil,
            preWindowCaptureArmedEpoch = captureActive and number(capture.armedEpoch) or nil,
            preWindowCaptureHandoffBarrierPending = captureActive and capture.handoffBarrierPending == true,
            preWindowCaptureHandoffBarrierRequiredFrames = captureActive and number(capture.handoffBarrierRequiredFrames) or 0,
            preWindowCaptureHandoffBarrierRemainingFrames = captureActive and handoffBarrierRemaining(capture) or 0,
            preWindowCaptureHandoffBarrierPublishedFrames = captureActive and number(capture.handoffBarrierPublishedFrames) or 0,
            preWindowCaptureRetryCount = captureActive and number(capture.retryCount) or 0,
            preWindowCaptureLastReason = captureActive and capture.lastRetryReason or nil,
            preWindowCaptureBridge = captureActive and capture.preCombatBridge == true,
            planState = nil,
            stepState = nil,
            stepStatusReason = self.lastStepObservation and self.lastStepObservation.reason or nil,
            candidateOfferCount = 0,
            preInjectionSkipAllowed = false,
            preInjectionRequired = false,
            preInjectionSkipStatus = nil,
            preInjectionCooldownConfirmations = 0,
            windowCooldownConfirmations = 0,
            officialDepartureObserved = false,
            lastStepObservation = shallowCopy(self.lastStepObservation),
            lastInjectionPreflight = shallowCopy(self.lastInjectionPreflight),
            lastSequencePreflight = shallowCopy(self.lastSequencePreflight),
        }
    end
    local step = plan.steps[plan.stepIndex]
    return {
        schema = 1,
        active = true,
        planId = plan.id,
        ruleId = plan.rule.id,
        direction = plan.rule.direction,
        mode = plan.rule.mode,
        state = plan.state,
        preCombatBridge = plan.preCombatBridge == true,
        preCombatBridgeEnteredCombat = plan.preCombatBridgeEnteredCombat == true,
        currentStep = plan.stepIndex,
        currentRole = step and step.role,
        currentActionKind = stepKind(step),
        currentSpellID = stepKind(step) == "spell" and positiveSpellID(step and step.spellID) or nil,
        currentInventorySlot = stepKind(step) == "inventory" and inventorySlot(step and step.inventorySlot) or nil,
        currentItemID = stepKind(step) == "inventory" and positiveItemID(step and step.expectedItemID) or nil,
        sequenceLength = number(plan.sequenceLength) or #(plan.steps or {}),
        sequenceKeys = plan.sequenceKeys,
        planState = plan.state,
        stepState = plan.state,
        stepStatusReason = plan.pauseReason
            or (plan.revalidate and "revalidating")
            or (plan.wait and plan.wait.phase)
            or (self.lastStepObservation and self.lastStepObservation.reason),
        completed = plan.completed,
        windowDispatchAttempted = plan.windowDispatchAttempted == true,
        preInjectionRequired = plan.preInjectionRequired == true,
        preInjectionSkipAllowed = plan.preInjectionSkipAllowed == true,
        preInjectionSkipStatus = plan.preInjectionSkipStatus,
        preInjectionCooldownConfirmations = type(plan.preInjectionCooldownConfirmation) == "table"
            and number(plan.preInjectionCooldownConfirmation.count) or 0,
        preInjectionCooldownIdentityKey = type(plan.preInjectionCooldownConfirmation) == "table"
            and plan.preInjectionCooldownConfirmation.identityKey or nil,
        windowCooldownConfirmations = type(plan.windowCooldownConfirmation) == "table"
            and number(plan.windowCooldownConfirmation.count) or 0,
        windowCooldownIdentityKey = type(plan.windowCooldownConfirmation) == "table"
            and plan.windowCooldownConfirmation.identityKey or nil,
        officialDepartureObserved = plan.officialDepartureObserved == true,
        officialDepartureObservedAt = number(plan.officialDepartureObservedAt),
        initialInjectionPhase = plan.initialInjectionPhase,
        initialInjectionReason = plan.initialInjectionReason,
        initialWindowPhase = plan.initialWindowPhase,
        initialWindowReason = plan.initialWindowReason,
        windowAvailabilityConflict = plan.windowAvailabilityConflict == true,
        windowAvailabilityConflictReason = plan.windowAvailabilityConflictReason,
        windowAvailabilityConflictResolvedAt = number(plan.windowAvailabilityConflictResolvedAt),
        candidateOfferCount = plan.candidateOfferCount or 0,
        handoffBarrierPending = plan.handoffBarrierPending == true,
        handoffBarrierRequiredFrames = number(plan.handoffBarrierRequiredFrames) or 0,
        handoffBarrierRemainingFrames = handoffBarrierRemaining(plan),
        handoffBarrierPublishedFrames = number(plan.handoffBarrierPublishedFrames) or 0,
        waitingForConfirmation = plan.state == "WAIT_CONFIRM",
        pendingConfirmationSpellID = plan.wait and positiveSpellID(plan.wait.expectedSpellID) or nil,
        pendingConfirmationActionKind = plan.wait and plan.wait.expectedActionKind or nil,
        pendingConfirmationInventorySlot = plan.wait and inventorySlot(plan.wait.expectedInventorySlot) or nil,
        pendingConfirmationItemID = plan.wait and positiveItemID(plan.wait.expectedItemID) or nil,
        confirmationEventSpellID = plan.wait and positiveSpellID(plan.wait.spellcastSucceededSpellID) or nil,
        confirmationEventMatchKind = plan.wait and plan.wait.spellcastSucceededMatchKind or nil,
        waitInputPhase = plan.wait and plan.wait.phase or nil,
        inventoryRecoveryEligible = plan.wait and plan.wait.inventoryRecoveryEligible == true,
        inventoryRecoveryActive = plan.wait and plan.wait.inventoryRecoveryActive == true,
        inventoryRecoveryPersistent = plan.wait and plan.wait.inventoryRecoveryPersistent == true,
        inventoryRecoveryReason = plan.wait and plan.wait.inventoryRecoveryReason or nil,
        inventoryRecoveryDeadlineAt = plan.wait and number(plan.wait.inventoryRecoveryDeadlineAt) or nil,
        confirmationGraceElapsed = plan.wait and plan.wait.confirmationGraceElapsed == true,
        dispatchAttempt = plan.dispatchAttempt or 0,
        pauseReason = plan.pauseReason,
        requireWindowDeparture = self.requireWindowDeparture == true,
        preCombatBridgeDepartureLock = self.preCombatBridgeDepartureLock == true,
        preCombatBridgeWorldFence = self.preCombatBridgeWorldFence == true,
        preCombatBridgeAuthorizationRequiresHandoff = self.preCombatBridgeAuthorizationRequiresHandoff == true,
        worldTransitionEpoch = self.worldTransitionEpoch or 0,
        lastWorldTransition = shallowCopy(self.lastWorldTransition),
        combatEpoch = self.combatEpoch or 0,
        armedEpoch = self.armedEpoch or 0,
        firstHealthyFramePending = self.firstHealthyFramePending == true,
        windowGeneration = self.windowGeneration or 0,
        consumedWindowGeneration = self.consumedWindowGeneration or 0,
        activePlanGeneration = self.activePlanGeneration,
        departureLockGeneration = self.departureLockGeneration,
        currentWindowSpellID = self.currentWindowSpellID,
        preWindowCaptureActive = captureActive,
        preWindowCaptureId = captureActive and number(capture.id) or nil,
        preWindowCaptureRuleId = captureActive and capture.rule and capture.rule.id or nil,
        preWindowCaptureOfficialSpellID = captureActive and positiveSpellID(capture.officialSpellID) or nil,
        preWindowCaptureWindowGeneration = captureActive and number(capture.windowGeneration) or nil,
        preWindowCaptureArmedEpoch = captureActive and number(capture.armedEpoch) or nil,
        preWindowCaptureHandoffBarrierPending = captureActive and capture.handoffBarrierPending == true,
        preWindowCaptureHandoffBarrierRequiredFrames = captureActive and number(capture.handoffBarrierRequiredFrames) or 0,
        preWindowCaptureHandoffBarrierRemainingFrames = captureActive and handoffBarrierRemaining(capture) or 0,
        preWindowCaptureHandoffBarrierPublishedFrames = captureActive and number(capture.handoffBarrierPublishedFrames) or 0,
        preWindowCaptureRetryCount = captureActive and number(capture.retryCount) or 0,
        preWindowCaptureLastReason = captureActive and capture.lastRetryReason or nil,
        preWindowCaptureBridge = captureActive and capture.preCombatBridge == true,
        planWindowGeneration = plan.windowGeneration,
        planArmedEpoch = plan.armedEpoch,
        lastStepObservation = shallowCopy(self.lastStepObservation),
        lastInjectionPreflight = shallowCopy(self.lastInjectionPreflight),
        lastSequencePreflight = shallowCopy(self.lastSequencePreflight),
    }
end

local function recentPriorityEvents()
    local store = ensureStore()
    local source = type(store.priorityEvents) == "table" and store.priorityEvents or {}
    local out = {}
    local first = math.max(1, #source - 15)
    for index = first, #source do out[#out + 1] = shallowCopy(source[index]) end
    return out
end

function AutoBurst:GetDiagnostics()
    local settings = tactics()
    local context = TE.Context and TE.Context:GetPlayer() or {}
    local rule, ruleReason = profileRule(context)
    local snapshot = self:GetSnapshot()
    local resolvedSteps = {}
    if rule then
        for index, step in ipairs(sequenceFor(rule)) do
            resolvedSteps[index] = {
                index = index,
                key = step.key,
                role = step.role,
                category = step.category,
                actionKind = stepKind(step),
                optional = isOptionalStep(step),
                spellID = stepKind(step) == "spell" and positiveSpellID(step.spellID) or nil,
                inventorySlot = stepKind(step) == "inventory" and inventorySlot(step.inventorySlot) or nil,
                offGCDExplicit = step.offGCDExplicit == true,
            }
        end
    end
    return {
        schema = 2,
        build = TE.version,
        enabled = settings.autoBurstEnabled == true,
        mode = settings.autoBurstMode,
        macroPolicy = "broad_visible_actionbar",
        resolvedRule = rule and {
            id = rule.id,
            source = rule.source,
            profileKey = rule.profileKey,
            windowSpellID = rule.windowSpellID,
            direction = rule.direction,
            mode = rule.mode,
            sequenceSignature = rule.sequenceSignature,
            optionalStepCount = rule.optionalStepCount,
            steps = resolvedSteps,
        } or nil,
        ruleReason = ruleReason,
        plan = snapshot,
        lastInjectionPreflight = shallowCopy(self.lastInjectionPreflight),
        lastSequencePreflight = shallowCopy(self.lastSequencePreflight),
        armedEpoch = self.armedEpoch or 0,
        firstHealthyFramePending = self.firstHealthyFramePending == true,
        windowGeneration = self.windowGeneration or 0,
        consumedWindowGeneration = self.consumedWindowGeneration or 0,
        activePlanGeneration = self.activePlanGeneration,
        departureLockGeneration = self.departureLockGeneration,
        preWindowCapture = {
            active = snapshot.preWindowCaptureActive == true,
            id = snapshot.preWindowCaptureId,
            ruleId = snapshot.preWindowCaptureRuleId,
            officialSpellID = snapshot.preWindowCaptureOfficialSpellID,
            windowGeneration = snapshot.preWindowCaptureWindowGeneration,
            armedEpoch = snapshot.preWindowCaptureArmedEpoch,
            handoffBarrierPending = snapshot.preWindowCaptureHandoffBarrierPending == true,
            preCombatBridge = snapshot.preWindowCaptureBridge == true,
            handoffBarrierRequiredFrames = snapshot.preWindowCaptureHandoffBarrierRequiredFrames,
            handoffBarrierRemainingFrames = snapshot.preWindowCaptureHandoffBarrierRemainingFrames,
            handoffBarrierPublishedFrames = snapshot.preWindowCaptureHandoffBarrierPublishedFrames,
            retryCount = snapshot.preWindowCaptureRetryCount,
            lastReason = snapshot.preWindowCaptureLastReason,
        },
        combatEpoch = self.combatEpoch or 0,
        preCombatBridgeWorldFence = self.preCombatBridgeWorldFence == true,
        preCombatBridgeAuthorizationRequiresHandoff = self.preCombatBridgeAuthorizationRequiresHandoff == true,
        worldTransitionEpoch = self.worldTransitionEpoch or 0,
        lastWorldTransition = shallowCopy(self.lastWorldTransition),
        preCombatBridgeDepartureLock = self.preCombatBridgeDepartureLock == true,
        lastDecision = shallowCopy(self.lastDecision),
        lastStepObservation = shallowCopy(self.lastStepObservation),
        lastCandidate = shallowCopy(self.lastCandidate),
        lastSpellcastSuccess = shallowCopy(self.lastSpellcastSuccess),
        lastConfirmationSource = self.lastConfirmationSource,
        lastAbortReason = self.lastAbortReason,
        lastWindowRejectReason = self.lastWindowRejectReason,
        lastArmedRebase = shallowCopy(self.lastArmedRebase),
        recentPriorityEvents = recentPriorityEvents(),
        lastFault = shallowCopy(self.lastFault),
    }
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "PLAYER_SPECIALIZATION_CHANGED",
    "UNIT_SPELLCAST_SUCCEEDED",
})
watcher:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Do not carry an idle/out-of-combat recommendation or the previous
        -- encounter's departure lock into the next encounter.  Without this
        -- reset, a window already visible at combat entry is misclassified as
        -- a stale same-window frame and front injection never gets a chance to
        -- offer its first candidate.
        AutoBurst:BeginCombatEpoch("player_regen_disabled")
    elseif event == "PLAYER_REGEN_ENABLED" then
        AutoBurst:Abort("out_of_combat", true)
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        AutoBurst:ActivateWorldTransitionFence(string.lower(event))
        if TE.SignalFrame and type(TE.SignalFrame.Refresh) == "function" then
            TE.SignalFrame:Refresh("world_transition_precombat_fenced")
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        AutoBurst.eventPauseUntil = now() + 0.10
        AutoBurst.eventPauseReason = "target_changed_revalidate"
    elseif event == "PLAYER_DEAD" then
        AutoBurst.deadPaused = true
    elseif event == "PLAYER_ALIVE" then
        AutoBurst.deadPaused = false
    elseif (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and unit == "player" then
        AutoBurst.vehiclePaused = event == "UNIT_ENTERED_VEHICLE"
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" then
        AutoBurst:Abort("specialization_changed", false)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
        local accepted = AutoBurst:RecordSpellcastSucceeded(spellID)
        if accepted == true and TE.SignalFrame and type(TE.SignalFrame.Refresh) == "function" then
            TE.SignalFrame:Refresh("autoburst_step_spellcast_succeeded")
        end
    end
end)
