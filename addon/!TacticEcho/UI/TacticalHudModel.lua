-- Tactical HUD model builder.
-- Converts TacticalAdvisors snapshots into display-only data. 0.7.4 also
-- scrubs secret values before a snapshot reaches any HUD layout/fingerprint UI.
local TE = _G.TacticEcho

local TacticalHudModel = {}
TE.TacticalHudModel = TacticalHudModel

local MAX_CANDIDATES = 3
local MAX_BURST_CARDS = 5 -- slot 1 window + up to four followups
local MAX_DEFENSIVES = 4

local NUMERIC_FIELDS = {
    "spellID", "matchedSpellID", "itemID", "itemCount", "itemSlot", "charges", "maxCharges",
    "cooldownRemaining", "cooldownDuration", "cooldownStart",
    "gcdRemaining", "gcdDuration", "gcdStart",
    "chargeCooldownRemaining", "chargeCooldownDuration", "chargeCooldownStart", "castingSpellID", "castingStartTimeMS", "castingEndTimeMS", "defensivePriority",
    "actionSlot", "slot", "inventorySlot", "bindingSourceIndex", "bindingToken", "displayBindingToken", "dispatchBindingToken", "burstOrder", "channelingSpellID", "empoweringSpellID",
    "reactionQualifyingCount", "reactionAoeThreshold",
}

local BOOLEAN_FIELDS = {
    "hidden", "empty", "dispatchAllowed", "paused", "blocked", "unbound",
    "unknown", "procHighlight", "burstOverlay", "casting", "channeling", "empowering",
    "channelingMatchesRecommendation", "empoweringMatchesRecommendation", "castingThisSpell", "globalCasting", "globalChanneling", "targetInvalid",
    "targetChecked", "rangeBlocked", "resourceBlocked", "advisoryOnly", "displayOnly", "gcdKnown",
    "cooldownKnown", "cooldownActive", "cooldownOnGCD", "cooldownGcdAlias", "cooldownFallback", "cooldownConfirmationPending", "cooldownActionBarNumericOwnEvidence", "burstVerificationPending", "gcdActive", "chargeCooldownKnown", "directActionSlot", "actionBarStateTrusted", "bindingMissing",
    "interruptible", "dangerous", "burstWindow", "burstReady", "gapCloser",
    "reactionHighlight", "reactionObservedTarget", "reactionAoe", "reactionRouteSafe",
    "reactionRouteAvailable", "reactionMappingRequired",
}

