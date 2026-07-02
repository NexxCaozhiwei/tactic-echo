-- Tactic Echo bootstrap.
local TE = _G.TacticEcho or {}
_G.TacticEcho = TE

TE.version = "1.0.07"
TE.interface = 120007
TE.locale = GetLocale and GetLocale() or "unknown"

function TE:Print(message)
    print("|cff66ccffTactic Echo|r " .. tostring(message))
end

-- Event registration policy.
--
-- 0.6.6 deliberately removes the previous deferred/polled registration gate.
-- WoW can taint protected paths when RegisterEvent is wrapped in retry/pcall
-- logic after the addon has already been touched by combat/UI state.  Modules
-- now register their events once during normal file loading.  Runtime enable /
-- disable must be handled inside OnEvent handlers with cheap `if disabled then
-- return end` checks, not by registering/unregistering during combat.
local EventGate = {
    status = {
        requested = 0,
        registered = 0,
        failed = 0,
        skippedCombat = 0,
        lastError = nil,
        policy = "load_once_no_retry",
    },
}
TE.EventGate = EventGate

local function isCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function directRegister(frame, eventName)
    EventGate.status.requested = (EventGate.status.requested or 0) + 1
    if not frame or type(eventName) ~= "string" or eventName == "" then
        EventGate.status.failed = (EventGate.status.failed or 0) + 1
        EventGate.status.lastError = "invalid_request"
        return false, "invalid_request"
    end
    if isCombatLocked() then
        -- Fail closed.  Do not retry from OnUpdate; the user can /reload out of
        -- combat.  This prevents the UNKNOWN protected-call taint chain seen in
        -- ProtocolMonitor/IconState registration.
        EventGate.status.skippedCombat = (EventGate.status.skippedCombat or 0) + 1
        EventGate.status.lastError = "combat_lockdown_skip_register:" .. eventName
        return false, "combat_lockdown"
    end
    -- Intentionally not pcall-wrapped.  RegisterEvent during addon load is the
    -- supported path; hiding a forbidden protected call in pcall only obscures
    -- the source and may itself appear as UNKNOWN() in BugGrabber.
    frame:RegisterEvent(eventName)
    EventGate.status.registered = (EventGate.status.registered or 0) + 1
    return true, "registered"
end

function TE:RegisterEventSafe(frame, eventName)
    return directRegister(frame, eventName)
end

function TE:RegisterEventsSafe(frame, eventNames)
    if type(eventNames) ~= "table" then return false, "invalid_event_list" end
    local allRegistered = true
    local lastReason = "registered"
    for _, eventName in ipairs(eventNames) do
        local ok, reason = directRegister(frame, eventName)
        if not ok then
            allRegistered = false
            lastReason = reason
        end
    end
    return allRegistered, lastReason
end

function TE:GetEventRegistrationStatus()
    return {
        requested = EventGate.status.requested or 0,
        registered = EventGate.status.registered or 0,
        failed = EventGate.status.failed or 0,
        skippedCombat = EventGate.status.skippedCombat or 0,
        lastError = EventGate.status.lastError,
        pending = false,
        policy = EventGate.status.policy,
    }
end
