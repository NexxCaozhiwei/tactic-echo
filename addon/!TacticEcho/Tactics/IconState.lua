-- Read-only ability icon state collector.
-- 0.7.4 hardening: values returned by modern WoW APIs can be "secret".
-- A secret value must never escape into a table.concat/string/branching UI path.
-- This module converts only verifiably ordinary Lua numbers to HUD fields; all
-- other numeric observations become unknown without affecting recommendations.
local TE = _G.TacticEcho

local IconState = {}
TE.IconState = IconState

local lastError

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
        local ok, a, b, c, d = call(GetSpellCooldown, spellID)
        if ok then startTime, duration, enabled, modRate = a, b, c, d end
    end
    local cd = deriveCooldown(startTime, duration)
    if isActive == nil and cd.known == true then isActive = cd.remaining > 0 end
    return cd.remaining, cd.duration, cd.start, plainBoolean(enabled), numeric(modRate), cd.known, cd.reason, isActive, isOnGCD, "spell_api", "spell:" .. tostring(spellID)
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
        local ok, info = call(C_Spell.GetSpellCharges, spellID)
        if ok and type(info) == "table" then
            current = info.currentCharges
            maximum = info.maxCharges
            startTime = info.cooldownStartTime
            duration = info.cooldownDuration
            modRate = info.chargeModRate
        end
    elseif type(GetSpellCharges) == "function" then
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
        spellID = spellID,
        startTimeMS = numeric(source.startTimeMS),
        endTimeMS = numeric(source.endTimeMS),
        channeling = active and (kind == "channel" or kind == "empower"),
    }
end

local function cooldownBlocked(remaining, charges)
    remaining = numeric(remaining)
    local current = charges and numeric(charges.current) or nil
    if remaining == nil or remaining <= 0 then return false end
    if current ~= nil and current > 0 then return false end
    return true
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
        cooldownLiveRead = options.liveCooldown == true,
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
    local castThisSpell = cast.spellID ~= nil and spellID ~= nil and cast.spellID == spellID
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

    -- Charges use live API values first. When charge numerics become protected
    -- in combat, the same tracker maintains the pre-cached max/current/recharge
    -- state from casts and lazy recovery. It is presentation-only.
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
    item.iconState = state
    item.cooldownRemaining = state.cooldownRemaining
    item.cooldownDuration = state.cooldownDuration
    item.cooldownStart = state.cooldownStart
    item.cooldownKnown = state.cooldownKnown
    item.cooldownUnknownReason = state.cooldownUnknownReason
    item.cooldownSource = state.cooldownSource
    item.cooldownIdentityKey = state.cooldownIdentityKey
    item.cooldownFallback = state.cooldownFallback == true
    item.cooldownConfirmationPending = state.cooldownConfirmationPending == true
    item.cooldownActive = state.cooldownActive
    item.cooldownOnGCD = state.cooldownOnGCD
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
