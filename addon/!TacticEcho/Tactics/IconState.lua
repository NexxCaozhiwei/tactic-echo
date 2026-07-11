-- Read-only ability icon state collector.
-- 0.7.4 hardening: values returned by modern WoW APIs can be "secret".
-- A secret value must never escape into a table.concat/string/branching UI path.
-- This module converts only verifiably ordinary Lua numbers to HUD fields; all
-- other numeric observations become unknown without affecting recommendations.
local TE = _G.TacticEcho

local IconState = {}
TE.IconState = IconState

local lastError

local function perfCount(name, amount)
    local perf = TE.PerformanceDiagnostics
    if perf and type(perf.Count) == "function" then perf:Count(name, amount) end
end

-- Blizzard exposes the current global cooldown through this spell ID. The
-- observation is display-only and is never used as a recommendation, token,
-- or input condition.
local GLOBAL_COOLDOWN_SPELL_ID = 61304
-- Some Retail cooldown responses do not expose `isOnGCD` for every spell.  In
-- that case a currently READY spell can temporarily look like it has a short
-- personal cooldown merely because the shared GCD is active.  Keep this
-- normalization inside the read-only icon/timing adapter so AutoBurst only
-- receives the public boolean `cooldownOnGCD`, never raw GCD arithmetic.
local GCD_ALIGNMENT_TOLERANCE_SECONDS = 0.12
local GCD_ALIGNMENT_MAX_DURATION_SECONDS = 2.25

local function call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return true, a, b, c, d, e end
    lastError = tostring(a)
    return false, nil
end

