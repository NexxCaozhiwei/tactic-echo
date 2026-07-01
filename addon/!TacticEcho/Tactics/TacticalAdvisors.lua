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

local function ensureSettings()
    -- 规范器拥有 interruptDisplayMode / controlDisplayMode / defensiveDisplayMode
    -- 等战术展示字段的默认值；本文件只读取，不再保留第二套钳制规则。
    -- Config/Normalize.lua is the sole owner of persisted tactical defaults.
    -- This fallback deliberately creates only tables: duplicating defaults here
    -- previously allowed load order to overwrite intended profile values.
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, settings = TE.Config.Normalize:All()
        return settings
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    return TacticEchoDB.tactics
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

local function bindingFor(spellID)
    if not TE.ActionBarBindingResolver or type(TE.ActionBarBindingResolver.ResolveSpell) ~= "function" then return nil end
    local info = TE.ActionBarBindingResolver:ResolveSpell(spellID)
    if not info then return nil end
    if info.status == "Ready" and info.binding then return info end
    if info.rawBinding then
        return {
            binding = info.rawBinding, bindingToken = 0, source = info.source,
            bindingSourceIndex = info.bindingSourceIndex,
            actionSlot = info.actionSlot or info.slot,
            directActionSlot = info.directActionSlot == true,
            requestedSpellID = info.requestedSpellID,
            matchedSpellID = info.matchedSpellID,
            equivalentSpellIDs = info.equivalentSpellIDs,
            advisoryOnlyBinding = true, reason = info.reason,
        }
    end
    return nil
end

local function firstBound(spellIDs)
    -- Prefer any real current action-bar binding before falling back to one
    -- unbound diagnostic card.  This keeps Hunter/other multi-interrupt lists
    -- from being pinned to an unavailable first candidate while a later skill
    -- is actually bound. It remains display-only.
    local firstUnbound = nil
    for _, spellID in ipairs(spellIDs or {}) do
        local binding = bindingFor(spellID)
        local name, icon = spellInfo(spellID)
        local item = {
            spellID = spellID,
            spellName = name or tostring(spellID),
            spellIcon = icon,
            binding = binding and binding.binding or nil,
            bindingToken = binding and binding.bindingToken or 0,
            bindingSource = binding and binding.source or nil,
            bindingSourceIndex = binding and binding.bindingSourceIndex or nil,
            actionSlot = binding and (binding.actionSlot or binding.slot) or nil,
            slot = binding and (binding.actionSlot or binding.slot) or nil,
            directActionSlot = binding and binding.directActionSlot == true or false,
            actionBarStateTrusted = binding and binding.directActionSlot == true or false,
            requestedSpellID = binding and (binding.requestedSpellID or spellID) or spellID,
            matchedSpellID = binding and binding.matchedSpellID or nil,
            equivalentSpellIDs = binding and binding.equivalentSpellIDs or nil,
            usableState = "unknown",
            cooldownRemaining = nil,
            bindingInfo = binding,
            unbound = binding == nil,
            unusableReason = binding and nil or "动作条未找到现实绑定",
            advisoryOnly = true,
        }
        if binding then return item end
        if not firstUnbound then firstUnbound = item end
    end
    return firstUnbound
end


local function idleInterrupt(classFile, settings, state, reason)
    if settings.interruptDisplayMode ~= "always" then
        return { active = false, state = state or "monitoring", cast = { active = false }, blockedReason = reason or "未监测到目标读条" }
    end
    local suggestion = TE.AbilityProfiles and firstBound(TE.AbilityProfiles:GetInterrupts(classFile)) or nil
    return {
        active = suggestion ~= nil,
        idle = true,
        state = "always_visible",
        cast = { active = false },
        interruptible = nil,
        suggestion = suggestion,
        source = "interrupt_always",
        notice = suggestion and "打断提示常驻：等待可打断读条" or "打断提示常驻：动作条未找到打断技能",
        blockedReason = suggestion and nil or "动作条未找到可用打断",
    }
end

