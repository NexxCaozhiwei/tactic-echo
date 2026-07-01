-- Boolean-only, read-only external environment bridge.
-- Environment data is advisory-only. Providers must refresh observedAt with
-- GetTime(); stale or unstamped signals fail closed instead of producing a
-- permanent danger/knockback recommendation.
local TE = _G.TacticEcho
local EnvironmentCompatibility = {}
TE.EnvironmentCompatibility = EnvironmentCompatibility

local DEFAULT_TTL_SECONDS = 1.5
local MIN_TTL_SECONDS = 0.25
local MAX_TTL_SECONDS = 10

local function now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function boolean(root, key)
    return root and root[key] == true
end

local function boundedTTL(value)
    value = tonumber(value) or DEFAULT_TTL_SECONDS
    return math.max(MIN_TTL_SECONDS, math.min(MAX_TTL_SECONDS, value))
end

function EnvironmentCompatibility:Sample()
    local root = (TacticEchoDB and TacticEchoDB.environmentSignals) or {}
    local observedAt = tonumber(root.observedAt) or 0
    local ttlSeconds = boundedTTL(root.ttlSeconds)
    local ageSeconds = observedAt > 0 and math.max(0, now() - observedAt) or nil
    local configured = root.available == true
    local fresh = configured and observedAt > 0 and ageSeconds ~= nil and ageSeconds <= ttlSeconds
    local state
    local reason
    if fresh then
        state = "fresh"
    elseif configured and observedAt <= 0 then
        state = "unstamped"
        reason = "环境兼容信号缺少 observedAt"
    elseif configured then
        state = "stale"
        reason = "环境兼容信号已过期"
    else
        state = "unavailable"
        reason = "环境兼容源不可用"
    end
    return {
        available = fresh,
        configured = configured,
        state = state,
        reason = reason,
        source = type(root.source) == "string" and root.source or "environment_compatibility",
        observedAt = observedAt,
        ttlSeconds = ttlSeconds,
        ageSeconds = ageSeconds,
        dangerZone = fresh and boolean(root, "dangerZone") or false,
        knockbackRisk = fresh and boolean(root, "knockbackRisk") or false,
        highPressure = fresh and boolean(root, "highPressure") or false,
    }
end
