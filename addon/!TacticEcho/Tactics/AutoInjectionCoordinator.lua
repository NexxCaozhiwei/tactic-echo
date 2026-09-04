-- Single-owner coordinator for specialization-scoped Auto Injection groups.
-- It selects one group rule; the existing AutoBurst OrderedPlan executor remains
-- the only state machine and the only producer of Burst dispatch candidates.
local TE = _G.TacticEcho

local Coordinator = {
    schema = 1,
    activeGroupId = nil,
    matchedGroupId = nil,
    lastOfficialSpellID = nil,
    ignoredUntilDeparture = {},
    lastIgnoredGroupId = nil,
    lastIgnoredEvent = nil,
    lastReleaseReason = nil,
    lastResetReason = nil,
    lastConflict = nil,
    windowIndex = {},
    indexRevision = nil,
    indexContainer = nil,
    validation = nil,
}
TE.AutoInjectionCoordinator = Coordinator

local function positiveInteger(value)
    local ok, number = pcall(tonumber, value)
    if not ok or type(number) ~= "number" or number <= 0 then return nil end
    return math.floor(number)
end

local function markIgnored(self, groupId, event)
    if not groupId then return end
    self.ignoredUntilDeparture[groupId] = true
    self.lastIgnoredGroupId = groupId
    self.lastIgnoredEvent = event
end

function Coordinator:Reset(reason)
    self.activeGroupId = nil
    self.matchedGroupId = nil
    self.lastOfficialSpellID = nil
    self.ignoredUntilDeparture = {}
    self.lastIgnoredGroupId = nil
    self.lastIgnoredEvent = nil
    self.lastReleaseReason = nil
    self.lastResetReason = reason
    self.lastConflict = nil
    self.windowIndex = {}
    self.indexRevision = nil
    self.indexContainer = nil
    self.validation = nil
end

-- Cast-time window fencing is intentionally narrower than Observe().  It may
-- refresh the validated window index, but it never builds/selects a group rule,
-- claims ownership, changes the missed-window latch, or mutates the ordered
-- executor.  AutoBurst uses this read-only identity check to keep a configured
-- official window from leaking through the ordinary input path while a normal
-- cast is still in progress.
function Coordinator:MatchesEnabledWindow(context, officialSpellID)
    officialSpellID = positiveInteger(officialSpellID)
    if not officialSpellID then return false, nil, "official_spell_invalid" end
    local groups = TE.AutoInjectionGroups
    if not groups then return false, nil, "auto_injection_groups_unavailable" end
    local revision, container, profileKey, revisionReason = groups:GetRevision(context)
    if not container then return false, nil, revisionReason, profileKey end
    local validation = self.validation
    if self.indexContainer ~= container or self.indexRevision ~= revision or type(validation) ~= "table" then
        local reason
        validation, _, reason, container = groups:Validate(context)
        if not validation then return false, nil, reason, profileKey end
        local index = {}
        for _, id in ipairs(container.order or {}) do
            local group = container.groups[id]
            local windowSpellID = group and positiveInteger(group.windowSpellID) or nil
            if group and group.enabled == true and validation.valid[id] and windowSpellID then
                index[windowSpellID] = id
            end
        end
        self.windowIndex = index
        self.indexContainer = container
        self.indexRevision = revision
        self.validation = validation
    end
    self.lastConflict = validation.conflicts and validation.conflicts[1] or nil
    local matched = self.windowIndex[officialSpellID]
    return matched ~= nil, matched, matched and nil or "official_not_group_window", profileKey
end

