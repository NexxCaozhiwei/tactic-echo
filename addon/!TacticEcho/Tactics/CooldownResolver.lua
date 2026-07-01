-- Unified, read-only cooldown snapshot resolver for HUD presentation.
--
-- Cooldown identity is intentionally source-specific:
--   spell:<SpellID>      -> C_Spell/GetSpellCooldown
--   inventory:<slot>     -> GetInventoryItemCooldown("player", 13/14)
--   item:<ItemID>        -> C_Item/C_Container/GetItemCooldown
--
-- The resolver normalizes those APIs into one public snapshot shape. It never
-- changes recommendations, bindings, TEAP payloads or TEK input. Raw cooldown
-- values returned as protected/secret values are sanitized inside pcall and are
-- never stored in the HUD model. In that case the snapshot remains readable via
-- public active flags and the native renderer fallback only.
--
-- P5.1 trinket rule:
--   * inventory:13 / inventory:14 are never indefinitely cached;
--   * every tracked trinket is re-probed at a short bounded interval;
--   * a slot reading is cross-checked against the currently equipped ItemID;
--   * player casts and cooldown events trigger a small coalesced confirmation
--     burst (0.01 / 0.05 / 0.15 / 0.35 seconds).
--
-- This is intentionally presentation-only. The fallback ItemID query never
-- creates an action binding, a token, TEAP state or any input request.
local TE = _G.TacticEcho

local INVENTORY_POLL_INTERVAL_SECONDS = 0.10
local INVENTORY_CONFIRMATION_DELAYS = { 0.01, 0.05, 0.15, 0.35 }
-- Spell cooldowns can still report ready for a fraction of a second after a
-- successful cast. These probes are event-driven, not an OnUpdate poll.
local SPELL_CONFIRMATION_DELAYS = { 0.01, 0.05, 0.15, 0.35 }

local Resolver = {
    entries = {},
    lastPotionItemID = nil,
    refreshScheduled = false,
    inventoryConfirmationScheduled = false,
    spellConfirmationScheduled = false,
}
TE.CooldownResolver = Resolver

