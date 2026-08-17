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
    self.lastIgnoredEvent = reason
    self.lastConflict = nil
    self.windowIndex = {}
    self.indexRevision = nil
    self.indexContainer = nil
    self.validation = nil
end

function Coordinator:Observe(context, officialSpellID, executor)
    officialSpellID = positiveInteger(officialSpellID)
    local groups = TE.AutoInjectionGroups
    if not groups then return nil, "auto_injection_groups_unavailable" end
    local revision, container, _, revisionReason = groups:GetRevision(context)
    if not container then return nil, revisionReason end
    local validation = self.validation
    if self.indexContainer ~= container or self.indexRevision ~= revision or type(validation) ~= "table" then
        local reason
        validation, _, reason, container = groups:Validate(context)
        if not validation then return nil, reason end
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

    -- A different group's window that first appears on the exact frame the
    -- prior owner releases its departure lock is still a missed window. It
    -- was observed while ownership belonged to the prior group and may only
    -- become eligible after leaving and entering again.
    if self.activeGroupId and matched and matched ~= self.activeGroupId then
        markIgnored(self, matched, "group_window_ignored_while_owner_active")
    end

    local owns = executor and (executor.plan ~= nil or executor.preWindowCapture ~= nil
        or executor.requireWindowDeparture == true)
    if owns and self.activeGroupId then
        if matched and matched ~= self.activeGroupId then
            markIgnored(self, matched, "group_window_ignored_while_owner_active")
        end
        local activeRule, activeReason = groups:BuildRule(context, self.activeGroupId)
        if not activeRule then return nil, activeReason or "active_group_invalid", self.activeGroupId end
        local frozenRule = executor.plan and executor.plan.rule
            or executor.preWindowCapture and executor.preWindowCapture.rule
        if frozenRule and frozenRule.id ~= activeRule.id then
            return nil, "active_group_changed", self.activeGroupId
        end
        return frozenRule or activeRule, nil, self.activeGroupId
    end

    if self.activeGroupId and not owns then self.activeGroupId = nil end
    if not matched then
        self.lastOfficialSpellID = officialSpellID
        return nil, "official_not_group_window"
    end
    if self.ignoredUntilDeparture[matched] == true then
        self.lastOfficialSpellID = officialSpellID
        return nil, "group_window_missed_while_busy", matched
    end
    local rule, buildReason = groups:BuildRule(context, matched)
    if not rule then return nil, buildReason, matched end
    self.lastOfficialSpellID = officialSpellID
    return rule, nil, matched
end

function Coordinator:Claim(groupId)
    self.activeGroupId = groupId and tostring(groupId) or nil
end

function Coordinator:Release(groupId, reason)
    if groupId and self.activeGroupId == tostring(groupId) then self.activeGroupId = nil end
    self.lastIgnoredEvent = reason or self.lastIgnoredEvent
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
        groupConflict = self.lastConflict,
    }
end