function Coordinator:Observe(context, officialSpellID, executor)
    officialSpellID = positiveInteger(officialSpellID)
    local groups = TE.AutoInjectionGroups
    if not groups then return nil, "auto_injection_groups_unavailable" end
    local revision, container, profileKey, revisionReason = groups:GetRevision(context)
    if not container then return nil, revisionReason, nil, profileKey end
    local validation = self.validation
    if self.indexContainer ~= container or self.indexRevision ~= revision or type(validation) ~= "table" then
        local reason
        validation, _, reason, container = groups:Validate(context)
        if not validation then return nil, reason, nil, profileKey end
        local index = {}
        for _, id in ipairs(container.order or {}) do
            local group = container.groups[id]
            local windowSpellID = group and positiveInteger(group.windowSpellID) or nil
            if group and group.enabled == true and validation.valid[id] and windowSpellID then
                index[windowSpellID] = id
            end
        end
        self.windowIndex = index
        self.indexContainer = container
        self.indexRevision = revision
        self.validation = validation
    end
    self.lastConflict = validation.conflicts and validation.conflicts[1] or nil

    -- Leaving a group's window is the only way to clear a missed-window latch.
    for _, id in ipairs(container.order or {}) do
        local group = container.groups[id]
        if group and positiveInteger(group.windowSpellID) ~= officialSpellID then
            self.ignoredUntilDeparture[id] = nil
        end
    end

    local matched = officialSpellID and self.windowIndex[officialSpellID] or nil
    self.matchedGroupId = matched

    local owns = executor and (executor.plan ~= nil or executor.preWindowCapture ~= nil
        or executor.requireWindowDeparture == true)
    local ownerGroupId = executor and (executor.plan and executor.plan.groupId
        or executor.preWindowCapture and executor.preWindowCapture.rule
            and executor.preWindowCapture.rule.groupId
        or executor.requireWindowDeparture == true and executor.runtimeGroupId) or nil
    if owns and ownerGroupId then
        self:Claim(ownerGroupId)
    elseif not owns and self.activeGroupId then
        self:Release(self.activeGroupId, "stale_group_identity_released")
    end

    if owns and self.activeGroupId then
        if matched and matched ~= self.activeGroupId then
            markIgnored(self, matched, "group_window_ignored_while_owner_active")
        end
        local activeRule, activeReason = groups:BuildRule(context, self.activeGroupId)
        if not activeRule then return nil, activeReason or "active_group_invalid", self.activeGroupId, profileKey end
        local frozenRule = executor.plan and executor.plan.rule
            or executor.preWindowCapture and executor.preWindowCapture.rule
        if frozenRule and frozenRule.id ~= activeRule.id then
            return nil, "active_group_changed", self.activeGroupId, profileKey
        end
        return frozenRule or activeRule, nil, self.activeGroupId, profileKey
    end

    if not matched then
        self.lastOfficialSpellID = officialSpellID
        return nil, "official_not_group_window", nil, profileKey
    end
    if self.ignoredUntilDeparture[matched] == true then
        self.lastOfficialSpellID = officialSpellID
        return nil, "group_window_missed_while_busy", matched, profileKey
    end
    local rule, buildReason = groups:BuildRule(context, matched)
    if not rule then return nil, buildReason, matched, profileKey end
    self.lastOfficialSpellID = officialSpellID
    return rule, nil, matched, profileKey
end

function Coordinator:Claim(groupId)
    self.activeGroupId = groupId and tostring(groupId) or nil
end

function Coordinator:Release(groupId, reason)
    if groupId and self.activeGroupId == tostring(groupId) then self.activeGroupId = nil end
    self.lastReleaseReason = reason or self.lastReleaseReason
end

function Coordinator:GetDisplayGroupId()
    return self.activeGroupId or self.matchedGroupId
end

function Coordinator:GetSnapshot(context)
    local groups = TE.AutoInjectionGroups
    local group = groups and select(1, groups:GetDisplayGroup(context, self:GetDisplayGroupId())) or nil
    return {
        schema = 1,
        activeGroupId = self.activeGroupId,
        activeGroupName = self.activeGroupId and group and group.name or nil,
        matchedGroupId = self.matchedGroupId,
        displayGroupId = group and group.groupId or nil,
        displayGroupName = group and group.name or nil,
        groupWindowSpellID = group and positiveInteger(group.windowSpellID) or nil,
        lastIgnoredGroupId = self.lastIgnoredGroupId,
        lastIgnoredEvent = self.lastIgnoredEvent,
        lastReleaseReason = self.lastReleaseReason,
        lastResetReason = self.lastResetReason,
        groupConflict = self.lastConflict,
    }
end