local function number(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local resolved = tonumber(value)
        if type(resolved) ~= "number" then return nil end
        local probe = resolved + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
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

local function copy(snapshot)
    local out = {}
    for key, value in pairs(snapshot or {}) do out[key] = value end
    return out
end

local function materialize(snapshot)
    local out = copy(snapshot)
    if out.known == true and (out.start or 0) > 0 and (out.duration or 0) > 0 then
        out.remaining = math.max(0, (out.start + out.duration) - now())
        out.active = out.remaining > 0
    elseif out.known == true then
        out.remaining = 0
        out.active = false
    end
    return out
end

local function buildSnapshot(kind, identity, source, startValue, durationValue, enabledValue, activeValue, onGCDValue, extra)
    local startTime = number(startValue)
    local duration = number(durationValue)
    local enabled = boolean(enabledValue)
    local active = boolean(activeValue)
    local onGCD = boolean(onGCDValue)
    local snapshot = {
        schema = 2,
        kind = kind,
        identity = identity,
        source = source,
        known = false,
        remaining = nil,
        start = nil,
        duration = nil,
        enabled = enabled,
        active = active,
        onGCD = onGCD,
        observedAt = now(),
        reason = nil,
    }
    for key, value in pairs(extra or {}) do snapshot[key] = value end

    if startTime == nil and duration == nil then
        snapshot.reason = "冷却 API 未返回可解释数值"
        return snapshot
    end
    if startTime == nil or duration == nil then
        snapshot.reason = "冷却数值受保护，已保留原生显示路径"
        return snapshot
    end

    snapshot.known = true
    if startTime <= 0 or duration <= 0 then
        snapshot.start, snapshot.duration, snapshot.remaining = 0, 0, 0
        if active == nil then snapshot.active = false end
        return snapshot
    end

    snapshot.start, snapshot.duration = startTime, duration
    snapshot.remaining = math.max(0, (startTime + duration) - now())
    if active == nil then snapshot.active = snapshot.remaining > 0 end
    return snapshot
end

local function activeSnapshot(snapshot)
    return type(snapshot) == "table" and snapshot.known == true and snapshot.active == true
end

local function knownSnapshot(snapshot)
    return type(snapshot) == "table" and snapshot.known == true
end

local function spellQuery(spellID)
    local startTime, duration, enabled, active, onGCD
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        -- Retail currently exposes an info table. Accept positional values too
        -- so the resolver remains safe across compatibility clients/shims.
        local ok, info, a, b, c, d = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            startTime = info.startTime
            duration = info.duration
            enabled = info.isEnabled
            active = info.isActive
            onGCD = info.isOnGCD
        elseif ok then
            startTime, duration, enabled, active, onGCD = info, a, b, c, d
        end
    elseif type(GetSpellCooldown) == "function" then
        local ok, a, b, c = pcall(GetSpellCooldown, spellID)
        if ok then startTime, duration, enabled = a, b, c end
    end
    return buildSnapshot("spell", "spell:" .. tostring(spellID), "spell_api", startTime, duration, enabled, active, onGCD, {
        spellID = spellID,
    })
end

local function inventoryItemID(slot)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local ok, itemID = pcall(GetInventoryItemID, "player", slot)
    return ok and number(itemID) or nil
end

local function readItemApiSnapshot(itemID, kind)
    itemID = number(itemID)
    if not itemID or itemID <= 0 then
        return buildSnapshot(kind or "item", "item:unknown", "item_api_unavailable", nil, nil, nil, nil, nil, {
            reason = "物品 ID 无效",
        })
    end
    itemID = math.floor(itemID)

    local candidates = {}
    local function append(source, fn)
        if type(fn) ~= "function" then return end
        local ok, first, second, third, fourth, fifth = pcall(fn, itemID)
        if not ok then return end
        local startTime, duration, enabled, active, onGCD
        if type(first) == "table" then
            startTime = first.startTime or first.start
            duration = first.duration
            enabled = first.isEnabled
            active = first.isActive
            onGCD = first.isOnGCD
        else
            startTime, duration, enabled, active, onGCD = first, second, third, fourth, fifth
        end
        candidates[#candidates + 1] = buildSnapshot(kind or "item", "item:" .. tostring(itemID), source, startTime, duration, enabled, active, onGCD, {
            itemID = itemID,
        })
    end

    -- Retail C_Item is preferred. C_Container and the legacy global API are
    -- compatibility fallbacks; each result is sanitized before comparison.
    if C_Item and type(C_Item.GetItemCooldown) == "function" then
        append("item_cooldown", C_Item.GetItemCooldown)
    end
    if C_Container and type(C_Container.GetItemCooldown) == "function" then
        append("container_item_cooldown", C_Container.GetItemCooldown)
    end
    if type(GetItemCooldown) == "function" then
        append("legacy_item_cooldown", GetItemCooldown)
    end

    local firstUnknown, firstKnown
    for _, snapshot in ipairs(candidates) do
        firstUnknown = firstUnknown or snapshot
        if activeSnapshot(snapshot) then return snapshot end
        if knownSnapshot(snapshot) and firstKnown == nil then firstKnown = snapshot end
    end
    return firstKnown or firstUnknown or buildSnapshot(kind or "item", "item:" .. tostring(itemID), "item_api_unavailable", nil, nil, nil, nil, nil, {
        itemID = itemID,
        reason = "当前客户端没有可用物品冷却 API",
    })
end

local function remapInventorySnapshot(snapshot, slot, itemID, source, slotSnapshot)
    local out = copy(snapshot)
    out.schema = 2
    out.kind = "inventory"
    out.identity = "inventory:" .. tostring(slot)
    out.source = source
    out.inventorySlot = slot
    out.itemID = itemID
    out.slotSource = slotSnapshot and slotSnapshot.source or nil
    out.slotKnown = slotSnapshot and slotSnapshot.known == true or false
    out.slotActive = slotSnapshot and slotSnapshot.active == true or false
    return out
end

