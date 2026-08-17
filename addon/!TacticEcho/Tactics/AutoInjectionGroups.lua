-- Specialization-scoped configuration for the Auto Injection feature.
--
-- This module owns configuration and validation only. It never observes combat,
-- creates BindingTokens, publishes TEAP frames, or advances an execution plan.
-- All groups are reduced to the one existing AutoBurst OrderedPlan shape before
-- they reach the dispatcher.
local TE = _G.TacticEcho

local AutoInjectionGroups = {
    schema = 1,
    MAX_GROUPS = 3,
    MAX_INJECTIONS = 6,
    MAX_SEQUENCE_STEPS = 9,
    lastMigration = nil,
    lastValidation = nil,
}
TE.AutoInjectionGroups = AutoInjectionGroups

local normalizedContainers = setmetatable({}, { __mode = "k" })
local containerRevisions = setmetatable({}, { __mode = "k" })
local validationCache = setmetatable({}, { __mode = "k" })

local function touch(container)
    if type(container) ~= "table" then return end
    containerRevisions[container] = (containerRevisions[container] or 0) + 1
    validationCache[container] = nil
end

local function positiveInteger(value)
    local ok, number = pcall(tonumber, value)
    if not ok or type(number) ~= "number" or number <= 0 then return nil end
    return math.floor(number)
end

local function copyScalarTable(source)
    local out = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        if type(value) ~= "table" then out[key] = value end
    end
    return out
end

local function tactics()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    return TacticEchoDB.tactics
end

local function profileKey(context)
    if not (TE.BurstProfiles and type(TE.BurstProfiles.SpecKey) == "function") then
        return nil
    end
    context = type(context) == "table" and context or {}
    return TE.BurstProfiles:SpecKey(context.classFile or context.class, context.specIndex)
end

local function profileStore(context, create)
    local key = profileKey(context)
    if not key then return nil, nil, "missing_specialization" end
    local all = tactics().burstProfiles
    if create then
        all = type(all) == "table" and all or {}
        tactics().burstProfiles = all
        all[key] = type(all[key]) == "table" and all[key] or {}
    end
    local profile = type(all) == "table" and all[key] or nil
    return profile, key, profile and nil or "missing_profile_store"
end

local function spellKey(spellID)
    spellID = positiveInteger(spellID)
    return spellID and ("injection:" .. tostring(spellID)) or nil
end

local function defaultTrinket(slot)
    return {
        key = "trinket:" .. tostring(slot),
        role = "trinket_" .. tostring(slot),
        category = "trinket",
        kind = "inventory",
        inventorySlot = slot,
        enabled = false,
        fixed = false,
        offGCDExplicit = false,
    }
end

local function normalizeEntry(entry, windowSpellID)
    if type(entry) ~= "table" then return nil end
    local key = tostring(entry.key or "")
    if key == "window" or entry.category == "window" then
        return {
            key = "window", role = "window", category = "window", kind = "spell",
            spellID = windowSpellID, enabled = true, fixed = true,
        }
    end
    local slot = positiveInteger(entry.inventorySlot)
    if key == "trinket:13" or slot == 13 then
        local out = defaultTrinket(13)
        out.enabled = entry.enabled == true
        out.offGCDExplicit = entry.offGCDExplicit == true
        return out
    end
    if key == "trinket:14" or slot == 14 then
        local out = defaultTrinket(14)
        out.enabled = entry.enabled == true
        out.offGCDExplicit = entry.offGCDExplicit == true
        return out
    end
    local spellID = positiveInteger(entry.spellID) or positiveInteger(key:match("^injection:(%d+)$"))
    if not spellID then return nil end
    return {
        key = spellKey(spellID), role = "injection", category = "injection", kind = "spell",
        spellID = spellID, enabled = entry.enabled ~= false, fixed = false,
    }
end

