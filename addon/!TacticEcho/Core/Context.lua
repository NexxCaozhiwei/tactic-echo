local TE = _G.TacticEcho

local Context = {}
TE.Context = Context

function Context:GetPlayer()
    local className, classFile = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID, specName

    if specIndex and GetSpecializationInfo then
        specID, specName = GetSpecializationInfo(specIndex)
    end

    return {
        className = className,
        class = classFile,
        specIndex = specIndex,
        specID = specID,
        specName = specName,
        locale = GetLocale and GetLocale() or "unknown",
        inCombat = InCombatLockdown and InCombatLockdown() or false,
    }
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