-- This deliberately performs arithmetic and comparisons inside pcall. Ordinary
-- numbers survive unchanged; retail "secret numbers" fail the probe and are
-- represented as nil. Do not replace this with tonumber/string.format alone:
-- both can preserve the secrecy wrapper rather than materializing a Lua number.
local function numeric(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local number = tonumber(value)
        if type(number) ~= "number" then return nil end
        local probe = number + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    if ok then return result end
    lastError = tostring(result)
    return nil
end

local function plainBoolean(value)
    local ok, result = pcall(function()
        if value == true then return true end
        if value == false then return false end
        return nil
    end)
    if ok then return result end
    lastError = tostring(result)
    return nil
end

local function plainText(value, fallback)
    local ok, result = pcall(function()
        if value == nil then return fallback end
        if type(value) == "string" then
            local length = #value
            if length < 0 then return fallback end
            return value
        end
        return fallback
    end)
    return ok and type(result) == "string" and result or fallback
end

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and numeric(value) or 0
end

local function deriveCooldown(startValue, durationValue)
    -- Do not branch on raw API values, including `value == nil`: secret values
    -- can make even that branch unsafe. Inspect only the sanitized results.
    local startTime = numeric(startValue)
    local duration = numeric(durationValue)
    if startTime == nil and duration == nil then
        return { known = false, remaining = nil, duration = nil, start = nil, reason = "冷却 API 未返回可解释数值" }
    end
    if startTime == nil or duration == nil then
        return { known = false, remaining = nil, duration = nil, start = nil, reason = "冷却数值受保护，已跳过比较" }
    end
    if duration <= 0 or startTime <= 0 then
        return { known = true, remaining = 0, duration = 0, start = 0 }
    end
    local remaining = math.max(0, startTime + duration - now())
    return { known = true, remaining = remaining, duration = duration, start = startTime }
end

local function spellCooldown(spellID, options)
    options = type(options) == "table" and options or {}
    -- HUD rendering remains event-driven through CooldownResolver.  AutoBurst
    -- timing, however, must not inherit an old event snapshot: a stale shared
    -- GCD can make a ready injection appear to be on personal cooldown forever.
    -- `liveOnly` therefore bypasses the resolver cache and queries the current
    -- public spell snapshot for this evaluation tick.
    if options.liveOnly ~= true
        and TE.CooldownResolver and type(TE.CooldownResolver.GetSpell) == "function" then
        perfCount("cooldown_resolver_read")
        local ok, snapshot = pcall(TE.CooldownResolver.GetSpell, TE.CooldownResolver, spellID)
        if ok and type(snapshot) == "table" then
            return snapshot.remaining, snapshot.duration, snapshot.start, snapshot.enabled, nil,
                snapshot.known == true, snapshot.reason, snapshot.active, snapshot.onGCD,
                snapshot.source, snapshot.identity
        end
    end

    local startTime, duration, enabled, modRate
    -- `isActive` and `isOnGCD` are public non-numeric API booleans. They enter
    -- only the read-only timing adapter to distinguish own cooldown from shared
    -- GCD waiting when countdown numerics are protected; no raw timing escapes.
    local isActive, isOnGCD
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        perfCount("cooldown_api_read")
        local ok, info = call(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            startTime = info.startTime
            duration = info.duration
            enabled = info.isEnabled
            modRate = info.modRate
            isActive = plainBoolean(info.isActive)
            isOnGCD = plainBoolean(info.isOnGCD)
        end
    elseif type(GetSpellCooldown) == "function" then
        perfCount("cooldown_api_read")
        local ok, a, b, c, d = call(GetSpellCooldown, spellID)
        if ok then startTime, duration, enabled, modRate = a, b, c, d end
    end
    local cd = deriveCooldown(startTime, duration)
    if isActive == nil and cd.known == true then isActive = cd.remaining > 0 end
    return cd.remaining, cd.duration, cd.start, plainBoolean(enabled), numeric(modRate), cd.known, cd.reason, isActive, isOnGCD, "spell_api", "spell:" .. tostring(spellID)
end

-- A directly trusted action-bar button is the authoritative public source for
-- the exact action TEK will press.  Retail clients do not always expose the
-- public `isActive` / `isOnGCD` booleans for that button, even while the same
-- button visibly owns a long cooldown.  Keep the numeric inspection entirely
-- inside this read-only timing adapter and export only scalar *classification*
-- booleans to AutoBurst; raw duration/start values never leave IconState.
local function actionBarPublicCooldown(actionSlot, trusted)
    actionSlot = numeric(actionSlot)
    if trusted ~= true or not actionSlot or actionSlot <= 0 then return nil end
    if not (C_ActionBar and type(C_ActionBar.GetActionCooldown) == "function") then return nil end
    perfCount("actionbar_cooldown_api_read")
    local ok, info = call(C_ActionBar.GetActionCooldown, actionSlot)
    if not ok or type(info) ~= "table" then return nil end

    local active = plainBoolean(info.isActive)
    local onGCD = plainBoolean(info.isOnGCD)
    local numericCooldown = deriveCooldown(info.startTime, info.duration)
    -- A duration above the existing maximum shared-GCD envelope can only be
    -- an own cooldown for this exact visible action button. Short/opaque reads
    -- remain UNKNOWN and can never authorize a simple-mode skip.
    local longOwnCooldown = numericCooldown.known == true
        and numericCooldown.remaining ~= nil and numericCooldown.remaining > 0
        and numericCooldown.duration ~= nil
        and numericCooldown.duration > GCD_ALIGNMENT_MAX_DURATION_SECONDS
    -- Some protected clients omit the public booleans even when the exact
    -- direct button exposes a normal 0/0 cooldown snapshot. Treat that as a
    -- positive ready observation only for this same trusted button; a nonzero
    -- short duration remains a possible shared GCD and is not promoted here.
    local numericReady = numericCooldown.known == true
        and numericCooldown.remaining ~= nil and numericCooldown.remaining <= 0
    -- `deriveCooldown` returns ordinary Lua values only after its protected
    -- value probe. When the exact current button proves a real own cooldown,
    -- carry those sanitized values to the HUD so its configurable CD label can
    -- remain visually consistent with trinkets and still match the action bar.
    local numericOwnCooldown = numericCooldown.known == true
        and numericCooldown.remaining ~= nil and numericCooldown.remaining > 0
        and ((active == true and onGCD == false) or longOwnCooldown == true)

    return {
        active = active,
        onGCD = onGCD,
        numericKnown = numericCooldown.known == true,
        longOwnCooldown = longOwnCooldown == true,
        numericReady = numericReady == true,
        numericOwnCooldown = numericOwnCooldown == true,
        numericRemaining = numericOwnCooldown and numericCooldown.remaining or nil,
        numericDuration = numericOwnCooldown and numericCooldown.duration or nil,
        numericStart = numericOwnCooldown and numericCooldown.start or nil,
    }
end

-- Only already-sanitized numeric values pass this boundary. It is used for
-- HUD presentation and exact direct-button cooldown reconciliation; shared
-- GCD, generic action-bar guesses and opaque protected readings stay excluded.
local function applyDirectActionbarNumericCooldown(state, actionCooldown, spellID)
    if type(state) ~= "table" or type(actionCooldown) ~= "table" then return false end
    if actionCooldown.numericOwnCooldown ~= true then return false end
    local remaining = numeric(actionCooldown.numericRemaining)
    local duration = numeric(actionCooldown.numericDuration)
    local start = numeric(actionCooldown.numericStart)
    if remaining == nil or remaining <= 0 or duration == nil or duration <= 0 or start == nil then return false end

    state.cooldownRemaining = remaining
    state.cooldownDuration = duration
    state.cooldownStart = start
    state.cooldownKnown = true
    state.cooldownActive = true
    state.cooldownOnGCD = false
    state.cooldownGcdAlias = false
    state.cooldownGcdAliasReason = nil
    state.cooldownPublicActive = true
    state.cooldownPublicActiveKnown = true
    state.cooldownPublicOnGCD = false
    state.cooldownPublicOnGCDKnown = true
    state.cooldownSource = "actionbar_numeric"
    state.cooldownIdentityKey = "spell:" .. tostring(spellID)
    state.cooldownUnknownReason = nil
    state.cooldownDirectActionBarEvidence = true
    state.cooldownActionBarNumericOwnEvidence = true
    return true
end

local function collectGcdSnapshot()
    -- The global cooldown is a moving time boundary rather than a durable
    -- cooldown record. Always read it live; the event-driven resolver cache is
    -- intentionally not a scheduler clock.
    local remaining, duration, start, _, _, known, reason, active = spellCooldown(GLOBAL_COOLDOWN_SPELL_ID, {
        liveOnly = true,
    })
    return {
        remaining = remaining,
        duration = duration,
        start = start,
        known = known == true,
        reason = reason,
        active = active == true,
        activeKnown = active ~= nil,
    }
end

-- Return a boolean-only classification.  This is deliberately stricter than
-- comparing only remaining time: a genuine short personal cooldown must not be
-- hidden merely because a GCD happens to be active at the same moment.
local function normalizeCooldownAgainstGcd(state, gcd)
    if type(state) ~= "table" or type(gcd) ~= "table" then return false end
    if state.cooldownOnGCD == true then return true end
    if state.cooldownKnown ~= true or state.cooldownActive ~= true then return false end
    if gcd.known ~= true or gcd.active ~= true then return false end

    local spellStart = numeric(state.cooldownStart)
    local spellDuration = numeric(state.cooldownDuration)
    local spellRemaining = numeric(state.cooldownRemaining)
    local gcdStart = numeric(gcd.start)
    local gcdDuration = numeric(gcd.duration)
    local gcdRemaining = numeric(gcd.remaining)
    if not spellDuration or not gcdDuration or spellDuration <= 0 or gcdDuration <= 0 then return false end
    if spellDuration > GCD_ALIGNMENT_MAX_DURATION_SECONDS or gcdDuration > GCD_ALIGNMENT_MAX_DURATION_SECONDS then
        return false
    end

    local durationAligned = math.abs(spellDuration - gcdDuration) <= GCD_ALIGNMENT_TOLERANCE_SECONDS
    local startAligned = spellStart and gcdStart and math.abs(spellStart - gcdStart) <= GCD_ALIGNMENT_TOLERANCE_SECONDS
    local remainingAligned = spellRemaining and gcdRemaining and math.abs(spellRemaining - gcdRemaining) <= GCD_ALIGNMENT_TOLERANCE_SECONDS
    if durationAligned and (startAligned or remainingAligned) then
        state.cooldownOnGCD = true
        state.cooldownActive = false
        state.cooldownGcdAlias = true
        state.cooldownGcdAliasReason = "gcd_snapshot_aligned"
        return true
    end
    return false
end

-- One TacticalAdvisors refresh can decorate many cards. The global cooldown is
-- identical for all of them, so callers pass this short-lived context through
-- planner and HUD collection instead of querying spell 61304 for every icon.
function IconState:CreateRefreshContext(primary)
    local castSnapshot = primary and primary.casting or nil
    if type(castSnapshot) ~= "table" and TE.SignalFrame and type(TE.SignalFrame.GetCastDisplayInfo) == "function" then
        castSnapshot = TE.SignalFrame:GetCastDisplayInfo()
    end
    return {
        schema = 2,
        gcdSnapshot = collectGcdSnapshot(),
        castSnapshot = type(castSnapshot) == "table" and castSnapshot or { active = false },
    }
end

local function spellCharges(spellID)
    local current, maximum, startTime, duration, modRate
    if C_Spell and type(C_Spell.GetSpellCharges) == "function" then
        perfCount("charge_api_read")
        local ok, info = call(C_Spell.GetSpellCharges, spellID)
        if ok and type(info) == "table" then
            current = info.currentCharges
            maximum = info.maxCharges
            startTime = info.cooldownStartTime
            duration = info.cooldownDuration
            modRate = info.chargeModRate
        end
    elseif type(GetSpellCharges) == "function" then
        perfCount("charge_api_read")
        local ok, a, b, c, d, e = call(GetSpellCharges, spellID)
        if ok then current, maximum, startTime, duration, modRate = a, b, c, d, e end
    end
    local safeCurrent, safeMaximum = numeric(current), numeric(maximum)
    if safeCurrent == nil and safeMaximum == nil then return nil end
    local cd = deriveCooldown(startTime, duration)
    return {
        current = safeCurrent,
        maximum = safeMaximum,
        cooldownStart = cd.start,
        cooldownDuration = cd.duration,
        cooldownRemaining = cd.remaining,
        cooldownKnown = cd.known,
        cooldownUnknownReason = cd.reason,
        modRate = numeric(modRate),
    }
end

local function usableState(spellID)
    local usable, noResource
    if C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        local ok, a, b = call(C_Spell.IsSpellUsable, spellID)
        if ok then usable, noResource = a, b end
    elseif type(IsUsableSpell) == "function" then
        local ok, a, b = call(IsUsableSpell, spellID)
        if ok then usable, noResource = a, b end
    end
    usable, noResource = plainBoolean(usable), plainBoolean(noResource)
    if usable == nil then return "unknown", nil end
    if usable == true then return "ready", nil end
    if noResource == true then return "resource", "资源不足" end
    return "unavailable", "技能当前不可用"
end

local function targetState(spellID, requiresHostileTarget)
    if requiresHostileTarget ~= true then return "not_checked", nil end
    if type(UnitExists) == "function" and not UnitExists("target") then
        return "target_missing", "没有目标"
    end
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("target") then
        return "target_dead", "目标已死亡"
    end
    if type(UnitCanAttack) == "function" and UnitExists and UnitExists("target") and not UnitCanAttack("player", "target") then
        return "target_invalid", "目标不可攻击"
    end
    local range
    if C_Spell and type(C_Spell.IsSpellInRange) == "function" then
        local ok, value = call(C_Spell.IsSpellInRange, spellID, "target")
        if ok then range = value end
    elseif type(IsSpellInRange) == "function" then
        local ok, value = call(IsSpellInRange, spellID, "target")
        if ok then range = value end
    end
    local rangeNumber, rangeBoolean = numeric(range), plainBoolean(range)
    if rangeNumber == nil and rangeBoolean == nil then return "unknown", "距离状态未知或受保护" end
    if rangeNumber == 0 or rangeBoolean == false then return "range", "目标不在技能距离内" end
    return "ready", nil
end

local function hasProc(spellID)
    if type(IsSpellOverlayed) == "function" then
        local ok, value = call(IsSpellOverlayed, spellID)
        return ok and plainBoolean(value) == true
    end
    if C_SpellActivationOverlay and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function" then
        local ok, value = call(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        return ok and plainBoolean(value) == true
    end
    return false
end

local function castSnapshot(options)
    local source = options and options.castSnapshot or nil
    if type(source) ~= "table" and TE.SignalFrame and type(TE.SignalFrame.GetCastDisplayInfo) == "function" then
        source = TE.SignalFrame:GetCastDisplayInfo()
    end
    source = type(source) == "table" and source or {}
    local active = source.active == true
    local kind = source.kind
    local spellID = numeric(source.spellID)
    return {
        active = active,
        kind = kind,
        name = plainText(source.name, nil),
        spellID = spellID,
        startTimeMS = numeric(source.startTimeMS),
        endTimeMS = numeric(source.endTimeMS),
        channeling = active and (kind == "channel" or kind == "empower"),
    }
end

local function sameBaseSpell(firstSpellID, secondSpellID)
    firstSpellID, secondSpellID = numeric(firstSpellID), numeric(secondSpellID)
    if not firstSpellID or not secondSpellID or type(FindBaseSpellByID) ~= "function" then return false end
    local okFirst, firstBase = pcall(FindBaseSpellByID, firstSpellID)
    local okSecond, secondBase = pcall(FindBaseSpellByID, secondSpellID)
    firstBase, secondBase = okFirst and numeric(firstBase) or nil, okSecond and numeric(secondBase) or nil
    return firstBase ~= nil and secondBase ~= nil and firstBase == secondBase
end

local function spellMatchesCast(spellID, cast, options)
    spellID = numeric(spellID)
    local castSpellID = numeric(cast and cast.spellID)
    if not spellID or not castSpellID then return false end
    if spellID == castSpellID then return true end
    if numeric(options and options.matchedSpellID) == castSpellID then return true end
    if type(options and options.equivalentSpellIDs) == "table" then
        for _, equivalentID in ipairs(options.equivalentSpellIDs) do
            if numeric(equivalentID) == castSpellID then return true end
        end
    end
    return sameBaseSpell(spellID, castSpellID)
end

local function cooldownBlocked(remaining, charges)
    remaining = numeric(remaining)
    local current = charges and numeric(charges.current) or nil
    if remaining == nil or remaining <= 0 then return false end
    if current ~= nil and current > 0 then return false end
    return true
end

-- Expand the narrow AutoBurst cooldown sample into the HUD state without
-- touching cooldown, charge, tracker or action-bar APIs a second time.
local SHARED_COOLDOWN_FIELDS = {
    "cooldownRemaining", "cooldownDuration", "cooldownStart", "cooldownKnown",
    "cooldownUnknownReason", "cooldownSource", "cooldownIdentityKey",
    "cooldownFallback", "cooldownFallbackOrigin", "cooldownConfirmationPending",
    "cooldownActive", "cooldownOnGCD", "cooldownGcdAlias", "cooldownGcdAliasReason",
    "cooldownPublicActive", "cooldownPublicActiveKnown", "cooldownPublicOnGCD",
    "cooldownPublicOnGCDKnown", "cooldownActionBarPublicActive",
    "cooldownActionBarPublicActiveKnown", "cooldownActionBarPublicOnGCD",
    "cooldownActionBarPublicOnGCDKnown", "cooldownActionBarDurationKnown",
    "cooldownActionBarDurationOwnEvidence", "cooldownActionBarNumericOwnEvidence",
    "cooldownActionBarNumericReady", "cooldownDirectActionBarEvidence",
    "cooldownDirectActionBarReadyEvidence", "cooldownExactActionVetoEvidence",
    "cooldownLiveRead", "charges", "maxCharges", "chargeCooldownRemaining",
    "chargeCooldownDuration", "chargeCooldownStart", "chargeCooldownKnown",
}

local function applySharedCooldownState(state, sample, gcd)
    for _, key in ipairs(SHARED_COOLDOWN_FIELDS) do
        if sample[key] ~= nil then state[key] = sample[key] end
    end
    gcd = type(gcd) == "table" and gcd or {}
    state.gcdRemaining = gcd.remaining
    state.gcdDuration = gcd.duration
    state.gcdStart = gcd.start
    state.gcdKnown = gcd.known == true
    state.gcdUnknownReason = gcd.reason
    state.gcdActive = gcd.active == true
    local charges
    if sample.charges ~= nil or sample.maxCharges ~= nil then
        charges = {
            current = sample.charges,
            maximum = sample.maxCharges,
            cooldownRemaining = sample.chargeCooldownRemaining,
            cooldownDuration = sample.chargeCooldownDuration,
            cooldownStart = sample.chargeCooldownStart,
            cooldownKnown = sample.chargeCooldownKnown == true,
        }
    end
    return charges
end

-- Narrow read-only sampler used by AutoBurst.  Unlike Collect(), this path
-- never calls spell-usability, target/range, proc or aura APIs, so burst
-- policy cannot accidentally acquire resource, target, Buff or enemy-count
-- inputs while it only needs spell CD, charges and the shared GCD snapshot.
function IconState:CollectCooldownOnly(spellID, options)
    options = options or {}
    spellID = numeric(spellID)
    local trackerMeta = {
        actionSlot = options.actionSlot or options.slot,
        directActionSlot = options.directActionSlot == true,
        actionBarStateTrusted = options.actionBarStateTrusted == true,
        matchedSpellID = options.matchedSpellID,
        requestedSpellID = options.requestedSpellID,
        equivalentSpellIDs = options.equivalentSpellIDs,
    }
    local state = {
        schema = 1,
        spellID = spellID,
        known = spellID ~= nil and spellID > 0,
        cooldownKnown = false,
        cooldownActive = nil,
        cooldownOnGCD = nil,
        -- Preserve public boolean provenance so false can be distinguished from
        -- unknown without materializing protected countdown values.
        cooldownPublicActive = nil,
        cooldownPublicActiveKnown = false,
        cooldownPublicOnGCD = nil,
        cooldownPublicOnGCDKnown = false,
        cooldownUnknownReason = nil,
        cooldownSource = nil,
        cooldownIdentityKey = nil,
        cooldownConfirmationPending = false,
        cooldownGcdAlias = false,
        cooldownGcdAliasReason = nil,
        -- Set only when a trusted, direct default-action-bar button explicitly
        -- reports an active non-GCD cooldown for this exact bound action.
        cooldownDirectActionBarEvidence = false,
        -- The symmetric positive-ready certificate.  It is intentionally
        -- separate from the own-CD evidence: an exact visible button that
        -- explicitly reports ready can correct a stale/base SpellID cooldown,
        -- but it never authorizes a cooldown skip by itself.
        cooldownDirectActionBarReadyEvidence = false,
        cooldownActionBarDurationKnown = false,
        cooldownActionBarDurationOwnEvidence = false,
        cooldownActionBarNumericOwnEvidence = false,
        cooldownLiveRead = options.liveCooldown == true,
        cooldownRequestedActionSlot = numeric(options.actionSlot or options.slot),
        cooldownActionBarStateTrusted = options.actionBarStateTrusted == true,
        cooldownRequestedSpellID = spellID,
        -- A verified reaction macro may be a target-management macro and is
        -- therefore not a general AutoBurst-ready actionbar source. It can
        -- still provide one narrow negative fact: its exact visible button is
        -- on a real non-GCD cooldown. This flag permits only that veto; it
        -- never lets a macro button's ready state authorize a dispatch.
        cooldownExactActionVeto = options.exactActionCooldownVeto == true,
        cooldownExactActionVetoEvidence = false,
        charges = nil,
        maxCharges = nil,
        chargeCooldownKnown = false,
        gcdKnown = false,
        gcdActive = nil,
        gcdActiveKnown = false,
        gcdUnknownReason = nil,
    }
    if not state.known then
        state.cooldownUnknownReason = "缺少可解释的技能编号"
        return state
    end

    if TE.CooldownTracker and type(TE.CooldownTracker.RegisterSpell) == "function" then
        TE.CooldownTracker:RegisterSpell(spellID, trackerMeta)
    end

    -- AutoBurst requests a fresh spell snapshot per state-machine tick.
    -- This avoids treating a cached shared-GCD overlay as a personal cooldown.
    local remaining, duration, start, _, _, cooldownKnown, cooldownReason, cooldownActive, cooldownOnGCD, resolverSource, resolverIdentity = spellCooldown(spellID, {
        liveOnly = options.liveCooldown == true,
    })
    state.cooldownRemaining, state.cooldownDuration, state.cooldownStart = remaining, duration, start
    state.cooldownKnown = cooldownKnown == true
    state.cooldownUnknownReason = cooldownReason
    state.cooldownPublicActive = cooldownActive
    state.cooldownPublicActiveKnown = cooldownActive ~= nil
    state.cooldownPublicOnGCD = cooldownOnGCD
    state.cooldownPublicOnGCDKnown = cooldownOnGCD ~= nil
    state.cooldownOnGCD = cooldownOnGCD
    state.cooldownActive = cooldownActive == true and cooldownOnGCD ~= true
    if state.cooldownKnown then
        state.cooldownSource = resolverSource or "spell_api"
        state.cooldownIdentityKey = resolverIdentity
    end

    -- Prefer the actual trusted action button for GCD provenance. This does
    -- not create a cooldown or binding; it only prevents a base/override spell
    -- API disagreement from being misclassified as a personal CD by AutoBurst.
    local actionCooldown = actionBarPublicCooldown(
        options.actionSlot or options.slot,
        options.directActionSlot == true or options.actionBarStateTrusted == true
    )
    -- Do not use `condition and value or nil` here: Lua would collapse the
    -- explicit public boolean `false` into nil, turning a known non-GCD button
    -- state into UNKNOWN and preventing the narrow direct-action certificate.
    local actionActive, actionOnGCD, actionLongOwnCooldown, actionNumericReady, actionNumericOwnCooldown
    if type(actionCooldown) == "table" then
        actionActive = actionCooldown.active
        actionOnGCD = actionCooldown.onGCD
        actionLongOwnCooldown = actionCooldown.longOwnCooldown == true
        actionNumericReady = actionCooldown.numericReady == true
        actionNumericOwnCooldown = actionCooldown.numericOwnCooldown == true
    end
    state.cooldownActionBarPublicActive = actionActive
    state.cooldownActionBarPublicActiveKnown = actionActive ~= nil
    state.cooldownActionBarPublicOnGCD = actionOnGCD
    state.cooldownActionBarPublicOnGCDKnown = actionOnGCD ~= nil
    state.cooldownActionBarDurationKnown = type(actionCooldown) == "table" and actionCooldown.numericKnown == true
    state.cooldownActionBarDurationOwnEvidence = actionLongOwnCooldown == true
    state.cooldownActionBarNumericOwnEvidence = actionNumericOwnCooldown == true
    state.cooldownActionBarNumericReady = actionNumericReady == true
    if actionOnGCD == true then
        state.cooldownOnGCD = true
        state.cooldownActive = false
        state.cooldownGcdAlias = true
        state.cooldownGcdAliasReason = "actionbar_public_on_gcd"
    end

    local trackerPending = TE.CooldownTracker and TE.CooldownTracker.IsConfirmationPending
        and TE.CooldownTracker:IsConfirmationPending(spellID, trackerMeta) or false
    state.cooldownConfirmationPending = trackerPending == true

    local trackedCooldown
    if TE.CooldownTracker and type(TE.CooldownTracker.GetCooldown) == "function" then
        local ok, value = pcall(TE.CooldownTracker.GetCooldown, TE.CooldownTracker, spellID, trackerMeta)
        if ok and type(value) == "table" then trackedCooldown = value end
    end
    local apiExplicitlyReady = state.cooldownKnown == true and state.cooldownActive == false and state.cooldownOnGCD ~= true
    -- A fresh public spell snapshot is authoritative for AutoBurst. In
    -- particular, `isOnGCD=true` must not be overwritten by an older
    -- CooldownTracker entry; doing so makes a ready pre-injection look like a
    -- real personal cooldown and lets the simple path incorrectly skip it.
    local liveApiAuthoritative = options.liveCooldown == true and state.cooldownKnown == true
    if trackedCooldown and liveApiAuthoritative ~= true and not (apiExplicitlyReady and trackerPending ~= true) then
        state.cooldownRemaining = numeric(trackedCooldown.remaining)
        state.cooldownDuration = numeric(trackedCooldown.duration)
        state.cooldownStart = numeric(trackedCooldown.start)
        state.cooldownKnown = state.cooldownRemaining ~= nil and state.cooldownDuration ~= nil and state.cooldownStart ~= nil
        state.cooldownActive = state.cooldownKnown and state.cooldownRemaining > 0 or state.cooldownActive
        state.cooldownSource = trackedCooldown.source or "local_tracker_cached"
        state.cooldownIdentityKey = trackedCooldown.identityKey or state.cooldownIdentityKey
        state.cooldownUnknownReason = nil
    elseif state.cooldownKnown == false and state.cooldownConfirmationPending == true then
        state.cooldownUnknownReason = state.cooldownUnknownReason or "技能冷却正在与动作条确认"
    end

    local gcd = type(options.gcdSnapshot) == "table" and options.gcdSnapshot or collectGcdSnapshot()
    state.gcdKnown = gcd.known == true
    state.gcdActive = gcd.active == true
    state.gcdActiveKnown = gcd.activeKnown == true
    state.gcdUnknownReason = gcd.reason
    -- This must run after the tracker reconciliation above so a cached
    -- cooldown cannot re-introduce a false personal CD during the shared GCD.
    normalizeCooldownAgainstGcd(state, gcd)

    -- A direct, trusted default action-bar button is the authoritative public
    -- source for the exact action the player will actually press. Some
    -- transformed/override spell APIs can transiently report the requested
    -- SpellID as ready while its visible button is already on a real personal
    -- cooldown. When that button explicitly says active and not-on-GCD, retain
    -- it as a narrow own-CD certificate candidate for AutoBurst. This never
    -- promotes generic gray styling, an opaque DurationObject, or a shared GCD.
    -- The same direct button is also authoritative when it explicitly says
    -- READY.  This closes the inverse of the long-CD compatibility issue:
    -- talent/hero/override variants can leave C_Spell reporting the declared
    -- SpellID's old/base cooldown (for example 120s) after the actual bound
    -- action has already recovered (for example 60s).  For AutoBurst this is
    -- not a speculative UI signal: it is the exact trusted default-action-bar
    -- action TEK would press.  Let GCDGate decide any shared queue/GCD phase;
    -- only clear the false *own cooldown* classification here.
    if (actionActive == false or actionNumericReady == true) and actionActive ~= true and actionOnGCD ~= true
        and options.directActionSlot == true
        and options.actionBarStateTrusted == true then
        state.cooldownRemaining = 0
        state.cooldownDuration = 0
        state.cooldownStart = 0
        state.cooldownKnown = true
        state.cooldownActive = false
        state.cooldownOnGCD = false
        state.cooldownGcdAlias = false
        state.cooldownGcdAliasReason = nil
        state.cooldownPublicActive = false
        state.cooldownPublicActiveKnown = true
        state.cooldownPublicOnGCD = actionOnGCD
        state.cooldownPublicOnGCDKnown = actionOnGCD ~= nil
        state.cooldownSource = "actionbar_api_ready"
        state.cooldownIdentityKey = "spell:" .. tostring(spellID)
        state.cooldownUnknownReason = nil
        state.cooldownDirectActionBarReadyEvidence = true
    elseif actionActive == true and actionOnGCD == false
        and options.directActionSlot == true
        and (options.actionBarStateTrusted == true or options.exactActionCooldownVeto == true) then
        if applyDirectActionbarNumericCooldown(state, actionCooldown, spellID) ~= true then
            state.cooldownKnown = true
            state.cooldownActive = true
            state.cooldownOnGCD = false
            state.cooldownGcdAlias = false
            state.cooldownGcdAliasReason = nil
            state.cooldownPublicActive = true
            state.cooldownPublicActiveKnown = true
            state.cooldownPublicOnGCD = false
            state.cooldownPublicOnGCDKnown = true
            state.cooldownSource = "actionbar_api"
            state.cooldownIdentityKey = "spell:" .. tostring(spellID)
            state.cooldownUnknownReason = nil
            state.cooldownDirectActionBarEvidence = options.actionBarStateTrusted == true
            state.cooldownExactActionVetoEvidence = options.exactActionCooldownVeto == true
        end
    elseif actionLongOwnCooldown == true
        and options.directActionSlot == true
        and (options.actionBarStateTrusted == true or options.exactActionCooldownVeto == true) then
        -- Compatibility path for clients that omit public action booleans while
        -- exposing a normal long CD on the exact direct button. For a verified
        -- reaction macro this remains a *veto only*: the same read cannot make
        -- a ready macro authoritative for delivery.
        if applyDirectActionbarNumericCooldown(state, actionCooldown, spellID) ~= true then
            state.cooldownKnown = true
            state.cooldownActive = true
            state.cooldownOnGCD = false
            state.cooldownGcdAlias = false
            state.cooldownGcdAliasReason = nil
            state.cooldownPublicActive = true
            state.cooldownPublicActiveKnown = true
            state.cooldownPublicOnGCD = false
            state.cooldownPublicOnGCDKnown = true
            state.cooldownSource = "actionbar_duration"
            state.cooldownIdentityKey = "spell:" .. tostring(spellID)
            state.cooldownUnknownReason = nil
            state.cooldownDirectActionBarEvidence = options.actionBarStateTrusted == true
            state.cooldownExactActionVetoEvidence = options.exactActionCooldownVeto == true
        end
    end

    local charges = spellCharges(spellID)
    local trackedCharges
    if TE.CooldownTracker and type(TE.CooldownTracker.GetCharges) == "function" then
        local ok, value = pcall(TE.CooldownTracker.GetCharges, TE.CooldownTracker, spellID, trackerMeta)
        if ok and type(value) == "table" then trackedCharges = value end
    end
    if trackedCharges then
        charges = charges or {}
        if charges.current == nil then charges.current = numeric(trackedCharges.current) end
        if charges.maximum == nil then charges.maximum = numeric(trackedCharges.maximum) end
        if charges.cooldownKnown ~= true and trackedCharges.cooldownKnown == true then
            charges.cooldownRemaining = numeric(trackedCharges.cooldownRemaining)
            charges.cooldownDuration = numeric(trackedCharges.cooldownDuration)
            charges.cooldownStart = numeric(trackedCharges.cooldownStart)
            charges.cooldownKnown = charges.cooldownDuration ~= nil and charges.cooldownDuration > 0
            charges.cooldownUnknownReason = nil
        end
    end
    if charges then
        state.charges, state.maxCharges = charges.current, charges.maximum
        state.chargeCooldownRemaining, state.chargeCooldownDuration = charges.cooldownRemaining, charges.cooldownDuration
        state.chargeCooldownStart = charges.cooldownStart
        state.chargeCooldownKnown = charges.cooldownKnown == true
        if charges.cooldownKnown == false and not state.cooldownUnknownReason then
            state.cooldownUnknownReason = charges.cooldownUnknownReason
        end
    end
    return state
end

-- Narrow inventory cooldown sampler for AutoBurst ordered-sequence.  It reads only
-- the explicitly selected equipped trinket slot and current ItemID cooldown;
-- it never queries usability, target/range, auras or HUD visual state.
function IconState:CollectInventoryCooldownOnly(slot, expectedItemID, options)
    options = type(options) == "table" and options or {}
    slot = numeric(slot)
    expectedItemID = numeric(expectedItemID)
    local state = {
        schema = 1,
        kind = "inventory",
        inventorySlot = slot,
        expectedItemID = expectedItemID,
        known = slot == 13 or slot == 14,
        cooldownKnown = false,
        cooldownActive = nil,
        cooldownOnGCD = nil,
        cooldownPublicActive = nil,
        cooldownPublicActiveKnown = false,
        cooldownPublicOnGCD = nil,
        cooldownPublicOnGCDKnown = false,
        cooldownUnknownReason = nil,
        cooldownSource = nil,
        cooldownIdentityKey = nil,
        cooldownConfirmationPending = false,
        cooldownGcdAlias = false,
        cooldownGcdAliasReason = nil,
        cooldownLiveRead = true,
        cooldownRequestedActionSlot = numeric(options.actionSlot or options.slot),
        cooldownActionBarStateTrusted = options.actionBarStateTrusted == true,
        charges = nil,
        maxCharges = nil,
        chargeCooldownKnown = false,
        gcdKnown = false,
        gcdActive = nil,
        gcdActiveKnown = false,
        gcdUnknownReason = nil,
    }
    if state.known ~= true then
        state.cooldownUnknownReason = "inventory_slot_invalid"
        return state
    end
    if not (TE.CooldownResolver and type(TE.CooldownResolver.GetInventoryLive) == "function") then
        state.cooldownUnknownReason = "inventory_cooldown_resolver_unavailable"
        return state
    end
    perfCount("cooldown_inventory_api_read")
    local ok, snapshot = pcall(TE.CooldownResolver.GetInventoryLive, TE.CooldownResolver, slot, expectedItemID)
    if not ok or type(snapshot) ~= "table" then
        state.cooldownUnknownReason = "inventory_cooldown_read_failed"
        return state
    end
    local currentItemID = numeric(snapshot.itemID)
    state.itemID = currentItemID
    if expectedItemID and currentItemID and expectedItemID ~= currentItemID then
        state.cooldownUnknownReason = "inventory_equipment_changed"
        state.inventoryEquipmentChanged = true
        return state
    end
    if expectedItemID and not currentItemID then
        state.cooldownUnknownReason = "inventory_item_missing"
        state.inventoryEquipmentChanged = true
        return state
    end
    state.cooldownRemaining = numeric(snapshot.remaining)
    state.cooldownDuration = numeric(snapshot.duration)
    state.cooldownStart = numeric(snapshot.start)
    state.cooldownKnown = snapshot.known == true
    state.cooldownPublicActive = snapshot.active
    state.cooldownPublicActiveKnown = snapshot.active ~= nil
    state.cooldownPublicOnGCD = snapshot.onGCD
    state.cooldownPublicOnGCDKnown = snapshot.onGCD ~= nil
    state.cooldownOnGCD = snapshot.onGCD
    state.cooldownActive = snapshot.active == true and snapshot.onGCD ~= true
    state.cooldownUnknownReason = snapshot.reason
    state.cooldownSource = snapshot.source
    state.cooldownIdentityKey = "inventory:" .. tostring(slot) .. ":item:" .. tostring(currentItemID or expectedItemID or 0)
    state.cooldownSlotSource = snapshot.slotSource
    state.cooldownSlotKnown = snapshot.slotKnown
    state.cooldownSlotActive = snapshot.slotActive
    state.cooldownItemFallbackKnown = snapshot.itemFallbackKnown
    state.cooldownItemFallbackActive = snapshot.itemFallbackActive

    local gcd = type(options.gcdSnapshot) == "table" and options.gcdSnapshot or collectGcdSnapshot()
    state.gcdKnown = gcd.known == true
    state.gcdActive = gcd.active == true
    state.gcdActiveKnown = gcd.activeKnown == true
    state.gcdUnknownReason = gcd.reason
    normalizeCooldownAgainstGcd(state, gcd)
    return state
end

function IconState:Collect(spellID, options)
    options = options or {}
    spellID = numeric(spellID)
    -- Preserve a single cooldown identity for base/override variants that point
    -- at the same visible action-bar button.  This affects HUD presentation
    -- only; planners and dispatch continue to use their original SpellID.
    local trackerMeta = {
        actionSlot = options.actionSlot or options.slot,
        directActionSlot = options.directActionSlot == true,
        actionBarStateTrusted = options.actionBarStateTrusted == true,
        matchedSpellID = options.matchedSpellID,
        requestedSpellID = options.requestedSpellID,
        equivalentSpellIDs = options.equivalentSpellIDs,
    }
    if TE.CooldownTracker and type(TE.CooldownTracker.RegisterSpell) == "function" then
        TE.CooldownTracker:RegisterSpell(spellID, trackerMeta)
    end
    local cast = castSnapshot(options)
    local castThisSpell = spellMatchesCast(spellID, cast, options)
    local state = {
        schema = 6,
        spellID = spellID,
        source = "wow_readonly_api+signalframe_cast_snapshot_secret_safe",
        known = spellID ~= nil and spellID > 0,
        cooldownRemaining = nil,
        cooldownDuration = nil,
        cooldownStart = nil,
        cooldownKnown = false,
        cooldownUnknownReason = nil,
        cooldownSource = nil,
        cooldownIdentityKey = nil,
        -- True only when numeric fields came from the event-driven local
        -- fallback because live API numerics are delayed/protected. Native
        -- DurationObjects still take rendering precedence in the HUD.
        cooldownFallback = false,
        cooldownFallbackOrigin = nil,
        -- True while the local tracker is reconciling a just-cast spell with
        -- post-event C_Spell snapshots. This is display-only and never affects
        -- a recommendation, binding, TEAP payload, or TEK input.
        cooldownConfirmationPending = false,
        -- Public state indicators only: they support HUD labels/tooltip status
        -- and cannot reveal an underlying remaining duration.
        cooldownActive = nil,
        cooldownOnGCD = nil,
        gcdRemaining = nil,
        gcdDuration = nil,
        gcdStart = nil,
        gcdKnown = false,
        gcdUnknownReason = nil,
        gcdActive = nil,
        charges = nil,
        maxCharges = nil,
        chargeCooldownRemaining = nil,
        chargeCooldownDuration = nil,
        chargeCooldownStart = nil,
        chargeCooldownKnown = false,
        resourceBlocked = false,
        rangeBlocked = false,
        targetInvalid = false,
        targetChecked = options.requiresHostileTarget == true,
        procHighlight = false,
        casting = castThisSpell == true and cast.active == true,
        channeling = castThisSpell == true and cast.channeling == true,
        globalCasting = cast.active == true,
        globalChanneling = cast.channeling == true,
        castingThisSpell = castThisSpell == true,
        castingSpellID = cast.spellID,
        castingKind = cast.kind,
        castingName = cast.name,
        castingStartTimeMS = cast.startTimeMS,
        castingEndTimeMS = cast.endTimeMS,
        unusableReason = nil,
        usableState = "unknown",
        targetState = "unknown",
        availability = "unknown",
        lastError = nil,
    }
    if not state.known then
        state.unusableReason = "缺少可解释的技能编号"
        return state
    end

    local charges
    local sharedCooldown = type(options.cooldownSnapshot) == "table" and options.cooldownSnapshot or nil
    if sharedCooldown and numeric(sharedCooldown.spellID) == spellID then
        charges = applySharedCooldownState(state, sharedCooldown, options.gcdSnapshot)
        state.source = "runtime_snapshot_shared_cooldown+signalframe_cast_snapshot_secret_safe"
    else
    -- AutoBurst requests a fresh spell snapshot per state-machine tick.
    -- This avoids treating a cached shared-GCD overlay as a personal cooldown.
    local remaining, duration, start, _, _, cooldownKnown, cooldownReason, cooldownActive, cooldownOnGCD, resolverSource, resolverIdentity = spellCooldown(spellID, {
        liveOnly = options.liveCooldown == true,
    })
    state.cooldownRemaining, state.cooldownDuration, state.cooldownStart = remaining, duration, start
    state.cooldownKnown = cooldownKnown == true
    state.cooldownUnknownReason = cooldownReason
    -- Do not call a GCD-only lockout a spell CD. `isOnGCD` is public API state;
    -- if it is absent, the HUD keeps the state neutral and lets the renderer
    -- attach Blizzard's native DurationObject where the client supports it.
    state.cooldownOnGCD = cooldownOnGCD
    state.cooldownActive = cooldownActive == true and cooldownOnGCD ~= true
    if state.cooldownKnown == true then
        state.cooldownSource = resolverSource or "spell_api"
        state.cooldownIdentityKey = resolverIdentity
    end

    -- The fallback tracker is only consulted after the shared resolver. It is
    -- event-driven (cast → local timer → API reconciliation) and never wins over
    -- a live active numeric snapshot. It closes the protected/delayed API gap
    -- that otherwise leaves a valid cooldown card with no readable countdown.
    local trackerPending = TE.CooldownTracker and TE.CooldownTracker.IsConfirmationPending
        and TE.CooldownTracker:IsConfirmationPending(spellID, trackerMeta) or false
    state.cooldownConfirmationPending = trackerPending == true

    local trackedCooldown
    if TE.CooldownTracker and type(TE.CooldownTracker.GetCooldown) == "function" then
        local ok, value = pcall(TE.CooldownTracker.GetCooldown, TE.CooldownTracker, spellID, trackerMeta)
        if ok and type(value) == "table" then trackedCooldown = value end
    end
    -- An explicit public ready state wins after the confirmation burst. During
    -- that short post-cast interval a 0/0 sample is known to be transient, so
    -- retain the locally started timer until the client exposes final state.
    local apiExplicitlyReady = state.cooldownKnown == true and state.cooldownActive == false and state.cooldownOnGCD ~= true
    if trackedCooldown and not (apiExplicitlyReady and trackerPending ~= true) then
        state.cooldownRemaining = numeric(trackedCooldown.remaining)
        state.cooldownDuration = numeric(trackedCooldown.duration)
        state.cooldownStart = numeric(trackedCooldown.start)
        state.cooldownKnown = state.cooldownRemaining ~= nil and state.cooldownDuration ~= nil and state.cooldownStart ~= nil
        state.cooldownActive = state.cooldownKnown and state.cooldownRemaining > 0 or state.cooldownActive
        state.cooldownSource = trackedCooldown.source or "local_tracker_cached"
        state.cooldownIdentityKey = trackedCooldown.identityKey or state.cooldownIdentityKey
        state.cooldownFallback = trackedCooldown.fallback == true
        state.cooldownFallbackOrigin = trackedCooldown.fallbackOrigin
        state.cooldownUnknownReason = nil
    elseif state.cooldownKnown == false and state.cooldownConfirmationPending == true then
        state.cooldownUnknownReason = state.cooldownUnknownReason or "技能冷却正在与动作条确认"
    end

    -- GCD is shared by every icon in the same advisory refresh. Prefer the
    -- caller-provided snapshot; retain a local fallback for external callers.
    local gcd = type(options.gcdSnapshot) == "table" and options.gcdSnapshot or collectGcdSnapshot()
    local gcdRemaining, gcdDuration, gcdStart = gcd.remaining, gcd.duration, gcd.start
    local gcdKnown, gcdReason, gcdActive = gcd.known, gcd.reason, gcd.active
    state.gcdRemaining, state.gcdDuration, state.gcdStart = gcdRemaining, gcdDuration, gcdStart
    state.gcdKnown = gcdKnown == true
    state.gcdUnknownReason = gcdReason
    state.gcdActive = gcdActive == true
    normalizeCooldownAgainstGcd(state, gcd)

    -- The HUD must not force native numbers merely because a directly bound
    -- skill has an adjusted/override CD. Reconcile its exact current button
    -- first: if readable, the sanitized action-bar timer becomes the custom HUD
    -- label source; if opaque, the existing DurationObject swipe remains safe.
    local displayActionCooldown = actionBarPublicCooldown(
        options.actionSlot or options.slot,
        options.directActionSlot == true or options.actionBarStateTrusted == true
    )
    local displayActionActive = type(displayActionCooldown) == "table" and displayActionCooldown.active or nil
    local displayActionOnGCD = type(displayActionCooldown) == "table" and displayActionCooldown.onGCD or nil
    local displayActionReady = type(displayActionCooldown) == "table" and displayActionCooldown.numericReady == true
    local displayActionLongOwn = type(displayActionCooldown) == "table" and displayActionCooldown.longOwnCooldown == true
    local displayActionTrusted = options.directActionSlot == true and options.actionBarStateTrusted == true
    -- Store only an already-sanitized exact action-bar numeric sample. If the
    -- client makes the next sample opaque, CooldownTracker can keep the HUD CD
    -- text continuous without inventing static/base cooldown values.
    if displayActionTrusted and type(displayActionCooldown) == "table"
        and displayActionCooldown.numericOwnCooldown == true
        and TE.CooldownTracker and type(TE.CooldownTracker.ObserveCooldown) == "function" then
        pcall(TE.CooldownTracker.ObserveCooldown, TE.CooldownTracker, spellID, trackerMeta, {
            start = displayActionCooldown.numericStart,
            duration = displayActionCooldown.numericDuration,
            remaining = displayActionCooldown.numericRemaining,
            source = "actionbar_numeric_observed",
        })
    end
    -- A generic action-bar `isOnGCD=true` observation must never erase a
    -- confirmed own cooldown captured earlier in this same collection. This is
    -- especially visible immediately after casting: the shared GCD arrives
    -- first on some clients while the spell/action slot is already cooling down.
    -- Prefer an exact direct-button long-CD numeric snapshot; otherwise retain
    -- a known non-GCD own cooldown and classify only the residual pure GCD.
    local knownOwnCooldown = state.cooldownKnown == true
        and state.cooldownActive == true
        and state.cooldownOnGCD ~= true
        and state.cooldownGcdAlias ~= true
        and numeric(state.cooldownRemaining) ~= nil
        and numeric(state.cooldownRemaining) > 0
    if displayActionTrusted and ((displayActionActive == true and displayActionOnGCD == false) or displayActionLongOwn == true) then
        if applyDirectActionbarNumericCooldown(state, displayActionCooldown, spellID) ~= true then
            state.cooldownKnown = true
            state.cooldownActive = true
            state.cooldownOnGCD = false
            state.cooldownGcdAlias = false
            state.cooldownGcdAliasReason = nil
            state.cooldownSource = displayActionLongOwn and "actionbar_duration" or "actionbar_api"
            state.cooldownIdentityKey = "spell:" .. tostring(spellID)
            state.cooldownUnknownReason = nil
        end
    elseif displayActionTrusted and displayActionOnGCD == true and knownOwnCooldown ~= true then
        state.cooldownOnGCD = true
        state.cooldownActive = false
        state.cooldownGcdAlias = true
        state.cooldownGcdAliasReason = "actionbar_public_on_gcd"
    elseif displayActionTrusted and (displayActionActive == false or displayActionReady == true)
        and displayActionActive ~= true and displayActionOnGCD ~= true then
        state.cooldownRemaining = 0
        state.cooldownDuration = 0
        state.cooldownStart = 0
        state.cooldownKnown = true
        state.cooldownActive = false
        state.cooldownOnGCD = false
        state.cooldownGcdAlias = false
        state.cooldownGcdAliasReason = nil
        state.cooldownSource = "actionbar_api_ready"
        state.cooldownIdentityKey = "spell:" .. tostring(spellID)
        state.cooldownUnknownReason = nil
    end

    -- Charges use live API values first. When charge numerics become protected
    -- in combat, the same tracker maintains the pre-cached max/current/recharge
    -- state from casts and lazy recovery. It is presentation-only.
    charges = spellCharges(spellID)
    local trackedCharges
    if TE.CooldownTracker and type(TE.CooldownTracker.GetCharges) == "function" then
        local ok, value = pcall(TE.CooldownTracker.GetCharges, TE.CooldownTracker, spellID, trackerMeta)
        if ok and type(value) == "table" then trackedCharges = value end
    end
    if trackedCharges then
        charges = charges or {}
        if charges.current == nil then charges.current = numeric(trackedCharges.current) end
        if charges.maximum == nil then charges.maximum = numeric(trackedCharges.maximum) end
        if charges.cooldownKnown ~= true and trackedCharges.cooldownKnown == true then
            charges.cooldownRemaining = numeric(trackedCharges.cooldownRemaining)
            charges.cooldownDuration = numeric(trackedCharges.cooldownDuration)
            charges.cooldownStart = numeric(trackedCharges.cooldownStart)
            charges.cooldownKnown = charges.cooldownDuration ~= nil and charges.cooldownDuration > 0
            charges.cooldownUnknownReason = nil
            charges.source = trackedCharges.source
        end
    end
    if charges then
        state.charges, state.maxCharges = charges.current, charges.maximum
        state.chargeCooldownRemaining, state.chargeCooldownDuration = charges.cooldownRemaining, charges.cooldownDuration
        state.chargeCooldownStart = charges.cooldownStart
        state.chargeCooldownKnown = charges.cooldownKnown == true
        if charges.cooldownKnown == false and not state.cooldownUnknownReason then state.cooldownUnknownReason = charges.cooldownUnknownReason end
    end

    end

    state.usableState, state.unusableReason = usableState(spellID)
    state.targetState, state.targetReason = targetState(spellID, options.requiresHostileTarget == true)
    state.resourceBlocked = state.usableState == "resource"
    state.rangeBlocked = state.targetState == "range"
    state.targetInvalid = state.targetState == "target_missing" or state.targetState == "target_dead" or state.targetState == "target_invalid"
    state.procHighlight = hasProc(spellID)

    if state.resourceBlocked then
        state.availability, state.unusableReason = "resource", "资源不足"
    elseif state.targetInvalid then
        state.availability, state.unusableReason = "target", state.targetReason
    elseif state.rangeBlocked then
        state.availability, state.unusableReason = "range", state.targetReason
    elseif cooldownBlocked(state.cooldownRemaining, charges) or state.cooldownActive == true then
        state.availability, state.unusableReason = "cooldown", "冷却中"
    elseif state.cooldownKnown == false and state.cooldownUnknownReason then
        state.availability = state.usableState == "ready" and "ready" or "unknown"
        state.unusableReason = state.unusableReason or state.cooldownUnknownReason
    elseif state.usableState == "unavailable" then
        state.availability = "unavailable"
    elseif state.usableState == "ready" then
        state.availability = "ready"
    end
    state.lastError = lastError
    return state
end

function IconState:ApplyState(item, state)
    item = item or {}
    state = type(state) == "table" and state or {
        schema = 6,
        known = false,
        availability = "unknown",
        usableState = "unknown",
        unusableReason = "图标状态不可用",
        source = "iconstate_apply_fail_safe",
    }
    item.iconState = state
    item.cooldownRemaining = state.cooldownRemaining
    item.cooldownDuration = state.cooldownDuration
    item.cooldownStart = state.cooldownStart
    item.cooldownKnown = state.cooldownKnown
    item.cooldownUnknownReason = state.cooldownUnknownReason
    item.cooldownSource = state.cooldownSource
    item.cooldownIdentityKey = state.cooldownIdentityKey
    item.cooldownFallback = state.cooldownFallback == true
    item.cooldownFallbackOrigin = state.cooldownFallbackOrigin
    item.cooldownConfirmationPending = state.cooldownConfirmationPending == true
    item.cooldownActionBarNumericOwnEvidence = state.cooldownActionBarNumericOwnEvidence == true
    item.cooldownActive = state.cooldownActive
    item.cooldownOnGCD = state.cooldownOnGCD
    item.cooldownGcdAlias = state.cooldownGcdAlias == true
    item.cooldownGcdAliasReason = state.cooldownGcdAliasReason
    item.gcdRemaining = state.gcdRemaining
    item.gcdDuration = state.gcdDuration
    item.gcdStart = state.gcdStart
    item.gcdKnown = state.gcdKnown
    item.gcdUnknownReason = state.gcdUnknownReason
    item.gcdActive = state.gcdActive
    item.charges = state.charges
    item.maxCharges = state.maxCharges
    item.chargeCooldownRemaining = state.chargeCooldownRemaining
    item.chargeCooldownDuration = state.chargeCooldownDuration
    item.chargeCooldownStart = state.chargeCooldownStart
    item.chargeCooldownKnown = state.chargeCooldownKnown
    item.procHighlight = state.procHighlight
    item.casting = state.casting
    item.channeling = state.channeling
    item.castingThisSpell = state.castingThisSpell
    item.castingSpellID = state.castingSpellID
    item.castingKind = state.castingKind
    item.castingName = state.castingName
    item.castingStartTimeMS = state.castingStartTimeMS
    item.castingEndTimeMS = state.castingEndTimeMS
    item.globalCasting = state.globalCasting
    item.globalChanneling = state.globalChanneling
    item.targetInvalid = state.targetInvalid
    item.targetChecked = state.targetChecked
    item.targetReason = state.targetReason
    item.rangeBlocked = state.rangeBlocked
    item.resourceBlocked = state.resourceBlocked
    item.unusableReason = state.unusableReason
    item.usableState = state.availability
    item.iconStateError = state.lastError
    return item
end

function IconState:Decorate(item, options)
    item = item or {}
    local ok, state = pcall(function() return self:Collect(item.spellID, options) end)
    if not ok then
        state = {
            schema = 6,
            known = false,
            availability = "unknown",
            usableState = "unknown",
            unusableReason = "图标状态采集失败，已启用安全模式",
            lastError = tostring(state),
            source = "iconstate_fail_safe",
        }
    end
    return self:ApplyState(item, state)
end
