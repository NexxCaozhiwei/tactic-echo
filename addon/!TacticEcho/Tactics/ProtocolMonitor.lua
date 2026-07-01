-- Tactic Echo protocol-side observer.
--
-- This monitor is polling-only. It deliberately avoids RegisterEvent in
-- tactical modules because field testing showed RegisterEvent can enter
-- ADDON_ACTION_FORBIDDEN/UNKNOWN taint chains on some clients. The monitor
-- remains diagnostic-only and never feeds TEK dispatch eligibility.
--
-- Performance contract: the poller is the sole source of API sampling.
-- Sample() returns the latest immutable advisory snapshot instead of issuing
-- a second target-cast / health probe for every consumer in one HUD cycle.
local TE = _G.TacticEcho

local ProtocolMonitor = {}
TE.ProtocolMonitor = ProtocolMonitor

local POLL_INTERVAL = 0.12

local state = {
    targetCasting = false,
    targetInterruptible = false,
    targetInterruptibleKnown = false,
    targetCastKind = nil,
    targetCastSpellID = nil,
    targetCastName = nil,
    targetCastDangerous = false,
    playerHealthObserved = false,
    playerHealthCritical = false,
    healthAvailable = false,
    healthSource = nil,
    healthState = "unavailable",
    playerHealthPercent = nil,
    playerRecentDamage = false,
    sampledAt = 0,
    initialized = false,
    snapshot = nil,
}

local function currentTime()
    return type(GetTime) == "function" and GetTime() or 0
end

local function readHealthCompatibility()
    if not TE.HealthCompatibility or type(TE.HealthCompatibility.Sample) ~= "function" then
        return { available = false, low = false, source = nil, state = "unavailable" }
    end
    local ok, sample = pcall(TE.HealthCompatibility.Sample, TE.HealthCompatibility)
    if not ok or type(sample) ~= "table" then
        return { available = false, low = false, source = nil, state = "unavailable" }
    end
    return {
        available = sample.available == true,
        low = sample.low == true,
        source = sample.source,
        state = sample.state or (sample.low and "critical" or "normal"),
        percent = tonumber(sample.percent),
    }
end

-- UnitCastingInfo / UnitChannelInfo can return Secret Values on current Retail
-- clients. This monitor is advisory-only, so every field crossing this boundary
-- is materialized inside pcall. A value that cannot be proven to be an ordinary
-- Lua scalar is treated as unknown rather than being compared, stored, rendered
-- or exported to TEAP.
local function plainBoolean(value)
    local ok, result = pcall(function()
        if value == true then return true end
        if value == false then return false end
        return nil
    end)
    -- Do not use `ok and result or nil`: a valid ordinary false would be
    -- collapsed to nil. Preserve false so interruptible casts remain known.
    if not ok then return nil end
    return result
end

