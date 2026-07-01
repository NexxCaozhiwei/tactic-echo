-- Local cooldown/charge fallback tracker for HUD presentation only.
--
-- Native DurationObjects remain the first presentation authority whenever the
-- client exposes them. This tracker exists for the complementary case: current
-- protected-cooldown clients can hide numeric start/duration fields in combat,
-- leaving a HUD card with no readable countdown even though the visible action
-- button is cooling down.
--
-- The fallback is deliberately layered:
--   1. A post-cast public API confirmation always replaces the local timer.
--   2. Out of combat, actual observed cooldowns and charge state are cached.
--   3. Only when the API numerics are protected/delayed do we start an
--      event-driven local timer from the cached spell duration.
--   4. A direct action-bar DurationObject still wins in TacticalIconButton, so
--      this module never replaces Blizzard's action-bar countdown when it is
--      available.
--
-- It never changes recommendations, action bindings, TEAP, or TEK input.
-- Cooldown identity is canonicalised to a directly mapped action-bar slot when
-- possible. A cast event that cannot resolve its slot reuses an existing slot
-- alias instead of creating a competing spell-only entry; base/override pairs
-- such as Ashes of Wake therefore share one lifecycle.
local TE = _G.TacticEcho

local SPELL_CONFIRMATION_DELAYS = { 0.01, 0.05, 0.15, 0.35 }
local MIN_TRACKABLE_COOLDOWN_SECONDS = 2.5

local Tracker = { entries = {}, aliases = {}, cooldowns = {}, charges = {} }
TE.CooldownTracker = Tracker

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

local function boolean(value)
    local ok, result = pcall(function()
        if value == true or value == false then return value end
        local resolved = tonumber(value)
        if resolved == 1 then return true end
        if resolved == 0 then return false end
        return nil
    end)
    return ok and result or nil