local function buildInterrupt(classFile, settings, monitor)
    if not settings.interruptEnabled then return { active = false, disabled = true, state = "disabled" } end
    -- TacticalAdvisors samples ProtocolMonitor once per refresh and shares that
    -- immutable observation with all tactical planners.
    monitor = type(monitor) == "table" and monitor or {}
    if monitor.targetCasting ~= true then
        return idleInterrupt(classFile, settings, "monitoring", "未监测到目标读条")
    end
    if monitor.targetInterruptSuppressed == true then
        return {
            active = false,
            state = "suppressed",
            cast = { active = true, channel = monitor.targetCastKind == "channel" },
            blockedReason = "目标读条刚被打断，短暂抑制重复提示",
            source = "interrupt_suppression",
        }
    end
    local interruptible = monitor.targetInterruptibleKnown and monitor.targetInterruptible or nil
    if interruptible == false then
        local suggestion = settings.interruptDisplayMode == "always" and TE.AbilityProfiles and firstBound(TE.AbilityProfiles:GetInterrupts(classFile)) or nil
        return {
            active = suggestion ~= nil,
            state = "not_interruptible",
            cast = { active = true, channel = monitor.targetCastKind == "channel" },
            interruptible = false,
            suggestion = suggestion,
            blockedReason = "目标不可打断；请查看控制建议",
            source = "target_cast",
            notice = "当前读条不可打断",
        }
    end
    local suggestion = TE.AbilityProfiles and firstBound(TE.AbilityProfiles:GetInterrupts(classFile)) or nil
    return {
        active = suggestion ~= nil,
        state = interruptible == true and "interruptible" or "unknown",
        cast = { active = true, channel = monitor.targetCastKind == "channel" },
        interruptible = interruptible,
        dangerous = monitor.targetCastDangerous == true,
        suggestion = suggestion,
        source = "target_cast",
        notice = monitor.targetCastDangerous and "危险读条：优先打断" or "目标正在读条：打断建议",
        blockedReason = suggestion and nil or "动作条未找到可用打断",
    }
end

-- The HUD must remain useful before combat even when the TEAP signal frame is
-- intentionally paused or has never been armed.  This observer is read-only:
-- it queries the official recommendation and the current visible action-bar
-- map solely for HUD presentation.  It never publishes TEAP, writes a token,
-- changes SignalFrame state, or requests TEK input.
local function buildOutOfCombatPrimary(context)
    if context and context.inCombat == true then return nil end
    if not TE.RecommendationAdapter or type(TE.RecommendationAdapter.ReadOfficial) ~= "function" then return nil end
    local ok, result = pcall(TE.RecommendationAdapter.ReadOfficial, TE.RecommendationAdapter)
    if not ok or type(result) ~= "table" then return nil end
    local spellID = tonumber(result.spellID)
    if not spellID or spellID <= 0 then return nil end

    local bindingInfo, bindingReason
    if TE.ActionBarBindingResolver and type(TE.ActionBarBindingResolver.ResolveSpell) == "function" then
        local resolveOK, resolved, reason = pcall(TE.ActionBarBindingResolver.ResolveSpell, TE.ActionBarBindingResolver, spellID)
        if resolveOK and type(resolved) == "table" then
            bindingInfo, bindingReason = resolved, reason
        end
    end
    local spellName, spellIcon = spellInfo(spellID)
    return {
        spellID = spellID,
        spellName = spellName or tostring(spellID),
        spellIcon = spellIcon,
        binding = bindingInfo and (bindingInfo.binding or bindingInfo.rawBinding) or nil,
        bindingToken = 0, -- display observer never exposes dispatch eligibility.
        bindingSource = bindingInfo and bindingInfo.source or nil,
        bindingSourceIndex = bindingInfo and bindingInfo.bindingSourceIndex or nil,
        bindingStatus = bindingInfo and bindingInfo.status or "NoBinding",
        state = "display_only",
        reason = bindingReason,
        reasonText = "脱战只读主推荐",
        displayOnly = true,
        dispatchAllowed = false,
        inCombat = false,
        usableState = "unknown",
        cooldownRemaining = nil,
        source = "out_of_combat_display_observer",
    }
end

