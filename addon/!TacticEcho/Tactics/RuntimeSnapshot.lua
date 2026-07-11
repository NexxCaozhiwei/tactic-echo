-- One read-only business-cycle snapshot shared by SignalFrame, AutoBurst and HUD.
-- It owns per-cycle binding/GCD/cooldown memoization. No method creates input,
-- changes TEAP fields, or relaxes macro identity rules.
local TE = _G.TacticEcho

local RuntimeSnapshot = {
    nextCycleId = 1,
    latest = nil,
}
TE.RuntimeSnapshot = RuntimeSnapshot

local EMPTY = {}

local function number(value)
    local resolved = tonumber(value)
    if type(resolved) ~= "number" then return nil end
    if resolved < -math.huge or resolved > math.huge then return nil end
    return resolved + 0
end

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

local function guarded(key, fn, ...)
    local perf = TE.PerformanceDiagnostics
    if perf and type(perf.Guard) == "function" then return perf:Guard(key, fn, ...) end
    return pcall(fn, ...)
end

local function bindingOptions(binding, extra)
    binding = type(binding) == "table" and binding or EMPTY
    extra = type(extra) == "table" and extra or EMPTY
    return {
        gcdSnapshot = extra.gcdSnapshot,
        liveCooldown = extra.liveCooldown == true,
        actionSlot = binding.actionSlot or binding.slot,
        directActionSlot = binding.directActionSlot == true,
        actionBarStateTrusted = binding.actionBarStateTrusted == true,
        exactActionCooldownVeto = extra.exactActionCooldownVeto == true,
        matchedSpellID = binding.matchedSpellID,
        requestedSpellID = binding.requestedSpellID,
        equivalentSpellIDs = binding.equivalentSpellIDs,
        castSnapshot = extra.castSnapshot,
        requiresHostileTarget = extra.requiresHostileTarget == true,
    }
end

local function spellCacheKey(spellID)
    spellID = number(spellID)
    return spellID and math.floor(spellID) or nil
end

local function inventoryCacheKey(slot, itemID)
    slot, itemID = number(slot), number(itemID)
    if not slot then return nil end
    return tostring(math.floor(slot)) .. ":" .. tostring(itemID and math.floor(itemID) or 0)
end

function RuntimeSnapshot:Begin(reason, input)
    input = type(input) == "table" and input or EMPTY
    local timer = perfBegin("RuntimeSnapshot.Begin")
    local cycleId = self.nextCycleId
    self.nextCycleId = cycleId + 1

    local gcdCycle
    if TE.GCDGate and type(TE.GCDGate.BeginCycle) == "function" then
        local ok, value = guarded("GCDGate.BeginCycle", TE.GCDGate.BeginCycle, TE.GCDGate, input.official)
        if ok and type(value) == "table" then gcdCycle = value end
    end
    gcdCycle = gcdCycle or { schema = 1, phase = "UNKNOWN", reason = "gcd_cycle_unavailable" }

    local snapshot = {
        schema = 1,
        cycleId = cycleId,
        reason = reason or "business",
        observedAt = type(GetTime) == "function" and GetTime() or 0,
        context = input.context or EMPTY,
        official = input.official,
        officialSpellID = input.official and number(input.official.spellID) or nil,
        inCombat = input.inCombat == true,
        intentState = input.intentState,
        effectiveState = input.effectiveState,
        runtimeReason = input.runtimeReason,
        inputFocusActive = input.inputFocusActive == true,
        inputFocusReason = input.inputFocusReason,
        manualPriority = input.manualPriority,
        castLock = input.castLock,
        castDisplay = input.castDisplay,
        resolveContext = input.resolveContext,
        gcdCycle = gcdCycle,
        gcdSnapshot = gcdCycle.gcdSnapshot,
        castSnapshot = gcdCycle.castSnapshot,
        bindings = { spell = {}, inventory = {}, inventoryBySlot = {}, item = {} },
        cooldowns = { spell = {}, inventory = {}, inventoryBySlot = {}, item = {}, fullSpell = {} },
        facts = {
            knownSpell = {},
            spellInfo = {},
            itemInfo = {},
            inventoryItem = {},
            itemCount = {},
            actionUsability = {},
        },
        autoBurstDecision = nil,
        autoBurst = nil,
        message = nil,
        sealed = false,
    }
    perfCount("runtime_snapshot_build")
    perfFinish(timer)
    return snapshot
