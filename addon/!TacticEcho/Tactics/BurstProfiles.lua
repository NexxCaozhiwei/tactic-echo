-- Explicit specialization-scoped burst registry.
--
-- Source policy:
-- * Initial trigger / injection seeds are normalized from reference spell data.
-- * Every playable specialization has an explicit profile key, including profiles
--   whose reference seed is intentionally empty.
-- * A profile can only produce display-only HUD candidates.  It never creates a
--   BindingToken, TEAP payload, or input request.
-- * User ordering / enablement stays inside the active specialization profile;
--   runtime known-spell and current-action-bar checks remain mandatory downstream.
local TE = _G.TacticEcho

local BurstProfiles = {}
TE.BurstProfiles = BurstProfiles

local DEFAULT_WINDOW_DURATION = 10

-- Generic offensive racial abilities. This is intentionally a narrow seed set
-- (only direct burst-style racials); a user may add a different racial SpellID
-- in TEUI when their character uses another offensive racial.
local RACIAL_BURST_SEEDS = { 20572, 26297, 265221, 274738 }

local SPEC_META = {
    -- Death Knight
    DEATHKNIGHT_1 = { classFile = "DEATHKNIGHT", specIndex = 1, specID = 250, label = "鲜血死亡骑士" },
    DEATHKNIGHT_2 = { classFile = "DEATHKNIGHT", specIndex = 2, specID = 251, label = "冰霜死亡骑士" },
    DEATHKNIGHT_3 = { classFile = "DEATHKNIGHT", specIndex = 3, specID = 252, label = "邪恶死亡骑士" },
    -- Demon Hunter
    DEMONHUNTER_1 = { classFile = "DEMONHUNTER", specIndex = 1, specID = 577, label = "浩劫恶魔猎手" },
    DEMONHUNTER_2 = { classFile = "DEMONHUNTER", specIndex = 2, specID = 581, label = "复仇恶魔猎手" },
    -- Druid
    DRUID_1 = { classFile = "DRUID", specIndex = 1, specID = 102, label = "平衡德鲁伊" },
    DRUID_2 = { classFile = "DRUID", specIndex = 2, specID = 103, label = "野性德鲁伊" },
    DRUID_3 = { classFile = "DRUID", specIndex = 3, specID = 104, label = "守护德鲁伊" },
    DRUID_4 = { classFile = "DRUID", specIndex = 4, specID = 105, label = "恢复德鲁伊" },
    -- Evoker
    EVOKER_1 = { classFile = "EVOKER", specIndex = 1, specID = 1467, label = "湮灭唤魔师" },
    EVOKER_2 = { classFile = "EVOKER", specIndex = 2, specID = 1468, label = "恩护唤魔师" },
    EVOKER_3 = { classFile = "EVOKER", specIndex = 3, specID = 1473, label = "增辉唤魔师" },
    -- Hunter
    HUNTER_1 = { classFile = "HUNTER", specIndex = 1, specID = 253, label = "兽王猎人" },
    HUNTER_2 = { classFile = "HUNTER", specIndex = 2, specID = 254, label = "射击猎人" },
    HUNTER_3 = { classFile = "HUNTER", specIndex = 3, specID = 255, label = "生存猎人" },
    -- Mage
    MAGE_1 = { classFile = "MAGE", specIndex = 1, specID = 62, label = "奥术法师" },
    MAGE_2 = { classFile = "MAGE", specIndex = 2, specID = 63, label = "火焰法师" },
    MAGE_3 = { classFile = "MAGE", specIndex = 3, specID = 64, label = "冰霜法师" },
    -- Monk
    MONK_1 = { classFile = "MONK", specIndex = 1, specID = 268, label = "酒仙武僧" },
    MONK_2 = { classFile = "MONK", specIndex = 2, specID = 270, label = "织雾武僧" },
    MONK_3 = { classFile = "MONK", specIndex = 3, specID = 269, label = "踏风武僧" },
    -- Paladin
    PALADIN_1 = { classFile = "PALADIN", specIndex = 1, specID = 65, label = "神圣圣骑士" },
    PALADIN_2 = { classFile = "PALADIN", specIndex = 2, specID = 66, label = "防护圣骑士" },
    PALADIN_3 = { classFile = "PALADIN", specIndex = 3, specID = 70, label = "惩戒圣骑士" },
    -- Priest
    PRIEST_1 = { classFile = "PRIEST", specIndex = 1, specID = 256, label = "戒律牧师" },
    PRIEST_2 = { classFile = "PRIEST", specIndex = 2, specID = 257, label = "神圣牧师" },
    PRIEST_3 = { classFile = "PRIEST", specIndex = 3, specID = 258, label = "暗影牧师" },
    -- Rogue
    ROGUE_1 = { classFile = "ROGUE", specIndex = 1, specID = 259, label = "奇袭潜行者" },
    ROGUE_2 = { classFile = "ROGUE", specIndex = 2, specID = 260, label = "狂徒潜行者" },
    ROGUE_3 = { classFile = "ROGUE", specIndex = 3, specID = 261, label = "敏锐潜行者" },
    -- Shaman
    SHAMAN_1 = { classFile = "SHAMAN", specIndex = 1, specID = 262, label = "元素萨满祭司" },
    SHAMAN_2 = { classFile = "SHAMAN", specIndex = 2, specID = 263, label = "增强萨满祭司" },
    SHAMAN_3 = { classFile = "SHAMAN", specIndex = 3, specID = 264, label = "恢复萨满祭司" },
    -- Warlock
    WARLOCK_1 = { classFile = "WARLOCK", specIndex = 1, specID = 265, label = "痛苦术士" },
    WARLOCK_2 = { classFile = "WARLOCK", specIndex = 2, specID = 266, label = "恶魔学识术士" },
    WARLOCK_3 = { classFile = "WARLOCK", specIndex = 3, specID = 267, label = "毁灭术士" },
    -- Warrior
    WARRIOR_1 = { classFile = "WARRIOR", specIndex = 1, specID = 71, label = "武器战士" },
    WARRIOR_2 = { classFile = "WARRIOR", specIndex = 2, specID = 72, label = "狂怒战士" },
    WARRIOR_3 = { classFile = "WARRIOR", specIndex = 3, specID = 73, label = "防护战士" },
}