local function inventoryQuery(slot, expectedItemID)
    local currentItemID = inventoryItemID(slot) or number(expectedItemID)
    local startTime, duration, enabled
    if type(GetInventoryItemCooldown) == "function" then
        local ok, a, b, c = pcall(GetInventoryItemCooldown, "player", slot)
        if ok then startTime, duration, enabled = a, b, c end
    end

    local slotSnapshot = buildSnapshot("inventory", "inventory:" .. tostring(slot), "inventory_item_cooldown", startTime, duration, enabled, nil, nil, {
        inventorySlot = slot,
        itemID = currentItemID,
    })
    local itemSnapshot = currentItemID and readItemApiSnapshot(currentItemID, "inventory") or nil

    -- The equipped-slot API is authoritative when it reports an active CD.
    -- Some client/event timing paths temporarily expose 0/0 immediately after
    -- use; cross-checking the equipped ItemID prevents that transient ready
    -- sample from hiding the trinket countdown.
    if activeSnapshot(slotSnapshot) then
        slotSnapshot.itemFallbackKnown = itemSnapshot and itemSnapshot.known == true or false
        slotSnapshot.itemFallbackActive = itemSnapshot and itemSnapshot.active == true or false
        return slotSnapshot
    end
    if activeSnapshot(itemSnapshot) then
        return remapInventorySnapshot(itemSnapshot, slot, currentItemID, "inventory_item_fallback", slotSnapshot)
    end
    if knownSnapshot(slotSnapshot) then
        slotSnapshot.itemFallbackKnown = itemSnapshot and itemSnapshot.known == true or false
        slotSnapshot.itemFallbackActive = itemSnapshot and itemSnapshot.active == true or false
        return slotSnapshot
    end
    if knownSnapshot(itemSnapshot) then
        return remapInventorySnapshot(itemSnapshot, slot, currentItemID, "inventory_item_fallback", slotSnapshot)
    end

    local unknown = copy(slotSnapshot)
    if itemSnapshot and itemSnapshot.reason then
        unknown.reason = (unknown.reason or "装备槽位冷却读取失败") .. "；物品 ID 回退：" .. tostring(itemSnapshot.reason)
    end
    unknown.itemFallbackKnown = false
    unknown.itemFallbackActive = false
    return unknown
end

local function itemQuery(itemID, kind)
    return readItemApiSnapshot(itemID, kind or "item")
end

local function entryFor(self, identity, kind, query, options)
    options = type(options) == "table" and options or {}
    local entry = self.entries[identity]
    if not entry then
        entry = {
            identity = identity,
            kind = kind,
            query = query,
            dirty = true,
            snapshot = nil,
            pollInterval = number(options.pollInterval),
            nextProbeAt = 0,
        }
        self.entries[identity] = entry
    else
        entry.kind = kind or entry.kind
        entry.query = query or entry.query
        if options.pollInterval ~= nil then entry.pollInterval = number(options.pollInterval) end
    end
    return entry
end

local function readEntry(entry)
    if not entry then return nil end
    local observedAt = now()
    local pollingDue = entry.pollInterval and entry.pollInterval > 0 and observedAt >= (entry.nextProbeAt or 0)
    if entry.dirty == true or type(entry.snapshot) ~= "table" or pollingDue then
        local ok, snapshot = pcall(entry.query)
        if ok and type(snapshot) == "table" then
            entry.snapshot = snapshot
            entry.dirty = false
        else
            entry.snapshot = {
                schema = 2,
                kind = entry.kind,
                identity = entry.identity,
                source = "resolver_error",
                known = false,
                reason = "冷却快照读取失败",
            }
            entry.dirty = false
        end
        entry.lastReadAt = observedAt
        entry.nextProbeAt = entry.pollInterval and entry.pollInterval > 0 and (observedAt + entry.pollInterval) or nil
    end
    return materialize(entry.snapshot)
end

function Resolver:GetSpell(spellID)
    spellID = number(spellID)
    if not spellID or spellID <= 0 then return nil end
    local identity = "spell:" .. tostring(spellID)
    return readEntry(entryFor(self, identity, "spell", function() return spellQuery(spellID) end))
end

