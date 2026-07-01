-- Tactic Echo profile manager.
--
-- Profiles contain configuration only (settings + tactical HUD preferences).
-- They never alter the official recommendation, action-bar bindings, TEAP
-- encoding, BindingToken generation, or TEK dispatch policy.
local TE = _G.TacticEcho

local ProfileManager = {}
TE.ProfileManager = ProfileManager

local SCHEMA = 1

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        if type(key) ~= "function" and type(child) ~= "function" then
            out[copy(key, seen)] = copy(child, seen)
        end
    end
    return out
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function database()
    TacticEchoDB = TacticEchoDB or {}
    return TacticEchoDB
end

local function ensureStore()
    local root = database()
    root.profileStore = type(root.profileStore) == "table" and root.profileStore or {}
    local store = root.profileStore
    store.schema = SCHEMA
    store.profiles = type(store.profiles) == "table" and store.profiles or {}
    store.assignments = type(store.assignments) == "table" and store.assignments or {}

    -- One-time migration: the 0.7.6 flat database becomes Default. Existing
    -- settings remain active; no game-play setting is discarded during upgrade.
    if type(store.profiles.Default) ~= "table" then
        store.profiles.Default = {
            settings = copy(root.settings or {}),
            tactics = copy(root.tactics or {}),
            createdByMigration = true,
        }
    end
    store.activeName = type(store.activeName) == "string" and store.activeName or "Default"
    if not store.profiles[store.activeName] then store.activeName = "Default" end
    return root, store
end

local function profilePayload(root)
    return {
        settings = copy(root.settings or {}),
        tactics = copy(root.tactics or {}),
    }
end

local function playerIdentity()
    local name, realm
    if type(UnitFullName) == "function" then
        local ok, unitName, unitRealm = pcall(UnitFullName, "player")
        if ok then name, realm = unitName, unitRealm end
    end
    if not name and type(UnitName) == "function" then
        local ok, unitName = pcall(UnitName, "player")
        if ok then name = unitName end
    end
    if not realm and type(GetRealmName) == "function" then
        local ok, value = pcall(GetRealmName)
        if ok then realm = value end
    end
    name = trim(name)
    realm = trim(realm)
    if name == "" then name = "未知角色" end
    if realm == "" then realm = "未知服务器" end
    return name .. "-" .. realm
end

function ProfileManager:GetContext()
    local context = TE.Context and TE.Context:GetPlayer() or {}
    return {
        character = playerIdentity(),
        class = context.class or "UNKNOWN",
        specIndex = tonumber(context.specIndex) or 0,
        specID = tonumber(context.specID) or 0,
        specName = context.specName or "未知专精",
    }
end

function ProfileManager:GetScopeKeys()
    local context = self:GetContext()
    return {
        global = "global",
        character = "character:" .. context.character,
        class = "class:" .. tostring(context.class),
        spec = "spec:" .. tostring(context.class) .. ":" .. tostring(context.specIndex),
    }, context
end

function ProfileManager:Ensure()
    return ensureStore()
end

