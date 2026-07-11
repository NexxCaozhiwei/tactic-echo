-- Tactic Echo P5.8 manual-click ownership gate.
--
-- This module does not send input, create bindings, edit macros, or select a
-- target.  It records only a short ownership window after a real left click on
-- a HUD secure proxy or a Blizzard default action-bar button. SignalFrame then
-- emits its existing `manual_hold` state with BindingToken=0, so TEK's existing
-- gates cannot dispatch during the player's direct action.
local TE = _G.TacticEcho

local ManualActionPriority = {}
TE.ManualActionPriority = ManualActionPriority

ManualActionPriority.schemaVersion = 1

local HOLD_SECONDS = 0.45
local DUPLICATE_WINDOW_SECONDS = 0.05
local runtime = {
    untilAt = 0,
    kind = nil,
    source = nil,
    startedAt = 0,
    attachCount = 0,
    attachReason = nil,
    attached = setmetatable({}, { __mode = "k" }),
}

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    value = ok and tonumber(value) or nil
    return value and value >= 0 and value or 0
end

local function inCombatLockdown()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function refreshSignal(reason)
    local frame = TE.SignalFrame
    if frame and type(frame.Refresh) == "function" then
        -- This only repaints the existing TEAP frame. It never invokes TEK or
        -- creates a second dispatch path.
        pcall(frame.Refresh, frame, reason or "manual_action_priority")
    end
end

function ManualActionPriority:IsActive()
    local active = now() < (tonumber(runtime.untilAt) or 0)
    if not active then
        return false, nil, nil, nil, tonumber(runtime.untilAt) or 0
    end
    -- Scalar hot-path accessor: SignalFrame can detect ownership transitions on
    -- every transport tick without allocating a status table.
    return true,
        "manual_click_priority:" .. tostring(runtime.kind or "unknown"),
        runtime.kind,
        runtime.source,
        runtime.untilAt
end

function ManualActionPriority:GetActive()
    local active, reason, kind, source, untilAt = self:IsActive()
    if not active then
        return {
            active = false,
            reason = nil,
            kind = nil,
            source = nil,
            untilAt = untilAt,
        }
    end
    return {
        active = true,
        -- SignalFrame must preserve the normal manual_hold state name because
        -- TEK already treats it as a non-dispatch pause state.
        reason = reason,
        kind = kind,
        source = source,
        untilAt = untilAt,
        startedAt = runtime.startedAt,
    }
end

function ManualActionPriority:GetSnapshot()
    local active = self:GetActive()
    active.schema = self.schemaVersion
    active.attachCount = runtime.attachCount or 0
    active.attachReason = runtime.attachReason
    return active
end

function ManualActionPriority:Begin(kind, source)
    kind = kind == "hud" and "hud" or "native_actionbar"
    source = type(source) == "string" and source or "unknown"
    local timestamp = now()
    local duplicate = runtime.kind == kind and runtime.source == source
        and (timestamp - (tonumber(runtime.startedAt) or 0)) >= 0
        and (timestamp - (tonumber(runtime.startedAt) or 0)) < DUPLICATE_WINDOW_SECONDS

    runtime.kind = kind
    runtime.source = source
    runtime.startedAt = timestamp
    runtime.untilAt = timestamp + HOLD_SECONDS
    if not duplicate then refreshSignal("manual_action_priority") end
    return self:GetActive()
end

function ManualActionPriority:Clear(reason)
    runtime.untilAt = 0
    runtime.kind = nil
    runtime.source = nil
    runtime.startedAt = 0
    refreshSignal(reason or "manual_action_priority_clear")
end

local function attachButton(button, buttonName)
    if not button or runtime.attached[button] then return false end
    if type(button.HookScript) ~= "function" then return false end
    local source = type(buttonName) == "string" and buttonName or "unknown_action_button"
    local function recordClick(_, mouseButton)
        if mouseButton == "LeftButton" then
            ManualActionPriority:Begin("native_actionbar", source)
        end
    end
    -- OnMouseDown gives the TEAP pause the earliest ordinary mouse callback;
    -- PreClick repeats the same idempotent marker immediately before the
    -- default button's secure action. Neither hook replaces Blizzard scripts.
    local mouseOK = pcall(button.HookScript, button, "OnMouseDown", recordClick)
    local preClickOK = pcall(button.HookScript, button, "PreClick", recordClick)
    if mouseOK or preClickOK then
        runtime.attached[button] = true
        runtime.attachCount = (runtime.attachCount or 0) + 1
        return true
    end
    return false
end

function ManualActionPriority:AttachDefaultActionButtons(reason)
    if inCombatLockdown() then
        runtime.attachReason = "combat_lockdown"
        return false, runtime.attachReason
    end
    local resolver = TE.ActionBarBindingResolver
    if not (resolver and type(resolver.GetButtonCache) == "function") then
        runtime.attachReason = "actionbar_resolver_unavailable"
        return false, runtime.attachReason
    end
    local ok, cache = pcall(resolver.GetButtonCache, resolver)
    if not ok or type(cache) ~= "table" then
        runtime.attachReason = "actionbar_cache_unavailable"
        return false, runtime.attachReason
    end
    local attachedThisPass = 0
    for _, entry in ipairs(type(cache.entries) == "table" and cache.entries or {}) do
        local buttonName = type(entry) == "table" and entry.buttonName or nil
        local button = type(buttonName) == "string" and _G[buttonName] or nil
        if attachButton(button, buttonName) then attachedThisPass = attachedThisPass + 1 end
    end
    runtime.attachReason = attachedThisPass > 0 and "attached" or "no_new_default_action_buttons"
    return attachedThisPass > 0, runtime.attachReason
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" })
watcher:SetScript("OnEvent", function(_, event)
    -- Default action button frames are static after login. PLAYER_REGEN_ENABLED
    -- is only a fail-closed opportunity to attach a frame a UI addon created
    -- late; no action-bar mutation occurs here.
    ManualActionPriority:AttachDefaultActionButtons(event)
end)
