-- Boolean-only compatibility bridge for defensive advisory monitoring.
--
-- Current Retail health values may be secret.  This module never reads,
-- compares or stores numeric health values.  A compatible local source can
-- register a callback or publish a short-lived *boolean* low-health state.
-- The output is advisory telemetry only (TEAP v3 bit4); it is never consulted
-- by the TE dispatch path and cannot emit an input token.
local TE = _G.TacticEcho

local HealthCompatibility = {}
TE.HealthCompatibility = HealthCompatibility

local providers = {}
local publications = {}
local DEFAULT_TTL_SECONDS = 1.5

local function now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function validId(value)
    return type(value) == "string" and value ~= "" and #value <= 64
end

local function normalizeSample(value, source)
    if type(value) == "boolean" then
        return { available = true, low = value, source = source, state = value and "critical" or "normal" }
    end
    if type(value) ~= "table" or value.available ~= true or type(value.low) ~= "boolean" then
        return nil
    end
    return {
        available = true,
        low = value.low,
        source = value.source or source,
        state = value.low and "critical" or "normal",
        percent = tonumber(value.percent),
        detail = value.detail,
    }
end

function HealthCompatibility:RegisterBooleanProvider(providerId, callback, priority)
    if not validId(providerId) or type(callback) ~= "function" then return false, "invalid_boolean_provider" end
    providers[providerId] = {
        callback = callback,
        priority = tonumber(priority) or 0,
    }
    return true
end

function HealthCompatibility:UnregisterBooleanProvider(providerId)
    providers[providerId] = nil
end

function HealthCompatibility:PublishBoolean(providerId, isLow, ttlSeconds, detail, percent)
    if not validId(providerId) or type(isLow) ~= "boolean" then return false, "boolean_required" end
    ttlSeconds = tonumber(ttlSeconds) or DEFAULT_TTL_SECONDS
    ttlSeconds = math.max(0.25, math.min(10, ttlSeconds))
    publications[providerId] = {
        low = isLow,
        expiresAt = now() + ttlSeconds,
        detail = type(detail) == "string" and detail:sub(1, 120) or nil,
        percent = tonumber(percent),
    }
    return true
end

function HealthCompatibility:Clear(providerId)
    publications[providerId] = nil
end

local function selectPublication()
    local current = now()
    local selectedId, selected
    for providerId, item in pairs(publications) do
        if item.expiresAt and item.expiresAt >= current then
            if not selectedId or tostring(providerId) < tostring(selectedId) then
                selectedId, selected = providerId, item
            end
        else
            publications[providerId] = nil
        end
    end
    if not selected then return nil end
    return { available = true, low = selected.low == true, source = selectedId, state = selected.low and "critical" or "normal", percent = selected.percent, detail = selected.detail }
end

local function selectProvider()
    local selectedId, selected
    for providerId, provider in pairs(providers) do
        local ok, value = pcall(provider.callback)
        local sample = ok and normalizeSample(value, providerId) or nil
        if sample and (not selected or provider.priority > selected.priority or (provider.priority == selected.priority and tostring(providerId) < tostring(selectedId))) then
            selectedId = providerId
            selected = { priority = provider.priority, sample = sample }
        end
    end
    return selected and selected.sample or nil
end

function HealthCompatibility:Sample()
    -- Explicitly published values win over callback providers.  This permits a
    -- compatible source to make an event-derived state available without an
    -- implicit external-addon dependency or any numeric health access here.
    local published = selectPublication()
    if published then return published end
    local provider = selectProvider()
    if provider then return provider end
    return { available = false, low = false, source = nil, state = "unavailable" }
end

return HealthCompatibility
