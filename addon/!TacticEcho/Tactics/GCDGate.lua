-- Normalized GCD timing gate for AutoBurst.
--
-- Raw global-cooldown values are read only inside this adapter.  Consumers see
-- a phase label, never a remaining-milliseconds value.  This keeps the burst
-- state machine independent from protected numeric timing details while still
-- allowing one legal pre-input attempt inside WoW's configured spell queue.
local TE = _G.TacticEcho

local Gate = {}
TE.GCDGate = Gate

local FALLBACK_QUEUE_SECONDS = 0.12
local MIN_QUEUE_SECONDS = 0.05
local MAX_QUEUE_SECONDS = 0.40

local function number(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local resolved = tonumber(value)
        if type(resolved) ~= "number" then return nil end
        local plain = resolved + 0
        if plain < -math.huge or plain > math.huge then return nil end
        return plain
    end)
    return ok and result or nil
end

local function queueWindowSeconds()
    local raw
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        local ok, value = pcall(C_CVar.GetCVar, "SpellQueueWindow")
        if ok then raw = number(value) end
    elseif type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, "SpellQueueWindow")
        if ok then raw = number(value) end
    end
    -- WoW exposes SpellQueueWindow in milliseconds.  Unknown or unreasonable
    -- client values fail back to a conservative default rather than widening
    -- a dispatch window.
    local seconds = raw and (raw / 1000) or FALLBACK_QUEUE_SECONDS
    if seconds < MIN_QUEUE_SECONDS then seconds = MIN_QUEUE_SECONDS end
    if seconds > MAX_QUEUE_SECONDS then seconds = MAX_QUEUE_SECONDS end
    return seconds
end

function Gate:BeginCycle(primary)
    if not (TE.IconState and type(TE.IconState.CreateRefreshContext) == "function") then
        return { schema = 1, phase = "UNKNOWN", reason = "icon_state_unavailable" }
    end
    local ok, context = pcall(TE.IconState.CreateRefreshContext, TE.IconState, primary)
    if not ok or type(context) ~= "table" or type(context.gcdSnapshot) ~= "table" then
        return { schema = 1, phase = "UNKNOWN", reason = "gcd_snapshot_unavailable" }
    end
    return {
        schema = 1,
        phase = nil,
        gcdSnapshot = context.gcdSnapshot,
        castSnapshot = context.castSnapshot,
        queueSeconds = queueWindowSeconds(),
    }
end

function Gate:Classify(cycle)
    cycle = type(cycle) == "table" and cycle or {}
    local snapshot = cycle.gcdSnapshot
    if type(snapshot) ~= "table" then
        return "UNKNOWN", "gcd_snapshot_missing"
    end
    if snapshot.known ~= true then
        -- Protected numeric GCD values are common on Retail. A public boolean
        -- still provides a safe one-bit answer: active waits conservatively;
        -- explicitly inactive permits the next single candidate.
        if snapshot.activeKnown == true then
            if snapshot.active == true then return "GCD_LOCKED", "gcd_active_boolean_only" end
            return "READY_NOW", "gcd_ready_boolean_only"
        end
        return "UNKNOWN", snapshot.reason or "gcd_unknown"
    end
    if snapshot.active ~= true then return "READY_NOW", nil end
    local remaining = number(snapshot.remaining)
    if remaining == nil then return "UNKNOWN", "gcd_remaining_unknown" end
    if remaining <= 0 then return "READY_NOW", nil end
    local queue = number(cycle.queueSeconds) or FALLBACK_QUEUE_SECONDS
    if remaining <= queue then return "QUEUE_WINDOW", nil end
    return "GCD_LOCKED", nil
end