-- Normalized from reference trigger default data.
local REFERENCE_TRIGGER_SEEDS = {
    DEATHKNIGHT_1 = { 49028 },
    DEATHKNIGHT_2 = { 51271, 152279 },
    DEATHKNIGHT_3 = { 63560, 42650 },
    DEMONHUNTER_1 = { 191427 },
    DEMONHUNTER_2 = { 187827 },
    DRUID_1 = { 194223, 102560 },
    DRUID_2 = { 106951, 102543 },
    DRUID_3 = { 50334, 102558 },
    EVOKER_1 = { 375087 },
    EVOKER_3 = { 403631 },
    HUNTER_1 = { 19574, 359844 },
    HUNTER_2 = { 288613 },
    HUNTER_3 = { 360952 },
    MAGE_1 = { 365350 },
    MAGE_2 = { 190319 },
    MAGE_3 = { 12472 },
    MONK_3 = { 137639 },
    PALADIN_2 = { 31884 },
    PALADIN_3 = { 31884, 231895 },
    PRIEST_3 = { 228260, 391109 },
    ROGUE_1 = { 360194 },
    ROGUE_2 = { 13750 },
    ROGUE_3 = { 121471 },
    SHAMAN_1 = { 114050 },
    SHAMAN_2 = { 51533 },
    WARLOCK_1 = { 205180 },
    WARLOCK_2 = { 265187 },
    WARLOCK_3 = { 1122 },
    WARRIOR_1 = { 167105, 262161 },
    WARRIOR_2 = { 1719 },
    WARRIOR_3 = { 107574 },
}

