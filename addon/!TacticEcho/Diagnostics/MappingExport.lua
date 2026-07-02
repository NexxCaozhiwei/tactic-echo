local TE = _G.TacticEcho

-- MappingExport is deliberately a SavedVariables snapshot rather than a file
-- writer.  WoW addons cannot write arbitrary files.  TEK.exe can read the
-- selected SavedVariables file and include this safe, plain-data snapshot in a
-- diagnostic bundle.  It never stores macro bodies or any keybinding changes.
local MappingExport = {}
TE.MappingExport = MappingExport

local MAX_HISTORY = 5

local function ensureStore()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.diagnostics = TacticEchoDB.diagnostics or {}
    TacticEchoDB.diagnostics.mappingExports = TacticEchoDB.diagnostics.mappingExports or {}
    return TacticEchoDB.diagnostics
end

local function asNumber(value)
    local number = tonumber(value)
    return number and math.floor(number) or nil
end

local function copySpecial(state)
    state = type(state) == "table" and state or {}
    local sources = {}
    local extraActionSources = {}
    for index, value in ipairs(state.sources or {}) do
        sources[index] = tostring(value)
    end
    for index, value in ipairs(state.extraActionSources or {}) do
        extraActionSources[index] = tostring(value)
    end
    return {
        active = state.active == true,
        reason = state.reason,
        sources = sources,
        extraActionVisible = state.extraActionVisible == true,
        extraActionSources = extraActionSources,
    }
end

local function plainEntry(entry)
    entry = type(entry) == "table" and entry or {}
    local parsed = type(entry.parsedBinding) == "table" and entry.parsedBinding or {}
    local macroDiagnostic = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic or {}
    return {
        buttonName = entry.buttonName,
        bar = entry.bar,
        barOrder = asNumber(entry.barOrder),
        buttonIndex = asNumber(entry.buttonIndex),
        visualOrder = asNumber(entry.visualOrder),
        actionSlot = asNumber(entry.actionSlot),
        actionSlotSource = entry.actionSlotSource,
        actionType = entry.actionType,
        actionInfoId = asNumber(entry.actionInfoId),
        spellID = asNumber(entry.spellID),
        source = entry.source,
        bindingCommand = entry.bindingCommand,
        rawBinding = entry.rawBinding,
        bindingSourceIndex = asNumber(entry.bindingSourceIndex),
        binding = parsed.binding,
        bindingToken = asNumber(parsed.token),
        inputType = parsed.inputType,
        bindingError = entry.bindingError,
        macroID = asNumber(entry.macroID),
        macroName = entry.macroName,
        macroSpellID = asNumber(entry.macroSpellID),
        macroResolvedSpellID = asNumber(entry.macroResolvedSpellID),
        macroActionInfoSpellID = asNumber(entry.macroActionInfoSpellID),
        macroLookupSource = macroDiagnostic.lookupSource,
        macroFailureReason = macroDiagnostic.failureReason,
        scanReason = entry.scanReason,
    }
end

local function plainCandidate(candidate)
    candidate = type(candidate) == "table" and candidate or {}
    local parsed = type(candidate.parsed) == "table" and candidate.parsed or {}
    return {
        spellID = asNumber(candidate.spellID),
        actionSlot = asNumber(candidate.actionSlot or candidate.slot),
        buttonName = candidate.buttonName,
        bar = candidate.bar,
        source = candidate.source,
        bindingCommand = candidate.bindingCommand,
        rawBinding = candidate.rawBinding,
        bindingSourceIndex = asNumber(candidate.bindingSourceIndex),
        binding = parsed.binding,
        bindingToken = asNumber(parsed.token),
        inputType = parsed.inputType,
        reason = candidate.reason,
        macroID = asNumber(candidate.macroID),
        macroName = candidate.macroName,
        macroAssociation = candidate.macroAssociation,
        matchedSpellID = asNumber(candidate.matchedSpellID),
        matchKind = candidate.matchKind,
        directActionSlot = candidate.directActionSlot == true,
    }
end

