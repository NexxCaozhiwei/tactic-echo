-- Controlled AutoBurst dispatcher candidate builder.
--
-- This module is intentionally not a second input path.  It can only return a
-- single, already-resolved action-bar candidate to SignalFrame; SignalFrame
-- still owns BindingToken → TEAP and TEK remains the only Windows input path.
--
-- Phase 1 supports exactly one rule at a time:
--   pre:  injection -> window
--   post: window -> injection
-- with simple/focused policy.  Trinkets, potions and multi-step macros are
-- deliberately excluded until the two-spell state machine is field-tested.
local TE = _G.TacticEcho

local AutoBurst = {
    schema = 1,
    nextPlanId = 1,
    plan = nil,
    requireWindowDeparture = false,
    lockedWindowSpellID = nil,
    lastOfficialSpellID = nil,
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
    -- Last logical candidate offered to SignalFrame. It contains no macro body,
    -- raw cooldown value or player-identifying data; it only makes the next
    -- diagnostic bundle show whether Burst ever reached TEAP.
    lastCandidate = nil,
    -- A compact scalar-only observation is exported with /temapping so a test
    -- can distinguish "injection was skipped as GCD" from "binding/token was
    -- missing" without persisting macro bodies or resolver internals.
    lastStepObservation = nil,
}
TE.AutoBurst = AutoBurst

local MAX_LOGS = 180
local STEP_CONFIRM_SECONDS = 2.20
-- UNKNOWN is a bounded revalidation state, never an implicit cooldown skip.
-- This short per-step timeout prevents a protected/ambiguous API response from
-- retaining the official window forever; the broader plan deadline remains the
-- final outer guard.
local STEP_REVALIDATE_SECONDS = 2.20
local PLAN_TOTAL_SECONDS = 8.00
-- A logical Burst candidate stays visible until the specific step is confirmed,
-- explicitly invalidated or reaches its bounded confirmation deadline. TEK
-- deduplicates the stable sequence, so this does not become repeated input.
local DECISION_LOG_MIN_SECONDS = 0.35

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
end

local function isInCombat(runtime)
    if type(runtime) == "table" and runtime.inCombat ~= nil then return runtime.inCombat == true end
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
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
    }
    self.lastDecision = record
    local signature = table.concat({
        tostring(phase), tostring(reason), tostring(record.planId or 0),
        tostring(record.officialSpellID or 0), tostring(record.windowSpellID or 0),
        tostring(record.injectionSpellID or 0), tostring(record.ruleSource or ""),
        tostring(record.state or ""),
    }, ":")
    local t = record.elapsed or 0
    if signature ~= self.lastDecisionSignature or t - (self.lastDecisionLoggedAt or 0) >= DECISION_LOG_MIN_SECONDS then
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

-- This is a confirmation-only event path. It does not influence trigger timing
-- and never reads Buffs, resources, targets or raw cooldown values. The event
-- can satisfy only the exact Phase-1 step already waiting for confirmation.
function AutoBurst:RecordSpellcastSucceeded(spellID)
    spellID = positiveSpellID(spellID)
    if not spellID then return end
    local t = now()

    local plan = self.plan
    if not (plan and plan.state == "WAIT_CONFIRM" and type(plan.wait) == "table") then return end
    local step = plan.steps and plan.steps[plan.stepIndex] or nil
    if not step or positiveSpellID(step.spellID) ~= spellID then return end
    if t < (number(plan.wait.dispatchedAt) or 0) then return end

    -- Persist only a matching current-step receipt, never unrelated manual
    -- casts. This keeps mapping export diagnostic-only and unambiguous.
    self.lastSpellcastSuccess = { spellID = spellID, elapsed = t, planId = plan.id }
    plan.wait.spellcastSucceededSpellID = spellID
    plan.wait.spellcastSucceededAt = t
    log(self, "step_spellcast_succeeded", {
        role = step.role,
        spellID = spellID,
        currentStep = plan.stepIndex,
        dispatchAttempt = plan.wait.dispatchAttempt,
    })
end