local function plainNumber(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local number = tonumber(value)
        if type(number) ~= "number" then return nil end
        local probe = number + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    return ok and result or nil
end

local function plainBoolean(value)
    local ok, result = pcall(function()
        if value == true then return true end
        if value == false then return false end
        return nil
    end)
    return ok and result or nil
end

local function plainText(value, fallback)
    local ok, result = pcall(function()
        if value == nil then return fallback end
        if type(value) == "string" then
            -- #secretString participates in secret propagation; this comparison
            -- deliberately rejects it inside pcall.
            local length = #value
            if length < 0 then return fallback end
            return value
        end
        local number = plainNumber(value)
        if number ~= nil then return tostring(number) end
        return fallback
    end)
    return ok and type(result) == "string" and result or fallback
end

local function plainTexture(value)
    local number = plainNumber(value)
    if number ~= nil then return number end
    return plainText(value, nil)
end

local function clone(source)
    local out = {}
    for key, value in pairs(source or {}) do out[key] = value end
    return out
end

local function sanitize(item)
    item = item or {}
    for _, key in ipairs(NUMERIC_FIELDS) do item[key] = plainNumber(item[key]) end
    for _, key in ipairs(BOOLEAN_FIELDS) do item[key] = plainBoolean(item[key]) end
    item.spellName = plainText(item.spellName, nil)
    item.binding = plainText(item.binding, nil)
    item.bindingSource = plainText(item.bindingSource, nil)
    item.usableState = plainText(item.usableState, "unknown")
    item.state = plainText(item.state, nil)
    item.runtimeState = plainText(item.runtimeState, nil)
    item.runtimeReason = plainText(item.runtimeReason, nil)
    item.runtimeReasonText = plainText(item.runtimeReasonText, nil)
    item.displayState = plainText(item.displayState, nil)
    item.channelingName = plainText(item.channelingName, nil)
    item.empoweringName = plainText(item.empoweringName, nil)
    item.unusableReason = plainText(item.unusableReason, nil)
    item.reasonText = plainText(item.reasonText, nil)
    item.advisoryCondition = plainText(item.advisoryCondition, nil)
    item.defensiveType = plainText(item.defensiveType, nil)
    item.defensiveConditionMode = plainText(item.defensiveConditionMode, nil)
    item.defensiveConditionText = plainText(item.defensiveConditionText, nil)
    item.cooldownSource = plainText(item.cooldownSource, nil)
    item.cooldownFallbackOrigin = plainText(item.cooldownFallbackOrigin, nil)
    item.cooldownIdentityKey = plainText(item.cooldownIdentityKey, nil)
    item.cooldownUnknownReason = plainText(item.cooldownUnknownReason, nil)
    item.cooldownGcdAliasReason = plainText(item.cooldownGcdAliasReason, nil)
    item.bindingReason = plainText(item.bindingReason, nil)
    item.source = plainText(item.source, nil)
    item.category = plainText(item.category, nil)
    item.burstRole = plainText(item.burstRole, nil)
    item.burstState = plainText(item.burstState, nil)
    item.burstVerificationRole = plainText(item.burstVerificationRole, nil)
    item.reactionKind = plainText(item.reactionKind, nil)
    item.reactionSource = plainText(item.reactionSource, nil)
    item.reactionSourceLabel = plainText(item.reactionSourceLabel, nil)
    item.reactionRouteMode = plainText(item.reactionRouteMode, nil)
    item.spellIcon = plainTexture(item.spellIcon)
    item.icon = plainTexture(item.icon)
    return item
end

local function classify(item, kind, meta, preparedMeta)
    local copy = sanitize(clone(item))
    copy.kind = kind
    copy.advisoryOnly = kind ~= "primary"
    -- Collection builders pass a pre-sanitized meta object. Each card still
    -- receives its own shallow copy, but the protected-value probes happen once
    -- per lane instead of once per physical HUD slot.
    copy.meta = preparedMeta and clone(preparedMeta) or sanitize(clone(meta or {}))
    for key, value in pairs(copy.meta) do
        if copy[key] == nil then copy[key] = value end
    end
    if TE.TacticalHudStyles and type(TE.TacticalHudStyles.Resolve) == "function" then
        local ok, visual = pcall(TE.TacticalHudStyles.Resolve, TE.TacticalHudStyles, copy, kind, copy.meta)
        copy.visual = ok and type(visual) == "table" and visual or { visualState = "unknown", label = "未知", reason = "样式模块不可用", previewOnly = kind ~= "primary" }
    else
        copy.visual = { visualState = "unknown", label = "未知", reason = "样式模块未加载", previewOnly = kind ~= "primary" }
    end
    return copy
end

local function matchesActiveCastLock(item, castLock)
    if type(castLock) ~= "table" or castLock.active ~= true then return false end
    local recommendationSpellID = plainNumber(item and item.spellID)
    local lockSpellID = plainNumber(castLock.spellID)
    if recommendationSpellID and lockSpellID then return recommendationSpellID == lockSpellID end
    -- SpellID is the primary key. Name comparison exists only as a safe
    -- display fallback for an incomplete Channel / Empower metadata sample.
    local recommendationName = plainText(item and item.spellName, nil)
    local lockName = plainText(castLock.name, nil)
    return recommendationName ~= nil and lockName ~= nil and recommendationName == lockName
end

local function buildPrimary(snapshot)
    local primary = snapshot and snapshot.primary or nil
    local display = snapshot and snapshot.primaryDisplay or nil
    local item = clone(display or primary or {})
    if item.spellID == nil and primary then item.spellID = primary.spellID end
    if item.spellName == nil and primary then item.spellName = primary.spellName end
    if item.spellIcon == nil and primary then item.spellIcon = primary.spellIcon end
    if item.binding == nil and primary then item.binding = primary.binding end
    if item.bindingToken == nil and primary then item.bindingToken = primary.bindingToken end

    -- `runtimeState` remains the actual TEAP state even when the display is
    -- intentionally projected to out-of-combat display-only. This preserves the
    -- required priority: error/blocked > cast lock > ordinary pause.
    local channeling = type(primary and primary.channeling) == "table" and primary.channeling or {}
    local empowering = type(primary and primary.empowering) == "table" and primary.empowering or {}
    item.runtimeState = item.runtimeState or (primary and primary.state)
    item.runtimeReason = item.runtimeReason or (primary and primary.reason)
    item.runtimeReasonText = item.runtimeReasonText or (primary and primary.reasonText)
    item.displayState = item.displayState or (primary and primary.displayState)
    item.channeling = channeling.active == true
    item.channelingSpellID = channeling.spellID
    item.channelingName = channeling.name
    item.channelingMatchesRecommendation = matchesActiveCastLock(item, channeling)
    item.empowering = empowering.active == true
    item.empoweringSpellID = empowering.spellID
    item.empoweringName = empowering.name
    item.empoweringMatchesRecommendation = matchesActiveCastLock(item, empowering)

    local displayOnly = item.displayOnly == true
    item.dispatchAllowed = displayOnly and false or ((primary and primary.dispatchAllowed == true) or item.dispatchAllowed == true)
    if displayOnly then
        item.state = plainText(item.state, "display_only")
        item.reasonText = plainText(item.reasonText, "脱战只读主推荐")
    else
        item.state = plainText(primary and primary.state or item.state, nil)
        item.reasonText = plainText(primary and primary.reasonText or item.reasonText, nil)
    end
    item.paused = item.runtimeState == "paused" or item.runtimeState == "channeling" or item.runtimeState == "empowering"
        or item.state == "paused" or item.state == "channeling" or item.state == "empowering"
    item.blocked = item.runtimeState == "blocked" or item.state == "blocked"
    -- classify() performs the required protected-value scrub. Do not run the
    -- same full scrub once here and once again in classify().
    local copy = classify(item, "primary")
    copy.spellName = copy.spellName or "无官方推荐"
    return copy
end

local function buildFixedItems(source, maxItems, kind, meta)
    local items = {}
    local preparedMeta = sanitize(clone(meta or {}))
    -- The board owns pre-created physical slots. The model only builds real
    -- cards, eliminating clone/sanitize/style work for hidden empty slots.
    for index = 1, maxItems do
        local raw = source and source[index] or nil
        if raw then items[index] = classify(raw, kind, nil, preparedMeta) end
    end
    return items
end

local function signature(item)
    item = item or {}
    local visual = item.visual or {}
    return table.concat({
        plainText(item.spellID, "?"),
        plainText(item.itemID, "-"),
        plainText(visual.visualState, "unknown"),
        plainText(item.hidden == true and "1" or "0", "0"),
        plainText(item.usableState, "unknown"),
    }, ":")
end

function TacticalHudModel:Build(snapshot, hud)
    snapshot = snapshot or {}
    local advisory = snapshot.advisory or {}
    local interrupt = snapshot.interrupt or {}
    local defensives = snapshot.defensives or {}
    local candidates = (snapshot.history or {}).items or (advisory.candidates or {}).items or {}

    local model = {
        schema = 3,
        primary = buildPrimary(snapshot),
        candidates = buildFixedItems(candidates, MAX_CANDIDATES, "candidate"),
        tactical = {
            interrupt = interrupt.suggestion and classify(interrupt.suggestion, "interrupt", {
                interruptible = interrupt.interruptible == true,
                dangerous = interrupt.dangerous == true,
                state = interrupt.state,
            }) or nil,
            -- Burst is a true independent queue. Slot 1 is the profile window
            -- trigger; subsequent slots are injection / trinket / potion / racial
            -- followups emitted by BurstPlanner. It never shares a lane with
            -- interrupt/control and never changes any dispatch path.
            burst = buildFixedItems((advisory.burst or {}).items, MAX_BURST_CARDS, "burst", {
                state = (advisory.burst or {}).state,
                profileKey = (advisory.burst or {}).profileKey,
                source = (advisory.burst or {}).source,
            }),
            control = ((advisory.control or {}).items or {})[1] and classify(((advisory.control or {}).items or {})[1], "control", {
                state = (advisory.control or {}).state,
            }) or nil,
            mobility = ((advisory.mobility or {}).items or {})[1] and classify(((advisory.mobility or {}).items or {})[1], "mobility", {
                state = (advisory.mobility or {}).state,
            }) or nil,
        },
        defense = buildFixedItems(defensives.items, MAX_DEFENSIVES, "defense", {
            severity = defensives.severity,
            state = defensives.state,
        }),
        meta = {
            paused = (snapshot.primary or {}).state == "paused" or (snapshot.primary or {}).state == "channeling" or (snapshot.primary or {}).state == "empowering",
            observedAt = plainNumber(snapshot.observedAt),
            source = "TacticalAdvisors snapshot",
            layoutPreset = hud and hud.layoutPreset or "queue_horizontal",
            defenseDetached = hud and hud.defenseDetached == true,
        },
    }

    if model.tactical.interrupt then
        model.tactical.interrupt.hidden = not (interrupt.active == true and interrupt.suggestion ~= nil)
    end
    -- Each burst slot decides its own visibility. The planner already applies
    -- window/always/cooldown policy; a valid card must not be discarded merely
    -- because it is a follower or because it is currently cooling down.
    for index, item in ipairs(model.tactical.burst or {}) do
        local raw = ((advisory.burst or {}).items or {})[index]
        item.hidden = raw == nil or raw.hidden == true
    end
    if model.tactical.control then
        model.tactical.control.hidden = not (((advisory.control or {}).active == true and ((advisory.control or {}).items or {})[1] ~= nil) or (advisory.control or {}).state == "unknown")
    end
    if model.tactical.mobility then
        model.tactical.mobility.hidden = not (((advisory.mobility or {}).active == true and ((advisory.mobility or {}).items or {})[1] ~= nil) or (advisory.mobility or {}).state == "environment_unknown")
    end

    local parts = { signature(model.primary) }
    for index = 1, MAX_CANDIDATES do parts[#parts + 1] = "candidate:" .. tostring(index) .. ":" .. signature(model.candidates[index]) end
    parts[#parts + 1] = "interrupt:" .. signature(model.tactical.interrupt)
    for index = 1, MAX_BURST_CARDS do parts[#parts + 1] = "burst:" .. tostring(index) .. ":" .. signature(model.tactical.burst[index]) end
    parts[#parts + 1] = "control:" .. signature(model.tactical.control)
    parts[#parts + 1] = "mobility:" .. signature(model.tactical.mobility)
    for index = 1, MAX_DEFENSIVES do parts[#parts + 1] = "def:" .. tostring(index) .. ":" .. signature(model.defense[index]) end
    model.fingerprint = table.concat(parts, "|")
    return model
end