local function copyBindingInfo(bindingInfo)
    bindingInfo = type(bindingInfo) == "table" and bindingInfo or {}
    local candidates = {}
    for index, candidate in ipairs(bindingInfo.candidates or {}) do
        candidates[index] = plainCandidate(candidate)
    end
    return {
        status = bindingInfo.status,
        reason = bindingInfo.reason,
        spellID = asNumber(bindingInfo.spellID),
        binding = bindingInfo.binding,
        bindingToken = asNumber(bindingInfo.bindingToken),
        source = bindingInfo.source,
        bindingSourceIndex = asNumber(bindingInfo.bindingSourceIndex),
        buttonName = bindingInfo.buttonName,
        actionSlot = asNumber(bindingInfo.actionSlot or bindingInfo.slot),
        cacheGeneration = asNumber(bindingInfo.cacheGeneration),
        requestedSpellID = asNumber(bindingInfo.requestedSpellID),
        matchedSpellID = asNumber(bindingInfo.matchedSpellID),
        matchKind = bindingInfo.matchKind,
        equivalentSpellIDs = (function()
            local out = {}
            for index, spellID in ipairs(bindingInfo.equivalentSpellIDs or {}) do out[index] = asNumber(spellID) end
            return out
        end)(),
        stateHash = asNumber(bindingInfo.stateHash),
        bindingSettling = bindingInfo.bindingSettling == true,
        directActionSlot = bindingInfo.directActionSlot == true,
        candidates = candidates,
        specialActionBar = copySpecial(bindingInfo.specialActionBar),
    }
end

local function copyAutoBurstDiagnostics()
    if not (TE.AutoBurst and type(TE.AutoBurst.GetDiagnostics) == "function") then
        return { available = false, reason = "autoburst_unavailable" }
    end
    local ok, data = pcall(TE.AutoBurst.GetDiagnostics, TE.AutoBurst)
    if not ok or type(data) ~= "table" then
        return { available = false, reason = "autoburst_diagnostics_failed" }
    end
    local rule = type(data.resolvedRule) == "table" and data.resolvedRule or {}
    local plan = type(data.plan) == "table" and data.plan or {}
    local decision = type(data.lastDecision) == "table" and data.lastDecision or {}
    local fault = type(data.lastFault) == "table" and data.lastFault or {}
    local step = type(data.lastStepObservation) == "table" and data.lastStepObservation or {}
    local message = TE.SignalFrame and type(TE.SignalFrame.GetLastMessage) == "function"
        and TE.SignalFrame:GetLastMessage() or nil
    message = type(message) == "table" and message or {}
    local officialBindingInfo = type(message.officialBindingInfo) == "table" and message.officialBindingInfo or {}
    local dispatchBindingInfo = type(message.bindingInfo) == "table" and message.bindingInfo or {}
    local candidate = type(data.lastCandidate) == "table" and data.lastCandidate or {}
    return {
        available = true,
        build = data.build,
        enabled = data.enabled == true,
        direction = data.direction,
        mode = data.mode,
        manualWindowSpellID = asNumber(data.manualWindowSpellID),
        manualInjectionSpellID = asNumber(data.manualInjectionSpellID),
        useProfileFallback = data.useProfileFallback == true,
        ruleReason = data.ruleReason,
        armedEpoch = asNumber(data.armedEpoch),
        firstHealthyFramePending = data.firstHealthyFramePending == true,
        windowGeneration = asNumber(data.windowGeneration),
        consumedWindowGeneration = asNumber(data.consumedWindowGeneration),
        activePlanGeneration = asNumber(data.activePlanGeneration),
        departureLockGeneration = asNumber(data.departureLockGeneration),
        officialSpellID = asNumber(message.officialSpellID or decision.officialSpellID),
        officialBinding = officialBindingInfo.binding or officialBindingInfo.rawBinding,
        dispatchSpellID = asNumber(message.dispatchSpellID or candidate.spellID),
        dispatchBinding = message.binding or dispatchBindingInfo.binding or dispatchBindingInfo.rawBinding or candidate.binding,
        dispatchOrigin = message.dispatchOrigin or "official",
        observationOnly = message.observationOnly == true,
        planState = plan.planState or plan.state,
        currentStep = asNumber(plan.currentStep),
        stepState = plan.stepState,
        stepStatusReason = plan.stepStatusReason or step.reason,
        lastCandidate = {
            spellID = asNumber(candidate.spellID),
            role = candidate.role,
            bindingToken = asNumber(candidate.bindingToken),
            binding = candidate.binding,
            dispatchAttempt = asNumber(candidate.dispatchAttempt),
            offerCount = asNumber(candidate.offerCount),
            windowGeneration = asNumber(candidate.windowGeneration),
        },
        candidateOfferCount = asNumber(plan.candidateOfferCount),
        lastSpellcastSuccess = {
            spellID = asNumber(type(data.lastSpellcastSuccess) == "table" and data.lastSpellcastSuccess.spellID),
        },
        lastConfirmationSource = data.lastConfirmationSource,
        lastAbortReason = data.lastAbortReason,
        lastWindowRejectReason = data.lastWindowRejectReason,
        resolvedRule = {
            id = rule.id,
            source = rule.source,
            profileKey = rule.profileKey,
            windowSpellID = asNumber(rule.windowSpellID),
            injectionSpellID = asNumber(rule.injectionSpellID),
        },
        plan = {
            active = plan.active == true,
            planId = asNumber(plan.planId),
            ruleId = plan.ruleId,
            state = plan.state,
            currentStep = asNumber(plan.currentStep),
            currentRole = plan.currentRole,
            currentSpellID = asNumber(plan.currentSpellID),
            pauseReason = plan.pauseReason,
            requireWindowDeparture = plan.requireWindowDeparture == true,
            preInjectionRequired = plan.preInjectionRequired == true,
            preInjectionSkipAllowed = plan.preInjectionSkipAllowed == true,
            waitingForConfirmation = plan.waitingForConfirmation == true,
            pendingConfirmationSpellID = asNumber(plan.pendingConfirmationSpellID),
            confirmationEventSpellID = asNumber(plan.confirmationEventSpellID),
            armedEpoch = asNumber(plan.armedEpoch),
            firstHealthyFramePending = plan.firstHealthyFramePending == true,
            windowGeneration = asNumber(plan.windowGeneration),
            consumedWindowGeneration = asNumber(plan.consumedWindowGeneration),
            activePlanGeneration = asNumber(plan.activePlanGeneration),
            departureLockGeneration = asNumber(plan.departureLockGeneration),
            planWindowGeneration = asNumber(plan.planWindowGeneration),
            planState = plan.planState,
            stepState = plan.stepState,
            stepStatusReason = plan.stepStatusReason,
            initialInjectionPhase = plan.initialInjectionPhase,
            initialInjectionReason = plan.initialInjectionReason,
            initialWindowPhase = plan.initialWindowPhase,
            initialWindowReason = plan.initialWindowReason,
            candidateOfferCount = asNumber(plan.candidateOfferCount),
        },
        lastDecision = {
            phase = decision.phase,
            reason = decision.reason,
            officialSpellID = asNumber(decision.officialSpellID),
            windowSpellID = asNumber(decision.windowSpellID),
            injectionSpellID = asNumber(decision.injectionSpellID),
            ruleSource = decision.ruleSource,
            state = decision.state,
        },
        lastStepObservation = {
            stage = step.stage,
            role = step.role,
            spellID = asNumber(step.spellID),
            phase = step.phase,
            reason = step.reason,
            bindingStatus = step.bindingStatus,
            bindingReason = step.bindingReason,
            bindingToken = asNumber(step.bindingToken),
            binding = step.binding,
            matchedSpellID = asNumber(step.matchedSpellID),
            cooldownKnown = step.cooldownKnown == true,
            cooldownActive = step.cooldownActive == true,
            cooldownOnGCD = step.cooldownOnGCD == true,
            cooldownPublicActiveKnown = step.cooldownPublicActiveKnown == true,
            cooldownPublicActive = step.cooldownPublicActive,
            cooldownPublicOnGCDKnown = step.cooldownPublicOnGCDKnown == true,
            cooldownPublicOnGCD = step.cooldownPublicOnGCD,
            cooldownGcdAlias = step.cooldownGcdAlias == true,
            cooldownLiveRead = step.cooldownLiveRead == true,
            cooldownSource = step.cooldownSource,
            chargeCount = asNumber(step.chargeCount),
            chargeMaximum = asNumber(step.chargeMaximum),
        },
        lastFault = {
            reason = fault.reason,
        },
    }