end


function RuntimeSnapshot:IsSpellKnown(snapshot, spellID)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(spellID)
    if not key then return false, "spell_id_invalid" end
    local cached = snapshot.facts.knownSpell[key]
    if cached then return cached.value, cached.source end

    local probes = {
        { name = "C_Spell.IsSpellKnown", fn = C_Spell and C_Spell.IsSpellKnown },
        { name = "IsPlayerSpell", fn = IsPlayerSpell },
        { name = "IsSpellKnown", fn = IsSpellKnown },
    }
    local value, source
    for _, probe in ipairs(probes) do
        if type(probe.fn) == "function" then
            perfCount("spell_known_read")
            local ok, result = guarded("SpellKnown:" .. probe.name .. ":" .. tostring(key), probe.fn, key)
            if ok and type(result) == "boolean" then
                value, source = result, probe.name
                break
            end
        end
    end
    snapshot.facts.knownSpell[key] = { value = value, source = source or "spell_known_unavailable" }
    return value, source or "spell_known_unavailable"
end

function RuntimeSnapshot:GetSpellInfo(snapshot, spellID)
    if type(snapshot) ~= "table" then return nil, nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(spellID)
    if not key then return nil, nil, "spell_id_invalid" end
    local cached = snapshot.facts.spellInfo[key]
    if cached then return cached.name, cached.icon, cached.source end

    local name, icon, source
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        perfCount("spell_info_read")
        local ok, info = guarded("SpellInfo:C_Spell:" .. tostring(key), C_Spell.GetSpellInfo, key)
        if ok and type(info) == "table" then
            name, icon, source = info.name, info.iconID or info.icon, "C_Spell.GetSpellInfo"
        end
    end
    if not name and type(GetSpellInfo) == "function" then
        perfCount("spell_info_read")
        local ok, legacyName, _, legacyIcon = guarded("SpellInfo:legacy:" .. tostring(key), GetSpellInfo, key)
        if ok then name, icon, source = legacyName, legacyIcon, "GetSpellInfo" end
    end
    snapshot.facts.spellInfo[key] = { name = name, icon = icon, source = source or "spell_info_unavailable" }
    return name, icon, source or "spell_info_unavailable"
end

function RuntimeSnapshot:GetItemInfo(snapshot, itemID)
    if type(snapshot) ~= "table" then return nil, nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(itemID)
    if not key then return nil, nil, "item_id_invalid" end
    local cached = snapshot.facts.itemInfo[key]
    if cached then return cached.name, cached.icon, cached.source end

    local name, icon, source
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        perfCount("item_info_read")
        local ok, value = guarded("ItemIcon:" .. tostring(key), C_Item.GetItemIconByID, key)
        if ok then icon = value; source = "C_Item.GetItemIconByID" end
    end
    if type(GetItemInfo) == "function" then
        perfCount("item_info_read")
        local ok, itemName, _, _, _, _, _, _, _, texture = guarded("ItemInfo:" .. tostring(key), GetItemInfo, key)
        if ok then name, icon, source = itemName, icon or texture, "GetItemInfo" end
    end
    snapshot.facts.itemInfo[key] = { name = name, icon = icon, source = source or "item_info_unavailable" }
    return name, icon, source or "item_info_unavailable"
end

