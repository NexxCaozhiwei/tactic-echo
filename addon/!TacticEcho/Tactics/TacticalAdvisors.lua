-- Read-only tactical display data.
-- The primary card mirrors TacticalState, which is published from the same
-- message that is encoded into TEAP. Auxiliary cards never produce a binding
-- token or a TEK dispatch request.
local TE = _G.TacticEcho

local TacticalAdvisors = {}
TE.TacticalAdvisors = TacticalAdvisors

local lastSnapshot
local subscribers = {}
local subscriberSequence = 0
local nextRefreshAt = 0

local function perfCount(name, amount)
    local perf = TE.PerformanceDiagnostics
    if perf and type(perf.Count) == "function" then perf:Count(name, amount) end
end

local function perfBegin(name)
    local perf = TE.PerformanceDiagnostics
    return perf and type(perf.Begin) == "function" and perf:Begin(name) or nil
end

local function perfFinish(token)
    local perf = TE.PerformanceDiagnostics
    if perf and type(perf.Finish) == "function" then perf:Finish(token) end
end

local function ensureConfig()
    -- Config/Normalize.lua is the sole owner of persisted tactical and HUD
    -- defaults. Fetch both views in one normalization pass per refresh; doing
    -- this through separate helpers doubled the table walk on the HUD watcher.
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, settings, hud = TE.Config.Normalize:All()
        if type(settings) == "table" and type(hud) == "table" then return settings, hud end
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.hud = type(TacticEchoDB.tactics.hud) == "table" and TacticEchoDB.tactics.hud or {}
    return TacticEchoDB.tactics, TacticEchoDB.tactics.hud
end

local function emptyAdvisory(reason)
    reason = reason or "scope_primary_burst"
    return {
        burst = { active = false, state = reason, items = {}, advisoryOnly = true, notice = reason },
    }
end

local function emptyInterrupt(reason)
    reason = reason or "hud_primary_only"
    return {
        active = false,
        state = reason,
        suggestion = nil,
        advisoryOnly = true,
        blockedReason = reason,
    }
end

local function emptyReaction(reason)
    reason = reason or "hud_primary_only"
    return {
        schema = 1,
        active = false,
        state = reason,
        readOnly = true,
        dispatchAllowed = false,
        source = reason,
        notice = reason,
    }
end

