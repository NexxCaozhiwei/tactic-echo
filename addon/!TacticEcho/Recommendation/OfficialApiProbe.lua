local TE = _G.TacticEcho

local Probe = {}
TE.OfficialApiProbe = Probe

local CANDIDATES = {
    { "C_AssistedCombat", "GetNextCastSpell" },
    { "C_AssistedCombat", "GetActionSpell" },
    { "C_AssistedCombat", "GetRotationSpells" },
    { "C_AssistedCombat", "GetNextRecommendedSpell" },
    { "C_AssistedCombat", "GetNextSpell" },
    { "C_AssistedCombat", "GetRecommendedSpell" },
    { "C_AssistedCombat", "IsAvailable" },
    { "C_AssistedCombat", "IsEnabled" },
    { "C_Spell", "GetSpellInfo" },
}

local EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UNIT_SPELLCAST_SUCCEEDED",
}

local function ensureStore()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.p0_01 = TacticEchoDB.p0_01 or {}
    local store = TacticEchoDB.p0_01
    store.client = store.client or {}
    store.observations = store.observations or {}
    store.scans = store.scans or {}
    return store
end

local function now()
    return GetTime and GetTime() or 0
end

local function safeToString(value)
    local valueType = type(value)
    if valueType == "table" then
        local parts = {}
        local count = 0
        for key, item in pairs(value) do
            count = count + 1
            if count > 12 then
                parts[#parts + 1] = "..."
                break
            end
            parts[#parts + 1] = tostring(key) .. "=" .. safeToString(item)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

local function packReturns(...)
    local packed = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        packed[index] = {
            type = type(value),
            value = safeToString(value),
        }
    end
    return packed
end

local function callSpellInfo(spellID)
    if type(spellID) ~= "number" or not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then
        return nil
    end

    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok then
        return {
            ok = false,
            error = tostring(info),
        }
    end

    if type(info) == "table" then
        return {
            ok = true,
            spellID = spellID,
            name = info.name,
            iconID = info.iconID,
            originalIconID = info.originalIconID,
        }
    end

    return {
        ok = true,
        spellID = spellID,
        valueType = type(info),
        value = safeToString(info),
    }
end

local function getPath(rootName, functionName)
    local root = _G[rootName]
    if type(root) ~= "table" then
        return nil
    end
    local fn = root[functionName]
    if type(fn) ~= "function" then
        return nil
    end
    return fn
end

function Probe:Observe(reason)
    local store = ensureStore()
    store.client = {
        interface = select(4, GetBuildInfo()),
        build = GetBuildInfo(),
        locale = GetLocale(),
        class = select(2, UnitClass("player")),
        specIndex = GetSpecialization and GetSpecialization() or nil,
        inCombat = InCombatLockdown and InCombatLockdown() or false,
        observedAt = date("%Y-%m-%d %H:%M:%S"),
    }

    local record = {
        reason = reason or "manual",
        elapsed = now(),
        inCombat = store.client.inCombat,
        results = {},
        derived = {},
    }

    for _, candidate in ipairs(CANDIDATES) do
        local rootName, functionName = candidate[1], candidate[2]
        local label = rootName .. "." .. functionName
        local fn = getPath(rootName, functionName)
        if fn then
            local ok, a, b, c, d, e = pcall(fn)
            record.results[label] = {
                exists = true,
                ok = ok,
                returns = ok and packReturns(a, b, c, d, e) or nil,
                error = ok and nil or tostring(a),
            }
        else
            record.results[label] = { exists = false }
        end
    end

    local nextCast = record.results["C_AssistedCombat.GetNextCastSpell"]
    if nextCast and nextCast.ok and nextCast.returns and nextCast.returns[1] then
        local spellID = tonumber(nextCast.returns[1].value)
        record.derived.nextCastSpell = callSpellInfo(spellID)
    end

    store.observations[#store.observations + 1] = record
    if #store.observations > 40 then
        table.remove(store.observations, 1)
    end

    if store.autoPrint then
        TE:Print("P0-01 观测已保存：" .. tostring(record.reason))
    end
end

function Probe:ScanGlobals()
    local store = ensureStore()
    local scan = {
        elapsed = now(),
        matches = {},
    }
    for name, value in pairs(_G) do
        if type(value) == "table" and string.match(name, "^C_") then
            for key, item in pairs(value) do
                if type(item) == "function" then
                    local text = name .. "." .. tostring(key)
                    if string.find(text, "Assist") or string.find(text, "Recommend") or string.find(text, "Suggest") then
                        scan.matches[#scan.matches + 1] = text
                    end
                end
            end
        end
    end
    table.sort(scan.matches)
    store.scans[#store.scans + 1] = scan
    if #store.scans > 10 then
        table.remove(store.scans, 1)
    end
    TE:Print("P0-01 全局扫描已保存，命中数量：" .. tostring(#scan.matches))
end

function Probe:PrintStatus()
    local store = ensureStore()
    TE:Print("客户端=" .. tostring(store.client.build) .. " 语言=" .. tostring(store.client.locale))
    TE:Print("观测=" .. tostring(#store.observations) .. " 扫描=" .. tostring(#store.scans))
end

local frame = CreateFrame("Frame")
TE:RegisterEventsSafe(frame, EVENTS)

frame:SetScript("OnEvent", function(_, eventName, unit)
    if eventName == "UNIT_SPELLCAST_SUCCEEDED" and unit ~= "player" then
        return
    end
    Probe:Observe(eventName)
end)

SLASH_TACTICECHOPROBE1 = "/teprobe"
SlashCmdList.TACTICECHOPROBE = function(message)
    local command = string.lower(message or "")
    if command == "scan" then
        Probe:ScanGlobals()
    elseif command == "status" then
        Probe:PrintStatus()
    elseif command == "clear" then
        TacticEchoDB = TacticEchoDB or {}
        TacticEchoDB.p0_01 = nil
        TE:Print("P0-01 观测记录已清空。")
    elseif command == "verbose" then
        local store = ensureStore()
        store.autoPrint = not store.autoPrint
        TE:Print("P0-01 自动打印：" .. (store.autoPrint and "开启" or "关闭"))
    else
        Probe:Observe("slash")
        TE:Print("P0-01 手动观测已保存。命令：/teprobe、/teprobe scan、/teprobe status、/teprobe clear、/teprobe verbose")
    end
end