function RuntimeSnapshot:GetInventoryItemID(snapshot, slot)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    slot = number(slot)
    if not slot then return nil, "inventory_slot_invalid" end
    slot = math.floor(slot)
    local cached = snapshot.facts.inventoryItem[slot]
    if cached then return cached.value, cached.reason end
    local value, reason
    if type(GetInventoryItemID) == "function" then
        perfCount("inventory_item_read")
        local ok, result = guarded("InventoryItemID:" .. tostring(slot), GetInventoryItemID, "player", slot)
        if ok then value = spellCacheKey(result) else reason = "inventory_item_read_failed:" .. tostring(result) end
    else
        reason = "inventory_item_api_unavailable"
    end
    snapshot.facts.inventoryItem[slot] = { value = value, reason = reason }
    return value, reason
end

function RuntimeSnapshot:GetItemCount(snapshot, itemID)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(itemID)
    if not key then return nil, "item_id_invalid" end
    local cached = snapshot.facts.itemCount[key]
    if cached then return cached.value, cached.reason end
    local value, reason
    if type(GetItemCount) == "function" then
        perfCount("item_count_read")
        local ok, result = guarded("ItemCount:" .. tostring(key), GetItemCount, key)
        if ok then value = number(result) else reason = "item_count_read_failed:" .. tostring(result) end
    else
        reason = "item_count_api_unavailable"
    end
    snapshot.facts.itemCount[key] = { value = value, reason = reason }
    return value, reason
end


function RuntimeSnapshot:GetActionUsability(snapshot, actionSlot)
    if type(snapshot) ~= "table" then return nil, nil, "runtime_snapshot_missing" end
    actionSlot = number(actionSlot)
    if not actionSlot or actionSlot <= 0 then return nil, nil, "action_slot_invalid" end
    actionSlot = math.floor(actionSlot)
    local cached = snapshot.facts.actionUsability[actionSlot]
    if cached then return cached.usable, cached.notEnough, cached.reason end
    local usable, notEnough, reason
    if C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" then
        perfCount("action_usability_read")
        local ok, value, resource = guarded("ActionUsability:" .. tostring(actionSlot), C_ActionBar.IsUsableAction, actionSlot)
        if ok then
            usable = value == true and true or value == false and false or nil
            notEnough = resource == true and true or resource == false and false or nil
        else
            reason = "action_usability_read_failed:" .. tostring(value)
        end
    else
        reason = "action_usability_api_unavailable"
    end
    snapshot.facts.actionUsability[actionSlot] = { usable = usable, notEnough = notEnough, reason = reason }
    return usable, notEnough, reason
end

function RuntimeSnapshot:ResolveSpell(snapshot, spellID)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(spellID)
    if not key then return nil, "spell_id_invalid" end
    local cached = snapshot.bindings.spell[key]
    if cached then return cached.value, cached.reason end
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveSpell) ~= "function" then return nil, "binding_resolver_unavailable" end
    perfCount("resolve_spell")
    local timer = perfBegin("ActionBarBindingResolver.ResolveSpell")
    local ok, value, reason = guarded("ResolveSpell:" .. tostring(key), resolver.ResolveSpell, resolver, key, snapshot.resolveContext)
    perfFinish(timer)
    if not ok then reason, value = "binding_resolver_failed:" .. tostring(value), nil end
    snapshot.bindings.spell[key] = { value = value, reason = reason }
    return value, reason
end

function RuntimeSnapshot:ResolveInventory(snapshot, slot, expectedItemID)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = inventoryCacheKey(slot, expectedItemID)
    if not key then return nil, "inventory_slot_invalid" end
    local slotKey = math.floor(number(slot) or 0)
    local cached = snapshot.bindings.inventory[key]
    if cached then return cached.value, cached.reason end
    local bySlot = snapshot.bindings.inventoryBySlot[slotKey]
    if bySlot then
        local currentItemID = number(bySlot.value and (bySlot.value.itemID or bySlot.value.expectedItemID))
        local expected = number(expectedItemID)
        if not expected or not currentItemID or math.floor(currentItemID) == math.floor(expected) then
            snapshot.bindings.inventory[key] = bySlot
            return bySlot.value, bySlot.reason
        end
    end
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveInventorySlot) ~= "function" then return nil, "inventory_binding_resolver_unavailable" end
    perfCount("resolve_inventory")
    local timer = perfBegin("ActionBarBindingResolver.ResolveInventorySlot")
    local ok, value, reason = guarded("ResolveInventory:" .. key, resolver.ResolveInventorySlot, resolver, slot, expectedItemID, snapshot.resolveContext)
    perfFinish(timer)
    if not ok then reason, value = "inventory_binding_resolver_failed:" .. tostring(value), nil end
    local entry = { value = value, reason = reason }
    snapshot.bindings.inventory[key] = entry
    snapshot.bindings.inventoryBySlot[slotKey] = entry
    return value, reason
