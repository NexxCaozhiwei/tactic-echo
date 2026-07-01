-- Small HUD animation/debounce helper.
-- It owns presentation hysteresis only; it never changes recommendations.
local TE = _G.TacticEcho

local TacticalHudAnimator = {}
TE.TacticalHudAnimator = TacticalHudAnimator

TacticalHudAnimator.POSITION_HOLD_TIME = 0.12

local function now()
    local ok, value = pcall(GetTime)
    if not ok then return 0 end
    local plain, result = pcall(function()
        local number = tonumber(value)
        if type(number) ~= "number" then return 0 end
        local probe = number + 0
        if probe < -math.huge or probe > math.huge then return 0 end
        return probe
    end)
    return plain and result or 0
end

function TacticalHudAnimator:NewSlotState()
    return { fingerprint = nil, pendingFingerprint = nil, pendingAt = 0, appliedAt = 0, shown = false }
end

function TacticalHudAnimator:ShouldCommit(slot, fingerprint, urgent)
    if not slot then return true end
    -- An urgent card must commit immediately when its identity/state changes,
    -- but it must not re-run the full Apply path on every repeated snapshot.
    -- Re-applying a native Cooldown frame restarts its presentation and caused
    -- visible HUD flashing while TEK repeat dispatch was active.
    if slot.fingerprint == fingerprint then
        slot.pendingFingerprint = nil
        return false
    end
    if urgent == true then
        slot.fingerprint, slot.pendingFingerprint, slot.appliedAt = fingerprint, nil, now()
        return true
    end
    local current = now()
    if slot.pendingFingerprint ~= fingerprint then
        slot.pendingFingerprint = fingerprint
        slot.pendingAt = current
        return false
    end
    if current - (slot.pendingAt or 0) < self.POSITION_HOLD_TIME then
        return false
    end
    slot.fingerprint, slot.pendingFingerprint, slot.appliedAt = fingerprint, nil, current
    return true
end
