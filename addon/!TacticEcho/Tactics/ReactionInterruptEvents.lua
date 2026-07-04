-- P4.2 event-backed interruptibility evidence.
--
-- Retail may expose a live UnitCastingInfo record while protecting the
-- `notInterruptible` scalar.  P3 keeps that state read-only; P4 needs one
-- ordinary event-derived confirmation before it can offer an existing
-- action-bar interrupt binding.  This module contains only a short-lived
-- target/focus/mouseover event cache:
--
-- * no protected action, binding mutation, macro parsing or TEAP write;
-- * no direct input and no interaction with TEK;
-- * `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` is always a veto;
-- * `UNIT_SPELLCAST_INTERRUPTIBLE` is a positive P4 confirmation;
-- * records are bounded and cleared on terminal casts / target changes.
--
-- The event watcher is intentionally loaded once during addon startup through
-- TE:RegisterEventsSafe.  It does not register/unregister in combat, retry a
-- protected registration, or create any hidden action source.
local TE = _G.TacticEcho

local ReactionInterruptEvents = {}
TE.ReactionInterruptEvents = ReactionInterruptEvents

ReactionInterruptEvents.schemaVersion = 2

local SOURCE_BY_UNIT = {
    target = "target",
    focus = "focus",
    mouseover = "mouseover",
}

local TERMINAL_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}

-- Event delivery can arrive a fraction of a second before the P3 polling
-- snapshot advances.  Keep bounded evidence briefly; AutoReaction still
-- requires a concurrent live P3 cast before consuming it.
local EVIDENCE_TTL_SECONDS = 1.10

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    if not ok then return 0 end
    local okNumber, number = pcall(function()
        local n = tonumber(value)
        if type(n) ~= "number" then return nil end
        local probe = n + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    return okNumber and number or 0
end

local function plainNumber(value)
    local ok, number = pcall(function()
        local n = tonumber(value)
        if type(n) ~= "number" then return nil end
        local probe = n + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return n
    end)
    return ok and number or nil
end

local function plainText(value)
    local ok, text = pcall(function()
        if type(value) ~= "string" then return nil end
        local length = #value
        if length < 0 then return nil end
        return value
    end)
    return ok and type(text) == "string" and text or nil
end

local state = {
    sources = {
        target = { active = false, status = "none", serial = 0, observedAt = 0, expiresAt = 0, event = "none", castGUID = nil, spellID = nil },
        focus = { active = false, status = "none", serial = 0, observedAt = 0, expiresAt = 0, event = "none", castGUID = nil, spellID = nil },
        mouseover = { active = false, status = "none", serial = 0, observedAt = 0, expiresAt = 0, event = "none", castGUID = nil, spellID = nil },
    },
}

local function resetSource(source, reason)
    local record = state.sources[source]
    if not record then return end
    record.active = false
    record.status = "none"
    record.observedAt = now()
    record.expiresAt = 0
    record.event = reason or "cleared"
    record.castGUID = nil
    record.spellID = nil
end

-- The start events carry identity fields on supported clients, whereas
-- INTERRUPTIBLE / NOT_INTERRUPTIBLE may expose only the unit token.  Preserve
-- the latest readable start identity when a status event does not carry a new
-- value; never replace it with nil and accidentally remove the stale-event
-- mismatch guard.
local function touchSource(source, status, eventName, castGUID, spellID, newCast)
    local record = state.sources[source]
    if not record then return end
    if newCast == true then
        record.serial = (tonumber(record.serial) or 0) + 1
        record.castGUID = plainText(castGUID)
        record.spellID = plainNumber(spellID)
    else
        local readableGUID = plainText(castGUID)
        local readableSpellID = plainNumber(spellID)
        if readableGUID ~= nil then record.castGUID = readableGUID end
        if readableSpellID ~= nil then record.spellID = readableSpellID end
    end
    record.active = true
    record.status = status
    record.observedAt = now()
    record.expiresAt = record.observedAt + EVIDENCE_TTL_SECONDS
    record.event = eventName
end

local function snapshotFor(source)
    local record = state.sources[source]
    if type(record) ~= "table" then
        return {
            schema = ReactionInterruptEvents.schemaVersion,
            active = false,
            status = "none",
            reason = "source_unknown",
        }
    end
    local age = math.max(0, now() - (tonumber(record.observedAt) or 0))
    local active = record.active == true and age <= EVIDENCE_TTL_SECONDS
    local status = active and record.status or "stale"
    return {
        schema = ReactionInterruptEvents.schemaVersion,
        active = active,
        status = status,
        serial = tonumber(record.serial) or 0,
        spellID = plainNumber(record.spellID),
        event = record.event,
        age = age,
        reason = active and ("unit_event_" .. tostring(status)) or "unit_event_stale",
    }
end

function ReactionInterruptEvents:GetEvidence(source)
    return snapshotFor(source)
end

function ReactionInterruptEvents:GetSnapshot()
    return {
        schema = self.schemaVersion,
        target = snapshotFor("target"),
        focus = snapshotFor("focus"),
        mouseover = snapshotFor("mouseover"),
    }
end

local function notifyRefresh(reason)
    -- The monitor remains the normal source of P3 samples.  Refresh once here
    -- so an interruptibility event can pair with an already-live target cast
    -- without waiting for the next 0.12s poll.  Fail closed on any reader
    -- error; this watcher never retries registration or emits an action.
    if TE.ReactionObservation and type(TE.ReactionObservation.Refresh) == "function" then
        pcall(TE.ReactionObservation.Refresh, TE.ReactionObservation)
    end
    if TE.SignalFrame and type(TE.SignalFrame.Refresh) == "function" then
        pcall(TE.SignalFrame.Refresh, reason or "reaction_interrupt_event")
    end
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
})

watcher:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if event == "PLAYER_TARGET_CHANGED" then
        resetSource("target", "target_changed")
        notifyRefresh("reaction_target_changed")
        return
    end
    if event == "PLAYER_FOCUS_CHANGED" then
        resetSource("focus", "focus_changed")
        notifyRefresh("reaction_focus_changed")
        return
    end
    if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        resetSource("target", "world_transition")
        resetSource("focus", "world_transition")
        resetSource("mouseover", "world_transition")
        return
    end

    local source = SOURCE_BY_UNIT[unit]
    if not source then return end

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        touchSource(source, "pending", event, castGUID, spellID, true)
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        touchSource(source, "interruptible", event, castGUID, spellID, false)
        notifyRefresh("reaction_interruptible_event")
        return
    end
    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        touchSource(source, "not_interruptible", event, castGUID, spellID, false)
        notifyRefresh("reaction_not_interruptible_event")
        return
    end
    if TERMINAL_EVENTS[event] then
        resetSource(source, string.lower(event))
        return
    end
end)