local function plainNumber(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local number = tonumber(value)
        if type(number) ~= "number" then return nil end
        -- Force arithmetic and comparison while still inside pcall. Secret
        -- numbers may survive tonumber/type but fail one of these probes.
        local probe = number + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    return ok and result or nil
end

local function plainText(value)
    local ok, result = pcall(function()
        if value == nil or type(value) ~= "string" then return nil end
        -- #secretString participates in secret propagation. Probe it so only a
        -- normal Lua string can leave this helper.
        local length = #value
        if length < 0 then return nil end
        return value
    end)
    return ok and type(result) == "string" and result or nil
end

local function isDangerousCastSafe(spellID)
    if not spellID or not TE.AbilityProfiles or type(TE.AbilityProfiles.IsDangerousCast) ~= "function" then
        return false
    end
    local ok, result = pcall(TE.AbilityProfiles.IsDangerousCast, TE.AbilityProfiles, spellID)
    return ok and result == true
end

local function clearTargetCast()
    state.targetCasting = false
    state.targetInterruptible = false
    state.targetInterruptibleKnown = false
    state.targetCastKind = nil
    state.targetCastSpellID = nil
    state.targetCastName = nil
    state.targetCastDangerous = false
end

local function readTargetCast()
    local castName, spellID, notInterruptible, kind
    if type(UnitCastingInfo) == "function" then
        local ok, name, _, _, _, _, _, _, noInterrupt, sid = pcall(UnitCastingInfo, "target")
        local safeName = ok and plainText(name) or nil
        if safeName then
            castName, spellID, notInterruptible, kind = safeName, sid, noInterrupt, "cast"
        end
    end
    if not castName and type(UnitChannelInfo) == "function" then
        local ok, name, _, _, _, _, _, noInterrupt, sid = pcall(UnitChannelInfo, "target")
        local safeName = ok and plainText(name) or nil
        if safeName then
            castName, spellID, notInterruptible, kind = safeName, sid, noInterrupt, "channel"
        end
    end
    if not castName then
        clearTargetCast()
        return
    end

    local safeSpellID = plainNumber(spellID)
    local safeNotInterruptible = plainBoolean(notInterruptible)

    state.targetCasting = true
    state.targetCastKind = kind
    state.targetCastName = castName
    state.targetCastSpellID = safeSpellID
    state.targetCastDangerous = isDangerousCastSafe(safeSpellID)

    -- Never compare the raw `notInterruptible` result. When Retail returns a
    -- secret boolean, preserve the cast observation but expose the interrupt
    -- property as unknown. This monitor does not influence recommendation or
    -- TEK dispatch eligibility, so fail-unknown is the safe behavior.
    state.targetInterruptibleKnown = safeNotInterruptible ~= nil
    state.targetInterruptible = safeNotInterruptible == false
end

local function rebuildSnapshot()
    -- Consumers treat this as read-only. Reusing one table per poll prevents
    -- four tactical subsystems from allocating and refreshing the same data.
    state.snapshot = {
        targetCasting = state.targetCasting == true,
        targetInterruptible = state.targetInterruptible == true,
        targetInterruptibleKnown = state.targetInterruptibleKnown == true,
        targetCastKind = state.targetCastKind,
        targetCastSpellID = state.targetCastSpellID,
        targetCastName = state.targetCastName,
        targetCastDangerous = state.targetCastDangerous == true,
        targetInterruptSuppressed = false,
        playerHealthObserved = state.playerHealthObserved == true,
        playerHealthCritical = state.playerHealthCritical == true,
        healthAvailable = state.healthAvailable == true,
        healthSource = state.healthSource,
        healthState = state.healthState,
        playerHealthPercent = state.playerHealthPercent,
        playerRecentDamage = state.playerRecentDamage == true,
        observedAt = state.sampledAt,
        source = "polling_safe_cached",
    }
end

local function refresh()
    readTargetCast()
    local health = readHealthCompatibility()
    state.playerHealthObserved = health.available == true
    state.playerHealthCritical = health.available == true and health.low == true
    state.healthAvailable = health.available == true
    state.healthSource = health.source
    state.healthState = health.state
    state.playerHealthPercent = health.percent
    state.sampledAt = currentTime()
    state.initialized = true
    rebuildSnapshot()
end

function ProtocolMonitor:Sample()
    -- First access may occur before the first OnUpdate tick. Initialise once,
    -- then return the cached sample until the poller advances it.
    if state.initialized ~= true then refresh() end
    return state.snapshot or {}
end

function ProtocolMonitor:GetFlags(sample)
    sample = sample or self:Sample()
    local flags = 0
    if sample.targetCasting == true then flags = flags + 4 end
    if sample.targetInterruptibleKnown == true and sample.targetInterruptible == true then flags = flags + 8 end
    if sample.playerHealthCritical == true then flags = flags + 16 end -- v3 bit 4
    return flags, sample
end

function ProtocolMonitor:GetStatusLabel()
    local sample = self:Sample()
    if sample.targetCasting ~= true then return "未监测到目标读条" end
    local danger = sample.targetCastDangerous and "危险读条；" or ""
    if sample.targetInterruptibleKnown then
        return danger .. (sample.targetInterruptible and "可打断" or "不可打断")
    end
    return danger .. "可打断状态未知"
end

local poller = CreateFrame("Frame")
local elapsed = 0
poller:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + (tonumber(delta) or 0)
    if elapsed < POLL_INTERVAL then return end
    elapsed = 0
    refresh()
end)
