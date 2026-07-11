local TE = _G.TacticEcho

local Context = {}
TE.Context = Context

-- Stable player identity changes only on login/world/spec transitions. Reuse one
-- session-local table so hot paths do not allocate and repopulate class/spec/
-- locale data every 50 ms. Consumers must treat the returned table as read-only.
local playerContext
local playerContextDirty = true
local contextRevision = 0

local function readStablePlayerContext()
    local className, classFile = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID, specName

    if specIndex and GetSpecializationInfo then
        specID, specName = GetSpecializationInfo(specIndex)
    end

    if contextRevision == 0 then contextRevision = 1 end
    playerContext = {
        className = className,
        class = classFile,
        specIndex = specIndex,
        specID = specID,
        specName = specName,
        locale = GetLocale and GetLocale() or "unknown",
        inCombat = false,
        revision = contextRevision,
    }
    playerContextDirty = false
    return playerContext
end

function Context:Invalidate(reason)
    contextRevision = contextRevision + 1
    playerContextDirty = true
    self.lastInvalidationReason = reason or "manual"
end

function Context:IsDirty()
    return playerContextDirty == true
end

function Context:GetPlayer()
    local context = playerContext
    if playerContextDirty or type(context) ~= "table" then
        context = readStablePlayerContext()
    end
    -- Combat is the only intentionally dynamic scalar on this shared context.
    -- Updating it in place avoids a new table while preserving current behavior.
    context.inCombat = InCombatLockdown and InCombatLockdown() or false
    return context
end

function Context:GetRevision()
    return contextRevision
end

function Context:MatchesAction(action, context)
    context = context or self:GetPlayer()
    if not action then
        return false, "action_missing"
    end
    if action.class and action.class ~= context.class then
        return false, "class_mismatch"
    end
    if action.specIndex and action.specIndex ~= context.specIndex then
        return false, "spec_mismatch"
    end
    return true
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
})
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
    Context:Invalidate(event)
end)
