local _, TEF = ...
local S = {}
TEF.Safety = S

-- No comparison, type check, indexing, formatting or persistence of a returned
-- value before the official detector has explicitly returned false.
function S.Public(value, expected)
    if type(issecretvalue) ~= "function" then return nil, "UNKNOWN_DETECTOR_MISSING" end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return nil, "UNKNOWN_DETECTOR_FAILED" end
    if type(secret) ~= "boolean" then return nil, "UNKNOWN_DETECTOR_RESULT" end
    if secret == true then return nil, "SECRET" end
    local valid, result, reason = pcall(function()
        if value == nil then return nil, "NO_DATA" end
        if type(value) ~= expected then return nil, "UNKNOWN_TYPE" end
        if expected == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            return nil, "UNKNOWN_NUMBER"
        end
        return value, "PUBLIC"
    end)
    if not valid then return nil, "UNKNOWN_OPERATION_FAILED" end
    return result, reason
end

function S.ID(value)
    local id, reason = S.Public(value, "number")
    if id == nil then return nil, reason end
    if id <= 0 or id > 2147483647 or id % 1 ~= 0 then return nil, "UNKNOWN_ID" end
    return id, "PUBLIC"
end

function S.Identity(value)
    local guid, reason = S.Public(value, "string")
    if guid == nil then return nil, reason end
    if #guid == 0 or #guid > 128 then return nil, "UNKNOWN_IDENTITY" end
    return guid, "PUBLIC"
end

function S.Resolve(path)
    local ok, fn = pcall(function()
        local value = _G
        for part in string.gmatch(path, "[^.]+") do value = value[part] end
        if type(value) == "function" then return value end
    end)
    if ok then return fn end
end

function S.Call(path, ...)
    local fn = S.Resolve(path)
    if not fn then return false, nil, "UNAVAILABLE" end
    local ok, value = pcall(fn, ...)
    if not ok then return false, nil, "CALL_FAILED" end
    return true, value, "CALLED"
end

function S.Field(record, key, expected)
    local parent, reason = S.Public(record, "table")
    if parent == nil then return nil, reason end
    local ok, value = pcall(function() return parent[key] end)
    if not ok then return nil, "FIELD_FAILED" end
    return S.Public(value, expected)
end

function S.Spell(id, label)
    local view = { name = label .. "（未解析）", icon = TEF.Placeholder, reason = "UNAVAILABLE" }
    local path = S.Resolve("C_Spell.GetSpellInfo") and "C_Spell.GetSpellInfo" or "GetSpellInfo"
    local ok, info, reason = S.Call(path, id)
    if ok then
        local name
        if path == "C_Spell.GetSpellInfo" then name, reason = S.Field(info, "name", "string")
        else name, reason = S.Public(info, "string") end
        if name and #name > 0 and #name <= 128 then view.name, view.reason = name, "PUBLIC"
        else view.reason = reason end
    else view.reason = reason end
    -- Icon failure is independent of name and sequence state.
    local iconPath = S.Resolve("C_Spell.GetSpellTexture") and "C_Spell.GetSpellTexture" or "GetSpellTexture"
    local iconOK, rawIcon, iconReason = S.Call(iconPath, id)
    if iconOK then
        local icon
        icon, iconReason = S.ID(rawIcon)
        if icon then view.icon = icon end
    end
    view.iconReason = iconReason
    return view
end