local function normalizeSequence(group)
    local windowSpellID = positiveInteger(group.windowSpellID)
    local source = type(group.sequence) == "table" and group.sequence.entries or nil
    if type(source) ~= "table" then source = group.entries end
    source = type(source) == "table" and source or {}
    local byKey, requestedOrder, injectionCount = {}, {}, 0
    for _, sourceEntry in ipairs(source) do
        local entry = normalizeEntry(sourceEntry, windowSpellID)
        if entry and not byKey[entry.key] then
            if entry.category ~= "injection" or injectionCount < AutoInjectionGroups.MAX_INJECTIONS then
                byKey[entry.key] = entry
                requestedOrder[#requestedOrder + 1] = entry.key
                if entry.category == "injection" then injectionCount = injectionCount + 1 end
            end
        end
    end
    byKey.window = normalizeEntry({ key = "window" }, windowSpellID)
    byKey["trinket:13"] = byKey["trinket:13"] or defaultTrinket(13)
    byKey["trinket:14"] = byKey["trinket:14"] or defaultTrinket(14)

    local entries, seen = {}, {}
    local function append(key)
        if byKey[key] and not seen[key] and #entries < AutoInjectionGroups.MAX_SEQUENCE_STEPS then
            seen[key] = true
            entries[#entries + 1] = byKey[key]
        end
    end
    for _, key in ipairs(requestedOrder) do append(key) end
    append("window")
    for _, sourceEntry in ipairs(source) do
        local entry = normalizeEntry(sourceEntry, windowSpellID)
        if entry and entry.category == "injection" then append(entry.key) end
    end
    append("trinket:13")
    append("trinket:14")
    group.sequence = { schema = 1, entries = entries }
    group.entries = nil
    return entries
end

local function normalizeGroup(group, fallbackId, fallbackName)
    group = type(group) == "table" and group or {}
    group.groupId = tostring(group.groupId or fallbackId)
    if group.groupId == "" then group.groupId = fallbackId end
    group.name = type(group.name) == "string" and group.name ~= "" and group.name or fallbackName
    group.enabled = group.enabled == true
    group.mode = group.mode == "focused" and "focused" or "simple"
    group.windowSpellID = positiveInteger(group.windowSpellID)
    normalizeSequence(group)
    return group
end

local function migrationGroup(context, key)
    if not (TE.BurstProfiles and type(TE.BurstProfiles.GetAutoBurstSequence) == "function") then
        return nil, "burst_sequence_profiles_unavailable"
    end
    local sequence, _, reason, profile = TE.BurstProfiles:GetAutoBurstSequence(context)
    if not sequence then return nil, reason or "burst_sequence_unavailable" end
    local mode = tactics().autoBurstMode == "focused" and "focused" or "simple"
    local entries = {}
    for _, entry in ipairs(sequence.entries or {}) do
        local copied = copyScalarTable(entry)
        entries[#entries + 1] = copied
    end
    local group = normalizeGroup({
        groupId = "group-1",
        name = (profile and profile.specLabel and (profile.specLabel .. "注入")) or "注入组 1",
        enabled = not profile or profile.enabled ~= false,
        mode = mode,
        windowSpellID = sequence.windowSpellID,
        sequence = { schema = 1, entries = entries },
        migratedFromAutoBurst = true,
    }, "group-1", "注入组 1")
    AutoInjectionGroups.lastMigration = {
        schema = 1, profileKey = key, groupId = group.groupId,
        source = "autoBurstSequence", sequenceSignature = sequence.signature,
    }
    return group
end

local function normalizeContainer(container)
    container.schema = 1
    container.groups = type(container.groups) == "table" and container.groups or {}
    local requested = type(container.order) == "table" and container.order or {}
    local ordered, seen = {}, {}
    local function append(id)
        id = tostring(id or "")
        if id ~= "" and not seen[id] and type(container.groups[id]) == "table"
            and #ordered < AutoInjectionGroups.MAX_GROUPS then
            seen[id] = true
            ordered[#ordered + 1] = id
        end
    end
    for _, id in ipairs(requested) do append(id) end
    local remaining = {}
    for id in pairs(container.groups) do remaining[#remaining + 1] = tostring(id) end
    table.sort(remaining)
    for _, id in ipairs(remaining) do append(id) end
    local normalizedGroups, normalizedOrder = {}, {}
    for index, id in ipairs(ordered) do
        local group = normalizeGroup(container.groups[id], id, "注入组 " .. tostring(index))
        if not normalizedGroups[group.groupId] then
            normalizedGroups[group.groupId] = group
            normalizedOrder[#normalizedOrder + 1] = group.groupId
        end
    end
    container.groups = normalizedGroups
    container.order = normalizedOrder
    container.selectedGroupId = tostring(container.selectedGroupId or normalizedOrder[1] or "")
    if not normalizedGroups[container.selectedGroupId] then container.selectedGroupId = normalizedOrder[1] end
    container.nextGroupNumber = math.max(1, positiveInteger(container.nextGroupNumber) or (#normalizedOrder + 1))
    container.migrated = container.migrated == true
    return container
end

function AutoInjectionGroups:Ensure(context)
    local profile, key, reason = profileStore(context, true)
    if not profile then return nil, key, reason end
    local container = type(profile.autoInjectionGroups) == "table" and profile.autoInjectionGroups or {
        schema = 1, order = {}, groups = {}, nextGroupNumber = 1,
    }
    profile.autoInjectionGroups = container
    if normalizedContainers[container] ~= true then normalizeContainer(container) end
    if container.migrated ~= true then
        if #container.order == 0 then
            local group, migrationReason = migrationGroup(context, key)
            if group then
                container.groups[group.groupId] = group
                container.order[1] = group.groupId
                container.selectedGroupId = group.groupId
                container.nextGroupNumber = 2
            else
                container.migrationReason = migrationReason
            end
        end
        container.migrated = true
        touch(container)
    end
    if normalizedContainers[container] ~= true then
        normalizeContainer(container)
        normalizedContainers[container] = true
        touch(container)
    end
    container.profileKey = key
    return container, key, nil
end

function AutoInjectionGroups:Get(context)
    local container, key, reason = self:Ensure(context)
    if not container then return nil, key, reason end
    return container, key, nil
end

function AutoInjectionGroups:GetGroup(context, groupId)
    local container, key, reason = self:Get(context)
    if not container then return nil, key, reason end
    groupId = tostring(groupId or container.selectedGroupId or "")
    return container.groups[groupId], key, nil, container
end

function AutoInjectionGroups:SelectGroup(context, groupId)
    local container = select(1, self:Get(context))
    groupId = tostring(groupId or "")
    if not container or not container.groups[groupId] then return false, "group_not_found" end
    container.selectedGroupId = groupId
    touch(container)
    return true
end

function AutoInjectionGroups:AddGroup(context)
    local container = select(1, self:Get(context))
    if not container then return false, "group_store_unavailable" end
    if #container.order >= self.MAX_GROUPS then return false, "group_limit_reached" end
    local number = container.nextGroupNumber or (#container.order + 1)
    local id
    repeat
        id = "group-" .. tostring(number)
        number = number + 1
    until not container.groups[id]
    local group = normalizeGroup({ groupId = id, name = "注入组 " .. tostring(#container.order + 1) }, id,
        "注入组 " .. tostring(#container.order + 1))
    container.groups[id] = group
    container.order[#container.order + 1] = id
    container.selectedGroupId = id
    container.nextGroupNumber = number
    touch(container)
    return true, id
end

local function enabledOtherGroups(container, currentId)
    local out = {}
    for _, id in ipairs(container.order or {}) do
        local group = container.groups[id]
        if id ~= currentId and group and group.enabled == true then out[#out + 1] = group end
    end
    return out
end

local function groupHasInjection(group, spellID)
    for _, entry in ipairs(group and group.sequence and group.sequence.entries or {}) do
        if entry.category == "injection" and positiveInteger(entry.spellID) == spellID then return true end
    end
    return false
end

local function enabledOptionalCount(group)
    local count = 0
    for _, entry in ipairs(group and group.sequence and group.sequence.entries or {}) do
        if entry.category ~= "window" and entry.enabled == true then count = count + 1 end
    end
    return count
end

local function groupReadinessReason(container, group)
    if type(group) ~= "table" then return "group_not_found" end
    local windowSpellID = positiveInteger(group.windowSpellID)
    if not windowSpellID then return "group_window_missing" end
    if groupHasInjection(group, windowSpellID) then
        return "window_used_as_same_group_injection"
    end
    if enabledOptionalCount(group) <= 0 then return "group_has_no_optional_steps" end
    for _, other in ipairs(enabledOtherGroups(container, group.groupId)) do
        if positiveInteger(other.windowSpellID) == windowSpellID then
            return "duplicate_group_window_spell"
        end
        if groupHasInjection(other, windowSpellID)
            or groupHasInjection(group, positiveInteger(other.windowSpellID)) then
            return "window_used_as_other_group_injection"
        end
    end
    return nil
end

function AutoInjectionGroups:GetGroupReadiness(context, groupId)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    local readinessReason = groupReadinessReason(container, group)
    return readinessReason == nil, readinessReason
end

function AutoInjectionGroups:SetGroupEnabled(context, groupId, enabled)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    if enabled == true then
        local readinessReason = groupReadinessReason(container, group)
        if readinessReason then return false, readinessReason end
    end
    group.enabled = enabled == true
    touch(container)
    return true
end

function AutoInjectionGroups:SetGroupName(context, groupId, name)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then return false, "group_name_missing" end
    group.name = name:sub(1, 40)
    touch(container)
    return true
end

function AutoInjectionGroups:SetGroupMode(context, groupId, mode)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    group.mode = mode == "focused" and "focused" or "simple"
    touch(container)
    return true
end

function AutoInjectionGroups:SetGroupWindow(context, groupId, spellID)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    spellID = positiveInteger(spellID)
    if not spellID then return false, "group_window_missing" end
    if groupHasInjection(group, spellID) then return false, "window_used_as_same_group_injection" end
    for _, other in ipairs(enabledOtherGroups(container, group.groupId)) do
        if positiveInteger(other.windowSpellID) == spellID then return false, "duplicate_group_window_spell" end
        if groupHasInjection(other, spellID) then return false, "window_used_as_other_group_injection" end
    end
    for _, other in ipairs(container.order or {}) do
        local candidate = container.groups[other]
        if candidate and candidate.enabled == true and candidate.groupId ~= group.groupId
            and positiveInteger(candidate.windowSpellID)
            and groupHasInjection(group, positiveInteger(candidate.windowSpellID)) then
            return false, "window_used_as_other_group_injection"
        end
    end
    group.windowSpellID = spellID
    normalizeSequence(group)
    touch(container)
    return true
end

function AutoInjectionGroups:AddInjection(context, groupId, spellID)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    spellID = positiveInteger(spellID)
    if not spellID then return false, "injection_spell_missing" end
    if positiveInteger(group.windowSpellID) == spellID then
        return false, "window_used_as_same_group_injection"
    end
    local count = 0
    for _, entry in ipairs(group.sequence.entries or {}) do
        if entry.category == "injection" then
            count = count + 1
            if positiveInteger(entry.spellID) == spellID then return false, "injection_spell_duplicate" end
        end
    end
    if count >= self.MAX_INJECTIONS then return false, "injection_limit_reached" end
    for _, id in ipairs(container.order or {}) do
        local other = container.groups[id]
        if other and other.enabled == true and positiveInteger(other.windowSpellID) == spellID
            and id ~= group.groupId then
            return false, "window_used_as_other_group_injection"
        end
    end
    local entries = group.sequence.entries
    local insertion = #entries + 1
    for index, entry in ipairs(entries) do
        if entry.category == "trinket" then insertion = index; break end
    end
    table.insert(entries, insertion, normalizeEntry({ spellID = spellID, enabled = true }, group.windowSpellID))
    normalizeSequence(group)
    touch(container)
    return true
end

function AutoInjectionGroups:RemoveInjection(context, groupId, spellID)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    spellID = positiveInteger(spellID)
    for index, entry in ipairs(group.sequence.entries or {}) do
        if entry.category == "injection" and positiveInteger(entry.spellID) == spellID then
            table.remove(group.sequence.entries, index)
            normalizeSequence(group)
            touch(container)
            return true
        end
    end
    return false, "injection_not_found"
end

function AutoInjectionGroups:MoveStep(context, groupId, stepKey, delta)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    delta = tonumber(delta)
    if delta ~= -1 and delta ~= 1 then return false, "invalid_move" end
    local entries, index = group.sequence.entries or {}, nil
    for i, entry in ipairs(entries) do if entry.key == stepKey then index = i; break end end
    if not index then return false, "step_not_in_group_sequence" end
    local target = index + delta
    if target < 1 or target > #entries then return false, "already_at_boundary" end
    entries[index], entries[target] = entries[target], entries[index]
    touch(container)
    return true
end

function AutoInjectionGroups:SetStepEnabled(context, groupId, stepKey, enabled)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    for _, entry in ipairs(group.sequence.entries or {}) do
        if entry.key == stepKey then
            if entry.category == "window" then return false, "window_step_cannot_be_disabled" end
            entry.enabled = enabled == true
            touch(container)
            return true
        end
    end
    return false, "step_not_in_group_sequence"
end

function AutoInjectionGroups:SetTrinketOffGCD(context, groupId, stepKey, enabled)
    local group, _, reason, container = self:GetGroup(context, groupId)
    if not group then return false, reason or "group_not_found" end
    for _, entry in ipairs(group.sequence.entries or {}) do
        if entry.key == stepKey and entry.category == "trinket" then
            entry.offGCDExplicit = enabled == true
            touch(container)
            return true
        end
    end
    return false, "trinket_step_required"
end

function AutoInjectionGroups:Validate(context)
    local container, key, reason = self:Get(context)
    if not container then return nil, key, reason end
    local revision = containerRevisions[container] or 0
    local cached = validationCache[container]
    if cached and cached.revision == revision then
        self.lastValidation = cached.validation
        return cached.validation, key, nil, container
    end
    local validation = { schema = 1, profileKey = key, valid = {}, conflicts = {}, byGroup = {} }
    local claimedWindows = {}
    local enabled = {}
    for _, id in ipairs(container.order or {}) do
        local group = container.groups[id]
        if group and group.enabled == true then enabled[#enabled + 1] = group end
    end
    for _, group in ipairs(enabled) do
        local groupId = group.groupId
        local windowSpellID = positiveInteger(group.windowSpellID)
        local conflict
        if not windowSpellID then
            conflict = "group_window_missing"
        elseif groupHasInjection(group, windowSpellID) then
            conflict = "window_used_as_same_group_injection"
        elseif claimedWindows[windowSpellID] then
            conflict = "duplicate_group_window_spell"
        else
            -- The first group in explicit display order owns this window claim
            -- even if another validation later rejects that group. Corrupt
            -- duplicate data therefore never promotes a later group by chance.
            claimedWindows[windowSpellID] = groupId
            for _, other in ipairs(enabled) do
                if other.groupId ~= groupId and (groupHasInjection(other, windowSpellID)
                    or groupHasInjection(group, positiveInteger(other.windowSpellID))) then
                    conflict = "window_used_as_other_group_injection"
                    break
                end
            end
        end
        local optionalCount = enabledOptionalCount(group)
        if not conflict and optionalCount <= 0 then conflict = "group_has_no_optional_steps" end
        if conflict then
            validation.byGroup[groupId] = conflict
            validation.conflicts[#validation.conflicts + 1] = groupId .. ":" .. conflict
        else
            validation.valid[groupId] = true
        end
    end
    self.lastValidation = validation
    validationCache[container] = { revision = revision, validation = validation }
    return validation, key, nil, container
end

function AutoInjectionGroups:GetRevision(context)
    local container, key, reason = self:Get(context)
    if not container then return nil, nil, key, reason end
    return containerRevisions[container] or 0, container, key, nil
end

function AutoInjectionGroups:BuildRule(context, groupId)
    local validation, key, reason, container = self:Validate(context)
    if not validation then return nil, reason or "group_store_unavailable" end
    groupId = tostring(groupId or "")
    local group = container.groups[groupId]
    if not group then return nil, "group_not_found" end
    if group.enabled ~= true then return nil, "group_disabled" end
    if not validation.valid[groupId] then return nil, validation.byGroup[groupId] or "group_invalid" end
    local steps, keys, optionalCount, firstOptionalSpellID = {}, {}, 0, nil
    for _, entry in ipairs(group.sequence.entries or {}) do
        keys[#keys + 1] = entry.key .. ":" .. (entry.enabled == true and "1" or "0")
            .. ":" .. (entry.offGCDExplicit == true and "g" or "n")
        if entry.enabled == true then
            local step
            if entry.category == "window" then
                step = { key = "window", role = "window", category = "window", kind = "spell",
                    spellID = group.windowSpellID, optional = false }
            elseif entry.category == "trinket" then
                step = { key = entry.key, role = entry.role, category = "trinket", kind = "inventory",
                    inventorySlot = entry.inventorySlot, optional = true,
                    offGCDExplicit = entry.offGCDExplicit == true }
            else
                local spellID = positiveInteger(entry.spellID)
                step = spellID and { key = entry.key, role = "injection", category = "injection",
                    kind = "spell", spellID = spellID, optional = true,
                    specialResourceUnusableCompat = key == "DEMONHUNTER_3" and spellID == 1217605 } or nil
                firstOptionalSpellID = firstOptionalSpellID or spellID
            end
            if step then
                steps[#steps + 1] = step
                if step.optional == true then optionalCount = optionalCount + 1 end
            end
        end
    end
    if optionalCount <= 0 then return nil, "group_has_no_optional_steps" end
    local signature = "window=" .. tostring(group.windowSpellID) .. ";mode=" .. tostring(group.mode)
        .. ";steps=" .. table.concat(keys, ",")
    local firstStep = steps[1]
    local requiresPreWindowCapture = firstStep and firstStep.category ~= "window" or false
    return {
        id = key .. ":" .. groupId .. ":sequence:" .. signature,
        profileKey = key,
        source = "auto_injection_group",
        groupId = groupId,
        groupName = group.name,
        windowSpellID = positiveInteger(group.windowSpellID),
        injectionSpellID = firstOptionalSpellID,
        injectionKind = "sequence",
        steps = steps,
        optionalStepCount = optionalCount,
        requiresPreWindowCapture = requiresPreWindowCapture,
        direction = requiresPreWindowCapture and "pre" or "window_first",
        mode = group.mode,
        sequenceSignature = signature,
        groupSequenceSignature = signature,
        groupSequenceLength = #steps,
        groupSequenceKeys = table.concat(keys, ">"),
    }, nil, group
end

function AutoInjectionGroups:GetDisplayGroup(context, preferredGroupId)
    local container = select(1, self:Get(context))
    if not container then return nil end
    local id = preferredGroupId and tostring(preferredGroupId) or container.selectedGroupId
    return container.groups[id] or container.groups[container.order[1]], container
end