-- Normalized from reference injection default data.
-- Important correction: The reference seed placed Eye of Tyr (387174) under the wrong specialization
-- index. TE normalizes it under PALADIN_2 (Protection) before it reaches the
-- explicit specialization registry.
local REFERENCE_INJECTION_SEEDS = {
    DEATHKNIGHT_1 = { 194844 },
    DEATHKNIGHT_2 = { 51271 },
    DEATHKNIGHT_3 = { 42650 },
    DEMONHUNTER_1 = { 370965 },
    DEMONHUNTER_2 = { 187827 },
    DRUID_1 = { 391528 },
    DRUID_2 = { 391528, 274837 },
    DRUID_3 = { 50334, 102558, 391528 },
    EVOKER_1 = { 357210 },
    EVOKER_3 = { 403631 },
    HUNTER_1 = { 359844, 321530 },
    HUNTER_2 = { 260243 },
    HUNTER_3 = { 203415 },
    MAGE_1 = { 321507 },
    MAGE_2 = { 153561 },
    MAGE_3 = { 84714 },
    MONK_1 = { 325153 },
    MONK_3 = { 123904 },
    PALADIN_2 = { 387174 },
    PALADIN_3 = { 255937 },
    PRIEST_3 = { 263165 },
    ROGUE_1 = { 360194 },
    ROGUE_2 = { 51690 },
    ROGUE_3 = { 280719 },
    SHAMAN_1 = { 114050 },
    SHAMAN_2 = { 384352 },
    WARLOCK_1 = { 386997 },
    WARLOCK_2 = { 111898 },
    WARLOCK_3 = { 152108 },
    WARRIOR_1 = { 107574 },
    WARRIOR_2 = { 107574 },
    WARRIOR_3 = { 228920 },
}

-- Normalized from reference duration default data.
local REFERENCE_DURATION_SEEDS = {
    DEATHKNIGHT_1 = 15,
    DEMONHUNTER_1 = 24,
    DRUID_2 = 20,
    DRUID_3 = 15,
    MAGE_2 = 12,
    ROGUE_2 = 20,
    ROGUE_3 = 20,
    WARRIOR_2 = 12,
    WARRIOR_3 = 20,
}

-- Normalized from reference trigger aura map.
local TRIGGER_AURA_OVERRIDES = {
    [191427] = 162264, -- Havoc Metamorphosis cast -> player aura.
}