end

local function copyCastLockTransitions()
    local source = TE.SignalFrame and type(TE.SignalFrame.GetCastLockDiagnostics) == "function"
        and TE.SignalFrame:GetCastLockDiagnostics() or {}
    local copied = {}
    for index, entry in ipairs(source) do
        entry = type(entry) == "table" and entry or {}
        copied[index] = {
            schemaVersion = asNumber(entry.schemaVersion),
            component = entry.component,
            eventType = entry.eventType,
            observedAt = entry.observedAt,
            elapsed = asNumber(entry.elapsed),
            event = entry.event,
            outcome = entry.outcome,
            eventSpellID = asNumber(entry.eventSpellID),
            beforeActive = entry.beforeActive == true,
            beforeKind = entry.beforeKind,
            beforeSource = entry.beforeSource,
            beforeSpellID = asNumber(entry.beforeSpellID),
            beforeHasCastGUID = entry.beforeHasCastGUID == true,
            afterActive = entry.afterActive == true,
            afterKind = entry.afterKind,
            afterSource = entry.afterSource,
            afterSpellID = asNumber(entry.afterSpellID),
            afterHasCastGUID = entry.afterHasCastGUID == true,
        }
    end
    return copied
end

-- Movement binding export is diagnostic-only.  It lets TEK compare the
-- persisted bindings-cache.wtf classification with the live WoW binding table;
-- it is never passed into TEAP, BindingToken resolution, or input dispatch.
local MOVEMENT_BINDING_COMMANDS = {
    "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT",
    "TURNLEFT", "TURNRIGHT", "JUMP", "TOGGLEAUTORUN", "TOGGLERUN",
}