end

function RuntimeSnapshot:ResolveItem(snapshot, itemID)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(itemID)
    if not key then return nil, "item_id_invalid" end
    local cached = snapshot.bindings.item[key]
    if cached then return cached.value, cached.reason end
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveItem) ~= "function" then return nil, "item_binding_resolver_unavailable" end
    perfCount("resolve_item")
    local ok, value, reason = guarded("ResolveItem:" .. tostring(key), resolver.ResolveItem, resolver, key, snapshot.resolveContext)
    if not ok then reason, value = "item_binding_resolver_failed:" .. tostring(value), nil end
    snapshot.bindings.item[key] = { value = value, reason = reason }
    return value, reason
end

function RuntimeSnapshot:CollectSpellCooldown(snapshot, spellID, binding, extra)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(spellID)
    if not key then return nil, "spell_id_invalid" end
    local cached = snapshot.cooldowns.spell[key]
    if cached then return cached.value, cached.reason end
    if not TE.IconState or type(TE.IconState.CollectCooldownOnly) ~= "function" then
        return nil, "cooldown_only_sampler_unavailable"
    end
    local options = bindingOptions(binding, extra)
    options.gcdSnapshot = snapshot.gcdSnapshot
    perfCount("cooldown_sample_spell")
    local timer = perfBegin("IconState.CollectCooldownOnly")
    local ok, value = guarded("CollectSpellCooldown:" .. tostring(key), TE.IconState.CollectCooldownOnly, TE.IconState, key, options)
    perfFinish(timer)
    local reason
    if not ok then reason, value = "cooldown_only_state_failed:" .. tostring(value), nil
    elseif type(value) ~= "table" then reason, value = "cooldown_only_state_invalid", nil end
    snapshot.cooldowns.spell[key] = { value = value, reason = reason }
    return value, reason
end

function RuntimeSnapshot:CollectInventoryCooldown(snapshot, slot, expectedItemID, binding, extra)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local requestedItemID = expectedItemID or (binding and binding.itemID)
    local key = inventoryCacheKey(slot, requestedItemID)
    if not key then return nil, "inventory_slot_invalid" end
    local slotKey = math.floor(number(slot) or 0)
    local cached = snapshot.cooldowns.inventory[key]
    if cached then return cached.value, cached.reason end
    local bySlot = snapshot.cooldowns.inventoryBySlot[slotKey]
    if bySlot then
        local currentItemID = number(bySlot.value and (bySlot.value.itemID or bySlot.value.expectedItemID))
        local expected = number(requestedItemID)
        if not expected or not currentItemID or math.floor(currentItemID) == math.floor(expected) then
            snapshot.cooldowns.inventory[key] = bySlot
            return bySlot.value, bySlot.reason
        end
    end
    if not TE.IconState or type(TE.IconState.CollectInventoryCooldownOnly) ~= "function" then
        return nil, "inventory_cooldown_sampler_unavailable"
    end
    local options = bindingOptions(binding, extra)
    options.gcdSnapshot = snapshot.gcdSnapshot
    perfCount("cooldown_sample_inventory")
    local timer = perfBegin("IconState.CollectInventoryCooldownOnly")
    local ok, value = guarded("CollectInventoryCooldown:" .. key, TE.IconState.CollectInventoryCooldownOnly,
        TE.IconState, slot, expectedItemID or (binding and binding.itemID), options)
    perfFinish(timer)
    local reason
    if not ok then reason, value = "inventory_cooldown_state_failed:" .. tostring(value), nil
    elseif type(value) ~= "table" then reason, value = "inventory_cooldown_state_invalid", nil end
    local entry = { value = value, reason = reason }
    snapshot.cooldowns.inventory[key] = entry
    snapshot.cooldowns.inventoryBySlot[slotKey] = entry
    return value, reason
