-- Built-in read-only tactical spell profiles.
--
-- Safety boundary:
-- * Profiles are lookup data only.
-- * A profile never creates a binding, BindingToken, TEAP message, or input request.
-- * A tactical card may display an unbound current-spec spell for diagnosis, but
--   a spell from another specialization must never be offered as a normal card.
--
-- Defensive data uses an explicit specialization-only registry:
--   CLASS_SPECINDEX -> empty profile.
-- A missing specialization identity intentionally returns no defensive card;
-- TE never falls back to a class-wide list for defense recommendations.
local TE = _G.TacticEcho

local AbilityProfiles = {}
TE.AbilityProfiles = AbilityProfiles

AbilityProfiles.interrupts = {
    DEATHKNIGHT = { 47528 },
    DEMONHUNTER = { 183752 },
    DRUID = { 106839 },
    EVOKER = { 351338 },
    HUNTER = { 147362, 187707 },
    MAGE = { 2139 },
    MONK = { 116705 },
    PALADIN = { 96231 },
    PRIEST = { 15487 },
    ROGUE = { 1766 },
    SHAMAN = { 57994 },
    WARLOCK = { 19647 },
    WARRIOR = { 6552 },
}

-- A defensive entry is intentionally structured instead of being a bare
-- SpellID.  The type, effective priority and applicability rule travel with
-- the current-specialization record so debug/HUD code can explain why a card
-- exists without reintroducing a class-wide fallback.
local DEFENSE_CATEGORIES = { "selfheal", "minor", "major", "emergency" }

local DEFAULT_DEFENSE_CONDITIONS = {
    selfheal = {
        mode = "defense_trigger_or_standby",
        text = "已知技能、当前有效动作条和真实绑定；脱战待命或战斗中防御触发",
    },
    minor = {
        mode = "defense_trigger_or_standby",
        text = "已知技能、当前有效动作条和真实绑定；脱战待命或战斗中防御触发",
    },
    major = {
        mode = "defense_trigger_or_standby",
        text = "已知技能、当前有效动作条和真实绑定；脱战待命或战斗中防御触发",
    },
    emergency = {
        mode = "defense_trigger_or_standby",
        text = "已知技能、当前有效动作条和真实绑定；脱战待命或战斗中防御触发",
    },
}

local function copyConditions(conditions)
    local out = {}
    for key, value in pairs(conditions or {}) do out[key] = value end
    return out
end

local function defenseEntry(spellID, category, priority, conditions)
    local selected = conditions or DEFAULT_DEFENSE_CONDITIONS[category] or {}
    return {
        spellID = tonumber(spellID),
        type = category,
        priority = tonumber(priority) or 1,
        conditions = copyConditions(selected),
        conditionText = selected.text or "当前专精防御条件",
    }
end