local function copyMovementBindings()
    local entries = {}
    if type(GetBindingKey) ~= "function" then return entries end
    for _, command in ipairs(MOVEMENT_BINDING_COMMANDS) do
        local primary, secondary = GetBindingKey(command)
        entries[#entries + 1] = {
            command = command,
            primary = primary,
            secondary = secondary,
        }
    end
    return entries
end

local function copyLastMessage()
    local message = TE.SignalFrame and type(TE.SignalFrame.GetLastMessage) == "function"
        and TE.SignalFrame:GetLastMessage() or nil
    message = type(message) == "table" and message or {}
    return {
        state = message.state,
        intentState = message.intentState,
        sequence = asNumber(message.sequence),
        frameFreshnessCounter = asNumber(message.frameFreshnessCounter),
        spellID = asNumber(message.spellID),
        officialSpellID = asNumber(message.officialSpellID),
        dispatchSpellID = asNumber(message.dispatchSpellID),
        dispatchOrigin = message.dispatchOrigin,
        observationOnly = message.observationOnly == true,
        observationReason = message.observationReason,
        binding = message.binding,
        officialBinding = type(message.officialBindingInfo) == "table" and message.officialBindingInfo.binding or nil,
        bindingToken = asNumber(message.bindingToken),
        bindingReason = message.bindingReason,
        unresolvedReason = message.unresolvedReason,
        inCombat = message.inCombat == true,
        inputFocusActive = message.inputFocusActive == true,
        manualHoldActive = message.manualHoldActive == true,
        channelingActive = message.channelingActive == true,
        empoweringActive = message.empoweringActive == true,
        monitorFlags = asNumber(message.monitorFlags),
        monitor = type(message.monitor) == "table" and {
            targetCasting = message.monitor.targetCasting == true,
            targetInterruptible = message.monitor.targetInterruptible == true,
            playerHealthCritical = message.monitor.playerHealthCritical == true,
            healthSource = message.monitor.healthSource,
        } or nil,
        bindingInfo = copyBindingInfo(message.bindingInfo),
    }
end

function MappingExport:Capture(reason)
    local resolver = TE.ActionBarBindingResolver
    local cache = resolver and type(resolver.GetButtonCache) == "function"
        and resolver:GetButtonCache() or { entries = {}, diagnostics = {}, state = {} }
    local summary = resolver and type(resolver.GetCacheSummary) == "function"
        and resolver:GetCacheSummary() or {}
    local entries = {}
    local diagnostics = {}
    for index, entry in ipairs(cache.entries or {}) do
        entries[index] = plainEntry(entry)
    end
    for index, entry in ipairs(cache.diagnostics or {}) do
        diagnostics[index] = plainEntry(entry)
    end

    local snapshot = {
        schemaVersion = 1,
        component = "TE",
        eventType = "mapping_export",
        exportedAt = date("%Y-%m-%d %H:%M:%S"),
        elapsed = GetTime and GetTime() or 0,
        reason = reason or "manual",
        cache = {
            generation = asNumber(summary.generation),
            scanReason = summary.scanReason,
            scannedButtons = asNumber(summary.scannedButtons),
            visibleButtons = asNumber(summary.visibleButtons),
            entries = asNumber(summary.entries),
            macroEntries = asNumber(summary.macroEntries),
            diagnostics = asNumber(summary.diagnostics),
            mainPage = asNumber(summary.mainPage),
            blockedBySpecialActionBar = summary.blockedBySpecialActionBar == true,
            specialActionBar = copySpecial(summary.specialActionBar),
        },
        entries = entries,
        diagnostics = diagnostics,
        lastSignal = copyLastMessage(),
        movementBindings = copyMovementBindings(),
        castLockTransitions = copyCastLockTransitions(),
        autoBurst = copyAutoBurstDiagnostics(),
    }

    local store = ensureStore()
    store.mappingExport = snapshot
    store.mappingExports[#store.mappingExports + 1] = snapshot
    while #store.mappingExports > MAX_HISTORY do
        table.remove(store.mappingExports, 1)
    end
    return snapshot
end

function MappingExport:GetLatest()
    local store = ensureStore()
    return store.mappingExport
end

return MappingExport