local function profileRule(context)
    local settings = tactics()
    local direction = settings.autoBurstDirection == "post" and "post" or "pre"
    local mode = settings.autoBurstMode == "focused" and "focused" or "simple"
    local manualWindow = positiveSpellID(settings.autoBurstWindowSpellID)
    local manualInjection = positiveSpellID(settings.autoBurstInjectionSpellID)

    -- A Phase-1 rule can be declared explicitly.  This is the preferred test
    -- path because the skill Blizzard recommends as the official anchor is not
    -- necessarily the first skill shown by the legacy HUD burst profile.
    if manualWindow or manualInjection then
        if not manualWindow or not manualInjection then
            return nil, "auto_burst_manual_rule_incomplete"
        end
        return {
            id = "manual:" .. direction .. ":" .. mode .. ":" .. tostring(manualWindow) .. ":" .. tostring(manualInjection),
            profileKey = "manual",
            source = "manual_spell_ids",
            windowSpellID = manualWindow,
            injectionSpellID = manualInjection,
            direction = direction,
            mode = mode,
            windowRetryLimit = 1,
            injectionRetryLimit = 0,
        }, nil
    end

    if settings.autoBurstUseProfileFallback ~= true then
        return nil, "auto_burst_manual_rule_required"
    end
    if not (TE.BurstProfiles and type(TE.BurstProfiles.Get) == "function") then
        return nil, "burst_profiles_unavailable"
    end
    local profile, profileKey, reason = TE.BurstProfiles:Get(context)
    if not profile or profile.enabled == false then return nil, reason or "burst_profile_disabled" end
    if profile.noSeedNotice then return nil, "burst_profile_unseeded" end

    local function firstAllowed(list)
        for _, spellID in ipairs(list or {}) do
            spellID = number(spellID)
            if spellID and spellID > 0 and not (TE.BurstProfiles:IsBlacklisted(profile, spellID)) then return math.floor(spellID) end
        end
        return nil
    end

    local windowSpellID = firstAllowed(profile.openerSpellIDs)
    local injectionSpellID = firstAllowed(profile.injectionSpellIDs)
    if not windowSpellID or not injectionSpellID then return nil, "burst_rule_missing_window_or_injection" end
    return {
        id = tostring(profileKey) .. ":" .. direction .. ":" .. mode .. ":" .. tostring(windowSpellID) .. ":" .. tostring(injectionSpellID),
        profileKey = profileKey,
        source = "profile_first_enabled",
        windowSpellID = windowSpellID,
        injectionSpellID = injectionSpellID,
        direction = direction,
        mode = mode,
        windowRetryLimit = 1,
        injectionRetryLimit = 0,
    }, nil
end

local function macroAllowed(bindingInfo)
    if not bindingInfo or bindingInfo.source ~= "macro" then return true end
    local semantics = bindingInfo.macroSemantics
    return type(semantics) == "table" and semantics.directSlotEligible == true
end

local function resolveBinding(spellID)
    if not (TE.ActionBarBindingResolver and type(TE.ActionBarBindingResolver.ResolveSpell) == "function") then
        return nil, "BLOCKED", "binding_resolver_unavailable"
    end
    local ok, bindingInfo, reason = pcall(TE.ActionBarBindingResolver.ResolveSpell, TE.ActionBarBindingResolver, spellID)
    if not ok or type(bindingInfo) ~= "table" then return nil, "BLOCKED", "binding_resolver_failed" end
    local special = bindingInfo.specialActionBar
    if special and special.active == true then return bindingInfo, "PAUSED", special.reason or "special_actionbar" end
    if bindingInfo.status ~= "Ready" or (number(bindingInfo.bindingToken) or 0) <= 0 then
        return bindingInfo, "BLOCKED", reason or bindingInfo.reason or bindingInfo.status or "binding_not_ready"
    end
    if not macroAllowed(bindingInfo) then return bindingInfo, "BLOCKED", "macro_not_single_use" end
    return bindingInfo, nil, nil
end

local function collectCooldownState(spellID, cycle, bindingInfo)
    if not (TE.IconState and type(TE.IconState.CollectCooldownOnly) == "function") then
        return nil, "cooldown_only_sampler_unavailable"
    end
    -- AutoBurst must re-evaluate a live, skill-specific cooldown at every
    -- state-machine tick. HUD cooldown snapshots are intentionally event-driven
    -- and can be stale across a short shared GCD; using them here caused a ready
    -- pre-injection to be skipped before it ever became a Burst candidate.
    bindingInfo = type(bindingInfo) == "table" and bindingInfo or {}
    local options = {
        gcdSnapshot = type(cycle) == "table" and cycle.gcdSnapshot or nil,
        liveCooldown = true,
        actionSlot = bindingInfo.actionSlot or bindingInfo.slot,
        directActionSlot = bindingInfo.directActionSlot == true,
        actionBarStateTrusted = bindingInfo.directActionSlot == true,
        matchedSpellID = bindingInfo.matchedSpellID,
        requestedSpellID = bindingInfo.requestedSpellID,
        equivalentSpellIDs = bindingInfo.equivalentSpellIDs,
    }
    local ok, state = pcall(TE.IconState.CollectCooldownOnly, TE.IconState, spellID, options)
    return ok and type(state) == "table" and state or nil, ok and "cooldown_only_state_invalid" or "cooldown_only_state_failed"
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
    if iconState.cooldownActive == true and iconState.cooldownOnGCD ~= true then
        return "COOLDOWN", "spell_cooldown_active"
    end
    return "OWN_READY", nil
end

local sequenceFor

