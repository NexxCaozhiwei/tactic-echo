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
local REACTION_READONLY_HIGHLIGHT_SUSPENDED = true

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

local function ensureHudSettings()
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, _, hud = TE.Config.Normalize:All()
        if type(hud) == "table" then return hud end
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.hud = type(TacticEchoDB.tactics.hud) == "table" and TacticEchoDB.tactics.hud or {}
    return TacticEchoDB.tactics.hud
end

local function emptyAdvisory(reason)
    reason = reason or "hud_primary_only"
    return {
        candidates = { active = false, mode = "primary_only", items = {}, state = reason, advisoryOnly = true, notice = reason },
        burst = { active = false, state = reason, items = {}, advisoryOnly = true, notice = reason },
        control = { active = false, state = reason, items = {}, advisoryOnly = true, notice = reason },
        mobility = { active = false, state = reason, items = {}, advisoryOnly = true, notice = reason },
        defense = { active = false, state = reason, items = {}, advisoryOnly = true, notice = reason },
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

local function verifiedManualPresentationSource(info)
    if type(info) ~= "table" or info.source ~= "macro" then return true end
    local resolver = TE.ActionBarBindingResolver
    if resolver and type(resolver.IsVerifiedCurrentMacroSource) == "function" then
        local verified = resolver:IsVerifiedCurrentMacroSource(info, info.macroAssociation)
        return verified == true
    end
    -- Conservative load-order fallback: this is intentionally narrower than
    -- the resolver contract and never admits opaque action-info compatibility.
    local diagnostic = type(info.macroDiagnostic) == "table" and info.macroDiagnostic or {}
    local association = tostring(info.macroAssociation or "")
    return diagnostic.macroIdentityVerified == true
        and type(info.macroSemantics) == "table"
        and (association:find("macro_body_", 1, true) == 1
            or association:find("macro_item_", 1, true) == 1
            or association:find("macro_inventory_", 1, true) == 1)
end

local function actionbarPresentationSource(info)
    info = type(info) == "table" and info or nil
    if not info or type(info.buttonName) ~= "string" or info.buttonName == "" then return nil end
    if verifiedManualPresentationSource(info) ~= true then return nil end
    -- A visible default button / verified macro remains a legitimate HUD manual
    -- source even when it has no keyboard binding or an unsupported BindingToken.
    -- It remains bindingToken=0 and cannot authorize TEAP/TEK dispatch.
    return {
        binding = info.binding or info.rawBinding,
        bindingToken = 0,
        source = info.source,
        bindingSourceIndex = info.bindingSourceIndex,
        actionSlot = info.actionSlot or info.slot,
        slot = info.actionSlot or info.slot,
        buttonName = info.buttonName,
        directActionSlot = info.directActionSlot == true,
        actionBarStateTrusted = info.actionBarStateTrusted == true,
        requestedSpellID = info.requestedSpellID,
        matchedSpellID = info.matchedSpellID,
        equivalentSpellIDs = info.equivalentSpellIDs,
        macroID = info.macroID,
        macroAssociation = info.macroAssociation,
        macroDiagnostic = info.macroDiagnostic,
        macroSemantics = info.macroSemantics,
        manualActionSource = true,
        advisoryOnlyBinding = true,
        reason = info.reason,
    }
end

local function bindingFor(spellID)
    if not TE.ActionBarBindingResolver or type(TE.ActionBarBindingResolver.ResolveSpell) ~= "function" then return nil end
    local info = TE.ActionBarBindingResolver:ResolveSpell(spellID)
    if not info then return nil end
    if info.status == "Ready" and info.binding and verifiedManualPresentationSource(info) == true then return info end
    return actionbarPresentationSource(info)
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
            buttonName = binding and binding.buttonName or nil,
            actionSlot = binding and (binding.actionSlot or binding.slot) or nil,
            slot = binding and (binding.actionSlot or binding.slot) or nil,
            directActionSlot = binding and binding.directActionSlot == true or false,
            actionBarStateTrusted = binding and binding.actionBarStateTrusted == true or false,
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


-- P3 reaction planner. This is still a display-only projection: it joins the
-- existing action-bar/macro mapping snapshot with ProtocolMonitor's shared
-- target/focus/mouseover/nameplate observations. It must not construct a
-- BindingToken, touch TEAP, call TEK, or alter AutoBurst / official rotation.
local REACTION_SOURCE_ORDER = { "target", "focus", "mouseover" }
local REACTION_SOURCE_LABELS = {
    target = "当前目标",
    focus = "焦点目标",
    mouseover = "鼠标指向目标",
}

local function reactionBranch(settings, name)
    local auto = type(settings) == "table" and settings.autoReaction or nil
    local branch = type(auto) == "table" and auto[name] or nil
    branch = type(branch) == "table" and branch or {}
    local enabled = type(branch.targetEnabled) == "table" and branch.targetEnabled or {}
    local requested = type(branch.targetOrder) == "table" and branch.targetOrder or REACTION_SOURCE_ORDER
    local order, seen = {}, {}
    for _, source in ipairs(requested) do
        if REACTION_SOURCE_LABELS[source] and seen[source] ~= true then
            order[#order + 1] = source
            seen[source] = true
        end
    end
    for _, source in ipairs(REACTION_SOURCE_ORDER) do
        if seen[source] ~= true then
            order[#order + 1] = source
            seen[source] = true
        end
    end
    return branch, enabled, order
end

local function reactionBindingSnapshot()
    local bindings = TE.ReactionBindings
    if not (bindings and type(bindings.GetSnapshot) == "function") then return nil end
    local ok, snapshot = pcall(bindings.GetSnapshot, bindings)
    return ok and type(snapshot) == "table" and snapshot or nil
end

local function reactionRoute(snapshot, group, role, routeName, requireSafeRoute)
    snapshot = type(snapshot) == "table" and snapshot or {}
    for _, entry in ipairs(snapshot[group] or {}) do
        if role == nil or entry.role == role then
            local route = type(entry.routes) == "table" and entry.routes[routeName] or nil
            if type(route) == "table" and route.bindingReady == true and type(route.binding) == "string" and route.binding ~= "" then
                if requireSafeRoute ~= true or route.safeForFutureAuto == true then
                    return entry, route
                end
            end
        end
    end
    return nil, nil
end

-- A cursor/conditional control macro may be executable by its own existing
-- button but cannot truthfully be recast as a target/focus/mouseover route.
-- Use this only as a read-only manual-source fallback after the source-specific
-- route lookup fails. It never carries a dispatch token or a safe-auto flag.
local function reactionManualSource(snapshot, group, role)
    snapshot = type(snapshot) == "table" and snapshot or {}
    for _, entry in ipairs(snapshot[group] or {}) do
        if role == nil or entry.role == role then
            local source = type(entry.manualSource) == "table" and entry.manualSource or nil
            if source and source.manualActionSource == true
                and type(source.buttonName) == "string" and source.buttonName ~= ""
                and tonumber(source.actionSlot) then
                return entry, source
            end
        end
    end
    return nil, nil
end

local function reactionItem(entry, route, candidate, reactionKind)
    entry = type(entry) == "table" and entry or {}
    route = type(route) == "table" and route or {}
    candidate = type(candidate) == "table" and candidate or {}
    local aoe = reactionKind == "aoe_control"
    return {
        spellID = tonumber(entry.spellID),
        spellName = entry.spellName,
        spellIcon = entry.spellIcon,
        binding = route.binding,
        -- Advisory HUD cards stay incapable of dispatch, even when the
        -- underlying P2 mapping parsed a real action-bar binding.
        bindingToken = 0,
        -- Preserve the exact current visible source so HUD click verification
        -- cannot replace a user-authored macro (e.g. CTRL+1 cursor trap) with
        -- another same-spell action-bar copy.
        buttonName = route.buttonName,
        bindingSource = route.source,
        bindingSourceIndex = route.bindingSourceIndex,
        actionSlot = route.actionSlot,
        slot = route.actionSlot,
        directActionSlot = route.directActionSlot == true,
        actionBarStateTrusted = route.actionBarStateTrusted == true,
        unbound = false,
        advisoryOnly = true,
        displayOnly = true,
        usableState = "unknown",
        category = aoe and "aoe_control" or (reactionKind == "interrupt" and "interrupt" or "control"),
        source = "reaction_p3_observer",
        procHighlight = true,
        reactionHighlight = true,
        reactionKind = reactionKind,
        reactionSource = candidate.source,
        reactionSourceLabel = REACTION_SOURCE_LABELS[candidate.source] or (aoe and "可见姓名板" or "目标"),
        reactionObservedTarget = aoe ~= true,
        reactionAoe = aoe,
        reactionRouteSafe = route.safeForFutureAuto == true,
        reactionRouteMode = route.autoRouteMode or route.routeKind,
        reactionRouteAvailable = route.manualActionSource ~= true,
        reactionManualActionSource = route.manualActionSource == true,
        reactionMappingRequired = true,
        reactionQualifyingCount = aoe and tonumber(candidate.qualifyingCount) or nil,
        reactionAoeThreshold = aoe and tonumber(candidate.threshold) or nil,
    }
end

-- P3 is a visual observation stage, not an automatic-dispatch stage. A missing
-- P2 route must not suppress a proven cast highlight; otherwise cast sampling
-- and macro/action-bar mapping cannot be tested independently. This fallback
-- shows the class profile icon as an unbound/read-only prompt. It intentionally
-- carries bindingToken=0 and P4 must not treat it as an executable route.
local function reactionFallbackItem(classFile, reactionKind, candidate)
    local spellIDs = {}
    if reactionKind == "interrupt" then
        if TE.AbilityProfiles and type(TE.AbilityProfiles.GetInterrupts) == "function" then
            spellIDs = TE.AbilityProfiles:GetInterrupts(classFile) or {}
        end
    elseif reactionKind == "single_control" then
        if TE.AbilityProfiles and type(TE.AbilityProfiles.GetReactionControls) == "function" then
            for _, control in ipairs(TE.AbilityProfiles:GetReactionControls(classFile) or {}) do
                if type(control) == "table" and control.role == "single" and tonumber(control.spellID) then
                    spellIDs[#spellIDs + 1] = tonumber(control.spellID)
                end
            end
        end
    end
    local item = firstBound(spellIDs)
    if not item then return nil end
    candidate = type(candidate) == "table" and candidate or {}
    item.bindingToken = 0
    item.advisoryOnly = true
    item.displayOnly = true
    item.procHighlight = true
    item.reactionHighlight = true
    item.reactionKind = reactionKind
    item.reactionSource = candidate.source
    item.reactionSourceLabel = REACTION_SOURCE_LABELS[candidate.source] or "目标"
    item.reactionObservedTarget = true
    item.reactionAoe = false
    item.reactionRouteSafe = false
    item.reactionRouteMode = "unmapped_display_fallback"
    item.reactionRouteAvailable = false
    item.reactionMappingRequired = true
    item.category = reactionKind == "interrupt" and "interrupt" or "control"
    item.source = "reaction_p3_profile_fallback"
    item.unusableReason = item.binding and "未解析到 P2 目标路由；当前仅提示" or "动作条/宏尚未识别；当前仅提示"
    return item
end

local function unitReactionCandidate(observation, settings, classFile, configName, bindingSnapshot, reactionKind)
    observation = type(observation) == "table" and observation or {}
    local _, sourceEnabled, sourceOrder = reactionBranch(settings, configName)
    for _, source in ipairs(sourceOrder) do
        if sourceEnabled[source] == true then
            local unit = type(observation.sources) == "table" and observation.sources[source] or nil
            local cast = type(unit) == "table" and unit.cast or nil
            local observed = type(unit) == "table" and unit.hostile == true and unit.alive == true
                and type(cast) == "table" and cast.active == true
            if observed then
                if reactionKind == "interrupt" and cast.interruptibleKnown == true and cast.interruptible == true then
                    local entry, route = reactionRoute(bindingSnapshot, "interrupt", "interrupt", source, false)
                    local item = entry and route and reactionItem(entry, route, { source = source }, "interrupt")
                        or reactionFallbackItem(classFile, "interrupt", { source = source })
                    if item then
                        return {
                            kind = "interrupt", source = source, castKind = cast.kind,
                            castSpellID = cast.spellID, item = item,
                            routeAvailable = entry ~= nil and route ~= nil,
                            verification = "confirmed",
                        }
                    end
                elseif reactionKind == "interrupt" and cast.interruptibleKnown ~= true then
                    -- P3 diagnostic pre-alert: Retail may keep the ordinary
                    -- notInterruptible bit secret while a cast is undeniably
                    -- present. Keep the HUD useful for validation, but label
                    -- this strictly read-only and explicitly ineligible for
                    -- P4/P5 auto dispatch. Confirmed steel bars remain
                    -- suppressed whenever any native source resolves them.
                    local entry, route = reactionRoute(bindingSnapshot, "interrupt", "interrupt", source, false)
                    local item = entry and route and reactionItem(entry, route, { source = source }, "interrupt")
                        or reactionFallbackItem(classFile, "interrupt", { source = source })
                    if item then
                        item.reactionVerification = "unverified"
                        item.reactionAutoEligible = false
                        item.reactionProbeOnly = true
                        item.unusableReason = "读条已观察到，但客户端未暴露钢条状态；P3 仅提示，不能自动打断"
                        return {
                            kind = "interrupt_unverified", source = source, castKind = cast.kind,
                            castSpellID = cast.spellID, item = item,
                            routeAvailable = entry ~= nil and route ~= nil,
                            verification = "unverified",
                        }
                    end
                elseif reactionKind == "single_control" and cast.interruptibleKnown == true
                    and cast.interruptible == false and unit.controlEligible == true then
                    local entry, route = reactionRoute(bindingSnapshot, "control", "single", source, false)
                    local manualSource = false
                    if not entry or not route then
                        entry, route = reactionManualSource(bindingSnapshot, "control", "single")
                        manualSource = entry ~= nil and route ~= nil
                    end
                    local item = entry and route and reactionItem(entry, route, { source = source }, "single_control")
                        or reactionFallbackItem(classFile, "single_control", { source = source })
                    if item then
                        if manualSource then
                            item.reactionManualActionSource = true
                            item.reactionRouteAvailable = false
                            item.reactionRouteSafe = false
                            item.reactionRouteMode = "manual_existing_macro"
                            item.unusableReason = "已识别当前可见控制宏；仅可点击 HUD 或原生动作条执行，保留宏的原目标/落点语义，不参与派发"
                        end
                        return {
                            kind = "single_control", source = source, castKind = cast.kind,
                            castSpellID = cast.spellID, item = item,
                            routeAvailable = entry ~= nil and route ~= nil and manualSource ~= true,
                            manualSource = manualSource,
                            verification = "confirmed",
                        }
                    end
                end
            end
        end
    end
    return nil
end

-- P3.2 repair path: ProtocolMonitor already samples the current target through
-- the same polling cadence.  Keep ReactionObservation as the canonical source,
-- but reconcile a target-cast record when the observer had an API-materialising
-- failure. This is still display-only and never promotes unknown target facts.
local function withTargetMonitorFallback(observation, monitor)
    observation = type(observation) == "table" and observation or {}
    monitor = type(monitor) == "table" and monitor or {}
    local sources = type(observation.sources) == "table" and observation.sources or {}
    local target = type(sources.target) == "table" and sources.target or nil
    if not target or target.hostile ~= true or target.alive ~= true or monitor.targetCasting ~= true then
        return observation
    end
    local currentCast = type(target.cast) == "table" and target.cast or {}
    local needsCast = currentCast.active ~= true
    local needsInterruptState = currentCast.interruptibleKnown ~= true and monitor.targetInterruptibleKnown == true
    if needsCast ~= true and needsInterruptState ~= true then return observation end

    local copiedSources, copiedTarget, copiedCast = {}, {}, {}
    for key, value in pairs(sources) do copiedSources[key] = value end
    for key, value in pairs(target) do copiedTarget[key] = value end
    for key, value in pairs(currentCast) do copiedCast[key] = value end
    if needsCast == true then
        copiedCast.active = true
        copiedCast.kind = monitor.targetCastKind or copiedCast.kind
        copiedCast.spellID = monitor.targetCastSpellID or copiedCast.spellID
        copiedCast.evidence = "protocol_monitor_target_fallback"
    end
    if needsInterruptState == true then
        copiedCast.interruptibleKnown = true
        copiedCast.interruptible = monitor.targetInterruptible == true
        copiedCast.evidence = copiedCast.evidence or "protocol_monitor_interruptibility_fallback"
    end
    copiedTarget.cast = copiedCast
    copiedSources.target = copiedTarget

    local copied = {}
    for key, value in pairs(observation) do copied[key] = value end
    copied.sources = copiedSources
    copied.reconciledTargetCast = true
    return copied
end

local function reactionObservationDiagnostics(observation, monitor, bindingsAvailable)
    observation = type(observation) == "table" and observation or {}
    monitor = type(monitor) == "table" and monitor or {}
    local sources = type(observation.sources) == "table" and observation.sources or {}
    local target = type(sources.target) == "table" and sources.target or {}
    local cast = type(target.cast) == "table" and target.cast or {}
    local interruptState = cast.interruptibleKnown == true
        and (cast.interruptible == true and "interruptible" or "not_interruptible")
        or "unknown"
    return {
        observerAvailable = type(observation) == "table",
        bindingsAvailable = bindingsAvailable == true,
        targetExists = target.exists == true,
        targetHostile = target.hostile == true,
        targetAlive = target.alive == true,
        targetCastActive = cast.active == true,
        targetCastKind = cast.kind,
        targetCastEvidence = cast.evidence,
        targetCastArity = tonumber(cast.apiReturnArity),
        targetNativeCastbar = cast.nativeCastbar == true,
        targetNativeCastbarSource = cast.nativeBarSource,
        targetNativeInterruptibilityEvidence = cast.interruptibilityEvidence,
        targetNativeSteelConfirmed = cast.nativeSteelConfirmed == true,
        targetNativeShieldKnown = cast.nativeShieldKnown == true,
        targetNativeShieldVisible = cast.nativeShieldVisible == true,
        targetNativeShieldSource = cast.nativeShieldSource,
        targetCastContinuity = cast.continuity,
        targetInterruptState = interruptState,
        monitorTargetCasting = monitor.targetCasting == true,
        reconciledTargetCast = observation.reconciledTargetCast == true,
    }
end

local function aoeReactionCandidate(observation, bindingSnapshot)
    observation = type(observation) == "table" and observation or {}
    local aoe = type(observation.aoe) == "table" and observation.aoe or {}
    if aoe.active ~= true then return nil end
    -- User-confirmed ground-control contract: an area-control candidate exists
    -- only when the existing visible macro has an explicit @cursor route.
    local entry, route = reactionRoute(bindingSnapshot, "control", "aoe", "cursor", true)
    if not entry or not route then return nil end
    return {
        kind = "aoe_control",
        source = "nameplate",
        qualifyingCount = tonumber(aoe.qualifyingCount) or 0,
        threshold = tonumber(aoe.threshold) or 4,
        item = reactionItem(entry, route, {
            source = "nameplate", qualifyingCount = tonumber(aoe.qualifyingCount) or 0, threshold = tonumber(aoe.threshold) or 4,
        }, "aoe_control"),
    }
end

local function buildReactionReadOnly(settings, monitor)
    local observation = type(monitor) == "table" and monitor.reaction or nil
    local out = {
        schema = 1,
        active = false,
        state = "monitoring",
        readOnly = true,
        dispatchAllowed = false,
        source = "p3_reaction_observer",
        interrupt = nil,
        aoe = nil,
        control = nil,
        selected = nil,
        auto = nil,
    }
    if type(observation) ~= "table" then
        out.state = "observation_unavailable"
        out.diagnostics = reactionObservationDiagnostics({}, monitor, false)
        return out
    end

    local mappings = reactionBindingSnapshot()
    local bindingsAvailable = mappings ~= nil
    -- P3 highlight validation must not disappear merely because the P2 cache
    -- is temporarily unavailable during login/actionbar reconstruction. Empty
    -- mapping data still permits the immutable profile fallback card; P4/P5
    -- must require a real route again before any dispatch is considered.
    mappings = mappings or { interrupt = {}, control = {}, source = "p3_empty_mapping_fallback" }
    observation = withTargetMonitorFallback(observation, monitor)
    out.diagnostics = reactionObservationDiagnostics(observation, monitor, bindingsAvailable)

    local context = TE.Context and TE.Context:GetPlayer() or {}
    local classFile = context and context.class or nil
    if settings.interruptEnabled ~= false then
        out.interrupt = unitReactionCandidate(observation, settings, classFile, "interrupt", mappings, "interrupt")
    end
    if settings.controlEnabled ~= false then
        out.aoe = aoeReactionCandidate(observation, mappings)
        out.control = unitReactionCandidate(observation, settings, classFile, "control", mappings, "single_control")
    end

    -- P3 exposes exactly one highest-priority highlight. A lower-priority card
    -- may still remain visible through the legacy advisory path, but only this
    -- selected item receives the reaction glow / proc marker.
    out.selected = out.interrupt or out.aoe or out.control
    out.active = out.selected ~= nil
    if out.selected then
        out.state = out.selected.kind
        local mappingSuffix = out.selected.routeAvailable == false and "（未识别动作条/宏，仅提示）" or ""
        out.notice = (out.selected.kind == "interrupt" and ("可打断读条：" .. tostring(REACTION_SOURCE_LABELS[out.selected.source] or "目标") .. mappingSuffix))
            or (out.selected.kind == "interrupt_unverified" and ("读条状态未验证：" .. tostring(REACTION_SOURCE_LABELS[out.selected.source] or "目标") .. "（P3 仅提示，不能自动打断）"))
            or out.selected.kind == "aoe_control" and ("群控候选：可见有效钢条 " .. tostring(out.selected.qualifyingCount or 0) .. " 个")
            or ("单体控制候选：" .. tostring(REACTION_SOURCE_LABELS[out.selected.source] or "目标") .. mappingSuffix)
    elseif (type(observation.aoe) == "table" and observation.aoe.active == true) then
        out.state = "aoe_route_unavailable"
        out.notice = "范围钢条达到阈值，但未找到已识别的 @cursor 群控宏"
    else
        out.notice = "等待可打断读条、可控制钢条或范围钢条"
    end
    -- P4 runtime status is scalar-only diagnostic metadata. It does not alter
    -- the P3 selected card, visibility, cooldown display, or HUD routing.
    if TE.AutoReaction and type(TE.AutoReaction.GetSnapshot) == "function" then
        local ok, snapshot = pcall(TE.AutoReaction.GetSnapshot, TE.AutoReaction)
        if ok and type(snapshot) == "table" then out.auto = snapshot end
    end
    return out
end

local function applyReactionReadOnly(reaction, interrupt, advisory)
    reaction = type(reaction) == "table" and reaction or {}
    advisory = type(advisory) == "table" and advisory or {}
    local selected = reaction.selected
    if not selected then return interrupt, advisory end

    -- Existing current-target interrupt cards carry the native interrupt glow
    -- by default. Suppress it when P3 selects a higher-priority control card so
    -- there is never more than one reaction highlight.
    if selected.kind ~= "interrupt" and type(interrupt) == "table" and type(interrupt.suggestion) == "table" then
        interrupt.suggestion.reactionHighlight = false
    end

    if selected.kind == "interrupt" or selected.kind == "interrupt_unverified" then
        interrupt = {
            active = true,
            state = selected.kind == "interrupt" and "reaction_interruptible" or "reaction_interruptibility_unverified",
            cast = { active = true, channel = selected.castKind == "channel" },
            interruptible = true,
            dangerous = false,
            suggestion = selected.item,
            source = "reaction_p3_observer",
            notice = reaction.notice,
            reaction = reaction,
        }
    elseif selected.kind == "single_control" or selected.kind == "aoe_control" then
        advisory.control = {
            active = true,
            state = selected.kind,
            items = { selected.item },
            advisoryOnly = true,
            source = "reaction_p3_observer",
            notice = reaction.notice,
            reaction = reaction,
        }
    end
    return interrupt, advisory
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
        item.actionBarStateTrusted = binding.actionBarStateTrusted == true
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
        -- P3 has already verified the actual focus/mouseover/nameplate source
        -- in ReactionObservation. IconState's generic target-only probe must
        -- not overwrite that result with a missing/current-target warning.
        if item.reactionObservedTarget == true or item.reactionAoe == true then
            options.requiresHostileTarget = false
        end
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

-- “校验” is a Burst plan-state label, not a generic CooldownTracker label.
-- Project it only onto the current declared injection/window spell while that
-- plan is actively awaiting spellcast/CD proof (or confirming a strict front
-- own-CD skip). This is read-only HUD data and never changes a candidate,
-- binding token, TEAP message or input decision.
local function applyAutoBurstVerification(primaryDisplay, advisory)
    if not (TE.AutoBurst and type(TE.AutoBurst.GetSnapshot) == "function") then return end
    local ok, plan = pcall(TE.AutoBurst.GetSnapshot, TE.AutoBurst)
    if not ok or type(plan) ~= "table" or plan.active ~= true then return end
    local pending = plan.waitingForConfirmation == true
        or plan.preInjectionSkipStatus == "confirming_own_cooldown"
    local spellID = tonumber(plan.currentSpellID)
    if pending ~= true or not spellID or spellID <= 0 then return end

    local function mark(item)
        if type(item) ~= "table" or tonumber(item.spellID) ~= spellID then return end
        item.burstVerificationPending = true
        item.burstVerificationRole = plan.currentRole
    end

    mark(primaryDisplay)
    for _, item in ipairs((advisory and advisory.burst and advisory.burst.items) or {}) do mark(item) end
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
    local hud = ensureHudSettings()
    local primaryOnly = hud and hud.queueMode == "primary"
    local primaryIconContext = TE.IconState and type(TE.IconState.CreateRefreshContext) == "function"
        and TE.IconState:CreateRefreshContext(primary) or {}
    local primaryDisplay = primaryDisplayFromState(primary, context)
    if not primaryDisplay and context.inCombat ~= true then
        primaryDisplay = buildOutOfCombatPrimary(context)
    end

    if primaryOnly == true then
        local advisory = emptyAdvisory("hud_primary_only")
        local interrupt = emptyInterrupt("hud_primary_only")
        local reaction = emptyReaction("hud_primary_only")
        decorateItem(primaryDisplay, "primary", primaryIconContext)
        applyAutoBurstVerification(primaryDisplay, advisory)
        local snapshot = {
            primary = primary,
            primaryDisplay = primaryDisplay,
            history = { active = false, items = {}, source = "hud_primary_only", notice = "hud_primary_only" },
            interrupt = interrupt,
            defensives = advisory.defense,
            advisory = advisory,
            reaction = reaction,
            context = context,
            settings = settings,
            hudPrimaryOnly = true,
            observedAt = now,
            queue = {
                schema = 2,
                items = {},
                order = { "primary" },
                source = "hud_primary_only",
            },
        }
        if TE.TacticalTelemetry and type(TE.TacticalTelemetry.Record) == "function" then
            TE.TacticalTelemetry:Record(snapshot)
        end
        publish(snapshot)
        return snapshot
    end

    local runtime = {
        monitor = TE.ProtocolMonitor and TE.ProtocolMonitor:Sample() or {},
        environment = TE.EnvironmentCompatibility and TE.EnvironmentCompatibility:Sample() or nil,
        iconContext = primaryIconContext,
    }

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

    local interrupt
    do
        local ok, result = pcall(buildInterrupt, context.class, settings, runtime.monitor)
        interrupt = ok and result or { active = false, state = "safe_mode", blockedReason = "打断建议安全模式", error = tostring(result) }
    end

    -- P3 consumes the shared monitor sample only after the legacy advisory
    -- builders have completed. It projects read-only target/focus/mouseover and
    -- visible-nameplate evidence into the same HUD lanes without touching any
    -- recommendation, AutoBurst, TEAP, TEK or input state.
    local reaction
    if REACTION_READONLY_HIGHLIGHT_SUSPENDED == true then
        reaction = {
            schema = 1,
            active = false,
            state = "suspended",
            readOnly = true,
            dispatchAllowed = false,
            source = "reaction_p3_suspended",
            notice = "P3 reaction highlight suspended for performance while automatic reaction development is paused.",
        }
    else
        do
            local ok, result = pcall(buildReactionReadOnly, settings, runtime.monitor)
            reaction = ok and type(result) == "table" and result or {
                schema = 1, active = false, state = "safe_mode", readOnly = true,
                dispatchAllowed = false, source = "reaction_p3_safe_mode", error = tostring(result),
            }
        end
        interrupt, advisory = applyReactionReadOnly(reaction, interrupt, advisory)
    end

    decorateItem(primaryDisplay, "primary", runtime.iconContext)
    decorateCollection((advisory.candidates or {}).items, "candidate", runtime.iconContext)
    decorateCollection((advisory.burst or {}).items, "burst", runtime.iconContext)
    applyAutoBurstVerification(primaryDisplay, advisory)
    decorateCollection((advisory.control or {}).items, "control", runtime.iconContext)
    decorateCollection((advisory.mobility or {}).items, "mobility", runtime.iconContext)
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
        reaction = reaction,
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