function Resolver:GetInventory(slot, expectedItemID)
    slot = number(slot)
    if not slot or slot <= 0 then return nil end
    slot = math.floor(slot)
    local identity = "inventory:" .. tostring(slot)
    return readEntry(entryFor(self, identity, "inventory", function() return inventoryQuery(slot, expectedItemID) end, {
        -- Only two equipped trinket identities use this bounded live probe. It
        -- is a safety net for delayed/missing cooldown events, not a global
        -- OnUpdate poll over every spell or inventory item.
        pollInterval = INVENTORY_POLL_INTERVAL_SECONDS,
    }))
end

function Resolver:GetItem(itemID, kind)
    itemID = number(itemID)
    if not itemID or itemID <= 0 then return nil end
    itemID = math.floor(itemID)
    local identity = "item:" .. tostring(itemID)
    return readEntry(entryFor(self, identity, kind or "item", function() return itemQuery(itemID, kind or "item") end))
end

function Resolver:GetPotion(itemID)
    itemID = number(itemID) or self.lastPotionItemID
    if not itemID or itemID <= 0 then return nil end
    self.lastPotionItemID = math.floor(itemID)
    return self:GetItem(self.lastPotionItemID, "potion")
end

function Resolver:MarkDirty(identity)
    local entry = identity and self.entries[identity] or nil
    if entry then entry.dirty = true end
end

function Resolver:MarkAllDirty(kind)
    for _, entry in pairs(self.entries) do
        if kind == nil or entry.kind == kind then entry.dirty = true end
    end
end

function Resolver:RefreshDirty()
    self.refreshScheduled = false
    for _, entry in pairs(self.entries) do
        if entry.dirty == true then readEntry(entry) end
    end
end

function Resolver:ScheduleRefresh(delay)
    if self.refreshScheduled == true then return end
    self.refreshScheduled = true
    delay = number(delay) or 0.01
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function()
            if TE.CooldownResolver then TE.CooldownResolver:RefreshDirty() end
        end)
    else
        self:RefreshDirty()
    end
end

function Resolver:ScheduleInventoryConfirmation()
    if self.inventoryConfirmationScheduled == true then return end
    local hasInventoryEntry = false
    for _, entry in pairs(self.entries) do
        if entry.kind == "inventory" then hasInventoryEntry = true; break end
    end
    if not hasInventoryEntry then return end

    self.inventoryConfirmationScheduled = true
    local remaining = #INVENTORY_CONFIRMATION_DELAYS
    local function probe()
        local current = TE.CooldownResolver
        if current then
            current:MarkAllDirty("inventory")
            current:RefreshDirty()
        end
        remaining = remaining - 1
        if remaining <= 0 and current then current.inventoryConfirmationScheduled = false end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        for _, delay in ipairs(INVENTORY_CONFIRMATION_DELAYS) do C_Timer.After(delay, probe) end
    else
        for _ = 1, #INVENTORY_CONFIRMATION_DELAYS do probe() end
    end
end

-- P5.2 spell confirmation mirrors the trinket confirmation burst. A cast
-- event may precede C_Spell's final cooldown snapshot, so a single 0.01s read
-- must not permanently cache a false ready result.
function Resolver:ScheduleSpellConfirmation()
    if self.spellConfirmationScheduled == true then return end
    local hasSpellEntry = false
    for _, entry in pairs(self.entries) do
        if entry.kind == "spell" then hasSpellEntry = true; break end
    end
    if not hasSpellEntry then return end

    self.spellConfirmationScheduled = true
    local remaining = #SPELL_CONFIRMATION_DELAYS
    local function probe()
        local current = TE.CooldownResolver
        if current then
            current:MarkAllDirty("spell")
            current:RefreshDirty()
        end
        remaining = remaining - 1
        if remaining <= 0 and current then current.spellConfirmationScheduled = false end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        for _, delay in ipairs(SPELL_CONFIRMATION_DELAYS) do C_Timer.After(delay, probe) end
    else
        for _ = 1, #SPELL_CONFIRMATION_DELAYS do probe() end
    end
end