local function stepSample(step, cycle)
    local bindingInfo, bindingState, bindingReason = resolveBinding(step.spellID)
    if bindingState then return { phase = bindingState, reason = bindingReason, bindingInfo = bindingInfo } end
    local iconState, iconReason = collectCooldownState(step.spellID, cycle, bindingInfo)
    local ownState, ownReason = ownReadyState(iconState)
    if ownState ~= "OWN_READY" then
        return { phase = ownState, reason = ownReason or iconReason, bindingInfo = bindingInfo, iconState = iconState }
    end
    if not (TE.GCDGate and type(TE.GCDGate.Classify) == "function") then
        return { phase = "UNKNOWN", reason = "gcd_gate_unavailable", bindingInfo = bindingInfo, iconState = iconState }
    end
    local phase, phaseReason = TE.GCDGate:Classify(cycle)
    return {
        phase = phase,
        reason = phaseReason,
        bindingInfo = bindingInfo,
        iconState = iconState,
    }
end

local function validateRuleBindings(self, rule)
    for _, step in ipairs(sequenceFor(rule)) do
        local bindingInfo, bindingState, bindingReason = resolveBinding(step.spellID)
        if bindingState then
            rememberStepObservation(self, nil, step, {
                phase = bindingState,
                reason = bindingReason,
                bindingInfo = bindingInfo,
            }, "plan_gate_binding")
            return false, step, bindingState, bindingReason
        end
    end
    return true, nil, nil, nil
end

local function confirmationBaseline(sample)
    local icon = sample and sample.iconState or {}
    return {
        cooldownKnown = icon.cooldownKnown == true,
        cooldownActive = icon.cooldownActive == true and icon.cooldownOnGCD ~= true,
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
        and baseline.cooldownActive ~= true then
        return true, "spell_cooldown_started"
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
    if eventSpellID and eventSpellID == positiveSpellID(step.spellID) then
        return true, "unit_spellcast_succeeded"
    end
    return false, nil
end

sequenceFor = function(rule)
    if rule.direction == "post" then
        return {
            { role = "window", spellID = rule.windowSpellID },
            { role = "injection", spellID = rule.injectionSpellID },
        }
    end
    return {
        { role = "injection", spellID = rule.injectionSpellID },
        { role = "window", spellID = rule.windowSpellID },
    }
end

local function rememberStepObservation(self, plan, step, sample, stage)
    sample = type(sample) == "table" and sample or {}
    local binding = type(sample.bindingInfo) == "table" and sample.bindingInfo or {}
    local icon = type(sample.iconState) == "table" and sample.iconState or {}
    local observation = {
        schema = 1,
        stage = stage,
        elapsed = now(),
        planId = plan and plan.id or nil,
        role = step and step.role or nil,
        spellID = step and positiveSpellID(step.spellID) or nil,
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
        chargeCount = number(icon.charges),
        chargeMaximum = number(icon.maxCharges),
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
        role = step.role,
        spellID = positiveSpellID(step.spellID),
        bindingToken = sample and sample.bindingInfo and number(sample.bindingInfo.bindingToken) or nil,
        dispatchAttempt = plan.wait and plan.wait.dispatchAttempt or 0,
        offerCount = plan.candidateOfferCount,
    }
    return {
        kind = "candidate",
        dispatchOrigin = "burst",
        dispatchSpellID = step.spellID,
        officialSpellID = plan.officialSpellID,
        bindingInfo = sample.bindingInfo,
        planId = plan.id,
        ruleId = plan.rule.id,
        ruleSource = plan.rule.source,
        direction = plan.rule.direction,
        mode = plan.rule.mode,
        stepRole = step.role,
        -- This increments only for a logical dispatch attempt.  The same
        -- candidate is re-offered until proof/timeout, keeping one TEAP action
        -- sequence so TEK can deduplicate physical input safely.
        dispatchAttempt = plan.wait and plan.wait.dispatchAttempt or 0,
    }
end

local function holdResult(plan, reason)
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
    }
end

local function noneResult()
    return { kind = "none", dispatchOrigin = "official" }
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
        return holdResult(nil, "burst_await_window_departure")
    end
    recordDecision(self, "released", fields.reason, fields)
    return noneResult()
end