end


function RuntimeSnapshot:CollectItemCooldown(snapshot, itemID, kind)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(itemID)
    if not key then return nil, "item_id_invalid" end
    kind = tostring(kind or "item")
    local cacheKey = kind .. ":" .. tostring(key)
    local cached = snapshot.cooldowns.item[cacheKey]
    if cached then return cached.value, cached.reason end
    local resolver = TE.CooldownResolver
    if not resolver then return nil, "item_cooldown_resolver_unavailable" end
    local fn = kind == "potion" and resolver.GetPotion or resolver.GetItem
    if type(fn) ~= "function" then return nil, "item_cooldown_sampler_unavailable" end
    perfCount("cooldown_sample_item")
    local timer = perfBegin("CooldownResolver.GetItem")
    local ok, value
    if kind == "potion" then
        ok, value = guarded("CollectItemCooldown:potion:" .. tostring(key), fn, resolver, key)
    else
        ok, value = guarded("CollectItemCooldown:" .. cacheKey, fn, resolver, key, kind)
    end
    perfFinish(timer)
    local reason
    if not ok then reason, value = "item_cooldown_state_failed:" .. tostring(value), nil
    elseif type(value) ~= "table" then reason, value = "item_cooldown_state_invalid", nil end
    snapshot.cooldowns.item[cacheKey] = { value = value, reason = reason }
    return value, reason
end

function RuntimeSnapshot:CollectSpellState(snapshot, spellID, binding, extra)
    if type(snapshot) ~= "table" then return nil, "runtime_snapshot_missing" end
    local key = spellCacheKey(spellID)
    if not key then return nil, "spell_id_invalid" end
    local hostile = type(extra) == "table" and extra.requiresHostileTarget == true or false
    local cacheKey = tostring(key) .. ":" .. (hostile and "hostile" or "neutral")
    local cached = snapshot.cooldowns.fullSpell[cacheKey]
    if cached then return cached.value, cached.reason end
    if not TE.IconState or type(TE.IconState.Collect) ~= "function" then return nil, "icon_state_unavailable" end
    local options = bindingOptions(binding, extra)
    options.gcdSnapshot = snapshot.gcdSnapshot
    options.castSnapshot = snapshot.castSnapshot
    -- Reuse AutoBurst's exact cooldown/charge/actionbar sample when available.
    local cooldown = snapshot.cooldowns.spell[key]
    if cooldown and type(cooldown.value) == "table" then options.cooldownSnapshot = cooldown.value end
    perfCount("icon_state_collect")
    local timer = perfBegin("IconState.Collect")
    local ok, value = guarded("CollectSpellState:" .. cacheKey, TE.IconState.Collect, TE.IconState, key, options)
    perfFinish(timer)
    local reason
    if not ok then reason, value = "icon_state_failed:" .. tostring(value), nil
    elseif type(value) ~= "table" then reason, value = "icon_state_invalid", nil end
    snapshot.cooldowns.fullSpell[cacheKey] = { value = value, reason = reason }
    return value, reason
end

function RuntimeSnapshot:SetAutoBurst(snapshot, decision, stateSnapshot)
    if type(snapshot) ~= "table" then return end
    snapshot.autoBurstDecision = decision
    snapshot.autoBurst = stateSnapshot
end

function RuntimeSnapshot:Seal(snapshot, message)
    if type(snapshot) ~= "table" then return nil end
    snapshot.message = message
    snapshot.businessRevision = message and message._businessRevision or snapshot.businessRevision
    snapshot.sealed = true
    self.latest = snapshot
    return snapshot
end

function RuntimeSnapshot:GetLatest()
    return self.latest
end

function RuntimeSnapshot:Clear()
    self.latest = nil
end