end

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and (number(value) or 0) or 0
end

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function normalizeIDs(meta, spellID)
    local ids, seen = {}, {}
    local function add(value)
        value = number(value)
        if value and value > 0 and not seen[value] then
            seen[value] = true
            ids[#ids + 1] = math.floor(value)
        end
    end
    add(spellID)
    meta = type(meta) == "table" and meta or {}
    add(meta.matchedSpellID)
    add(meta.requestedSpellID)
    for _, value in ipairs(type(meta.equivalentSpellIDs) == "table" and meta.equivalentSpellIDs or {}) do
        add(value)
    end
    return ids
end

local function directSlot(meta)
    meta = type(meta) == "table" and meta or {}
    local slot = number(meta.actionSlot or meta.slot)
    if slot and slot > 0 and (meta.directActionSlot == true or meta.actionBarStateTrusted == true) then
        return math.floor(slot)
    end
    return nil
end

local function directIdentity(meta)
    local slot = directSlot(meta)
    return slot and ("slot:" .. tostring(slot)) or nil, slot
end

local function positiveCooldownDuration(value)
    value = number(value)
    if not value or value <= 0 then return nil end
    -- Compatibility APIs may expose milliseconds while modern APIs expose
    -- seconds. Raw protected values never survive `number`.
    if value > 1000 then value = value / 1000 end
    return value > 0 and value or nil
end

local function normaliseCooldownDuration(value)
    value = positiveCooldownDuration(value)
    return value and value > MIN_TRACKABLE_COOLDOWN_SECONDS and value or nil
end

--------------------------------------------------------------------------------
-- Out-of-combat duration cache
--------------------------------------------------------------------------------

local cooldownProbeTooltip

local function tooltipCooldownDuration(spellID)
    if inCombat() or not spellID or type(CreateFrame) ~= "function" then return nil end

    if not cooldownProbeTooltip then
        local existing = _G and _G.TacticEchoCooldownTrackerProbe
        cooldownProbeTooltip = existing
            or CreateFrame("GameTooltip", "TacticEchoCooldownTrackerProbe", UIParent, "GameTooltipTemplate")
    end
    local tooltip = cooldownProbeTooltip
    if not tooltip or type(tooltip.SetSpellByID) ~= "function" then return nil end

    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()
    local ok = pcall(tooltip.SetSpellByID, tooltip, spellID)
    if not ok then return nil end

    local function parse(text)
        if type(text) ~= "string" then return nil end
        -- English game clients.
        local seconds = text:match("([%d%.]+)%s*sec%s*cooldown")
            or text:match("cooldown%s*[:：]?%s*([%d%.]+)%s*sec")
        if seconds then return normaliseCooldownDuration(seconds) end
        local minutes = text:match("([%d%.]+)%s*min%s*cooldown")
            or text:match("cooldown%s*[:：]?%s*([%d%.]+)%s*min")
        if minutes then return normaliseCooldownDuration((tonumber(minutes) or 0) * 60) end

        -- Simplified-Chinese tooltip variants used by current clients.
        seconds = text:match("([%d%.]+)%s*秒%s*冷却")
            or text:match("冷却时间%s*[:：]?%s*([%d%.]+)%s*秒")
        if seconds then return normaliseCooldownDuration(seconds) end
        minutes = text:match("([%d%.]+)%s*分钟%s*冷却")
            or text:match("([%d%.]+)%s*分%s*钟%s*冷却")
            or text:match("冷却时间%s*[:：]?%s*([%d%.]+)%s*分钟")
            or text:match("冷却时间%s*[:：]?%s*([%d%.]+)%s*分%s*钟")
        if minutes then return normaliseCooldownDuration((tonumber(minutes) or 0) * 60) end
        return nil
    end

    for index = 1, tooltip:NumLines() do
        local right = _G and _G["TacticEchoCooldownTrackerProbeTextRight" .. index]
        local left = _G and _G["TacticEchoCooldownTrackerProbeTextLeft" .. index]
        local duration = right and parse(right:GetText()) or nil
        if duration then return duration end
        duration = left and parse(left:GetText()) or nil
        if duration then return duration end
    end
    return nil
end

local function baseCooldownDuration(spellID)
    if type(GetSpellBaseCooldown) ~= "function" then return nil end
    local ok, milliseconds = pcall(GetSpellBaseCooldown, spellID)
    if not ok then return nil end
    return normaliseCooldownDuration(milliseconds)
end

local function cacheFallbackDuration(entry)
    if not entry then return nil end
    if normaliseCooldownDuration(entry.duration) then return entry.duration end
    if inCombat() then return nil end

    for _, spellID in ipairs(entry.ids or {}) do
        local duration = tooltipCooldownDuration(spellID)
        if duration then
            entry.duration = duration
            entry.durationSource = "tooltip_cache"
            return duration
        end
    end
    for _, spellID in ipairs(entry.ids or {}) do
        local duration = baseCooldownDuration(spellID)
        if duration then
            entry.duration = duration
            entry.durationSource = "base_cache"
            return duration
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Live spell/charge reads
--------------------------------------------------------------------------------

local function liveCooldown(spellID)
    spellID = number(spellID)
    if not spellID or spellID <= 0 then return nil end

    local startTime, duration, onGCD
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info, a, b, c = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            startTime = info.startTime
            duration = info.duration
            onGCD = info.isOnGCD
        elseif ok then
            startTime, duration, onGCD = info, a, c
        end
    elseif type(GetSpellCooldown) == "function" then
        local ok, start, length = pcall(GetSpellCooldown, spellID)
        if ok then startTime, duration = start, length end
    end

    startTime = number(startTime)
    duration = normaliseCooldownDuration(duration)
    onGCD = boolean(onGCD)
    if not startTime or not duration or startTime <= 0 or onGCD == true then return nil end
    local remaining = math.max(0, (startTime + duration) - now())
    if remaining <= 0 then return nil end
    return {
        start = startTime,
        duration = duration,
        remaining = remaining,
        source = "spell_api_confirmation",
    }
end

local function publicCooldownState(spellID)
    spellID = number(spellID)
    if not spellID or spellID <= 0 then return nil, nil end
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            return boolean(info.isActive), boolean(info.isOnGCD)
        end
    end
    return nil, nil
end

local function entryLiveCooldown(entry)
    for _, spellID in ipairs(entry and entry.ids or {}) do
        local snapshot = liveCooldown(spellID)
        if snapshot then return snapshot, spellID end
    end
    return nil, nil
end

local function existingAliasKey(ids)
    for _, spellID in ipairs(ids or {}) do
        local key = Tracker.aliases[spellID]
        if key and Tracker.entries[key] then return key end
    end
    return nil
end

local function mergeEntryIDs(entry, ids)
    for _, spellID in ipairs(ids or {}) do
        if not entry.seen[spellID] then
            entry.seen[spellID] = true
            entry.ids[#entry.ids + 1] = spellID
        end
        -- A low-confidence spell-only event must never overwrite a direct
        -- action-slot canonical identity for a transformed/override skill.
        local mapped = Tracker.aliases[spellID]
        if mapped == nil or entry.key:match("^slot:") then
            Tracker.aliases[spellID] = entry.key
        end
    end
end

local function cacheFromApi(entry)
    if inCombat() or not entry then return nil end
    local live = entryLiveCooldown(entry)
    if live then
        entry.duration = live.duration
        entry.durationSource = "spell_api_observed"
    else
        cacheFallbackDuration(entry)
    end

    -- Charge observations use the same canonical entry. A replacement spell and
    -- its base alias cannot therefore render different recharge timers.
    if C_Spell and type(C_Spell.GetSpellCharges) == "function" then
        for _, spellID in ipairs(entry.ids or {}) do
            local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
            if ok and type(info) == "table" then
                local maximum = number(info.maxCharges)
                if maximum and maximum > 1 then
                    local current = number(info.currentCharges) or maximum
                    local recharge = positiveCooldownDuration(info.cooldownDuration) or entry.chargeDuration or 0
                    local start = number(info.cooldownStartTime)
                    entry.maxCharges, entry.chargeDuration = maximum, recharge
                    Tracker.charges[entry.key] = {
                        current = current,
                        max = maximum,
                        duration = recharge,
                        endTime = start and recharge > 0 and start + recharge or 0,
                    }
                    break
                end
            end
        end
    end
    return live
end

function Tracker:RegisterSpell(spellID, meta)
    spellID = number(spellID)
    if not spellID or spellID <= 0 then return nil end

    local ids = normalizeIDs(meta, spellID)
    local key, slot = directIdentity(meta)
    if not key then key = existingAliasKey(ids) end
    if not key then key = "spell:" .. tostring(math.floor(spellID)) end

    local entry = self.entries[key]
    if not entry then
        entry = {
            key = key,
            slot = slot,
            ids = {},
            seen = {},
            confirmationGeneration = 0,
            confirmationPending = false,
            duration = nil,
            durationSource = nil,
        }
        self.entries[key] = entry
    elseif slot then
        entry.slot = slot
    end
    mergeEntryIDs(entry, ids)
    if not inCombat() then cacheFromApi(entry) end
    return entry
end

function Tracker:ResolveIdentity(spellID, meta)
    local directKey, slot = directIdentity(meta)
    if directKey and self.entries[directKey] then return directKey, slot end

    for _, spellIDValue in ipairs(normalizeIDs(meta, spellID)) do
        local alias = self.aliases[spellIDValue]
        if alias and self.entries[alias] then return alias, nil end
    end
    spellID = number(spellID)
    return spellID and ("spell:" .. tostring(math.floor(spellID))) or nil, slot
end

local function advanceCharge(data)
    if not data or not data.duration or data.duration <= 0 then return end
    local time = now()
    while data.current < data.max and data.endTime and data.endTime > 0 and time >= data.endTime do
        data.current = data.current + 1
        data.endTime = data.current < data.max and (data.endTime + data.duration) or 0
    end
end

local function eventMeta(spellID)
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveSpell) ~= "function" then return {} end
    local ok, binding = pcall(resolver.ResolveSpell, resolver, spellID)
    if not ok or type(binding) ~= "table" then return {} end
    return {
        actionSlot = binding.actionSlot or binding.slot,
        directActionSlot = binding.directActionSlot == true,
        actionBarStateTrusted = binding.directActionSlot == true,
        matchedSpellID = binding.matchedSpellID,
        requestedSpellID = binding.requestedSpellID,
        equivalentSpellIDs = binding.equivalentSpellIDs,
    }
end

local function storeCooldown(entry, snapshot, source, isFallback)
    if not entry or type(snapshot) ~= "table" then return false end
    local duration = normaliseCooldownDuration(snapshot.duration)
    local start = number(snapshot.start)
    if not duration or not start or start <= 0 then return false end
    local finish = start + duration
    if finish <= now() then return false end
    entry.duration = duration
    if isFallback ~= true then entry.durationSource = "spell_api_observed" end
    Tracker.cooldowns[entry.key] = {
        start = start,
        duration = duration,
        finish = finish,
        source = source or snapshot.source,
        fallback = isFallback == true,
    }
    return true
end

local function startFallbackCooldown(entry)
    if not entry then return false end
    local duration = normaliseCooldownDuration(entry.duration) or cacheFallbackDuration(entry)
    if not duration then return false end

    local source = entry.durationSource == "spell_api_observed"
        and "local_tracker_observed"
        or "local_tracker_cached"
    return storeCooldown(entry, {
        start = now(),
        duration = duration,
        source = source,
    }, source, true)
end

function Tracker:ConfirmEntry(entry)
    if not entry then return false end
    local snapshot = entryLiveCooldown(entry)
    if snapshot and storeCooldown(entry, snapshot, "spell_api_confirmation", false) then
        return true
    end
    -- A transient ready response must never clear a timer started from an
    -- observed/cached duration. A later confirmation or public ready signal may
    -- correct it; otherwise it expires naturally.
    return false
end

function Tracker:ScheduleConfirmation(entry)
    if not entry then return end
    entry.confirmationGeneration = (entry.confirmationGeneration or 0) + 1
    entry.confirmationPending = true
    local generation = entry.confirmationGeneration
    local remaining = #SPELL_CONFIRMATION_DELAYS
    local function probe()
        if entry.confirmationGeneration ~= generation then return end
        Tracker:ConfirmEntry(entry)
        remaining = remaining - 1
        if remaining <= 0 and entry.confirmationGeneration == generation then
            entry.confirmationPending = false
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        for _, delay in ipairs(SPELL_CONFIRMATION_DELAYS) do
            C_Timer.After(delay, probe)
        end
    else
        probe()
    end
end

function Tracker:RecordCast(spellID)
    spellID = number(spellID)
    if not spellID or spellID <= 0 then return end
    local meta = eventMeta(spellID)
    local entry = self:RegisterSpell(spellID, meta)
    if not entry then return end

    local charge = self.charges[entry.key]
    if charge and charge.max > 1 then
        advanceCharge(charge)
        charge.current = math.max(0, (charge.current or charge.max) - 1)
        if charge.current < charge.max and (not charge.endTime or charge.endTime <= now()) and charge.duration > 0 then
            charge.endTime = now() + charge.duration
        end
        self:ScheduleConfirmation(entry)
        return
    end

    -- Prefer an immediately available authoritative snapshot. When the client
    -- has not committed readable numerics yet, start the event-driven cached
    -- fallback. The renderer still uses a native DurationObject first.
    if not self:ConfirmEntry(entry) then
        startFallbackCooldown(entry)
    end
    self:ScheduleConfirmation(entry)
end

function Tracker:GetCooldown(spellID, meta)
    local key = self:ResolveIdentity(spellID, meta)
    local data = key and self.cooldowns[key] or nil
    if not data then return nil end
    local remaining = math.max(0, data.finish - now())
    if remaining <= 0 then
        self.cooldowns[key] = nil
        return nil
    end
    return {
        known = true,
        remaining = remaining,
        duration = data.duration,
        start = data.start,
        source = data.source or "spell_api_confirmation",
        fallback = data.fallback == true,
        identityKey = key,
        confirmationPending = self.entries[key] and self.entries[key].confirmationPending == true or false,
    }
end

function Tracker:IsConfirmationPending(spellID, meta)
    local key = self:ResolveIdentity(spellID, meta)
    local entry = key and self.entries[key] or nil
    return entry and entry.confirmationPending == true or false
end

function Tracker:GetCharges(spellID, meta)
    local key = self:ResolveIdentity(spellID, meta)
    local data = key and self.charges[key] or nil
    if not data then return nil end
    advanceCharge(data)
    local remaining = data.endTime and data.endTime > 0 and math.max(0, data.endTime - now()) or 0
    return {
        current = data.current,
        maximum = data.max,
        cooldownRemaining = remaining,
        cooldownDuration = data.duration,
        cooldownStart = remaining > 0 and (data.endTime - data.duration) or 0,
        cooldownKnown = data.duration and data.duration > 0,
        source = "local_tracker_charge",
        identityKey = key,
    }
end

function Tracker:ReconcileSpell(spellID)
    spellID = number(spellID)
    if not spellID then return end
    local meta = eventMeta(spellID)
    local key = self:ResolveIdentity(spellID, meta)
    local entry = key and self.entries[key] or nil
    local data = entry and self.cooldowns[key] or nil
    if not data then return end

    -- Public activity flags can only clear a fallback when the spell is not on
    -- the GCD. `isOnGCD=true` is deliberately ignored because it also occurs in
    -- the immediate post-cast window of long-CD, unflagged spells.
    for _, candidateID in ipairs(entry.ids or { spellID }) do
        local active, onGCD = publicCooldownState(candidateID)
        if active == true then return end
        if active == false and onGCD ~= true then
            self.cooldowns[key] = nil
            return
        end
    end
end

function Tracker:RefreshOutOfCombat()
    if inCombat() then return end
    for _, entry in pairs(self.entries) do
        local live = cacheFromApi(entry)
        if live then
            storeCooldown(entry, live, "spell_api_ooc_resync", false)
        else
            self.cooldowns[entry.key] = nil
        end
    end
end

function Tracker:ClearTransient()
    for key in pairs(self.cooldowns) do self.cooldowns[key] = nil end
    for key in pairs(self.charges) do self.charges[key] = nil end
    for _, entry in pairs(self.entries) do entry.confirmationPending = false end
end

function Tracker:InvalidateDurationCache()
    self:ClearTransient()
    for _, entry in pairs(self.entries) do
        entry.duration = nil
        entry.durationSource = nil
        entry.chargeDuration = nil
        entry.maxCharges = nil
    end
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, {
    "UNIT_SPELLCAST_SUCCEEDED",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_DEAD",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
})
watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then Tracker:RecordCast(spellID) end
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        Tracker:ReconcileSpell(select(1, ...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        Tracker:RefreshOutOfCombat()
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
        Tracker:ClearTransient()
        Tracker:RefreshOutOfCombat()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
        Tracker:InvalidateDurationCache()
        Tracker:RefreshOutOfCombat()
    end
end)