local function revalidateUnknownStep(self, plan, step, sample, reason)
    local t = now()
    local current = plan.revalidate
    if type(current) ~= "table" or current.stepIndex ~= plan.stepIndex or current.spellID ~= step.spellID then
        current = {
            stepIndex = plan.stepIndex,
            role = step.role,
            spellID = step.spellID,
            startedAt = t,
            deadlineAt = t + STEP_REVALIDATE_SECONDS,
        }
        plan.revalidate = current
        log(self, "step_revalidate_started", {
            role = step.role,
            spellID = step.spellID,
            reason = reason,
            currentStep = plan.stepIndex,
        })
    end
    if t >= (number(current.deadlineAt) or t) then
        self:Abort("step_revalidate_timeout:" .. tostring(reason), false)
        return terminalResult(self, "step_revalidate_timeout", {
            abortReason = reason,
            windowSpellID = plan.rule.windowSpellID,
            injectionSpellID = plan.rule.injectionSpellID,
            ruleSource = plan.rule.source,
            ruleId = plan.rule.id,
        })
    end
    log(self, "step_revalidate_wait", {
        role = step.role,
        spellID = step.spellID,
        reason = reason,
        currentStep = plan.stepIndex,
    })
    return holdResult(plan, "burst_step_revalidate")
end

function AutoBurst:Abort(reason, hard)
    if self.plan then
        log(self, hard and "hard_abort" or "plan_aborted", { reason = reason, currentStep = self.plan.stepIndex })
        -- A created Burst plan owns its official window through terminal state.
        -- It must never fail open to the ordinary recommendation after UNKNOWN,
        -- confirmation timeout or a rejected candidate; a new plan requires the
        -- official recommendation to leave the window and re-enter.
        self.lockedWindowSpellID = self.plan.rule.windowSpellID
        self.requireWindowDeparture = true
    end
    self.plan = nil
end

-- Begin a new encounter-scoped official-window epoch.  This deliberately
-- clears only stale AutoBurst edge/lock memory; it does not fabricate a
-- candidate or bypass the normal in-combat, armed, rule, binding, TEAP or TEK
-- gates.  On the next healthy in-combat frame, a currently recommended window
-- is therefore treated as the first recommendation edge of this combat.
function AutoBurst:BeginCombatEpoch(reason)
    self.combatEpoch = (self.combatEpoch or 0) + 1
    self.plan = nil
    self.requireWindowDeparture = false
    self.lockedWindowSpellID = nil
    self.lastOfficialSpellID = nil
    self.eventPauseUntil = 0
    self.eventPauseReason = nil
    log(self, "combat_epoch_started", {
        reason = reason or "combat_started",
        combatEpoch = self.combatEpoch,
    })
end

function AutoBurst:SoftPause(reason)
    if not self.plan then return end
    if self.plan.state ~= "SOFT_PAUSED" or self.plan.pauseReason ~= reason then
        self.plan.state = "SOFT_PAUSED"
        self.plan.pauseReason = reason
        log(self, "soft_paused", { reason = reason, currentStep = self.plan.stepIndex })
    end
end

function AutoBurst:ResumeIfPossible()
    if not self.plan or self.plan.state ~= "SOFT_PAUSED" then return end
    self.plan.state = self.plan.wait and "WAIT_CONFIRM" or "PENDING"
    self.plan.pauseReason = nil
    log(self, "soft_resumed", { currentStep = self.plan.stepIndex })
end

local function isRuntimePaused(self, runtime)
    if self.deadPaused then return true, "player_dead" end
    if self.vehiclePaused then return true, "vehicle_active" end
    local t = now()
    if self.eventPauseUntil and t < self.eventPauseUntil then return true, self.eventPauseReason or "event_revalidation" end
    local effective = runtime and runtime.effectiveState
    if effective and effective ~= "armed" then return true, runtime.runtimeReason or ("runtime_" .. tostring(effective)) end
    return false, nil
end

local function stepFailure(self, plan, step, reason)
    if step.role == "window" and (plan.windowRetryCount or 0) < (plan.rule.windowRetryLimit or 0) then
        plan.windowRetryCount = (plan.windowRetryCount or 0) + 1
        plan.state = "PENDING"
        plan.wait = nil
        log(self, "window_retry", { reason = reason, retry = plan.windowRetryCount, currentStep = plan.stepIndex })
        return holdResult(plan, "burst_window_retry")
    end

    if step.role == "injection" and plan.rule.mode == "simple" then
        if plan.rule.direction == "post" then
            -- In post mode the already-confirmed window has been consumed. A
            -- failed optional injection ends the plan, but it must never retry
            -- or re-send the window.
            log(self, "post_injection_skipped_after_timeout", { reason = reason, currentStep = plan.stepIndex })
            plan.wait = nil
            plan.stepIndex = plan.stepIndex + 1
            plan.state = "PENDING"
            if plan.stepIndex > #plan.steps then
                log(self, "plan_completed", { reason = "post_injection_skipped" })
                self.lockedWindowSpellID = plan.rule.windowSpellID
                self.requireWindowDeparture = true
                self.plan = nil
                return terminalResult(self, "post_injection_skipped", {
                    windowSpellID = plan.rule.windowSpellID,
                    injectionSpellID = plan.rule.injectionSpellID,
                    ruleSource = plan.rule.source,
                    ruleId = plan.rule.id,
                })
            end
            return nil
        end

        -- Front injection is strictly ordered. Once a candidate for injection
        -- has been offered, a failed confirmation must not release the official
        -- window back to the normal path; otherwise `window` can be sent even
        -- though the required first action never succeeded.
        self:Abort("pre_injection_confirmation_timeout:" .. tostring(reason), false)
        return terminalResult(self, "pre_injection_confirmation_timeout", {
            abortReason = reason,
            windowSpellID = plan.rule.windowSpellID,
            injectionSpellID = plan.rule.injectionSpellID,
            ruleSource = plan.rule.source,
            ruleId = plan.rule.id,
        })
    end

    self:Abort(reason, false)
    return terminalResult(self, "burst_plan_aborted", { abortReason = reason })