local function spellInfo(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil, nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name, info.iconID or info.icon end
        if ok and type(info) == "string" then return info, nil end
    end
    if type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
    return nil, nil
end

local function buildOutOfCombatPrimary(context, runtimeSnapshot)
    if context and context.inCombat == true then return nil end
    local runtime = TE.RuntimeSnapshot
    local result = type(runtimeSnapshot) == "table" and runtimeSnapshot.official or nil
    if type(result) ~= "table" and TE.RecommendationAdapter and type(TE.RecommendationAdapter.ReadOfficial) == "function" then
        local ok, value = pcall(TE.RecommendationAdapter.ReadOfficial, TE.RecommendationAdapter, context)
        if ok and type(value) == "table" then result = value end
    end
    if type(result) ~= "table" then return nil end
    local spellID = tonumber(result.spellID)
    if not spellID or spellID <= 0 then return nil end

    local bindingInfo, bindingReason
    if type(runtimeSnapshot) == "table" and runtime and type(runtime.ResolveSpell) == "function" then
        bindingInfo, bindingReason = runtime:ResolveSpell(runtimeSnapshot, spellID)
    elseif TE.ActionBarBindingResolver and type(TE.ActionBarBindingResolver.ResolveSpell) == "function" then
        local ok, resolved, reason = pcall(TE.ActionBarBindingResolver.ResolveSpell, TE.ActionBarBindingResolver, spellID)
        if ok and type(resolved) == "table" then bindingInfo, bindingReason = resolved, reason end
    end
    local spellName, spellIcon
    if type(runtimeSnapshot) == "table" and runtime and type(runtime.GetSpellInfo) == "function" then
        spellName, spellIcon = runtime:GetSpellInfo(runtimeSnapshot, spellID)
    else
        spellName, spellIcon = spellInfo(spellID)
    end
    return {
        spellID = spellID,
        spellName = spellName or result.spellName or tostring(spellID),
        spellIcon = spellIcon or result.spellIcon,
        binding = bindingInfo and (bindingInfo.binding or bindingInfo.rawBinding) or nil,
        rawBinding = bindingInfo and bindingInfo.rawBinding or nil,
        bindingToken = 0,
        bindingSource = bindingInfo and bindingInfo.source or nil,
        bindingSourceIndex = bindingInfo and bindingInfo.bindingSourceIndex or nil,
        buttonName = bindingInfo and bindingInfo.buttonName or nil,
        actionSlot = bindingInfo and (bindingInfo.actionSlot or bindingInfo.slot) or nil,
        slot = bindingInfo and (bindingInfo.actionSlot or bindingInfo.slot) or nil,
        directActionSlot = bindingInfo and bindingInfo.directActionSlot == true or false,
        actionBarStateTrusted = bindingInfo and bindingInfo.actionBarStateTrusted == true or false,
        requestedSpellID = bindingInfo and (bindingInfo.requestedSpellID or spellID) or spellID,
        matchedSpellID = bindingInfo and bindingInfo.matchedSpellID or nil,
        equivalentSpellIDs = bindingInfo and bindingInfo.equivalentSpellIDs or nil,
        bindingInfo = bindingInfo,
        bindingStatus = bindingInfo and bindingInfo.status or "NoBinding",
        state = "display_only",
        reason = bindingReason,
        reasonText = "脱战只读主推荐",
        displayOnly = true,
        dispatchAllowed = false,
        inCombat = false,
        usableState = "unknown",
        cooldownRemaining = nil,
        source = "runtime_snapshot_out_of_combat_primary",
    }
end

local function primaryDisplayFromState(primary, context)
    if not primary or not primary.spellID then return nil end
    local display = {
        spellID = primary.spellID,
        spellName = primary.spellName,
        spellIcon = primary.spellIcon,
        binding = primary.binding or primary.rawBinding,
        rawBinding = primary.rawBinding,
        bindingToken = primary.bindingToken,
        bindingSource = primary.bindingSource,
        bindingSourceIndex = primary.bindingSourceIndex,
        buttonName = primary.bindingButton or primary.buttonName,
        actionSlot = primary.actionSlot or primary.bindingSlot or primary.slot,
        slot = primary.actionSlot or primary.bindingSlot or primary.slot,
        directActionSlot = primary.directActionSlot == true,
        actionBarStateTrusted = primary.actionBarStateTrusted == true,
        requestedSpellID = primary.requestedSpellID or primary.spellID,
        matchedSpellID = primary.matchedSpellID,
        equivalentSpellIDs = primary.equivalentSpellIDs,
        bindingInfo = {
            binding = primary.binding or primary.rawBinding,
            rawBinding = primary.rawBinding,
            source = primary.bindingSource,
            bindingSourceIndex = primary.bindingSourceIndex,
            buttonName = primary.bindingButton or primary.buttonName,
            actionSlot = primary.actionSlot or primary.bindingSlot or primary.slot,
            slot = primary.actionSlot or primary.bindingSlot or primary.slot,
            directActionSlot = primary.directActionSlot == true,
            actionBarStateTrusted = primary.actionBarStateTrusted == true,
            requestedSpellID = primary.requestedSpellID or primary.spellID,
            matchedSpellID = primary.matchedSpellID,
            equivalentSpellIDs = primary.equivalentSpellIDs,
        },
        state = primary.state,
        reason = primary.reason,
        reasonText = primary.reasonText,
        -- Keep the actual TEAP state/reason beside any display-only OOC
        -- projection. HUD styling can therefore give blocked/error priority
        -- over a channel-lock label without re-reading recommendations.
        runtimeState = primary.state,
        runtimeReason = primary.reason,
        runtimeReasonText = primary.reasonText,
        displayState = primary.displayState,
        channeling = type(primary.channeling) == "table" and {
            active = primary.channeling.active == true,
            name = primary.channeling.name,
            spellID = primary.channeling.spellID,
            remainingMs = primary.channeling.remainingMs,
        } or { active = false },
        empowering = type(primary.empowering) == "table" and {
            active = primary.empowering.active == true,
            name = primary.empowering.name,
            spellID = primary.empowering.spellID,
        } or { active = false },
        dispatchAllowed = primary.dispatchAllowed,
        usableState = "unknown",
        cooldownRemaining = nil,
    }
    -- Out of combat, a paused TEAP dispatch state is correct for safety but is
    -- not a reason to erase or darken the HUD's read-only recommendation.
    if context and context.inCombat ~= true then
        display.state = "display_only"
        display.reasonText = "脱战只读主推荐"
        display.displayOnly = true
        display.dispatchAllowed = false
    end
    return display
end

local ROLE_OPTIONS = {
    primary = { requiresHostileTarget = false },
    burst = { requiresHostileTarget = false },
}

local function decorateItem(item, role, runtimeSnapshot)
    if type(item) ~= "table" then return item end
    if item.itemID then
        item.usableState = item.usableState or "unknown"
        return item
    end
    if type(item.iconState) == "table" and item.iconState.schema >= 5 then return item end

    local options = {}
    for key, value in pairs(ROLE_OPTIONS[role] or {}) do options[key] = value end
    local runtime = TE.RuntimeSnapshot
    if type(runtimeSnapshot) == "table" and runtime
        and type(runtime.ResolveSpell) == "function"
        and type(runtime.CollectSpellState) == "function" then
        local binding = type(item.bindingInfo) == "table" and item.bindingInfo or nil
        if not binding and item.spellID then
            binding = runtime:ResolveSpell(runtimeSnapshot, item.spellID)
            item.bindingInfo = binding
        end
        if type(binding) == "table" then
            local slot = binding.actionSlot or binding.slot
            item.actionSlot, item.slot = slot, slot
            item.directActionSlot = binding.directActionSlot == true
            item.actionBarStateTrusted = binding.actionBarStateTrusted == true
            item.requestedSpellID = binding.requestedSpellID or item.requestedSpellID or item.spellID
            item.matchedSpellID = binding.matchedSpellID or item.matchedSpellID
            item.equivalentSpellIDs = binding.equivalentSpellIDs or item.equivalentSpellIDs
        end
        local state, reason = runtime:CollectSpellState(runtimeSnapshot, item.spellID, binding, options)
        if type(state) == "table" and TE.IconState and type(TE.IconState.ApplyState) == "function" then
            return TE.IconState:ApplyState(item, state)
        end
        item.iconState = { schema = 6, availability = "unknown", source = "runtime_snapshot_fail_safe", lastError = reason }
        item.usableState = "unknown"
        item.unusableReason = reason or "统一周期图标状态读取失败"
        return item
    end

    if TE.IconState and type(TE.IconState.Decorate) == "function" then
        local ok, err = pcall(TE.IconState.Decorate, TE.IconState, item, options)
        if not ok then
            item.iconState = { availability = "unknown", unusableReason = "图标状态安全模式", lastError = tostring(err), source = "tactical_advisors_fail_safe" }
            item.usableState = "unknown"
            item.unusableReason = "图标状态采集中断，战术面板已跳过该状态"
        end
    end
    return item
end

local function decorateCollection(items, role, runtimeSnapshot)
    for _, item in ipairs(items or {}) do decorateItem(item, role, runtimeSnapshot) end
    return items
end

-- Project only a real BindingToken-bearing Burst TEAP frame onto the matching
-- display card. Waiting, validation, GCD and retry states remain internal.
-- The HUD card stays display-only and keeps bindingToken=0; this boolean cannot
-- authorize SignalFrame, TEAP, TEK or a secure click route.
local function applyAutoBurstDispatch(primary, advisory)
    if type(primary) ~= "table"
        or primary.dispatchOrigin ~= "burst"
        or primary.dispatchAllowed ~= true
        or primary.observationOnly == true
        or (tonumber(primary.dispatchBindingToken or primary.bindingToken) or 0) <= 0 then
        return
    end
    local actionKind = primary.dispatchActionKind or "spell"
    local spellID = tonumber(primary.dispatchSpellID or primary.spellID)
    local inventorySlot = tonumber(primary.dispatchInventorySlot)
    local itemID = tonumber(primary.dispatchItemID)
    for _, item in ipairs((advisory and advisory.burst and advisory.burst.items) or {}) do
        local matches = actionKind == "inventory"
            and inventorySlot ~= nil
            and tonumber(item.inventorySlot) == inventorySlot
            and (itemID == nil or tonumber(item.itemID) == itemID)
            or actionKind ~= "inventory" and spellID ~= nil and tonumber(item.spellID) == spellID
        if matches then
            item.burstDispatchActive = true
            break
        end
    end
end

local function publish(snapshot)
    perfCount("hud_submit")
    lastSnapshot = snapshot
    for _, callback in pairs(subscribers) do pcall(callback, snapshot) end
end

function TacticalAdvisors:Refresh(force)
    local now = type(GetTime) == "function" and GetTime() or 0
    if not force and now < nextRefreshAt then return lastSnapshot end
    nextRefreshAt = now + 0.10
    perfCount("tactical_advisors_refresh")
    local timer = perfBegin("TacticalAdvisors.Refresh")

    local runtimeSnapshot = TE.RuntimeSnapshot and type(TE.RuntimeSnapshot.GetLatest) == "function"
        and TE.RuntimeSnapshot:GetLatest() or nil
    local primary = TE.TacticalState and TE.TacticalState:GetSnapshot() or nil
    local context = type(runtimeSnapshot) == "table" and type(runtimeSnapshot.context) == "table"
        and runtimeSnapshot.context or (TE.Context and TE.Context:GetPlayer() or {})
    local settings, hud = ensureConfig()
    local primaryDisplay = primaryDisplayFromState(primary, context)
    if not primaryDisplay and context.inCombat ~= true then
        primaryDisplay = buildOutOfCombatPrimary(context, runtimeSnapshot)
    end

    local runtime = {
        runtimeSnapshot = runtimeSnapshot,
        iconContext = type(runtimeSnapshot) == "table" and {
            gcdSnapshot = runtimeSnapshot.gcdSnapshot,
            castSnapshot = runtimeSnapshot.castSnapshot,
        } or {},
    }
    local advisory = emptyAdvisory("scope_primary_burst")
    if TE.BurstPlanner and type(TE.BurstPlanner.Build) == "function" then
        local perf = TE.PerformanceDiagnostics
        local ok, result
        if perf and type(perf.Guard) == "function" then
            ok, result = perf:Guard("BurstPlanner.Build", TE.BurstPlanner.Build,
                TE.BurstPlanner, primary, context, settings, runtime)
        else
            ok, result = pcall(TE.BurstPlanner.Build, TE.BurstPlanner, primary, context, settings, runtime)
        end
        if ok and type(result) == "table" then
            advisory.burst = result
        else
            advisory.burst = {
                active = false,
                state = "safe_mode",
                items = {},
                advisoryOnly = true,
                blockedReason = "burst_planner_safe_mode",
                error = tostring(result),
            }
        end
    else
        advisory.burst = {
            active = false,
            state = "unavailable",
            items = {},
            advisoryOnly = true,
            blockedReason = "burst_planner_unavailable",
        }
    end

    decorateItem(primaryDisplay, "primary", runtimeSnapshot)
    -- AutoBurst already materializes Burst cards from this exact cycle. This is
    -- intentionally a schema check only; no second binding/cooldown pass occurs.
    decorateCollection((advisory.burst or {}).items, "burst", runtimeSnapshot)
    applyAutoBurstDispatch(primary, advisory)

    local snapshot = {
        schema = 3,
        primary = primary,
        primaryDisplay = primaryDisplay,
        history = { active = false, items = {}, source = "retired_scope", notice = "candidate queue retired" },
        interrupt = emptyInterrupt("retired_scope"),
        defensives = { active = false, items = {}, state = "retired_scope", advisoryOnly = true },
        advisory = advisory,
        reaction = emptyReaction("retired_scope"),
        context = context,
        settings = settings,
        hudPrimaryOnly = hud and hud.queueMode == "primary" or false,
        observedAt = now,
        runtimeCycleId = runtimeSnapshot and runtimeSnapshot.cycleId or nil,
        queue = {
            schema = 2,
            items = {},
            order = { "primary", "burst" },
            source = "primary_burst_scope",
        },
    }
    publish(snapshot)
    perfFinish(timer)
    return snapshot
end

function TacticalAdvisors:GetSnapshot()
    return lastSnapshot or self:Refresh(true)
end

function TacticalAdvisors:Subscribe(callback)
    if type(callback) ~= "function" then return nil end
    subscriberSequence = subscriberSequence + 1
    subscribers[subscriberSequence] = callback
    return subscriberSequence
end

function TacticalAdvisors:Unsubscribe(token)
    subscribers[token] = nil
end

-- Polling-only refresh.  Tactical modules must not RegisterEvent in 0.6.8;
-- field testing showed protected-call taint chains on some clients.
local watcher = CreateFrame("Frame")
local refreshElapsed = 0
watcher:SetScript("OnUpdate", function(_, delta)
    refreshElapsed = refreshElapsed + (tonumber(delta) or 0)
    if refreshElapsed < 0.20 then return end
    refreshElapsed = 0
    -- The tactical HUD is the only consumer of this display snapshot in the
    -- current primary+burst product scope.  Do not keep rebuilding BurstPlanner
    -- and cooldown presentation data while the HUD is disabled.  SignalFrame /
    -- AutoBurst own the TEAP/TEK path and continue running independently.
    local hud = type(TacticEchoDB) == "table"
        and type(TacticEchoDB.tactics) == "table"
        and type(TacticEchoDB.tactics.hud) == "table"
        and TacticEchoDB.tactics.hud or nil
    -- Defaults enable the HUD, so a missing pre-normalization table must keep
    -- the first refresh alive. Only an explicit persisted false stops polling.
    if type(hud) == "table" and hud.enabled == false then return end
    -- Respect Refresh's own freshness gate.  Passing force=true here made the
    -- internal nextRefreshAt contract ineffective for the permanent watcher.
    TacticalAdvisors:Refresh(false)
end)