local function primaryDisplayFromState(primary, context)
    if not primary or not primary.spellID then return nil end
    local display = {
        spellID = primary.spellID,
        spellName = primary.spellName,
        spellIcon = primary.spellIcon,
        binding = primary.binding or primary.rawBinding,
        bindingToken = primary.bindingToken,
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

local function buildPreview(primary, settings, candidates)
    if settings.previewMode == "prediction" then
        return candidates or { mode = "prediction", label = "候选预测", items = {}, advisoryOnly = true }
    end
    local result = { mode = "history", label = "近况", items = {}, advisoryOnly = true, notice = "仅显示已发生的官方推荐记录，不代表未来步骤" }
    local source = TE.TacticalState and TE.TacticalState:GetHistory(6) or {}
    for index = #source - 1, math.max(1, #source - 3), -1 do
        local entry = source[index]
        if entry and entry.spellID and (not primary or entry.spellID ~= primary.spellID or index ~= #source) then
            entry.advisoryOnly = true
            result.items[#result.items + 1] = entry
        end
    end
    return result
end

local ROLE_OPTIONS = {
    interrupt = { requiresHostileTarget = true },
    control = { requiresHostileTarget = true },
    primary = { requiresHostileTarget = false },
    candidate = { requiresHostileTarget = false },
    defense = { requiresHostileTarget = false },
    burst = { requiresHostileTarget = false },
    mobility = { requiresHostileTarget = false },
}

local function normalizeCooldownIdentity(item)
    if type(item) ~= "table" or item.itemID then return item end
    local binding = type(item.bindingInfo) == "table" and item.bindingInfo or nil
    if not binding and item.spellID and TE.ActionBarBindingResolver and type(TE.ActionBarBindingResolver.ResolveSpell) == "function" then
        local ok, resolved = pcall(TE.ActionBarBindingResolver.ResolveSpell, TE.ActionBarBindingResolver, item.spellID)
        if ok and type(resolved) == "table" then binding = resolved; item.bindingInfo = resolved end
    end
    if binding then
        local slot = binding.actionSlot or binding.slot
        if slot then item.actionSlot, item.slot = slot, slot end
        item.directActionSlot = binding.directActionSlot == true
        item.actionBarStateTrusted = binding.directActionSlot == true
        item.requestedSpellID = binding.requestedSpellID or item.requestedSpellID or item.spellID
        item.matchedSpellID = binding.matchedSpellID or item.matchedSpellID
        item.equivalentSpellIDs = binding.equivalentSpellIDs or item.equivalentSpellIDs
    end
    return item
end

local function decorateItem(item, role, iconContext)
    if item and item.itemID then
        -- Item cards are read-only survival observations, not spell state probes.
        item.usableState = item.usableState or "unknown"
        return item
    end
    -- BurstPlanner already collects the same schema while ranking its cards.
    -- Reusing that state avoids a second cooldown/charge/range/API pass.
    if item and type(item.iconState) == "table" and item.iconState.schema >= 5 then
        return item
    end
    if item and TE.IconState and type(TE.IconState.Decorate) == "function" then
        item = normalizeCooldownIdentity(item)
        local options = {
            actionSlot = item.actionSlot or item.slot,
            directActionSlot = item.directActionSlot == true,
            actionBarStateTrusted = item.actionBarStateTrusted == true,
            requestedSpellID = item.requestedSpellID or item.spellID,
            matchedSpellID = item.matchedSpellID,
            equivalentSpellIDs = item.equivalentSpellIDs,
        }
        for key, value in pairs(ROLE_OPTIONS[role] or {}) do options[key] = value end
        if iconContext and type(iconContext.gcdSnapshot) == "table" then
            options.gcdSnapshot = iconContext.gcdSnapshot
        end
        local ok, err = pcall(function()
            TE.IconState:Decorate(item, options)
        end)
        if not ok then
            item.iconState = { availability = "unknown", unusableReason = "图标状态安全模式", lastError = tostring(err), source = "tactical_advisors_fail_safe" }
            item.usableState = "unknown"
            item.unusableReason = "图标状态采集中断，战术面板已跳过该状态"
            item.iconStateError = tostring(err)
        end
    end
    return item
end

local function decorateCollection(items, role, iconContext)
    for _, item in ipairs(items or {}) do decorateItem(item, role, iconContext) end
    return items
end

local function publish(snapshot)
    lastSnapshot = snapshot
    for _, callback in pairs(subscribers) do pcall(callback, snapshot) end
end

function TacticalAdvisors:Refresh(force)
    local now = type(GetTime) == "function" and GetTime() or 0
    if not force and now < nextRefreshAt then return lastSnapshot end
    nextRefreshAt = now + 0.10

    local primary = TE.TacticalState and TE.TacticalState:GetSnapshot() or nil
    local context = TE.Context and TE.Context:GetPlayer() or {}
    local settings = ensureSettings()
    local runtime = {
        monitor = TE.ProtocolMonitor and TE.ProtocolMonitor:Sample() or {},
        environment = TE.EnvironmentCompatibility and TE.EnvironmentCompatibility:Sample() or nil,
        iconContext = TE.IconState and type(TE.IconState.CreateRefreshContext) == "function"
            and TE.IconState:CreateRefreshContext(primary) or {},
    }
    local primaryDisplay = primaryDisplayFromState(primary, context)
    if not primaryDisplay and context.inCombat ~= true then
        primaryDisplay = buildOutOfCombatPrimary(context)
    end

    local advisory
    if TE.AdvisoryPlanner and type(TE.AdvisoryPlanner.Build) == "function" then
        -- 兼容调用形态：TE.AdvisoryPlanner:Build(primary, context, settings)
        -- 第四个 runtime 仅用于本轮共享的监控/环境/GCD 显示快照。
        local ok, result = pcall(function() return TE.AdvisoryPlanner:Build(primary, context, settings, runtime) end)
        if ok and type(result) == "table" then
            advisory = result
        else
            advisory = {
                safeMode = true,
                error = tostring(result),
                candidates = { mode = "prediction", label = "候选预测", items = {}, state = "safe_mode", advisoryOnly = true, blockedReason = "建议引擎安全模式" },
                burst = { active = false, state = "safe_mode", items = {}, advisoryOnly = true, blockedReason = "建议引擎安全模式" },
                control = { active = false, state = "safe_mode", items = {}, advisoryOnly = true, blockedReason = "建议引擎安全模式" },
                mobility = { active = false, state = "safe_mode", items = {}, advisoryOnly = true, blockedReason = "建议引擎安全模式" },
                defense = { active = false, state = "safe_mode", items = {}, advisoryOnly = true, blockedReason = "建议引擎安全模式" },
            }
        end
    else
        advisory = {
            candidates = { mode = "prediction", label = "候选预测", items = {}, state = "unavailable", advisoryOnly = true },
            burst = { active = false, state = "unavailable", items = {}, advisoryOnly = true },
            control = { active = false, state = "unavailable", items = {}, advisoryOnly = true },
            mobility = { active = false, state = "unavailable", items = {}, advisoryOnly = true },
            defense = { active = false, state = "unavailable", items = {}, advisoryOnly = true },
        }
    end
    if primaryDisplay and advisory and advisory.burst and advisory.burst.overlayPrimary == true and settings.burstHighlightPrimary ~= false then
        primaryDisplay.procHighlight = true
        primaryDisplay.burstOverlay = true
        primaryDisplay.burstState = advisory.burst.state
        primaryDisplay.burstReason = advisory.burst.notice
    end
    decorateItem(primaryDisplay, "primary", runtime.iconContext)
    decorateCollection((advisory.candidates or {}).items, "candidate", runtime.iconContext)
    decorateCollection((advisory.burst or {}).items, "burst", runtime.iconContext)
    decorateCollection((advisory.control or {}).items, "control", runtime.iconContext)
    decorateCollection((advisory.mobility or {}).items, "mobility", runtime.iconContext)

    local interrupt
    do
        local ok, result = pcall(buildInterrupt, context.class, settings, runtime.monitor)
        interrupt = ok and result or { active = false, state = "safe_mode", blockedReason = "打断建议安全模式", error = tostring(result) }
    end
    if interrupt and interrupt.suggestion then decorateItem(interrupt.suggestion, "interrupt", runtime.iconContext) end
    local defensives = advisory.defense or { active = false, items = {}, state = "unavailable" }
    decorateCollection(defensives.items, "defense", runtime.iconContext)

    local snapshot = {
        primary = primary,
        primaryDisplay = primaryDisplay,
        history = buildPreview(primary, settings, advisory.candidates),
        interrupt = interrupt,
        defensives = defensives,
        advisory = advisory,
        context = context,
        settings = settings,
        observedAt = now,
    }
    if TE.RecommendationQueue and type(TE.RecommendationQueue.Build) == "function" then
        local ok, queue = pcall(function() return TE.RecommendationQueue:Build(snapshot, settings) end)
        snapshot.queue = ok and queue or { schema = 1, items = {}, source = "queue_fail_safe", error = tostring(queue) }
    else
        snapshot.queue = { schema = 1, items = {}, source = "unavailable" }
    end
    if TE.TacticalTelemetry and type(TE.TacticalTelemetry.Record) == "function" then
        TE.TacticalTelemetry:Record(snapshot)
    end
    publish(snapshot)
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
    TacticalAdvisors:Refresh(true)
end)