end

local function skipOptionalInjection(self, plan, reason)
    log(self, "injection_skipped", { phase = reason, reason = reason, currentStep = plan.stepIndex })
    plan.revalidate = nil
    plan.candidateOfferCount = 0
    plan.candidateFirstOfferedAt = nil
    plan.candidateLastOfferedAt = nil
    plan.stepIndex = plan.stepIndex + 1
    if plan.stepIndex > #plan.steps then
        log(self, "plan_completed", { reason = reason })
        self.lockedWindowSpellID = plan.rule.windowSpellID
        self.requireWindowDeparture = true
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

local function finishStep(self, plan, source)
    local step = plan.steps[plan.stepIndex]
    plan.completed[#plan.completed + 1] = step.role
    plan.wait = nil
    plan.revalidate = nil
    plan.candidateOfferCount = 0
    plan.candidateFirstOfferedAt = nil
    plan.candidateLastOfferedAt = nil
    plan.stepIndex = plan.stepIndex + 1
    plan.state = "PENDING"
    log(self, "step_confirmed", { role = step.role, spellID = step.spellID, confirmation = source, currentStep = plan.stepIndex - 1 })
    if plan.stepIndex > #plan.steps then
        log(self, "plan_completed", { reason = "all_steps_confirmed" })
        self.lockedWindowSpellID = plan.rule.windowSpellID
        self.requireWindowDeparture = true
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

local function createPlan(self, rule, officialSpellID, creation)
    creation = type(creation) == "table" and creation or {}
    local t = now()
    local plan = {
        id = self.nextPlanId,
        rule = rule,
        officialSpellID = officialSpellID,
        createdAt = t,
        deadlineAt = t + PLAN_TOTAL_SECONDS,
        steps = sequenceFor(rule),
        stepIndex = 1,
        state = "PENDING",
        completed = {},
        windowRetryCount = 0,
        windowDispatchAttempted = false,
        dispatchAttempt = 0,
        wait = nil,
        revalidate = nil,
        candidateOfferCount = 0,
        candidateFirstOfferedAt = nil,
        candidateLastOfferedAt = nil,
        initialWindowPhase = creation.initialWindowPhase,
        initialWindowReason = creation.initialWindowReason,
        -- A strict front plan owns the window from creation unless the official
        -- window edge explicitly proved injection was on its own cooldown.
        -- UNKNOWN is not cooldown and never grants a skip.
        preInjectionRequired = creation.preInjectionRequired == true,
        preInjectionSkipAllowed = creation.preInjectionSkipAllowed == true,
        initialInjectionPhase = creation.initialInjectionPhase,
        initialInjectionReason = creation.initialInjectionReason,
    }
    self.nextPlanId = self.nextPlanId + 1
    self.plan = plan
    log(self, "plan_created", { direction = rule.direction, mode = rule.mode, officialSpellID = officialSpellID })
    return plan
end

local function canCreateFocused(rule, cycle)
    for _, step in ipairs(sequenceFor(rule)) do
        local sample = stepSample(step, cycle)
        if sample.phase ~= "READY_NOW" and sample.phase ~= "QUEUE_WINDOW" and sample.phase ~= "GCD_LOCKED" then
            return false, sample.phase, sample.reason
        end
    end
    return true, nil, nil
end

function AutoBurst:Evaluate(official, runtime)
    runtime = type(runtime) == "table" and runtime or {}
    local settings = tactics()
    local officialSpellID = official and positiveSpellID(official.spellID) or nil
    local previousOfficialSpellID = self.lastOfficialSpellID

    if self.lastOfficialSpellID ~= officialSpellID then
        self.lastOfficialSpellID = officialSpellID
        if self.requireWindowDeparture and officialSpellID ~= self.lockedWindowSpellID then
            log(self, "window_departed", { spellID = self.lockedWindowSpellID })
            self.requireWindowDeparture = false
            self.lockedWindowSpellID = nil
        end
    end

    if not isInCombat(runtime) then
        self:Abort("out_of_combat", true)
        recordDecision(self, "idle", "out_of_combat", { officialSpellID = officialSpellID })
        return noneResult()
    end

    if settings.autoBurstEnabled ~= true then
        if self.plan then self:Abort("auto_burst_disabled", false) end
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

    local paused, pauseReason = isRuntimePaused(self, runtime)
    if paused then
        self:SoftPause(pauseReason)
        recordDecision(self, self.plan and "paused" or "idle", pauseReason or "runtime_paused", { officialSpellID = officialSpellID })
        return self.plan and holdResult(self.plan, pauseReason) or noneResult()
    end

    -- A completed/aborted plan must not reacquire the same still-visible window
    -- recommendation.  This internal suppression is evaluated only after the
    -- real auto-run and runtime gates, so Start/Pause always retains its normal
    -- meaning and cannot be masked by an old burst lock.
    if self.requireWindowDeparture and officialSpellID == self.lockedWindowSpellID then
        -- Do not re-send a just-consumed window while the official API still
        -- presents its old recommendation. This is observation-only; the HUD
        -- receives the official display binding from SignalFrame.
        recordDecision(self, "hold", "await_window_departure", { officialSpellID = officialSpellID, windowSpellID = self.lockedWindowSpellID })
        return holdResult(nil, "burst_await_window_departure")
    end

    local context = runtime.context or (TE.Context and TE.Context:GetPlayer()) or {}
    local rule, ruleReason = profileRule(context)
    if not rule then
        if self.plan then self:Abort(ruleReason, false) end
        recordDecision(self, "idle", ruleReason or "rule_unavailable", { officialSpellID = officialSpellID })
        return noneResult()
    end

    if self.plan and self.plan.rule.id ~= rule.id then
        self:Abort("rule_changed", false)
        return terminalResult(self, "rule_changed", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
    end

    local cycle = TE.GCDGate and TE.GCDGate:BeginCycle(runtime.primary) or { phase = "UNKNOWN" }
    if not self.plan then
        if not officialSpellID or officialSpellID ~= rule.windowSpellID then
            recordDecision(self, "armed", "official_not_window", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
            return noneResult()
        end
        -- A window plan is an edge-triggered takeover. Enabling AutoBurst in
        -- the middle of an already displayed official window must not create a
        -- late plan; the recommendation has to leave and enter again first.
        local windowEntry = previousOfficialSpellID ~= officialSpellID
        if not windowEntry then
            recordDecision(self, "armed", "window_edge_missing", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
            return noneResult()
        end
        local creation = {}
        local bindingsReady, blockedStep, bindingPhase, bindingReason = validateRuleBindings(self, rule)
        if not bindingsReady then
            log(self, "plan_rejected", {
                reason = bindingReason or bindingPhase,
                role = blockedStep and blockedStep.role,
                mode = rule.mode,
            })
            recordDecision(self, "armed", "burst_binding_not_ready", {
                officialSpellID = officialSpellID,
                windowSpellID = rule.windowSpellID,
                injectionSpellID = rule.injectionSpellID,
                ruleSource = rule.source,
                ruleId = rule.id,
            })
            return noneResult()
        end
        if rule.direction == "pre" then
            local injectionStep = { role = "injection", spellID = rule.injectionSpellID }
            local injectionSample = stepSample(injectionStep, cycle)
            rememberStepObservation(self, nil, injectionStep, injectionSample, "plan_gate_injection")
            creation.initialInjectionPhase = injectionSample.phase
            creation.initialInjectionReason = injectionSample.reason
            -- Only an explicit own-cooldown result at the official window edge
            -- permits a simple pre plan to skip injection. UNKNOWN, binding
            -- faults and timing ambiguity all preserve strict injection → window
            -- ownership until revalidation or bounded plan termination.
            creation.preInjectionSkipAllowed = injectionSample.phase == "COOLDOWN"
            creation.preInjectionRequired = creation.preInjectionSkipAllowed ~= true
        end

        if rule.mode == "focused" then
            local ready, phase, reason = canCreateFocused(rule, cycle)
            if not ready then
                -- Focused mode simply declines takeover when its required
                -- steps are not ready.  It must not manufacture a paused/hold
                -- frame or suppress the immutable official recommendation.
                log(self, "plan_rejected", { reason = reason or phase, mode = rule.mode })
                recordDecision(self, "armed", "burst_focused_not_ready", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
                return noneResult()
            end
        else
            local windowStep = { role = "window", spellID = rule.windowSpellID }
            local windowSample = stepSample(windowStep, cycle)
            rememberStepObservation(self, nil, windowStep, windowSample, "plan_gate_window")
            creation.initialWindowPhase = windowSample.phase
            creation.initialWindowReason = windowSample.reason
            if windowSample.phase == "UNKNOWN" then
                -- The official engine has already selected the window. A
                -- protected cooldown read may not hand that window back to the
                -- normal path: create a bounded plan and revalidate its first
                -- step instead.
                log(self, "plan_gate_window_unknown", { reason = windowSample.reason, mode = rule.mode })
            elseif windowSample.phase ~= "READY_NOW" and windowSample.phase ~= "QUEUE_WINDOW" and windowSample.phase ~= "GCD_LOCKED" then
                -- Explicit BLOCKED/UNUSABLE/PAUSED facts still do not create a
                -- synthetic candidate. The ordinary recommendation retains its
                -- behavior because this is not an unknown-read ambiguity.
                log(self, "plan_rejected", { reason = windowSample.reason or windowSample.phase, mode = rule.mode })
                recordDecision(self, "armed", "burst_window_not_ready", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
                return noneResult()
            end
        end
        createPlan(self, rule, officialSpellID, creation)
        recordDecision(self, "plan_created", "official_window_edge", { officialSpellID = officialSpellID, windowSpellID = rule.windowSpellID, injectionSpellID = rule.injectionSpellID, ruleSource = rule.source, ruleId = rule.id })
    end

    local plan = self.plan
    if not plan then return noneResult() end
    if now() >= plan.deadlineAt then
        self:Abort("plan_timeout", false)
        return terminalResult(self, "plan_timeout", { officialSpellID = officialSpellID })
    end

    if plan.state == "SOFT_PAUSED" then
        self:ResumeIfPossible()
    end

    local step = plan.steps[plan.stepIndex]
    if not step then
        self:Abort("step_missing", false)
        return terminalResult(self, "step_missing", { officialSpellID = officialSpellID })
    end

    if plan.state == "WAIT_CONFIRM" and plan.wait then
        local eventSuccess, eventSource = spellcastEventConfirmed(plan, step)
        if eventSuccess then
            local result = finishStep(self, plan, eventSource)
            return result or holdResult(plan, "burst_next_step_pending")
        end

        local sample = stepSample(step, cycle)
        rememberStepObservation(self, plan, step, sample, "wait_confirm")
        local success, source = confirmed(sample, plan.wait.baseline)
        if success then
            local result = finishStep(self, plan, source)
            return result or holdResult(plan, "burst_next_step_pending")
        end
        if sample.phase == "PAUSED" then
            self:SoftPause(sample.reason or "step_paused")
            return holdResult(plan, sample.reason or "step_paused")
        end
        if sample.phase == "BLOCKED" or sample.phase == "UNUSABLE" then
            self:Abort(sample.reason or sample.phase, false)
            return terminalResult(self, "burst_wait_confirmation_invalidated", { officialSpellID = officialSpellID, abortReason = sample.reason or sample.phase })
        end
        -- Persist the same candidate until confirmation, explicit invalidation
        -- or the bounded deadline. TEK deduplicates the stable Burst sequence
        -- after its first physical attempt, so this cannot become continuous
        -- repeated keypresses.
        if now() >= plan.wait.deadlineAt then
            local result = stepFailure(self, plan, step, "confirmation_timeout")
            return result or holdResult(plan, "burst_next_step_pending")
        end
        return candidateResult(self, plan, step, plan.wait.offerSample or sample)
    end

    local sample = stepSample(step, cycle)
    rememberStepObservation(self, plan, step, sample, "step_pending")
    if sample.phase == "PAUSED" then
        self:SoftPause(sample.reason or "step_paused")
        return holdResult(plan, sample.reason or "step_paused")
    end
    if sample.phase == "GCD_LOCKED" then
        return holdResult(plan, "burst_gcd_locked")
    end
    if sample.phase == "COOLDOWN" then
        if step.role == "injection" and plan.rule.mode == "simple" then
            if plan.rule.direction == "pre" and plan.preInjectionSkipAllowed ~= true then
                -- Later cooldown samples may not rewrite a ready/unknown strict
                -- front plan into permission to send the window first.
                return revalidateUnknownStep(self, plan, step, sample, "pre_injection_revalidate:" .. tostring(sample.reason or sample.phase))
            end
            return skipOptionalInjection(self, plan, "injection_cooldown")
        end
        self:Abort(sample.reason or sample.phase, false)
        return terminalResult(self, "burst_step_unavailable", { officialSpellID = officialSpellID, abortReason = sample.reason or sample.phase })
    end
    if sample.phase == "UNKNOWN" then
        if plan.rule.mode == "focused" then
            self:Abort(sample.reason or sample.phase, false)
            return terminalResult(self, "burst_step_unknown_focused", { officialSpellID = officialSpellID, abortReason = sample.reason or sample.phase })
        end
        if step.role == "injection" and plan.rule.mode == "simple" and plan.rule.direction == "post" then
            return skipOptionalInjection(self, plan, "post_injection_unknown")
        end
        -- UNKNOWN is not cooldown. Keep sequence ownership and re-sample for a
        -- fixed step deadline; terminal abort keeps the window departure lock.
        return revalidateUnknownStep(self, plan, step, sample, "step_unknown:" .. tostring(sample.reason or "unknown"))
    end
    if sample.phase == "UNUSABLE" or sample.phase == "BLOCKED" then
        self:Abort(sample.reason or sample.phase, false)
        return terminalResult(self, "burst_step_blocked", { officialSpellID = officialSpellID, abortReason = sample.reason or sample.phase })
    end
    if sample.phase ~= "READY_NOW" and sample.phase ~= "QUEUE_WINDOW" then
        self:Abort("invalid_step_phase:" .. tostring(sample.phase), false)
        return terminalResult(self, "burst_invalid_step_phase", { officialSpellID = officialSpellID, abortReason = sample.phase })
    end

    local dispatchedAt = now()
    plan.revalidate = nil
    plan.candidateOfferCount = 0
    plan.candidateFirstOfferedAt = nil
    plan.candidateLastOfferedAt = nil
    plan.dispatchAttempt = (plan.dispatchAttempt or 0) + 1
    if step.role == "window" then plan.windowDispatchAttempted = true end
    plan.state = "WAIT_CONFIRM"
    plan.wait = {
        baseline = confirmationBaseline(sample),
        dispatchedAt = dispatchedAt,
        deadlineAt = dispatchedAt + STEP_CONFIRM_SECONDS,
        offerSample = sample,
        phase = sample.phase,
        dispatchAttempt = plan.dispatchAttempt,
        expectedSpellID = step.spellID,
        spellcastSucceededSpellID = nil,
        spellcastSucceededAt = nil,
    }
    log(self, "step_dispatched", {
        role = step.role,
        spellID = step.spellID,
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
    if not plan then
        return {
            schema = 1,
            active = false,
            requireWindowDeparture = self.requireWindowDeparture == true,
            lockedWindowSpellID = self.lockedWindowSpellID,
            combatEpoch = self.combatEpoch or 0,
            lastStepObservation = shallowCopy(self.lastStepObservation),
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
        currentStep = plan.stepIndex,
        currentRole = step and step.role,
        currentSpellID = step and step.spellID,
        completed = plan.completed,
        windowRetryCount = plan.windowRetryCount,
        windowDispatchAttempted = plan.windowDispatchAttempted == true,
        preInjectionRequired = plan.preInjectionRequired == true,
        preInjectionSkipAllowed = plan.preInjectionSkipAllowed == true,
        initialInjectionPhase = plan.initialInjectionPhase,
        initialInjectionReason = plan.initialInjectionReason,
        initialWindowPhase = plan.initialWindowPhase,
        initialWindowReason = plan.initialWindowReason,
        candidateOfferCount = plan.candidateOfferCount or 0,
        waitingForConfirmation = plan.state == "WAIT_CONFIRM",
        pendingConfirmationSpellID = plan.wait and positiveSpellID(plan.wait.expectedSpellID) or nil,
        confirmationEventSpellID = plan.wait and positiveSpellID(plan.wait.spellcastSucceededSpellID) or nil,
        dispatchAttempt = plan.dispatchAttempt or 0,
        pauseReason = plan.pauseReason,
        requireWindowDeparture = self.requireWindowDeparture == true,
        combatEpoch = self.combatEpoch or 0,
        lastStepObservation = shallowCopy(self.lastStepObservation),
    }
end

function AutoBurst:GetDiagnostics()
    local settings = tactics()
    local context = TE.Context and TE.Context:GetPlayer() or {}
    local rule, ruleReason = profileRule(context)
    local snapshot = self:GetSnapshot()
    return {
        schema = 1,
        build = TE.version,
        enabled = settings.autoBurstEnabled == true,
        direction = settings.autoBurstDirection,
        mode = settings.autoBurstMode,
        manualWindowSpellID = positiveSpellID(settings.autoBurstWindowSpellID),
        manualInjectionSpellID = positiveSpellID(settings.autoBurstInjectionSpellID),
        useProfileFallback = settings.autoBurstUseProfileFallback == true,
        resolvedRule = rule and {
            id = rule.id,
            source = rule.source,
            profileKey = rule.profileKey,
            windowSpellID = rule.windowSpellID,
            injectionSpellID = rule.injectionSpellID,
            direction = rule.direction,
            mode = rule.mode,
        } or nil,
        ruleReason = ruleReason,
        plan = snapshot,
        combatEpoch = self.combatEpoch or 0,
        lastDecision = shallowCopy(self.lastDecision),
        lastStepObservation = shallowCopy(self.lastStepObservation),
        lastCandidate = shallowCopy(self.lastCandidate),
        lastSpellcastSuccess = shallowCopy(self.lastSpellcastSuccess),
        lastFault = shallowCopy(self.lastFault),
    }
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
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
        AutoBurst:RecordSpellcastSucceeded(spellID)
    end
end)