function ProfileManager:GetNames()
    local _, store = ensureStore()
    local names = {}
    for name in pairs(store.profiles) do names[#names + 1] = name end
    table.sort(names, function(left, right)
        if left == "Default" then return true end
        if right == "Default" then return false end
        return left:lower() < right:lower()
    end)
    return names
end

function ProfileManager:GetActiveName()
    local _, store = ensureStore()
    return store.activeName
end

function ProfileManager:GetProfile(name)
    local _, store = ensureStore()
    return store.profiles[name or store.activeName]
end

function ProfileManager:SaveActive()
    local root, store = ensureStore()
    local name = store.activeName
    if type(name) ~= "string" or name == "" then name = "Default"; store.activeName = name end
    store.profiles[name] = profilePayload(root)
    return true, name
end

function ProfileManager:Activate(name, reason)
    name = trim(name)
    local root, store = ensureStore()
    if name == "" or type(store.profiles[name]) ~= "table" then return false, "配置文件不存在" end
    self:SaveActive()
    local source = store.profiles[name]
    root.settings = copy(source.settings or {})
    root.tactics = copy(source.tactics or {})
    store.activeName = name
    store.lastActivationReason = reason or "manual"
    return true, name
end

function ProfileManager:Create(name, sourceName)
    name = trim(name)
    local root, store = ensureStore()
    if name == "" then return false, "配置名称不能为空" end
    if #name > 40 then return false, "配置名称不能超过 40 个字符" end
    if store.profiles[name] then return false, "同名配置已存在" end
    local source = store.profiles[sourceName or store.activeName]
    store.profiles[name] = source and copy(source) or profilePayload(root)
    return true, name
end

function ProfileManager:Duplicate(name)
    return self:Create(name, self:GetActiveName())
end

function ProfileManager:Rename(oldName, newName)
    oldName, newName = trim(oldName), trim(newName)
    local _, store = ensureStore()
    if oldName == "" or type(store.profiles[oldName]) ~= "table" then return false, "原配置不存在" end
    if newName == "" then return false, "新名称不能为空" end
    if newName ~= oldName and store.profiles[newName] then return false, "同名配置已存在" end
    if newName == oldName then return true, newName end
    store.profiles[newName] = store.profiles[oldName]
    store.profiles[oldName] = nil
    if store.activeName == oldName then store.activeName = newName end
    for scope, assigned in pairs(store.assignments) do
        if assigned == oldName then store.assignments[scope] = newName end
    end
    return true, newName
end

function ProfileManager:Delete(name)
    name = trim(name)
    local _, store = ensureStore()
    if name == "Default" then return false, "Default 配置不可删除" end
    if type(store.profiles[name]) ~= "table" then return false, "配置不存在" end
    if store.activeName == name then
        local ok, reason = self:Activate("Default", "delete_fallback")
        if not ok then return false, reason end
    end
    store.profiles[name] = nil
    for scope, assigned in pairs(store.assignments) do
        if assigned == name then store.assignments[scope] = nil end
    end
    return true, "已删除"
end

function ProfileManager:SetScopeProfile(scopeKey, profileName)
    scopeKey, profileName = trim(scopeKey), trim(profileName)
    local _, store = ensureStore()
    if scopeKey == "" then return false, "配置范围无效" end
    if profileName == "" or type(store.profiles[profileName]) ~= "table" then return false, "目标配置不存在" end
    store.assignments[scopeKey] = profileName
    return true, profileName
end

function ProfileManager:ClearScopeProfile(scopeKey)
    scopeKey = trim(scopeKey)
    local _, store = ensureStore()
    if scopeKey == "" then return false, "配置范围无效" end
    store.assignments[scopeKey] = nil
    return true, "已清除"
end

function ProfileManager:GetScopeProfile(scopeKey)
    local _, store = ensureStore()
    return store.assignments[scopeKey]
end

function ProfileManager:ResolveAssignedProfile()
    local _, store = ensureStore()
    local keys = self:GetScopeKeys()
    -- Scope precedence: spec -> class -> character -> global -> Default.
    for _, scopeKey in ipairs({ keys.spec, keys.class, keys.character, keys.global }) do
        local name = store.assignments[scopeKey]
        if name and store.profiles[name] then return name, scopeKey end
    end
    return "Default", "default"
end

function ProfileManager:ApplyBestScope(reason)
    local target, scope = self:ResolveAssignedProfile()
    local active = self:GetActiveName()
    if target == active then return true, active, scope end
    local ok, value = self:Activate(target, reason or "scope_switch")
    return ok, value, scope
end

function ProfileManager:GetSummary()
    local _, store = ensureStore()
    local keys, context = self:GetScopeKeys()
    local target, source = self:ResolveAssignedProfile()
    return {
        schema = SCHEMA,
        activeName = store.activeName,
        selectedByScope = target,
        selectedScope = source,
        profiles = self:GetNames(),
        assignments = copy(store.assignments),
        keys = keys,
        context = context,
    }
end

local eventFrame = CreateFrame("Frame")
TE:RegisterEventsSafe(eventFrame, { "PLAYER_LOGIN", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LOGOUT" })
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ProfileManager:ApplyBestScope("login")
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        ProfileManager:SaveActive()
        ProfileManager:ApplyBestScope("specialization_changed")
    elseif event == "PLAYER_LOGOUT" then
        ProfileManager:SaveActive()
    end
end)