local function defenseGroup(category, spellIDs, conditions)
    local out = {}
    for priority, spellID in ipairs(spellIDs or {}) do
        out[#out + 1] = defenseEntry(spellID, category, priority, conditions)
    end
    return out
end

local function defenseProfile(selfheal, minor, major, emergency)
    return {
        selfheal = defenseGroup("selfheal", selfheal),
        minor = defenseGroup("minor", minor),
        major = defenseGroup("major", major),
        emergency = defenseGroup("emergency", emergency),
    }
end

-- Defensive registry: one explicit profile for every playable specialization.
--
-- Source policy:
-- * Initial candidates are seeded from the reference defensive-default data set.
-- * Each key is `CLASS_SPECINDEX`, matching GetSpecialization().
-- * There is deliberately no class-level fallback.  If TE cannot identify the
--   active specialization, it returns an empty defensive set instead of risking
--   a cross-specialization recommendation.
-- * Every generated entry retains its spellID, type, effective priority and
--   applicability condition. Runtime known-spell and real action-bar checks
--   remain mandatory downstream.
-- * A profile-local override may only reorder IDs already declared by the
--   active specialization; it cannot inject another specialization's spell.
--
-- Groups describe display severity/order only.  They never grant automatic use.
AbilityProfiles.defensives = {
    -- Death Knight: Blood / Frost / Unholy
    DEATHKNIGHT_1 = defenseProfile({ 49998 }, { 48707 }, { 55233, 48792 }, {}),
    DEATHKNIGHT_2 = defenseProfile({ 49998 }, { 48707 }, { 48792 }, {}),
    DEATHKNIGHT_3 = defenseProfile({ 49998 }, { 48707 }, { 48792 }, {}),

    -- Demon Hunter: Havoc / Vengeance
    DEMONHUNTER_1 = defenseProfile({}, { 198589 }, { 196718 }, {}),
    DEMONHUNTER_2 = defenseProfile({ 228477 }, { 203720, 198589 }, { 204021, 263648 }, {}),

    -- Druid: Balance / Feral / Guardian / Restoration
    DRUID_1 = defenseProfile({ 8936 }, { 108238 }, { 22812 }, {}),
    DRUID_2 = defenseProfile({ 8936 }, { 108238, 22812 }, { 61336 }, {}),
    DRUID_3 = defenseProfile({ 22842 }, { 192081, 22812 }, { 61336, 200851 }, {}),
    DRUID_4 = defenseProfile({ 8936 }, { 108238 }, { 22812 }, {}),

    -- Evoker: Devastation / Preservation / Augmentation
    EVOKER_1 = defenseProfile({ 360995 }, { 363916 }, {}, {}),
    EVOKER_2 = defenseProfile({ 360995 }, { 363916 }, {}, {}),
    EVOKER_3 = defenseProfile({ 360995 }, { 363916 }, {}, {}),

    -- Hunter: Beast Mastery / Marksmanship / Survival
    HUNTER_1 = defenseProfile({ 109304 }, {}, { 186265 }, { 388035 }),
    HUNTER_2 = defenseProfile({ 109304 }, {}, { 186265 }, { 388035 }),
    HUNTER_3 = defenseProfile({ 109304 }, {}, { 186265 }, { 388035 }),

    -- Mage: Arcane / Fire / Frost (barrier is specialization-specific)
    MAGE_1 = defenseProfile({}, { 235450 }, {}, { 45438 }),
    MAGE_2 = defenseProfile({}, { 235313 }, {}, { 45438 }),
    MAGE_3 = defenseProfile({}, { 11426 }, {}, { 45438 }),

    -- Monk: Brewmaster / Mistweaver / Windwalker
    MONK_1 = defenseProfile({ 322101 }, { 322507 }, { 120954 }, {}),
    MONK_2 = defenseProfile({}, { 122783 }, { 115203 }, {}),
    MONK_3 = defenseProfile({ 322101 }, { 122470 }, { 201318, 122783 }, {}),

    -- Paladin: Holy / Protection / Retribution
    PALADIN_1 = defenseProfile({ 85673 }, { 403876 }, { 642 }, { 633 }),
    PALADIN_2 = defenseProfile({ 85673 }, { 31850 }, { 86659 }, { 642, 633 }),
    PALADIN_3 = defenseProfile({ 85673 }, { 403876, 184662 }, { 642 }, { 633 }),

    -- Priest: Discipline / Holy / Shadow
    PRIEST_1 = defenseProfile({ 17 }, { 586 }, { 19236 }, {}),
    PRIEST_2 = defenseProfile({ 17 }, { 586 }, { 19236 }, {}),
    PRIEST_3 = defenseProfile({ 17 }, { 586 }, { 47585, 19236 }, {}),

    -- Rogue: Assassination / Outlaw / Subtlety
    ROGUE_1 = defenseProfile({ 185311 }, { 1966 }, { 31224, 5277 }, {}),
    ROGUE_2 = defenseProfile({ 185311 }, { 1966 }, { 31224, 5277 }, {}),
    ROGUE_3 = defenseProfile({ 185311 }, { 1966 }, { 31224, 5277 }, {}),

    -- Shaman: Elemental / Enhancement / Restoration
    SHAMAN_1 = defenseProfile({ 8004 }, { 108271 }, { 198103 }, {}),
    SHAMAN_2 = defenseProfile({ 8004 }, { 108271 }, { 198103 }, {}),
    SHAMAN_3 = defenseProfile({ 8004 }, { 108271 }, { 198103 }, {}),

    -- Warlock: Affliction / Demonology / Destruction
    WARLOCK_1 = defenseProfile({ 234153 }, { 108416 }, { 104773 }, {}),
    WARLOCK_2 = defenseProfile({ 234153 }, { 108416 }, { 104773 }, {}),
    WARLOCK_3 = defenseProfile({ 234153 }, { 108416 }, { 104773 }, {}),

    -- Warrior: Arms / Fury / Protection
    WARRIOR_1 = defenseProfile({ 34428, 202168 }, { 190456 }, { 118038, 97462 }, {}),
    WARRIOR_2 = defenseProfile({ 34428, 202168 }, { 190456 }, { 118038, 97462 }, {}),
    WARRIOR_3 = defenseProfile({}, { 190456, 23920 }, { 871 }, { 97462 }),
}

local function cloneDefensiveEntry(entry, category, priority)
    local spellID = type(entry) == "table" and tonumber(entry.spellID) or tonumber(entry)
    if not spellID then return nil end
    local selected = type(entry) == "table" and entry.conditions or DEFAULT_DEFENSE_CONDITIONS[category]
    return {
        spellID = spellID,
        type = type(entry) == "table" and entry.type or category,
        priority = tonumber(priority) or (type(entry) == "table" and tonumber(entry.priority)) or 1,
        conditions = copyConditions(selected),
        conditionText = type(entry) == "table" and entry.conditionText or ((selected or {}).text),
    }
end

local function copyDefensiveGroups(groups)
    local out = {}
    for _, category in ipairs(DEFENSE_CATEGORIES) do
        out[category] = {}
        for _, entry in ipairs(groups[category] or {}) do
            local copy = cloneDefensiveEntry(entry, category, #out[category] + 1)
            if copy then out[category][#out[category] + 1] = copy end
        end
    end
    return out
end

-- Optional per-profile ordering override stored inside the active TE profile.
-- It may reorder only IDs that already exist in the exact spec profile.
-- Unlisted default IDs remain after the chosen ordering; cross-specialization
-- spell injection is rejected by construction.
local function applyDefensiveOrderOverride(profileKey, groups)
    local tactics = TacticEchoDB and TacticEchoDB.tactics
    local overrides = tactics and tactics.defensiveProfileOverrides
    local override = type(overrides) == "table" and overrides[profileKey] or nil
    if type(override) ~= "table" then return groups, false end

    local out = {}
    for _, category in ipairs(DEFENSE_CATEGORIES) do
        local allowed, used = {}, {}
        for _, entry in ipairs(groups[category] or {}) do
            local spellID = type(entry) == "table" and tonumber(entry.spellID) or tonumber(entry)
            if spellID then allowed[spellID] = entry end
        end
        out[category] = {}
        for _, requested in ipairs(override[category] or {}) do
            local spellID = tonumber(requested)
            local entry = spellID and allowed[spellID] or nil
            if entry and not used[spellID] then
                local copy = cloneDefensiveEntry(entry, category, #out[category] + 1)
                if copy then out[category][#out[category] + 1] = copy end
                used[spellID] = true
            end
        end
        for _, entry in ipairs(groups[category] or {}) do
            local spellID = type(entry) == "table" and tonumber(entry.spellID) or tonumber(entry)
            if spellID and not used[spellID] then
                local copy = cloneDefensiveEntry(entry, category, #out[category] + 1)
                if copy then out[category][#out[category] + 1] = copy end
            end
        end
    end
    return out, true
end


-- A unified priority list is the UI-facing contract for defense ordering.
-- The list remains constrained to entries from the active specialization's
-- explicit registry; a user may reorder or disable an entry but cannot inject
-- another specialization's spell through this path.
local function flattenDefensiveGroups(groups)
    local out = {}
    for _, category in ipairs(DEFENSE_CATEGORIES) do
        for _, entry in ipairs((groups or {})[category] or {}) do
            local copy = cloneDefensiveEntry(entry, category, #out + 1)
            if copy then
                copy.type = copy.type or category
                out[#out + 1] = copy
            end
        end
    end
    return out
end

local function normalizedPriorityDisabled(value)
    local out = {}
    if type(value) ~= "table" then return out end
    for key, enabled in pairs(value) do
        local spellID = tonumber(key)
        if spellID and enabled == true then out[spellID] = true end
    end
    for _, spellID in ipairs(value) do
        spellID = tonumber(spellID)
        if spellID then out[spellID] = true end
    end
    return out
end

local function applyUnifiedDefensivePriorityOverride(profileKey, entries)
    local tactics = TacticEchoDB and TacticEchoDB.tactics
    local overrides = tactics and tactics.defensivePriorityOverrides
    local override = type(overrides) == "table" and overrides[profileKey] or nil
    local allowed, seen = {}, {}
    for _, entry in ipairs(entries or {}) do
        local spellID = tonumber(entry.spellID)
        if spellID then allowed[spellID] = entry end
    end

    local requested = type(override) == "table" and override.order or nil
    local disabled = normalizedPriorityDisabled(type(override) == "table" and override.disabled or nil)
    local out = {}
    for _, spellID in ipairs(requested or {}) do
        spellID = tonumber(spellID)
        local entry = spellID and allowed[spellID] or nil
        if entry and not seen[spellID] then
            local copy = cloneDefensiveEntry(entry, entry.type, #out + 1)
            if copy then
                copy.enabled = disabled[spellID] ~= true
                out[#out + 1] = copy
            end
            seen[spellID] = true
        end
    end
    for _, entry in ipairs(entries or {}) do
        local spellID = tonumber(entry.spellID)
        if spellID and not seen[spellID] then
            local copy = cloneDefensiveEntry(entry, entry.type, #out + 1)
            if copy then
                copy.enabled = disabled[spellID] ~= true
                out[#out + 1] = copy
            end
            seen[spellID] = true
        end
    end
    return out, type(override) == "table"
end

local function priorityOverride(profileKey, create)
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.defensivePriorityOverrides = type(TacticEchoDB.tactics.defensivePriorityOverrides) == "table"
        and TacticEchoDB.tactics.defensivePriorityOverrides or {}
    if create then
        TacticEchoDB.tactics.defensivePriorityOverrides[profileKey] = type(TacticEchoDB.tactics.defensivePriorityOverrides[profileKey]) == "table"
            and TacticEchoDB.tactics.defensivePriorityOverrides[profileKey] or {}
    end
    return TacticEchoDB.tactics.defensivePriorityOverrides[profileKey]
end

-- These remain broad display candidates.  The dedicated BurstProfiles module
-- is authoritative for the implemented Ret/Frost/Feral burst-window helper.
AbilityProfiles.bursts = {
    DEATHKNIGHT = { 51271, 47568, 42650 }, DEMONHUNTER = { 191427, 162264, 187827 },
    DRUID = { 194223, 102560, 106951 }, EVOKER = { 375087, 403631, 370960 },
    HUNTER = { 19574, 288613, 266779 }, MAGE = { 190319, 12472, 321507 },
    MONK = { 137639, 123904, 152173 }, PALADIN = { 31884, 231895 },
    PRIEST = { 10060, 47536, 193223 }, ROGUE = { 121471, 13750, 79140 },
    SHAMAN = { 114051, 191634, 51533 }, WARLOCK = { 205180, 1122, 104316 },
    WARRIOR = { 1719, 107574, 227847 },
}

AbilityProfiles.controls = {
    DEATHKNIGHT = { 108194, 47476 }, DEMONHUNTER = { 179057, 207684 },
    DRUID = { 5211, 99 }, EVOKER = { 360806, 351338 },
    -- Current live action-bar identity for 胁迫 is 19577; the reaction
    -- catalog must query the spell exposed by the visible button, not the
    -- historic 24394 entry.
    HUNTER = { 19577, 187650 }, MAGE = { 118, 122 },
    MONK = { 119381, 115078 }, PALADIN = { 853, 105421 },
    PRIEST = { 8122, 605 }, ROGUE = { 2094, 1776 },
    SHAMAN = { 51514, 192058 }, WARLOCK = { 5782, 710 },
    WARRIOR = { 5246, 132168 },
}

-- Typed control catalogue used by P2 reaction-binding inspection.  The legacy
-- `controls` list above remains untouched for the existing advisory planner.
-- `role` expresses only the intended future reaction bucket; it grants no
-- control immunity assumption and no automatic action.
AbilityProfiles.reactionControls = {
    DEATHKNIGHT = {
        { spellID = 108194, role = "single", roleLabel = "单体控制" },
        { spellID = 47476, role = "single", roleLabel = "单体控制" },
    },
    DEMONHUNTER = {
        { spellID = 179057, role = "aoe", roleLabel = "群体控制" },
        { spellID = 207684, role = "aoe", roleLabel = "群体控制" },
    },
    DRUID = {
        { spellID = 5211, role = "single", roleLabel = "单体控制" },
        { spellID = 99, role = "aoe", roleLabel = "群体控制" },
    },
    EVOKER = {
        { spellID = 360806, role = "single", roleLabel = "单体控制" },
        { spellID = 351338, role = "single", roleLabel = "单体控制" },
    },
    HUNTER = {
        { spellID = 19577, role = "single", roleLabel = "单体控制" },
        { spellID = 187650, role = "single", roleLabel = "单体控制" },
    },
    MAGE = {
        { spellID = 118, role = "single", roleLabel = "单体控制" },
        { spellID = 122, role = "aoe", roleLabel = "群体控制" },
    },
    MONK = {
        { spellID = 119381, role = "aoe", roleLabel = "群体控制" },
        { spellID = 115078, role = "single", roleLabel = "单体控制" },
    },
    PALADIN = {
        { spellID = 853, role = "single", roleLabel = "单体控制" },
        { spellID = 105421, role = "aoe", roleLabel = "群体控制" },
    },
    PRIEST = {
        { spellID = 8122, role = "aoe", roleLabel = "群体控制" },
        { spellID = 605, role = "single", roleLabel = "单体控制" },
    },
    ROGUE = {
        { spellID = 2094, role = "single", roleLabel = "单体控制" },
        { spellID = 1776, role = "single", roleLabel = "单体控制" },
    },
    SHAMAN = {
        { spellID = 51514, role = "single", roleLabel = "单体控制" },
        { spellID = 192058, role = "aoe", roleLabel = "群体控制" },
    },
    WARLOCK = {
        { spellID = 5782, role = "single", roleLabel = "单体控制" },
        { spellID = 710, role = "single", roleLabel = "单体控制" },
    },
    WARRIOR = {
        { spellID = 5246, role = "aoe", roleLabel = "群体控制" },
        { spellID = 132168, role = "aoe", roleLabel = "群体控制" },
    },
}

AbilityProfiles.mobility = {
    DEATHKNIGHT = { 49576, 77761 }, DEMONHUNTER = { 195072, 198793 },
    DRUID = { 102401, 1850 }, EVOKER = { 358267, 361227 },
    HUNTER = { 781, 109304 }, MAGE = { 1953, 212653 },
    MONK = { 109132, 115008 }, PALADIN = { 190784 },
    PRIEST = { 73325, 121536 }, ROGUE = { 36554, 2983 },
    SHAMAN = { 58875, 192063 }, WARLOCK = { 48020, 111771 },
    WARRIOR = { 6544, 100 },
}

local function specKey(classFile, specIndex)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    specIndex = tonumber(specIndex)
    if not specIndex or specIndex <= 0 then return nil end
    return classFile .. "_" .. tostring(specIndex)
end

function AbilityProfiles:GetInterrupts(classFile) return self.interrupts[classFile] or {} end

-- Returns the exact active-specialization registry plus diagnostic metadata.
-- There is intentionally no class fallback: missing specialization identity yields
-- an empty set rather than a broad class candidate list.
function AbilityProfiles:GetDefensiveGroups(classFile, specIndex)
    local key = specKey(classFile, specIndex)
    local base = key and self.defensives[key] or nil
    if type(base) == "table" then
        local groups, overridden = applyDefensiveOrderOverride(key, copyDefensiveGroups(base))
        return groups, {
            profileKey = key,
            source = overridden and "spec_registry_profile_order" or "spec_registry",
            calibrated = true,
            explicitSpecOnly = true,
        }
    end
    return {}, {
        profileKey = key or classFile or "unknown",
        source = "missing_spec_registry",
        calibrated = false,
        explicitSpecOnly = true,
    }
end


-- Returns one ordered list across self-heals, minor, major and emergency skills.
-- It is the authoritative ordering source for the defense HUD; category remains
-- metadata only and does not grant an input-capable action.
function AbilityProfiles:GetDefensivePriorityList(classFile, specIndex)
    local groups, profile = self:GetDefensiveGroups(classFile, specIndex)
    local entries, overridden = applyUnifiedDefensivePriorityOverride(profile.profileKey, flattenDefensiveGroups(groups))
    profile.prioritySource = overridden and "spec_registry_unified_profile_order" or "spec_registry_unified_default_order"
    profile.unifiedPriority = true
    return entries, profile
end

function AbilityProfiles:GetEditableDefensivePriority(context)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local entries, profile = self:GetDefensivePriorityList(context.class, context.specIndex)
    local out = {}
    for index, entry in ipairs(entries or {}) do
        out[index] = cloneDefensiveEntry(entry, entry.type, index)
        out[index].enabled = entry.enabled ~= false
    end
    return out, profile
end

function AbilityProfiles:MoveDefensivePriority(context, spellID, delta)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local entries, profile = self:GetDefensivePriorityList(context.class, context.specIndex)
    local profileKey = profile and profile.profileKey
    spellID, delta = tonumber(spellID), tonumber(delta)
    if not profileKey or not spellID or (delta ~= -1 and delta ~= 1) then return false, "invalid_defense_move" end
    local index
    for i, entry in ipairs(entries or {}) do
        if tonumber(entry.spellID) == spellID then index = i; break end
    end
    if not index then return false, "spell_not_in_current_spec_defense_registry" end
    local target = index + delta
    if target < 1 or target > #entries then return false, "already_at_boundary" end
    entries[index], entries[target] = entries[target], entries[index]
    local override = priorityOverride(profileKey, true)
    override.order = {}
    for i, entry in ipairs(entries) do override.order[i] = tonumber(entry.spellID) end
    return true
end

function AbilityProfiles:SetDefensivePriorityEnabled(context, spellID, enabled)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local entries, profile = self:GetDefensivePriorityList(context.class, context.specIndex)
    local profileKey = profile and profile.profileKey
    spellID = tonumber(spellID)
    if not profileKey or not spellID then return false, "invalid_defense_toggle" end
    local present = false
    for _, entry in ipairs(entries or {}) do
        if tonumber(entry.spellID) == spellID then present = true; break end
    end
    if not present then return false, "spell_not_in_current_spec_defense_registry" end
    local override = priorityOverride(profileKey, true)
    override.disabled = type(override.disabled) == "table" and override.disabled or {}
    override.disabled[spellID] = enabled ~= true
    return true
end

function AbilityProfiles:RestoreDefensivePriority(context)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local _, profile = self:GetDefensivePriorityList(context.class, context.specIndex)
    local profileKey = profile and profile.profileKey
    if not profileKey then return false, "missing_spec_registry" end
    local override = priorityOverride(profileKey, false)
    if override then
        local tactics = TacticEchoDB and TacticEchoDB.tactics
        if tactics and tactics.defensivePriorityOverrides then tactics.defensivePriorityOverrides[profileKey] = nil end
    end
    return true
end

function AbilityProfiles:GetBursts(classFile) return self.bursts[classFile] or {} end
function AbilityProfiles:GetControls(classFile) return self.controls[classFile] or {} end

-- Returns copies so the read-only reaction inspector cannot mutate profile
-- data used by the existing advisory planner. If a future class entry is only
-- present in the legacy list, keep it visible as an unclassified single-target
-- candidate rather than silently omitting a learned control binding.
function AbilityProfiles:GetReactionControls(classFile)
    local out, seen = {}, {}
    for _, entry in ipairs(self.reactionControls[classFile] or {}) do
        local spellID = tonumber(entry and entry.spellID)
        if spellID and not seen[spellID] then
            out[#out + 1] = {
                spellID = spellID,
                role = entry.role == "aoe" and "aoe" or "single",
                roleLabel = entry.roleLabel or (entry.role == "aoe" and "群体控制" or "单体控制"),
            }
            seen[spellID] = true
        end
    end
    for _, spellID in ipairs(self.controls[classFile] or {}) do
        spellID = tonumber(spellID)
        if spellID and not seen[spellID] then
            out[#out + 1] = {
                spellID = spellID,
                role = "single",
                roleLabel = "单体控制（未分类）",
                legacyFallback = true,
            }
            seen[spellID] = true
        end
    end
    return out
end

function AbilityProfiles:GetMobility(classFile) return self.mobility[classFile] or {} end

-- Optional dangerous-cast registry.  It starts empty deliberately: exact NPC
-- spell IDs are instance/version dependent.  Users or a future encounter pack
-- may populate TacticEchoDB.tactics.dangerousCastSpellIDs = { [spellID] = true }.
function AbilityProfiles:IsDangerousCast(spellID)
    local configured = TacticEchoDB and TacticEchoDB.tactics and TacticEchoDB.tactics.dangerousCastSpellIDs
    return type(configured) == "table" and configured[tonumber(spellID)] == true
end

function AbilityProfiles:GetCoverage(classFile, specIndex)
    local groups, profile = self:GetDefensiveGroups(classFile, specIndex)
    return {
        class = classFile,
        specIndex = specIndex,
        defensiveProfileKey = profile.profileKey,
        defensiveProfileSource = profile.source,
        defensiveCalibrated = profile.calibrated == true,
        hasDefensiveGroups = type(groups) == "table" and next(groups) ~= nil,
        mode = "explicit_spec_registry",
    }
end
