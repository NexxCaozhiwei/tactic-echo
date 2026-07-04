-- P4.5 automatic interrupt coordinator: strict confirmed interrupt dispatch with guarded priority macros.
--
-- Boundary:
-- * It consumes the P3 scalar observation snapshot and P2 existing
--   action-bar/macro routes only.
-- * It never parses/re-writes macros, issues protected WoW actions, creates
--   hidden buttons, or contacts TEK directly.
-- * A successful candidate is fed back to SignalFrame, which uses the same
--   existing BindingToken -> TEAP v3 -> TEK safety path as the official
--   recommendation and AutoBurst.
-- * P4.4 remains automatic-interrupt-only. It dispatches only when a current
--   cast is positively confirmed interruptible. Actual native shield visibility
--   is the visual fallback; the cast-bar `showShield` configuration flag is not
--   accepted as evidence. Single control and AOE control remain P5 work.
local TE = _G.TacticEcho

local AutoReaction = {}
TE.AutoReaction = AutoReaction

AutoReaction.schemaVersion = 7

local SOURCE_ORDER = { "target", "focus", "mouseover" }
local SOURCE_LABELS = {
    target = "当前目标",
    focus = "焦点目标",
    mouseover = "鼠标指向目标",
}

local runtime = {
    activeCastKey = nil,
    offeredCastKey = nil,
    -- Native visual results are accepted only after two distinct P3 samples for
    -- the same cast. This lets the Blizzard shield widget settle at cast start
    -- without adding a timer, an OnUpdate loop, or an input path.
    nativeVisual = { castKey = nil, evidence = nil, observedAt = nil, samples = 0 },
    -- A missing P2 route may be caused by an action-bar cache settling after
    -- reload/page changes.  Refresh at most once for one confirmed cast; never
    -- turn the existing polling cadence into a rescan loop.
    routeRefreshCastKey = nil,
    -- Persist only state transitions, never a per-poll audit stream.  This
    -- lets a SavedVariables capture distinguish `not armed`, cast-evidence
    -- and P2-route blockers before any TEAP frame is considered.
    lastAuditSignature = nil,
    last = {
        state = "idle",
        reason = "not_evaluated",
        enabled = false,
        burstBlocked = false,
    },
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return false, nil end
    return true, a, b, c
end

local function plainNumber(value)
    local ok, number = pcall(function()
        local out = tonumber(value)
        if type(out) ~= "number" then return nil end
        local probe = out + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return out
    end)
    return ok and number or nil
end

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = safeCall(GetTime)
    return ok and plainNumber(value) or 0
end

local function normalizedOrder(value)
    local seen, out = {}, {}
    for _, source in ipairs(type(value) == "table" and value or {}) do
        if SOURCE_LABELS[source] and seen[source] ~= true then
            out[#out + 1] = source
            seen[source] = true
        end
    end
    for _, source in ipairs(SOURCE_ORDER) do
        if seen[source] ~= true then
            out[#out + 1] = source
            seen[source] = true
        end
    end
    return out
end

local function settings()
    local normalize = TE.Config and TE.Config.Normalize
    if normalize and type(normalize.All) == "function" then
        local ok, _, tactics = safeCall(normalize.All, normalize)
        if ok and type(tactics) == "table" then return tactics end
    end
    return type(TacticEchoDB) == "table" and type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
end

local function interruptConfig(tactics)
    local auto = type(tactics) == "table" and tactics.autoReaction or nil
    local branch = type(auto) == "table" and auto.interrupt or nil
    branch = type(branch) == "table" and branch or {}
    return {
        enabled = branch.enabled == true,
        targetEnabled = type(branch.targetEnabled) == "table" and branch.targetEnabled or {},
        targetOrder = normalizedOrder(branch.targetOrder),
    }
end

local function getObservation()
    local observer = TE.ReactionObservation
    if not (observer and type(observer.Sample) == "function") then return nil end
    local ok, snapshot = safeCall(observer.Sample, observer)
    return ok and type(snapshot) == "table" and snapshot or nil
end

local function getBindings(force)
    local bindings = TE.ReactionBindings
    if not (bindings and type(bindings.GetSnapshot) == "function") then return nil end
    local ok, snapshot = safeCall(bindings.GetSnapshot, bindings, force == true)
    return ok and type(snapshot) == "table" and snapshot or nil
end

-- Only called after P3 has already confirmed a live interruptible cast and P2
-- has no route.  The implementation in ReactionBindings rebuilds the existing
-- Blizzard-default action-bar cache once, or reports a binding-settlement
-- window.  No macro/action-bar mutation and no new input path are involved.
local function refreshBindingsForAuto()
    local bindings = TE.ReactionBindings
    if not bindings then return nil, "binding_registry_unavailable" end
    if type(bindings.RefreshForAuto) == "function" then
        local ok, snapshot, reason = safeCall(bindings.RefreshForAuto, bindings, "reaction_auto_route_refresh")
        if ok and type(snapshot) == "table" then return snapshot, reason or "binding_rebuilt" end
        return nil, reason or "binding_refresh_failed"
    end
    return getBindings(true), "binding_refresh_unsupported"
end

local function isReadySafeRoute(route)
    if type(route) ~= "table" then return false end
    if route.bindingReady ~= true or route.safeForFutureAuto ~= true then return false end
    if type(route.binding) ~= "string" or route.binding == "" then return false end
    return (tonumber(route.bindingToken) or 0) > 0
end

local function macroBranchUnitEligible(observation, source)
    local unit = type(observation) == "table" and type(observation.sources) == "table"
        and observation.sources[source] or nil
    return type(unit) == "table" and unit.exists == true and unit.hostile == true and unit.alive == true
end

-- A player-authored integrated macro cannot test whether a unit is casting.
-- It only sees normal macro predicates such as [harm,nodead].  Before P4 uses
-- the macro for a focus/target candidate, verify that no earlier macro branch
-- would already match another live hostile unit.  This is a fail-closed route
-- compatibility check, not generic macro condition evaluation.
local function priorityMacroRouteAllowed(route, source, observation)
    if type(route) ~= "table" or route.macroPriorityChain ~= true then return true, nil end
    local order = type(route.priorityRouteOrder) == "table" and route.priorityRouteOrder or {}
    local sourceIndex = nil
    for index, routeSource in ipairs(order) do
        if routeSource == source then
            sourceIndex = index
            break
        end
    end
    if not sourceIndex then return false, "macro_priority_chain_metadata_invalid" end
    for index = 1, sourceIndex - 1 do
        local earlier = order[index]
        if macroBranchUnitEligible(observation, earlier) then
            return false, "macro_priority_preempted_by_" .. tostring(earlier)
        end
    end
    return true, "macro_priority_route_match"
end

local function findInterruptRoute(snapshot, source, observation)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local routeGateReason = nil
    for _, entry in ipairs(snapshot.interrupt or {}) do
        if type(entry) == "table" and entry.role == "interrupt" then
            local route = type(entry.routes) == "table" and entry.routes[source] or nil
            if isReadySafeRoute(route) then
                local routeAllowed, gateReason = priorityMacroRouteAllowed(route, source, observation)
                if routeAllowed then return entry, route, nil end
                routeGateReason = routeGateReason or gateReason
            end
        end
    end
    return nil, nil, routeGateReason
end

-- P4.2 event-backed interruptibility confirmation.
--
-- P3 may observe a live cast while Retail keeps UnitCastingInfo's
-- `notInterruptible` scalar opaque.  The lightweight event watcher records
-- only the ordinary UNIT_SPELLCAST_INTERRUPTIBLE / NOT_INTERRUPTIBLE outcome
-- for target, focus and mouseover.  It is consumed only while P3 still
-- confirms a live cast from the same source; a NOT_INTERRUPTIBLE event is an
-- explicit veto.  The watcher never creates a binding, TEAP frame or input.
local function eventInterruptibility(source, cast)
    local tracker = TE.ReactionInterruptEvents
    if not (tracker and type(tracker.GetEvidence) == "function") then
        return { active = false, status = "unavailable", reason = "unit_event_tracker_unavailable" }
    end
    local ok, evidence = safeCall(tracker.GetEvidence, tracker, source)
    if not ok or type(evidence) ~= "table" then
        return { active = false, status = "unavailable", reason = "unit_event_read_failed" }
    end

    -- When both sides expose an ordinary spellID, reject a stale event from a
    -- prior mouseover / cast rather than letting it authorize the current P3
    -- cast.  Opaque IDs remain unknown and therefore do not manufacture a
    -- match; the short tracker TTL still bounds that case.
    local eventSpellID = plainNumber(evidence.spellID)
    local castSpellID = plainNumber(type(cast) == "table" and cast.spellID or nil)
    if eventSpellID and castSpellID and eventSpellID ~= castSpellID then
        return {
            active = false,
            status = "mismatch",
            reason = "unit_event_spell_mismatch",
            spellID = eventSpellID,
        }
    end
    return evidence
end

-- P4.4 strict evidence ranking.
--
-- Direct UnitCastingInfo/UnitChannelInfo booleans are authoritative. When the
-- Retail value is opaque, the bounded UNIT_SPELLCAST event cache may confirm or
-- veto the current read. Native UI is only a final fallback: actual shield
-- widget visibility, a current native false, or an explicit native
-- interruptible method. The `showShield` template flag is never evidence.
local function confirmedInterruptible(cast, source)
    cast = type(cast) == "table" and cast or {}
    if cast.active ~= true then return false, "cast_not_active", "unit_event_not_checked" end
    if cast.continuity == "transient_gap_hold" then return false, "transient_gap_display_only", "unit_event_not_checked" end

    local directKnown = cast.directInterruptibilityKnown == true
        or cast.interruptibilitySource == "unit_api"
        or (cast.interruptibilityEvidence == "unit_api" and cast.interruptibleKnown == true)
    if directKnown then
        if cast.interruptible == true then
            return true, "unit_api_confirmed", "unit_event_not_needed"
        end
        return false, "unit_api_not_interruptible", "unit_event_not_needed"
    end

    local nativeEvidence = type(cast.nativeInterruptibilityEvidence) == "string"
        and cast.nativeInterruptibilityEvidence or ""
    -- A current visible shield is a direct visual steel-bar conclusion. Check
    -- it before a short-lived positive event cache so a stale interruptible
    -- event can never override a presently uninterruptible cast.
    if cast.nativeSteelConfirmed == true or string.find(nativeEvidence, "native_visible_shield:", 1, true) then
        return false, "native_visible_shield", "unit_event_not_checked"
    end

    local eventEvidence = eventInterruptibility(source, cast)
    local eventStatus = type(eventEvidence.status) == "string" and eventEvidence.status or "unavailable"
    local eventReason = type(eventEvidence.reason) == "string" and eventEvidence.reason or ("unit_event_" .. eventStatus)
    if eventEvidence.active == true and eventStatus == "not_interruptible" then
        return false, "unit_event_not_interruptible", eventReason
    end
    if eventEvidence.active == true and eventStatus == "interruptible" then
        return true, "unit_event_interruptible_confirmed", eventReason
    end

    local nativeKnown = cast.nativeInterruptibilityKnown == true
        or (cast.interruptibilitySource == "native" and cast.interruptibleKnown == true)
    if nativeKnown then
        if cast.interruptible == true then
            if cast.nativeShieldKnown == true then
                return true, "visible_no_shield_confirmed", eventReason
            end
            return true, "native_explicit_interruptible_confirmed", eventReason
        end
        return false, "native_not_interruptible", eventReason
    end

    if cast.nativeCastbar == true then
        if string.find(nativeEvidence, "native_visible_no_shield:", 1, true) then
            return true, "visible_no_shield_confirmed", eventReason
        end
        if string.find(nativeEvidence, "native_scalar_false:", 1, true)
            or string.find(nativeEvidence, "native_scalar_interruptible:", 1, true)
            or string.find(nativeEvidence, "native_method_interruptible:", 1, true) then
            return true, "native_explicit_interruptible_confirmed", eventReason
        end
    end
    return false, "interruptibility_unconfirmed", eventReason
end

local NATIVE_VISUAL_MIN_SAMPLES = 2

local function nativeVisualNeedsStability(cast, confirmationReason)
    if type(cast) ~= "table" then return false end
    if cast.directInterruptibilityKnown == true or cast.interruptibilitySource == "unit_api" then return false end
    return confirmationReason == "visible_no_shield_confirmed"
        or confirmationReason == "native_explicit_interruptible_confirmed"
end

local function resetNativeVisualStability()
    runtime.nativeVisual = { castKey = nil, evidence = nil, observedAt = nil, samples = 0 }
end

local function nativeVisualStabilized(key, observation, cast, confirmationReason)
    if nativeVisualNeedsStability(cast, confirmationReason) ~= true then
        resetNativeVisualStability()
        return true, 0
    end

    local observationTime = plainNumber(type(observation) == "table" and observation.observedAt or nil)
    local evidence = type(cast.nativeInterruptibilityEvidence) == "string"
        and cast.nativeInterruptibilityEvidence or confirmationReason
    local tracker = type(runtime.nativeVisual) == "table" and runtime.nativeVisual or {}
    if tracker.castKey ~= key or tracker.evidence ~= evidence then
        tracker = { castKey = key, evidence = evidence, observedAt = observationTime, samples = 1 }
    elseif observationTime and (not tracker.observedAt or observationTime > tracker.observedAt) then
        tracker.observedAt = observationTime
        tracker.samples = math.min(NATIVE_VISUAL_MIN_SAMPLES, (tonumber(tracker.samples) or 0) + 1)
    end
    runtime.nativeVisual = tracker
    local samples = tonumber(tracker.samples) or 0
    return samples >= NATIVE_VISUAL_MIN_SAMPLES, samples
end

local function castKey(source, cast)
    cast = type(cast) == "table" and cast or {}
    local serial = math.floor(plainNumber(cast.castSerial) or 0)
    local spellID = math.floor(plainNumber(cast.spellID) or 0)
    local start = math.floor(plainNumber(cast.startTimeMS) or 0)
    local finish = math.floor(plainNumber(cast.endTimeMS) or 0)
    local kind = type(cast.kind) == "string" and cast.kind or "cast"
    return table.concat({ tostring(source), tostring(kind), tostring(serial), tostring(spellID), tostring(start), tostring(finish) }, ":")
end

local function bindingInfo(entry, route)
    return {
        status = "Ready",
        spellID = tonumber(entry and entry.spellID) or nil,
        binding = route.binding,
        rawBinding = route.binding,
        bindingToken = tonumber(route.bindingToken) or 0,
        buttonName = route.buttonName,
        actionSlot = route.actionSlot,
        slot = route.actionSlot,
        source = "reaction_interrupt_" .. tostring(route.route or "target"),
        bindingSourceIndex = route.bindingSourceIndex,
        macroName = route.macroName,
        macroAssociation = route.macroAssociation,
        macroCommand = route.macroCommand,
        actionBarStateTrusted = route.actionBarStateTrusted == true,
        directActionSlot = route.directActionSlot == true,
        cacheGeneration = entry and entry.cacheGeneration or nil,
        reactionRouteMode = route.autoRouteMode or route.routeKind,
        macroManagedTarget = route.macroManagedTarget == true,
        macroPriorityChain = route.macroPriorityChain == true,
        priorityRouteOrder = route.priorityRouteOrder,
    }
end

local function burstOwnsPriority(snapshot, decision)
    snapshot = type(snapshot) == "table" and snapshot or {}
    if snapshot.active == true or snapshot.preWindowCaptureActive == true then return true end
    if type(decision) == "table" and (decision.kind == "candidate" or decision.kind == "hold")
        and decision.dispatchOrigin == "burst" then
        return true
    end
    return false
end

local MAX_AUDIT_EVENTS = 80

local function audit(event, fields)
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.autoReactionRuntime = TacticEchoDB.autoReactionRuntime or { schema = 1, events = {} }
    local store = TacticEchoDB.autoReactionRuntime
    store.schema = 1
    store.events = type(store.events) == "table" and store.events or {}
    fields = type(fields) == "table" and fields or {}
    local record = {
        schema = 1,
        component = "TE",
        event = event,
        elapsed = now(),
        source = fields.source,
        spellID = tonumber(fields.spellID) or nil,
        reason = fields.reason,
        routeMode = fields.routeMode,
        macroManagedTarget = fields.macroManagedTarget == true,
        macroPriorityChain = fields.macroPriorityChain == true,
        burstBlocked = fields.burstBlocked == true,
        confirmationReason = fields.confirmationReason,
        eventEvidence = fields.eventEvidence,
        routeReason = fields.routeReason,
        routeRefresh = fields.routeRefresh,
        nativeEvidence = fields.nativeEvidence,
        nativeVisualSamples = tonumber(fields.nativeVisualSamples) or 0,
        castKey = fields.castKey,
        bindingToken = tonumber(fields.bindingToken) or 0,
    }
    store.last = record
    store.events[#store.events + 1] = record
    while #store.events > MAX_AUDIT_EVENTS do table.remove(store.events, 1) end
end

local function mergeValues(base, extra)
    base = type(base) == "table" and base or {}
    extra = type(extra) == "table" and extra or {}
    local out = {}
    for key, value in pairs(extra) do out[key] = value end
    for key, value in pairs(base) do out[key] = value end
    return out
end

local function setLast(values)
    local out = {
        schema = AutoReaction.schemaVersion,
        state = values.state or "idle",
        reason = values.reason or "unknown",
        enabled = values.enabled == true,
        active = values.active == true,
        source = values.source,
        spellID = tonumber(values.spellID) or nil,
        routeMode = values.routeMode,
        macroManagedTarget = values.macroManagedTarget == true,
        macroPriorityChain = values.macroPriorityChain == true,
        burstBlocked = values.burstBlocked == true,
        attempted = values.attempted == true,
        confirmationReason = values.confirmationReason,
        eventEvidence = values.eventEvidence,
        routeReason = values.routeReason,
        routeRefresh = values.routeRefresh,
        nativeEvidence = values.nativeEvidence,
        nativeVisualSamples = tonumber(values.nativeVisualSamples) or 0,
        castKey = values.castKey,
        bindingToken = tonumber(values.bindingToken) or 0,
    }
    runtime.last = out

    -- Candidate delivery continues to have its dedicated audit below.  For
    -- all other outcomes retain just one scalar record per state transition,
    -- so the field capture can tell whether P4 stopped at runtime arming,
    -- interruptibility confirmation, or a P2 route without flooding
    -- SavedVariables on ProtocolMonitor's normal poll.
    local auditSignature = table.concat({
        tostring(out.state),
        tostring(out.reason),
        tostring(out.source or "none"),
        tostring(out.spellID or 0),
        tostring(out.confirmationReason or "none"),
        tostring(out.eventEvidence or "none"),
        tostring(out.routeReason or "none"),
        tostring(out.routeRefresh or "none"),
        tostring(out.nativeEvidence or "none"),
        tostring(out.nativeVisualSamples or 0),
        tostring(out.castKey or "none"),
        tostring(out.bindingToken or 0),
        tostring(out.macroPriorityChain == true),
        tostring(out.burstBlocked == true),
    }, ":")
    if runtime.lastAuditSignature ~= auditSignature and out.state ~= "candidate" then
        runtime.lastAuditSignature = auditSignature
        audit("interrupt_state", {
            source = out.source,
            spellID = out.spellID,
            reason = out.reason,
            routeMode = out.routeMode,
            macroManagedTarget = out.macroManagedTarget,
            macroPriorityChain = out.macroPriorityChain,
            burstBlocked = out.burstBlocked,
            confirmationReason = out.confirmationReason,
            eventEvidence = out.eventEvidence,
            routeReason = out.routeReason,
            routeRefresh = out.routeRefresh,
            nativeEvidence = out.nativeEvidence,
            nativeVisualSamples = out.nativeVisualSamples,
            castKey = out.castKey,
            bindingToken = out.bindingToken,
        })
    end
    return out
end

function AutoReaction:GetSnapshot()
    local value = runtime.last or {}
    return {
        schema = self.schemaVersion,
        state = value.state,
        reason = value.reason,
        enabled = value.enabled == true,
        active = value.active == true,
        source = value.source,
        spellID = value.spellID,
        routeMode = value.routeMode,
        macroManagedTarget = value.macroManagedTarget == true,
        macroPriorityChain = value.macroPriorityChain == true,
        burstBlocked = value.burstBlocked == true,
        attempted = value.attempted == true,
        confirmationReason = value.confirmationReason,
        eventEvidence = value.eventEvidence,
        routeReason = value.routeReason,
        routeRefresh = value.routeRefresh,
        nativeEvidence = value.nativeEvidence,
        nativeVisualSamples = value.nativeVisualSamples,
        castKey = value.castKey,
        bindingToken = value.bindingToken,
    }
end

-- Keep the same candidate visible until the observed cast disappears or changes
-- identity. SignalFrame assigns it one stable TEAP sequence, and TEK dispatches
-- that stable reaction sequence at most once after a successful SendInput.
-- This removes the previous one-50ms-frame race without adding a second input
-- path or bypassing any TEK safety gate.
function AutoReaction:Evaluate(runtimeInput)
    runtimeInput = type(runtimeInput) == "table" and runtimeInput or {}
    local tactics = settings()
    local config = interruptConfig(tactics)
    local burstBlocked = burstOwnsPriority(runtimeInput.autoBurstSnapshot, runtimeInput.autoBurstDecision)

    if config.enabled ~= true then
        runtime.activeCastKey, runtime.offeredCastKey, runtime.routeRefreshCastKey = nil, nil, nil
        resetNativeVisualStability()
        setLast({ state = "disabled", reason = "interrupt_disabled", enabled = false, burstBlocked = burstBlocked })
        return { kind = "none", reason = "interrupt_disabled" }
    end
    if runtimeInput.inCombat ~= true then
        runtime.activeCastKey, runtime.offeredCastKey, runtime.routeRefreshCastKey = nil, nil, nil
        resetNativeVisualStability()
        setLast({ state = "blocked", reason = "out_of_combat", enabled = true, burstBlocked = burstBlocked })
        return { kind = "none", reason = "out_of_combat" }
    end
    if runtimeInput.intentState ~= "armed" or runtimeInput.effectiveState ~= "armed" then
        setLast({ state = "blocked", reason = "runtime_not_armed", enabled = true, burstBlocked = burstBlocked })
        return { kind = "none", reason = "runtime_not_armed" }
    end

    local observation = getObservation()
    local mappings = getBindings()
    local candidate, blocker
    local sawActiveCast = false

    for _, source in ipairs(config.targetOrder) do
        if config.targetEnabled[source] == true then
            local unit = observation and type(observation.sources) == "table" and observation.sources[source] or nil
            local cast = type(unit) == "table" and unit.cast or nil
            local isUnitEligible = type(unit) == "table" and unit.exists == true and unit.hostile == true and unit.alive == true
            local castActive = type(cast) == "table" and cast.active == true
            if isUnitEligible and castActive then
                sawActiveCast = true
                local eligible, confirmationReason, eventEvidence = confirmedInterruptible(cast, source)
                local key = castKey(source, cast)
                local nativeEvidence = type(cast.nativeInterruptibilityEvidence) == "string" and cast.nativeInterruptibilityEvidence or nil
                if eligible then
                    local visualReady, visualSamples = nativeVisualStabilized(key, observation, cast, confirmationReason)
                    if visualReady ~= true then
                        blocker = blocker or {
                            reason = "native_visual_settling",
                            source = source,
                            spellID = tonumber(cast.spellID) or nil,
                            confirmationReason = confirmationReason,
                            eventEvidence = eventEvidence,
                            routeReason = "not_evaluated_until_native_visual_stable",
                            nativeEvidence = nativeEvidence,
                            nativeVisualSamples = visualSamples,
                            castKey = key,
                        }
                    else
                        local entry, route, routeGateReason = findInterruptRoute(mappings, source, observation)
                        local refreshReason = nil
                        -- A priority-chain macro can be mapped and bound yet be
                        -- unsafe for this source because an earlier macro branch
                        -- would capture the key.  That is not a P2 cache miss, so
                        -- do not rebuild bindings for it.
                        if not (entry and route) and not routeGateReason and runtime.routeRefreshCastKey ~= key then
                            runtime.routeRefreshCastKey = key
                            local refreshed
                            refreshed, refreshReason = refreshBindingsForAuto()
                            if type(refreshed) == "table" then
                                mappings = refreshed
                                entry, route, routeGateReason = findInterruptRoute(mappings, source, observation)
                            end
                        end
                        if entry and route then
                            candidate = {
                                source = source,
                                cast = cast,
                                castKey = key,
                                entry = entry,
                                route = route,
                                confirmationReason = confirmationReason,
                                eventEvidence = eventEvidence,
                                routeRefresh = refreshReason,
                                nativeEvidence = nativeEvidence,
                                nativeVisualSamples = visualSamples,
                            }
                            break
                        end
                        blocker = blocker or {
                            reason = routeGateReason or "interrupt_binding_route_missing",
                            source = source,
                            spellID = tonumber(cast.spellID) or nil,
                            confirmationReason = confirmationReason,
                            eventEvidence = eventEvidence,
                            routeReason = routeGateReason or refreshReason or "p2_safe_route_unavailable",
                            routeRefresh = refreshReason,
                            nativeEvidence = nativeEvidence,
                            nativeVisualSamples = visualSamples,
                            castKey = key,
                        }
                    end
                else
                    blocker = blocker or {
                        reason = confirmationReason,
                        source = source,
                        spellID = tonumber(cast and cast.spellID) or nil,
                        confirmationReason = confirmationReason,
                        eventEvidence = eventEvidence,
                        routeReason = "not_evaluated_until_interruptibility_confirmed",
                        nativeEvidence = nativeEvidence,
                        nativeVisualSamples = 0,
                        castKey = key,
                    }
                end
            end
        end
    end

    if not candidate then
        runtime.activeCastKey, runtime.offeredCastKey = nil, nil
        if sawActiveCast ~= true then
            runtime.routeRefreshCastKey = nil
            resetNativeVisualStability()
        end
        local reason = burstBlocked and "burst_active_priority" or (blocker and blocker.reason or "no_interrupt_cast_observed")
        setLast({
            state = burstBlocked and "burst_hold" or "idle",
            reason = reason,
            enabled = true,
            burstBlocked = burstBlocked,
            source = blocker and blocker.source,
            spellID = blocker and blocker.spellID,
            confirmationReason = blocker and blocker.confirmationReason,
            eventEvidence = blocker and blocker.eventEvidence,
            routeReason = blocker and blocker.routeReason,
            routeRefresh = blocker and blocker.routeRefresh,
            nativeEvidence = blocker and blocker.nativeEvidence,
            nativeVisualSamples = blocker and blocker.nativeVisualSamples,
            castKey = blocker and blocker.castKey,
        })
        return {
            kind = "none",
            reason = reason,
            burstBlocked = burstBlocked,
            source = blocker and blocker.source,
            confirmationReason = blocker and blocker.confirmationReason,
            eventEvidence = blocker and blocker.eventEvidence,
            routeReason = blocker and blocker.routeReason,
            routeRefresh = blocker and blocker.routeRefresh,
            nativeEvidence = blocker and blocker.nativeEvidence,
            nativeVisualSamples = blocker and blocker.nativeVisualSamples,
            castKey = blocker and blocker.castKey,
        }
    end

    local info = bindingInfo(candidate.entry, candidate.route)
    local values = {
        enabled = true,
        active = true,
        source = candidate.source,
        spellID = candidate.entry.spellID,
        routeMode = candidate.route.autoRouteMode or candidate.route.routeKind,
        macroManagedTarget = candidate.route.macroManagedTarget == true,
        macroPriorityChain = candidate.route.macroPriorityChain == true,
        burstBlocked = burstBlocked,
        confirmationReason = candidate.confirmationReason,
        eventEvidence = candidate.eventEvidence,
        routeReason = candidate.route.routeReason or "p2_route_ready",
        routeRefresh = candidate.routeRefresh,
        nativeEvidence = candidate.nativeEvidence,
        nativeVisualSamples = candidate.nativeVisualSamples,
        castKey = candidate.castKey,
        bindingToken = info.bindingToken,
    }

    if burstBlocked then
        setLast(mergeValues({ state = "burst_hold", reason = "burst_active_priority", attempted = runtime.offeredCastKey == candidate.castKey }, values))
        return { kind = "none", reason = "burst_active_priority", burstBlocked = true, source = candidate.source }
    end

    runtime.activeCastKey = candidate.castKey
    local firstOffer = runtime.offeredCastKey ~= candidate.castKey
    runtime.offeredCastKey = candidate.castKey

    local candidateReason = "confirmed_interrupt_candidate"
    setLast(mergeValues({ state = "candidate", reason = candidateReason, attempted = true }, values))

    -- Write one concise record when a real cast first enters the reaction
    -- transport. Subsequent polls intentionally keep the same candidate alive;
    -- SignalFrame/TEK dedupe it by stable transport sequence rather than turning
    -- it into an observation hold after only one refresh.
    if firstOffer then
        audit("interrupt_candidate", {
            source = candidate.source,
            spellID = candidate.entry.spellID,
            reason = candidateReason,
            routeMode = values.routeMode,
            macroManagedTarget = values.macroManagedTarget,
            macroPriorityChain = values.macroPriorityChain,
            confirmationReason = values.confirmationReason,
            eventEvidence = values.eventEvidence,
            routeReason = values.routeReason,
            routeRefresh = values.routeRefresh,
            nativeEvidence = values.nativeEvidence,
            nativeVisualSamples = values.nativeVisualSamples,
            castKey = candidate.castKey,
            bindingToken = info.bindingToken,
        })
    end

    return {
        kind = "candidate",
        dispatchOrigin = "reaction",
        reactionKind = "interrupt",
        dispatchSpellID = tonumber(candidate.entry.spellID),
        dispatchActionKind = "spell",
        bindingInfo = info,
        source = candidate.source,
        castKey = candidate.castKey,
        routeMode = values.routeMode,
        macroManagedTarget = values.macroManagedTarget,
        macroPriorityChain = values.macroPriorityChain,
        reason = candidateReason,
        confirmationReason = candidate.confirmationReason,
        eventEvidence = candidate.eventEvidence,
        routeReason = candidate.route.routeReason or "p2_route_ready",
        routeRefresh = candidate.routeRefresh,
        nativeEvidence = candidate.nativeEvidence,
        nativeVisualSamples = candidate.nativeVisualSamples,
        deliveryStable = true,
    }
end
