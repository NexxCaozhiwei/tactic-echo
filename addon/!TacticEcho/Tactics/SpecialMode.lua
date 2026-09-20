-- User-selected substitutions of ordinary official dispatch only.
-- No events, timers, input channels or mutation of the official recommendation.
local TE = _G.TacticEcho
local Mode = {}
TE.SpecialMode = Mode

local function spellID(value)
    local n = tonumber(value)
    if n and n > 0 and n < 2147483647 and n == math.floor(n) then return n end
end

function Mode:IsEnabled()
    return TacticEchoDB and TacticEchoDB.settings and TacticEchoDB.settings.specialModeEnabled == true
end

function Mode:GetGroups(context, create)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local key = TE.BurstProfiles and TE.BurstProfiles:SpecKey(context.classFile or context.class, context.specIndex)
    if not key then return nil end
    local db = TacticEchoDB
    if not db then return nil end
    if create then
        db.tactics = type(db.tactics) == "table" and db.tactics or {}
        db.tactics.specialModeProfiles = type(db.tactics.specialModeProfiles) == "table" and db.tactics.specialModeProfiles or {}
    end
    local profiles = db.tactics and db.tactics.specialModeProfiles
    if type(profiles) ~= "table" then return nil end
    if create then
        profiles[key] = type(profiles[key]) == "table" and profiles[key] or {}
        for i = 1, 3 do
            if type(profiles[key][i]) ~= "table" then profiles[key][i] = { enabled = false } end
        end
    end
    return type(profiles[key]) == "table" and profiles[key] or nil, key
end

function Mode:Configure(index, source, target, enabled)
    if index ~= 1 and index ~= 2 and index ~= 3 then return false, "组编号无效" end
    source, target = spellID(source), spellID(target)
    if not source or not target or source == target then return false, "请填写两个不同的数字 SpellID" end
    local groups = self:GetGroups(nil, true)
    if not groups then return false, "等待当前专精" end
    for i = 1, 3 do
        local other = groups[i]
        if i ~= index and enabled and other.enabled == true and spellID(other.sourceSpellID) == source then
            return false, "已启用组的原技能不能重复"
        end
    end
    groups[index] = { sourceSpellID = source, targetSpellID = target, enabled = enabled == true }
    return true
end

function Mode:Select(source, context)
    if not self:IsEnabled() then return nil end
    local groups = self:GetGroups(context, false)
    local selected
    for i = 1, 3 do
        local group = groups and groups[i]
        if type(group) == "table" and group.enabled == true and spellID(group.sourceSpellID) == source then
            if selected then return { reason = "special_mode_duplicate_source" } end
            local target = spellID(group.targetSpellID)
            selected = { groupIndex = i, spellID = target ~= source and target or nil,
                reason = "special_mode_invalid_target" }
        end
    end
    return selected
end

-- The replacement does not inherit readiness from the official AOE spell.
function Mode:CanDispatch(target, binding, snapshot)
    local resolver = TE.ActionBarBindingResolver
    if not binding or binding.status ~= "Ready" or (tonumber(binding.bindingToken) or 0) <= 0 then
        return false, "special_mode_unbound"
    end
    if binding.specialActionBar and binding.specialActionBar.active then return false, "special_mode_special_actionbar" end
    if binding.source == "macro" and (not resolver or not resolver.IsVerifiedCurrentMacroSource
        or resolver:IsVerifiedCurrentMacroSource(binding) ~= true) then return false, "special_mode_macro_unverified" end
    if not TE.RuntimeSnapshot or not snapshot then return false, "special_mode_snapshot_missing" end
    local icon = TE.RuntimeSnapshot:CollectSpellCooldown(snapshot, target, binding, { liveCooldown = true })
    if type(icon) ~= "table" then return false, "special_mode_cooldown_unknown" end
    local ready = false
    if (tonumber(icon.maxCharges) or 0) > 1 then
        ready = (tonumber(icon.charges) or 0) > 0
    elseif icon.cooldownKnown == true then
        ready = icon.cooldownActive ~= true or icon.cooldownOnGCD == true or icon.cooldownGcdAlias == true
    elseif icon.cooldownPublicActiveKnown == true then
        ready = icon.cooldownPublicActive == false or (icon.cooldownPublicActive == true
            and icon.cooldownPublicOnGCDKnown == true and icon.cooldownPublicOnGCD == true)
    end
    if not ready then return false, "special_mode_wait_cooldown" end
    if not TE.GCDGate then return false, "special_mode_gcd_unknown" end
    local phase = TE.GCDGate:Classify(TE.GCDGate:BeginCycle(nil, snapshot))
    if phase ~= "READY_NOW" and phase ~= "QUEUE_WINDOW" then return false, "special_mode_wait_gcd" end
    return true, "special_mode_replacement"
end