function Resolver:GetDurationObject(item)
    -- This helper remains inside the addon presentation boundary. It does not
    -- return or persist a raw object into the HUD model. Current clients expose
    -- action-bar DurationObjects reliably; item-specific DurationObject APIs are
    -- used only when the client explicitly provides them.
    item = type(item) == "table" and item or {}
    local itemID = number(item.itemID)
    local actionSlot = number(item.actionSlot or item.slot)
    local actionSlotTrusted = actionSlot and (itemID or item.directActionSlot == true or item.actionBarStateTrusted == true)
    if actionSlotTrusted and C_ActionBar and type(C_ActionBar.GetActionCooldownDuration) == "function" then
        local ok, duration = pcall(C_ActionBar.GetActionCooldownDuration, actionSlot)
        if ok and duration ~= nil then return duration, "actionbar_duration" end
    end
    if itemID and C_Item and type(C_Item.GetItemCooldownDuration) == "function" then
        local ok, duration = pcall(C_Item.GetItemCooldownDuration, itemID)
        if ok and duration ~= nil then return duration, "item_duration" end
    end
    return nil, nil
end

local watcher = CreateFrame("Frame")
-- Current retail clients do not expose an item-specific cooldown event.
-- BAG_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_COOLDOWN and player cast success cover
-- item/potion/trinket transitions; the bounded inventory re-probe remains the
-- final presentation-only convergence path.
TE:RegisterEventsSafe(watcher, {
    "PLAYER_EQUIPMENT_CHANGED",
    "BAG_UPDATE_COOLDOWN",
    "BAG_UPDATE_DELAYED",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "ACTIONBAR_UPDATE_COOLDOWN",
    "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_TALENT_UPDATE",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
    "PLAYER_ENTERING_WORLD",
})
watcher:SetScript("OnEvent", function(_, event, ...)
    local shouldConfirmInventory = false
    local shouldConfirmSpell = false
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = number(select(1, ...))
        if slot == 13 or slot == 14 then
            Resolver:MarkDirty("inventory:" .. tostring(slot))
            shouldConfirmInventory = true
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        -- This event is broadly available on current clients and is a useful
        -- fallback where item-specific cooldown notifications are delayed.
        Resolver:MarkAllDirty("item")
        Resolver:MarkAllDirty("potion")
        Resolver:MarkAllDirty("inventory")
        shouldConfirmInventory = true
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Bag changes affect count/potion availability, and may introduce a
        -- newly configured potion item. The category cooldown identity remains
        -- the ItemID and is therefore not tied to a particular stack.
        Resolver:MarkAllDirty("potion")
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        Resolver:MarkAllDirty("spell")
        shouldConfirmSpell = true
        -- Trinket use can cause only generic spell/action cooldown signals on
        -- some clients. Keep the two equipped slots synchronized as well.
        Resolver:MarkAllDirty("inventory")
        shouldConfirmInventory = true
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
        Resolver:MarkAllDirty("spell")
        shouldConfirmSpell = true
        Resolver:MarkAllDirty("inventory")
        Resolver:MarkAllDirty("item")
        Resolver:MarkAllDirty("potion")
        shouldConfirmInventory = true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Retail and compatibility clients provide (unit, castGUID, spellID).
        -- Keep an exact identity dirty when possible, then refresh all already
        -- tracked spell aliases so base/override cards converge on one result.
        if select(1, ...) == "player" then
            local spellID = number(select(3, ...))
            if spellID then Resolver:MarkDirty("spell:" .. tostring(math.floor(spellID))) end
            Resolver:MarkAllDirty("spell")
            Resolver:MarkAllDirty("inventory")
            shouldConfirmSpell = true
            shouldConfirmInventory = true
        end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "SPELLS_CHANGED" then
        Resolver:MarkAllDirty("spell")
        shouldConfirmSpell = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        Resolver:MarkAllDirty()
        shouldConfirmSpell = true
        shouldConfirmInventory = true
    end
    Resolver:ScheduleRefresh()
    if shouldConfirmSpell then Resolver:ScheduleSpellConfirmation() end
    if shouldConfirmInventory then Resolver:ScheduleInventoryConfirmation() end
end)
