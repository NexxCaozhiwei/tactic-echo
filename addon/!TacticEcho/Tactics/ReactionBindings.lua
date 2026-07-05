local TE = _G.TacticEcho

-- Read-only P2 registry for interrupt / control action-bar and macro mappings.
--
-- Safety boundary:
-- * Reuses ActionBarBindingResolver and MacroSemantics; it does not scan or
--   interpret a separate macro language.
-- * Never creates a BindingToken, never writes TEAP, never calls TEK, and
--   never invokes a protected action.
-- * Target-route metadata is descriptive only. A same-spell target-management
--   macro can be marked macroManagedTargetAuto so later automatic-reaction
--   phases may press its existing binding; the macro itself retains target
--   acquire/fallback/restore behavior. Later phases must still perform their
--   own cast / NPC / immunity checks before considering any route for input.
local ReactionBindings = {}
TE.ReactionBindings = ReactionBindings

ReactionBindings.schemaVersion = 2
ReactionBindings.cache = nil
ReactionBindings.cacheKey = nil
ReactionBindings.lastReason = "not_scanned"

local ROUTE_ORDER = { "target", "focus", "mouseover", "cursor" }
local ROUTE_LABELS = {
    target = "当前目标",
    focus = "焦点目标",
    mouseover = "鼠标指向目标",
    cursor = "@cursor",
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return false, nil end
    return true, a, b, c
end

local function spellInfo(spellID)
    spellID = tonumber(spellID)
    if not spellID then return tostring(spellID or "-"), nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = safeCall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then
            return info.name or tostring(spellID), info.iconID or info.icon
        end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = safeCall(GetSpellInfo, spellID)
        if ok and name then return name, icon end
    end
    return tostring(spellID), nil
end

local function getContext()
    if TE.Context and type(TE.Context.GetPlayer) == "function" then
        local ok, context = safeCall(TE.Context.GetPlayer, TE.Context)
        if ok and type(context) == "table" then return context end
    end
    return {}
end

local function sortedRouteList(routes)
    local out = {}
    for _, route in ipairs(ROUTE_ORDER) do
        if routes[route] then out[#out + 1] = route end
    end
    return out
end

local function candidateBinding(candidate)
    candidate = type(candidate) == "table" and candidate or {}
    local parsed = type(candidate.parsed) == "table" and candidate.parsed or nil
    return {
        binding = parsed and parsed.binding or candidate.rawBinding,
        bindingToken = parsed and parsed.token or 0,
        bindingReady = parsed ~= nil,
        buttonName = candidate.buttonName,
        actionSlot = candidate.actionSlot or candidate.slot,
        source = candidate.source,
        macroName = candidate.macroName,
        macroAssociation = candidate.macroAssociation,
        macroCommand = candidate.macroCommand,
        macroSemantics = candidate.macroSemantics,
        macroRepresentedSpellID = candidate.macroRepresentedSpellID,
        macroRepresentedSpellSource = candidate.macroRepresentedSpellSource,
        macroOpaqueRepresentedSpell = candidate.macroOpaqueRepresentedSpell == true,
        bindingSourceIndex = candidate.bindingSourceIndex,
        bindingReason = candidate.reason,
        actionBarStateTrusted = candidate.actionBarStateTrusted == true,
        directActionSlot = candidate.directActionSlot == true,
    }
end

-- A route can be unsuitable for target/focus/mouseover reaction selection and
-- still be a legitimate player-operated HUD source. The canonical example is a
-- `[@cursor] 冰冻陷阱` macro: its cursor placement must remain Blizzard macro
-- behavior, so it cannot be relabelled as a target route or sent through any
-- automatic path. Preserve its exact visible button only for physical manual
-- HUD/native clicks, with BindingToken permanently zero.
local function manualMacroSource(candidate)
    candidate = type(candidate) == "table" and candidate or {}
    if candidate.source ~= "macro" then return nil end
    -- P5.11 shares the resolver's current-visible macro contract with Burst,
    -- control, defense and survival. Opaque action-info identity remains a
    -- target-only P4 transport exception and cannot authorise a HUD card.
    local resolver = TE.ActionBarBindingResolver
    local verified = resolver and type(resolver.IsVerifiedCurrentMacroSource) == "function"
        and resolver:IsVerifiedCurrentMacroSource(candidate, candidate.macroAssociation) == true
    if verified ~= true then return nil end
    local record = candidateBinding(candidate)
    if type(record.buttonName) ~= "string" or record.buttonName == "" then return nil end
    if not tonumber(record.actionSlot) then return nil end
    record.bindingToken = 0
    record.manualActionSource = true
    record.manualOnly = true
    record.safeForFutureAuto = false
    record.routeKind = "manual_macro_source"
    record.routeReason = "manual_existing_macro"
    return record
end

local function manualMacroSourceFromResolved(resolved)
    -- `resolved.candidates` are already matched against the requested SpellID
    -- by ActionBarBindingResolver. Select only a current visible macro source;
    -- do not recover macro list entries by name/icon and do not create routes.
    for _, candidate in ipairs(type(resolved) == "table" and resolved.candidates or {}) do
        local source = manualMacroSource(candidate)
        if source then return source end
    end
    return nil
end

local function recordRoute(routes, route, candidate, sourceKind, routeReason, safeForFutureAuto, routeOptions)
    if not ROUTE_LABELS[route] then return end
    local current = routes[route]
    local record = candidateBinding(candidate)
    routeOptions = type(routeOptions) == "table" and routeOptions or {}
    record.route = route
    record.routeLabel = ROUTE_LABELS[route]
    record.routeKind = sourceKind
    record.routeReason = routeReason
    record.macroManagedTarget = routeOptions.macroManagedTarget == true
    record.macroManagedTargetFallback = routeOptions.macroManagedTargetFallback == true
    record.macroPriorityChain = routeOptions.macroPriorityChain == true
    -- P5.4 compatibility route: the current visible macro button is known by
    -- GetActionInfo to represent this interrupt SpellID, but its body/index is
    -- temporarily opaque. Keep it as a target-only route so P4.3's proven
    -- BindingToken -> TEAP -> TEK delivery can remain available without using
    -- a macro name, icon, or a guessed macro-list entry.
    record.macroOpaqueRepresentedSpell = routeOptions.macroOpaqueRepresentedSpell == true
    record.autoRouteMode = routeOptions.autoRouteMode
    record.targetMutationCommands = routeOptions.targetMutationCommands or {}
    record.managedTargetRouteOrder = {}
    for _, priorityRoute in ipairs(type(routeOptions.managedTargetRouteOrder) == "table" and routeOptions.managedTargetRouteOrder or {}) do
        if ROUTE_LABELS[priorityRoute] then record.managedTargetRouteOrder[#record.managedTargetRouteOrder + 1] = priorityRoute end
    end
    record.priorityRouteOrder = {}
    for _, priorityRoute in ipairs(type(routeOptions.priorityRouteOrder) == "table" and routeOptions.priorityRouteOrder or {}) do
        if ROUTE_LABELS[priorityRoute] then record.priorityRouteOrder[#record.priorityRouteOrder + 1] = priorityRoute end
    end
    record.safeForFutureAuto = safeForFutureAuto == true and record.bindingReady == true

    -- A direct target button has no macro branch that can preempt the observed
    -- target. Prefer it over a same-spell target-management macro when both are
    -- ready; focus/mouseover still require their explicit macro routes. The
    -- remaining order preserves the resolver's visible-button preference.
    local function safetyPriority(value)
        if type(value) ~= "table" then return 0 end
        if value.bindingReady ~= true then return 0 end
        if value.routeKind == "direct" then return 40 end
        if value.macroPriorityChain == true then return 30 end
        if value.macroManagedTargetFallback == true then return 25 end
        if value.macroManagedTarget == true then return 20 end
        -- Prefer an explicit parsed macro route over the P4.3 represented-spell
        -- compatibility route, while retaining the latter when it is the only
        -- bound visible interrupt action.
        if value.macroOpaqueRepresentedSpell == true then return 10 end
        return 30
    end
    if not current
        or (record.bindingReady and current.bindingReady ~= true)
        or (record.bindingReady and current.bindingReady and safetyPriority(record) > safetyPriority(current)) then
        routes[route] = record
    end
end

-- Retail can expose the exact spell identity of a visible macro button through
-- two equivalent action-info forms while withholding its usable macro body/index:
--   * action_info_represented_spell: `GetActionInfo(...).id` itself is the
--     represented SpellID outside the valid macro-index range;
--   * action_info_macro_spell: the action-info macro-spell return carries the
--     represented SpellID.
--
-- Both forms identify the same existing visible action-bar button and its
-- player-owned binding.  They are not macro-list recovery, macro-name matching,
-- icon matching, or branch inference.  When the body is genuinely opaque, keep
-- only a target-only P4.3 transport route: focus/mouseover remain unavailable
-- until a parsed body proves their explicit branch.
local OPAQUE_ACTION_SPELL_ASSOCIATIONS = {
    action_info_represented_spell = true,
    action_info_macro_spell = true,
}

local function opaqueActionSpellBodyUnavailable(candidate)
    candidate = type(candidate) == "table" and candidate or {}
    local diagnostic = type(candidate.macroDiagnostic) == "table" and candidate.macroDiagnostic or {}
    local failure = diagnostic.failureReason
    -- A semantic duplicate remains a true identity conflict.  Do not bypass
    -- P5's fail-closed rule through action-info transport compatibility.
    if failure == "macro_semantic_identity_ambiguous" then return false end
    if candidate.macroOpaqueRepresentedSpell == true then return true end
    return failure == "macro_body_unavailable_action_info_id"
        or failure == "macro_action_text_missing"
        or failure == "macro_action_text_name_not_found"
end

local function addOpaqueActionSpellMacroRoute(routes, candidate, spellID)
    if type(candidate) ~= "table" or candidate.source ~= "macro" then return false end
    -- The P4 exception transports only an existing physical action-bar binding.
    -- Without a parsed nonzero BindingToken there is no safe target-only route.
    local parsed = type(candidate.parsed) == "table" and candidate.parsed or nil
    if not parsed or tonumber(parsed.token) == nil or tonumber(parsed.token) <= 0 then return false end
    local association = candidate.macroAssociation
    if OPAQUE_ACTION_SPELL_ASSOCIATIONS[association] ~= true then return false end
    if opaqueActionSpellBodyUnavailable(candidate) ~= true then return false end

    -- `matchedSpellID` is supplied by the resolver only after the current
    -- visible button's action-info identity has matched the requested spell.
    -- Prefer it over any macro-list field, which may be absent in this opacity
    -- shape.
    local matchedSpellID = tonumber(candidate.matchedSpellID)
        or tonumber(candidate.macroRepresentedSpellID)
        or tonumber(candidate.spellID)
    if matchedSpellID ~= tonumber(spellID) then return false end

    local routeReason = association == "action_info_macro_spell"
        and "action_info_macro_spell_compat"
        or "action_info_represented_spell_compat"
    recordRoute(routes, "target", candidate, "macro", routeReason, true, {
        -- Retain the existing scalar for HUD/SavedVariables compatibility:
        -- it means "opaque exact action-spell route", not that a macro name was
        -- used to recover a body.
        macroOpaqueRepresentedSpell = true,
        autoRouteMode = routeReason,
    })
    return true
end


local function addMacroRoutes(routes, candidate, spellID, spellName, role)
    if addOpaqueActionSpellMacroRoute(routes, candidate, spellID) then
        return true, "action_info_opaque_spell_compat"
    end
    local resolver = TE.ActionBarBindingResolver
    if not (resolver and type(resolver.IsVerifiedCurrentMacroSource) == "function"
        and resolver:IsVerifiedCurrentMacroSource(candidate, candidate.macroAssociation) == true) then
        return false, "macro_identity_unverified"
    end
    local semantics = type(candidate.macroSemantics) == "table" and candidate.macroSemantics or nil
    local macro = TE.MacroSemantics
    if not (macro and type(macro.DescribeSpellRoutes) == "function") then
        return false, "macro_semantics_unavailable"
    end
    local ok, details = safeCall(macro.DescribeSpellRoutes, macro, semantics, spellID, spellName)
    if not ok or type(details) ~= "table" or details.recognized ~= true then
        return false, details and details.reason or "macro_route_unavailable"
    end

    local routesFound = false
    local macroManagedTarget = details.macroManagedTargetAuto == true
    local macroPriorityChain = details.macroPriorityChainAuto == true
    local routeOptions = {
        macroManagedTarget = macroManagedTarget,
        macroManagedTargetFallback = details.macroManagedTargetFallbackAuto == true,
        macroPriorityChain = macroPriorityChain,
        autoRouteMode = details.autoRouteMode,
        targetMutationCommands = details.targetMutationCommands,
        managedTargetRouteOrder = details.managedTargetRouteOrder,
        priorityRouteOrder = details.priorityRouteOrder,
    }
    for _, route in ipairs(details.routes or {}) do
        local supportedRoute = ROUTE_LABELS[route] ~= nil
        -- A cursor macro remains an automatic candidate only for explicitly
        -- typed AOE control.  For unit-target reaction skills, a same-spell
        -- macro with target-management commands is now user-authorized: TE
        -- treats the macro button as one atomic binding and leaves every target
        -- acquire/fallback/restore decision to Blizzard's normal macro engine.
        -- TE never emits /target commands or evaluates a macro branch itself.
        local explicitRouteSafe = details.singleRoute == true
            and details.hasCastsequence ~= true
            and details.otherSpellActionCount == 0
            and details.hasTargetMutation ~= true
        local routeSafe = (explicitRouteSafe or macroManagedTarget or macroPriorityChain)
            and details.hasCastsequence ~= true
            and details.otherSpellActionCount == 0
            and (route ~= "cursor" or role == "aoe")
        if supportedRoute then
            recordRoute(routes, route, candidate, "macro", details.reason, routeSafe, routeOptions)
            routesFound = true
        end
    end
    return routesFound, details.reason
end

local function collectRoutes(resolved, spellID, spellName, role)
    local routes = {}
    local sawMacro, macroReason = false, nil
    for _, candidate in ipairs(type(resolved) == "table" and resolved.candidates or {}) do
        if candidate.source == "macro" then
            sawMacro = true
            local _, reason = addMacroRoutes(routes, candidate, spellID, spellName, role)
            macroReason = macroReason or reason
        else
            -- A direct Blizzard action button uses Blizzard's current target.
            -- It never claims focus/mouseover capability without a user macro.
            recordRoute(routes, "target", candidate, "direct", "direct_actionbar", true)
        end
    end
    return routes, sawMacro, macroReason
end

local function buildEntry(profile, resolved)
    profile = type(profile) == "table" and profile or { spellID = profile }
    local spellID = tonumber(profile.spellID or profile.id)
    local name, icon = spellInfo(spellID)
    local role = profile.role or profile.kind or "single"
    local routes, sawMacro, macroReason = collectRoutes(resolved, spellID, name, role)
    local manualSource = manualMacroSourceFromResolved(resolved)
    local routeList = sortedRouteList(routes)
    local firstRoute = routes[routeList[1]]
    local readyCount = 0
    local safeRoutes = {}
    local macroManagedTargetAuto = false
    local macroManagedTargetFallbackAuto = false
    local macroPriorityChainAuto = false
    local macroOpaqueRepresentedSpellAuto = false
    for _, route in ipairs(routeList) do
        local routeInfo = routes[route]
        if routeInfo and routeInfo.bindingReady then readyCount = readyCount + 1 end
        if routeInfo and routeInfo.safeForFutureAuto then safeRoutes[#safeRoutes + 1] = route end
        if routeInfo and routeInfo.macroManagedTarget == true then macroManagedTargetAuto = true end
        if routeInfo and routeInfo.macroManagedTargetFallback == true then macroManagedTargetFallbackAuto = true end
        if routeInfo and routeInfo.macroPriorityChain == true then macroPriorityChainAuto = true end
        if routeInfo and routeInfo.macroOpaqueRepresentedSpell == true then macroOpaqueRepresentedSpellAuto = true end
    end

    local status, reason
    if readyCount > 0 then
        status = #safeRoutes > 0 and "ready" or "recognized_manual_only"
        reason = #safeRoutes > 0 and "route_ready" or "macro_route_ambiguous"
    elseif #routeList > 0 then
        status, reason = "binding_unsupported", (firstRoute and firstRoute.bindingReason) or "binding_token_invalid"
    elseif manualSource then
        status, reason = "recognized_manual_only", "manual_existing_macro"
    elseif sawMacro then
        status, reason = "recognized_manual_only", macroReason or "macro_route_unavailable"
    else
        status, reason = "unbound", type(resolved) == "table" and resolved.reason or "binding_resolver_unavailable"
    end

    return {
        spellID = spellID,
        spellName = name,
        spellIcon = icon,
        role = role,
        roleLabel = profile.roleLabel,
        status = status,
        reason = reason,
        routes = routes,
        routeOrder = routeList,
        safeRoutes = safeRoutes,
        recognizedMacro = sawMacro,
        macroRouteReason = macroReason,
        macroManagedTargetAuto = macroManagedTargetAuto,
        macroManagedTargetFallbackAuto = macroManagedTargetFallbackAuto,
        macroPriorityChainAuto = macroPriorityChainAuto,
        macroOpaqueRepresentedSpellAuto = macroOpaqueRepresentedSpellAuto,
        targetSwitchAuto = macroReason == "macro_target_switch_fallback_auto",
        resolverStatus = type(resolved) == "table" and resolved.status or "NoBinding",
        resolverReason = type(resolved) == "table" and resolved.reason or "binding_resolver_unavailable",
        cacheGeneration = type(resolved) == "table" and resolved.cacheGeneration or nil,
        candidates = type(resolved) == "table" and resolved.candidates or {},
        -- Not a target-route or automatic capability. It identifies one exact
        -- current visible macro button for physical HUD/native manual clicks.
        manualSource = manualSource,
        -- Read-only compact diagnostics for an unrecognized existing macro.
        -- Macro bodies are deliberately not copied into this P2 snapshot.
        macroDiagnostics = type(resolved) == "table" and resolved.macroDiagnostics or {},
    }
end

local function resolveSpell(spellID)
    local resolver = TE.ActionBarBindingResolver
    if not (resolver and type(resolver.ResolveSpell) == "function") then
        return { status = "NoBinding", reason = "binding_resolver_unavailable", candidates = {} }
    end
    local ok, result = safeCall(resolver.ResolveSpell, resolver, spellID)
    if not ok or type(result) ~= "table" then
        return { status = "NoBinding", reason = "binding_resolver_failed", candidates = {} }
    end
    return result
end

local function interruptProfiles(classFile)
    local list = TE.AbilityProfiles and type(TE.AbilityProfiles.GetInterrupts) == "function"
        and TE.AbilityProfiles:GetInterrupts(classFile) or {}
    local out = {}
    for _, spellID in ipairs(list or {}) do
        out[#out + 1] = { spellID = spellID, role = "interrupt", roleLabel = "打断" }
    end
    return out
end

local function controlProfiles(classFile)
    if TE.AbilityProfiles and type(TE.AbilityProfiles.GetReactionControls) == "function" then
        return TE.AbilityProfiles:GetReactionControls(classFile) or {}
    end
    -- Compatibility fallback: legacy broad controls are retained as single
    -- target candidates until the typed profile registry is available.
    local list = TE.AbilityProfiles and type(TE.AbilityProfiles.GetControls) == "function"
        and TE.AbilityProfiles:GetControls(classFile) or {}
    local out = {}
    for _, spellID in ipairs(list or {}) do
        out[#out + 1] = { spellID = spellID, role = "single", roleLabel = "单体控制", legacyFallback = true }
    end
    return out
end

local function buildGroup(profiles)
    local out = {}
    for _, profile in ipairs(profiles or {}) do
        local spellID = tonumber(type(profile) == "table" and profile.spellID or profile)
        if spellID and spellID > 0 then
            out[#out + 1] = buildEntry(profile, resolveSpell(spellID))
        end
    end
    return out
end

function ReactionBindings:Invalidate(reason)
    self.cache = nil
    self.cacheKey = nil
    self.lastReason = reason or "invalidated"
end

-- P4.1 narrow recovery path.  P2 normally follows the resolver's event-driven
-- cache; when a *confirmed* interrupt cast is observed but no safe route is
-- present, AutoReaction may request one bounded cache rebuild for that cast.
-- This still reads only existing Blizzard default action-bar slots and real
-- player bindings.  It never creates a key, edits a macro, or retries every
-- scheduler tick.  A binding-settlement window keeps the existing cache intact
-- so an incomplete UPDATE_BINDINGS transaction is never promoted to auto use.
function ReactionBindings:RefreshForAuto(reason)
    local resolver = TE.ActionBarBindingResolver
    if not (resolver and type(resolver.Rebuild) == "function") then
        self:Invalidate("reaction_auto_resolver_unavailable")
        return self:GetSnapshot(true), "binding_resolver_unavailable"
    end
    if type(resolver.IsBindingSettling) == "function" then
        local ok, settling = safeCall(resolver.IsBindingSettling, resolver)
        if ok and settling == true then
            self:Invalidate("reaction_auto_binding_settling")
            return self:GetSnapshot(true), "binding_settling"
        end
    end
    local ok = safeCall(resolver.Rebuild, resolver, reason or "reaction_auto_route_refresh")
    if not ok then
        self:Invalidate("reaction_auto_rebuild_failed")
        return self:GetSnapshot(true), "binding_rebuild_failed"
    end
    self:Invalidate(reason or "reaction_auto_route_refresh")
    return self:GetSnapshot(true), "binding_rebuilt"
end

function ReactionBindings:GetSnapshot(force)
    local context = getContext()
    local resolver = TE.ActionBarBindingResolver
    local generation = 0
    if resolver and type(resolver.GetButtonCache) == "function" then
        local ok, cache = safeCall(resolver.GetButtonCache, resolver)
        if ok and type(cache) == "table" then generation = tonumber(cache.generation) or 0 end
    end
    local key = table.concat({ tostring(context.class or "UNKNOWN"), tostring(context.specIndex or 0), tostring(generation) }, ":")
    if force ~= true and self.cache and self.cacheKey == key then return self.cache end

    local classFile = context.class
    local snapshot = {
        schema = self.schemaVersion,
        class = classFile,
        specIndex = context.specIndex,
        cacheGeneration = generation,
        interrupt = buildGroup(interruptProfiles(classFile)),
        control = buildGroup(controlProfiles(classFile)),
        readOnly = true,
        dispatchAllowed = false,
        source = "visible_default_actionbar_and_existing_macros",
    }
    self.cache = snapshot
    self.cacheKey = key
    self.lastReason = "ready"
    return snapshot
end

function ReactionBindings:GetRouteLabels()
    return ROUTE_LABELS
end