local function copyList(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        local numeric = tonumber(value)
        if numeric and numeric > 0 then out[#out + 1] = numeric end
    end
    return out
end

local function contains(values, spellID)
    spellID = tonumber(spellID)
    if not spellID then return false end
    for _, value in ipairs(values or {}) do
        if tonumber(value) == spellID then return true end
    end
    return false
end

local function uniqueAppend(out, seen, spellID)
    spellID = tonumber(spellID)
    if spellID and spellID > 0 and not seen[spellID] then
        seen[spellID] = true
        out[#out + 1] = spellID
    end
end

local function rootTactics()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.burstProfiles = type(TacticEchoDB.tactics.burstProfiles) == "table" and TacticEchoDB.tactics.burstProfiles or {}
    return TacticEchoDB.tactics, TacticEchoDB.tactics.burstProfiles
end

local function userProfile(profileKey, create)
    local _, profiles = rootTactics()
    if create then profiles[profileKey] = type(profiles[profileKey]) == "table" and profiles[profileKey] or {} end
    return type(profiles[profileKey]) == "table" and profiles[profileKey] or nil
end

local function listConfig(kind)
    if kind == "trigger" then
        return "triggerOrder", "triggerDisabled", "customTriggerSpellIDs", "openerSpellIDs"
    end
    return "injectionOrder", "injectionDisabled", "customInjectionSpellIDs", "injectionSpellIDs"
end

local function normalizedDisabled(value)
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

local function buildEntries(defaults, user, kind)
    local orderKey, disabledKey, customKey = listConfig(kind)
    local defaultsCopy = copyList(defaults)
    local customCopy = copyList(user and user[customKey] or {})
    local allowed, defaultSet = {}, {}
    for _, spellID in ipairs(defaultsCopy) do allowed[spellID], defaultSet[spellID] = true, true end
    for _, spellID in ipairs(customCopy) do allowed[spellID] = true end

    local requestedOrder = copyList(user and user[orderKey] or {})
    local disabled = normalizedDisabled(user and user[disabledKey])
    local ordered, seen = {}, {}
    for _, spellID in ipairs(requestedOrder) do
        if allowed[spellID] then uniqueAppend(ordered, seen, spellID) end
    end
    for _, spellID in ipairs(defaultsCopy) do uniqueAppend(ordered, seen, spellID) end
    for _, spellID in ipairs(customCopy) do uniqueAppend(ordered, seen, spellID) end

    local entries, enabled = {}, {}
    for priority, spellID in ipairs(ordered) do
        local item = {
            spellID = spellID,
            priority = priority,
            enabled = disabled[spellID] ~= true,
            builtIn = defaultSet[spellID] == true,
            custom = defaultSet[spellID] ~= true,
            source = defaultSet[spellID] and "reference_spell_seed" or "user_current_spec_custom",
        }
        entries[#entries + 1] = item
        if item.enabled then enabled[#enabled + 1] = spellID end
    end
    return entries, enabled
end

local function copyEntryList(entries)
    local out = {}
    for index, entry in ipairs(entries or {}) do
        out[index] = {
            spellID = tonumber(entry.spellID),
            priority = tonumber(entry.priority) or index,
            enabled = entry.enabled ~= false,
            builtIn = entry.builtIn == true,
            custom = entry.custom == true,
            source = entry.source,
        }
    end
    return out
end

local function createProfile(profileKey, meta)
    local triggerDefaults = copyList(REFERENCE_TRIGGER_SEEDS[profileKey])
    local injectionDefaults = copyList(REFERENCE_INJECTION_SEEDS[profileKey])
    local user = userProfile(profileKey, false)
    local triggerEntries, enabledTriggers = buildEntries(triggerDefaults, user, "trigger")
    local injectionEntries, enabledInjections = buildEntries(injectionDefaults, user, "injection")
    local confirmBuffIDs = {}
    for _, spellID in ipairs(enabledTriggers) do
        confirmBuffIDs[#confirmBuffIDs + 1] = TRIGGER_AURA_OVERRIDES[spellID] or spellID
    end
    local enabled = not user or user.enabled == nil or user.enabled == true
    local profile = {
        schema = 3,
        classFile = meta.classFile,
        specIndex = meta.specIndex,
        specID = meta.specID,
        profileKey = profileKey,
        label = meta.label .. "爆发",
        specLabel = meta.label,
        enabled = enabled,
        calibrated = #triggerDefaults > 0 or #injectionDefaults > 0,
        source = "reference_spell_seed_explicit_spec",
        triggerEntries = triggerEntries,
        injectionEntries = injectionEntries,
        openerSpellIDs = enabledTriggers,
        injectionSpellIDs = enabledInjections,
        confirmBuffIDs = confirmBuffIDs,
        windowDurationFallback = tonumber(REFERENCE_DURATION_SEEDS[profileKey]) or DEFAULT_WINDOW_DURATION,
        armedTimeout = 3.0,
        auraGraceMs = 500,
        debounceMs = 250,
        cooldownObserveTimeout = 8,
        displayCandidates = {
            offensiveCooldowns = copyList(enabledTriggers),
            rotationSpells = copyList(enabledInjections),
            trinkets = {
                { slot = 13, label = "饰品13", enabled = true },
                { slot = 14, label = "饰品14", enabled = true },
            },
            potions = {},
            racial = copyList(RACIAL_BURST_SEEDS),
        },
        displayPriority = { "offensiveCooldowns", "rotationSpells", "trinkets", "potions", "racial" },
        allowTrinketHint = not user or user.allowTrinketHint ~= false,
        allowPotionHint = not user or user.allowPotionHint ~= false,
        allowRacialHint = not user or user.allowRacialHint ~= false,
        allowBurstOverlay = not user or user.allowBurstOverlay ~= false,
        blacklistSpellIDs = copyList(user and user.blacklistSpellIDs),
        alternatives = {},
        duplicateGroups = {},
        noSeedNotice = (#triggerDefaults == 0 and #injectionDefaults == 0)
            and "参考技能资料未提供该专精的默认爆发触发/注入技能；列表保持为空，避免猜测治疗或跨专精技能。"
            or nil,
    }
    return profile
end

function BurstProfiles:SpecKey(classFile, specIndex)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    specIndex = tonumber(specIndex)
    if not specIndex or specIndex <= 0 then return nil end
    return classFile .. "_" .. tostring(math.floor(specIndex))
end

function BurstProfiles:Get(context)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local key = self:SpecKey(context.class, context.specIndex)
    local meta = key and SPEC_META[key] or nil
    if not meta then
        return nil, key, "当前职业/专精没有显式爆发注册表"
    end
    local profile = createProfile(key, meta)
    if profile.noSeedNotice then
        return profile, key, profile.noSeedNotice
    end
    return profile, key, nil
end

function BurstProfiles:GetEditableList(context, kind)
    local profile, profileKey, reason = self:Get(context)
    if not profile then return {}, profileKey, reason end
    if kind == "trigger" then return copyEntryList(profile.triggerEntries), profileKey, reason, profile end
    return copyEntryList(profile.injectionEntries), profileKey, reason, profile
end

function BurstProfiles:Contains(list, spellID)
    return contains(list, spellID)
end

function BurstProfiles:IsBlacklisted(profile, spellID)
    return self:Contains(profile and profile.blacklistSpellIDs, spellID)
end

local function currentSpecKnown(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return false, "spell_id_invalid" end
    local function probe(fn)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, spellID)
        if ok and type(value) == "boolean" then return value end
        return nil
    end
    local known = probe(C_Spell and C_Spell.IsSpellKnown)
    if known ~= nil then return known, "C_Spell.IsSpellKnown" end
    known = probe(IsPlayerSpell)
    if known ~= nil then return known, "IsPlayerSpell" end
    known = probe(IsSpellKnown)
    if known ~= nil then return known, "IsSpellKnown" end
    -- The runtime planner will require a known-spell / action-bar observation
    -- again. Do not accept a custom spell when no availability API exists.
    return false, "spell_known_api_unavailable"
end

local function containsEntry(entries, spellID)
    for _, entry in ipairs(entries or {}) do
        if tonumber(entry.spellID) == tonumber(spellID) then return true end
    end
    return false
end

function BurstProfiles:Move(context, kind, spellID, delta)
    local entries, profileKey, reason = self:GetEditableList(context, kind)
    if not profileKey then return false, reason or "missing_profile" end
    spellID, delta = tonumber(spellID), tonumber(delta)
    if not spellID or (delta ~= -1 and delta ~= 1) then return false, "invalid_move" end
    local index
    for i, entry in ipairs(entries) do
        if tonumber(entry.spellID) == spellID then index = i; break end
    end
    if not index then return false, "spell_not_in_current_spec_list" end
    local target = index + delta
    if target < 1 or target > #entries then return false, "already_at_boundary" end
    entries[index], entries[target] = entries[target], entries[index]
    local orderKey = listConfig(kind)
    local user = userProfile(profileKey, true)
    user[orderKey] = {}
    for i, entry in ipairs(entries) do user[orderKey][i] = tonumber(entry.spellID) end
    return true
end

function BurstProfiles:SetEnabled(context, kind, spellID, enabled)
    local entries, profileKey, reason = self:GetEditableList(context, kind)
    if not profileKey then return false, reason or "missing_profile" end
    spellID = tonumber(spellID)
    if not spellID or not containsEntry(entries, spellID) then return false, "spell_not_in_current_spec_list" end
    local _, disabledKey = listConfig(kind)
    local user = userProfile(profileKey, true)
    user[disabledKey] = type(user[disabledKey]) == "table" and user[disabledKey] or {}
    user[disabledKey][spellID] = enabled ~= true
    return true
end

function BurstProfiles:RemoveCustom(context, kind, spellID)
    local entries, profileKey, reason = self:GetEditableList(context, kind)
    if not profileKey then return false, reason or "missing_profile" end
    spellID = tonumber(spellID)
    local target
    for _, entry in ipairs(entries) do
        if tonumber(entry.spellID) == spellID then target = entry; break end
    end
    if not target then return false, "spell_not_in_current_spec_list" end
    if target.custom ~= true then
        return self:SetEnabled(context, kind, spellID, false)
    end
    local orderKey, disabledKey, customKey = listConfig(kind)
    local user = userProfile(profileKey, true)
    local remaining = {}
    for _, value in ipairs(user[customKey] or {}) do
        if tonumber(value) ~= spellID then remaining[#remaining + 1] = tonumber(value) end
    end
    user[customKey] = remaining
    local order = {}
    for _, value in ipairs(user[orderKey] or {}) do
        if tonumber(value) ~= spellID then order[#order + 1] = tonumber(value) end
    end
    user[orderKey] = order
    if type(user[disabledKey]) == "table" then user[disabledKey][spellID] = nil end
    return true
end

function BurstProfiles:AddCustom(context, kind, spellID)
    local profile, profileKey, reason = self:Get(context)
    if not profile then return false, reason or "missing_profile" end
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return false, "spell_id_invalid" end
    local known, knownSource = currentSpecKnown(spellID)
    if known ~= true then return false, "当前专精未确认该技能已学会（" .. tostring(knownSource) .. "）" end
    local entries = kind == "trigger" and profile.triggerEntries or profile.injectionEntries
    if containsEntry(entries, spellID) then return false, "技能已在当前专精列表中" end
    local orderKey, disabledKey, customKey = listConfig(kind)
    local user = userProfile(profileKey, true)
    user[customKey] = type(user[customKey]) == "table" and user[customKey] or {}
    user[customKey][#user[customKey] + 1] = spellID
    user[orderKey] = type(user[orderKey]) == "table" and user[orderKey] or {}
    user[orderKey][#user[orderKey] + 1] = spellID
    user[disabledKey] = type(user[disabledKey]) == "table" and user[disabledKey] or {}
    user[disabledKey][spellID] = nil
    return true
end

function BurstProfiles:RestoreDefaults(context)
    local _, profileKey, reason = self:Get(context)
    if not profileKey then return false, reason or "missing_profile" end
    local user = userProfile(profileKey, true)
    user.triggerOrder, user.triggerDisabled, user.customTriggerSpellIDs = nil, nil, nil
    user.injectionOrder, user.injectionDisabled, user.customInjectionSpellIDs = nil, nil, nil
    return true
end

function BurstProfiles:GetCoverage(context)
    local profile, profileKey, reason = self:Get(context)
    if not profile then
        return { profileKey = profileKey, explicitSpecOnly = true, calibrated = false, reason = reason }
    end
    return {
        profileKey = profileKey,
        profileLabel = profile.label,
        specLabel = profile.specLabel,
        explicitSpecOnly = true,
        calibrated = profile.calibrated == true,
        triggerCount = #(profile.triggerEntries or {}),
        injectionCount = #(profile.injectionEntries or {}),
        reason = reason,
        source = profile.source,
    }
end
