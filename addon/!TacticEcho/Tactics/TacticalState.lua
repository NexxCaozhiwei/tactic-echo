-- Tactic Echo tactical state bus.
-- The HUD renders the message already built for TEAP, which prevents UI and
-- dispatch drift.  A small session-only transition ledger is maintained only
-- for read-only candidate previews; it never writes into the dispatch path.
local TE = _G.TacticEcho

local TacticalState = {}
TE.TacticalState = TacticalState

local latest
local listeners = {}
local listenerSequence = 0
local history = {}
local lastHistorySignature
local transitions = {}
local transitionSources = {}
local MAX_HISTORY = 8
local MAX_TRANSITION_SOURCES = 48
-- TEAP freshness advances at 20 Hz, while HUD/listener consumers only need
-- state/recommendation transitions plus a modest liveness heartbeat.
local PUBLISH_HEARTBEAT_SECONDS = 0.50
local lastPublishSignature
local lastPublishedAt = 0

local reasonText = {
    chat_input_active = "聊天输入中",
    keyboard_focus_active = "文本输入焦点中",
    chat_editbox_active = "聊天输入框中",
    macro_editor_active = "宏编辑界面中",
    keybinding_editor_active = "按键绑定界面中",
    static_popup_active = "弹窗界面中",
    static_popup_edit_active = "弹窗输入中",
    player_channeling = "玩家正在引导",
    player_empowering = "玩家正在蓄力",
    out_of_combat_policy_pause = "脱战策略暂停",
    out_of_combat_auto_standby = "未进战斗，自动启停待命",
    actionbar_spell_not_found = "动作条未找到技能",
    binding_missing = "技能没有现实按键绑定",
    binding_token_invalid = "按键不在支持范围",
    spell_missing = "官方推荐为空",
    spell_unmapped = "旧目录未登记（不影响 v3）",
    special_actionbar_vehicle = "载具动作条已阻断",
    special_actionbar_possess = "控制单位动作条已阻断",
    special_actionbar_override = "覆盖动作条已阻断",
    special_actionbar_pet_battle = "宠物对战动作条已阻断",
}

local function spellInfo(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return nil, nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name, info.iconID or info.icon end
        if ok and type(info) == "string" then return info, nil end
    end
    if type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
    return nil, nil
end

local function snapshotFrom(message, encoded)
    if type(message) ~= "table" then return nil end
    local dispatchBinding = message.bindingInfo or {}
    -- Observation-only burst frames have no dispatch BindingToken by design.
    -- Their HUD card should nevertheless retain the official action-bar label
    -- and never be styled as “无绑定”.
    local officialBinding = message.officialBindingInfo or {}
    local binding = message.observationOnly == true and officialBinding or (message.bindingInfo or officialBinding)
    if type(binding) ~= "table" then binding = {} end
    local state = message.state or "waiting"
    local reason = message.unresolvedReason or message.bindingReason
    local dispatchSpellID = tonumber(message.dispatchSpellID or message.spellID)
    local officialSpellID = tonumber(message.officialSpellID or message.spellID)
    local spellID = dispatchSpellID or officialSpellID
    local spellName, spellIcon = spellInfo(spellID)
    local officialSpellName, officialSpellIcon = spellInfo(officialSpellID)
    local dispatchAllowed = state == "armed" and message.observationOnly ~= true
        and (tonumber(message.bindingToken) or 0) > 0
    local channelingActive = message.channelingActive == true
    local empoweringActive = message.empoweringActive == true
    -- `displayState` remains HUD-only. The actual encoded state now carries
    -- `channeling` / `empowering`; TEK treats both as non-dispatchable and only
    -- resumes after a fresh armed frame.
    local displayState
    if state == "channeling" and reason == "player_channeling" and channelingActive then
        displayState = "channeling_lock"
    elseif state == "empowering" and reason == "player_empowering" and empoweringActive then
        displayState = "empowering_lock"
    elseif state == "paused" and reason == "out_of_combat_auto_standby" then
        displayState = "standby"
    end
    return {
        sequence = tonumber(message.sequence) or 0,
        freshness = tonumber(message.frameFreshnessCounter) or 0,
        observedAt = type(GetTime) == "function" and GetTime() or 0,
        spellID = spellID,
        spellName = spellName or "无官方推荐",
        spellIcon = spellIcon,
        officialSpellID = officialSpellID,
        officialSpellName = officialSpellName or "无官方推荐",
        officialSpellIcon = officialSpellIcon,
        dispatchSpellID = dispatchSpellID,
        dispatchOrigin = message.dispatchOrigin or "official",
        burstPlan = type(message.burstPlan) == "table" and message.burstPlan or nil,
        observationOnly = message.observationOnly == true,
        observationReason = message.observationReason,
        officialSource = "C_AssistedCombat",
        state = state,
        intentState = message.intentState or "waiting",
        reason = reason,
        reasonText = TacticalState:DescribeReason(reason),
        dispatchAllowed = dispatchAllowed,
        inCombat = message.inCombat == true,
        -- `rawBinding` is presentation metadata only.  Unsupported dispatch
        -- modifiers still keep BindingToken=0 and dispatchAllowed=false.
        binding = message.binding or binding.binding or binding.rawBinding,
        rawBinding = binding.rawBinding,
        -- Keep this as the transport token (zero for observation frames), not
        -- the display-only official binding token.
        bindingToken = tonumber(message.bindingToken) or 0,
        displayBindingToken = tonumber(binding.bindingToken) or nil,
        dispatchBindingToken = tonumber(message.bindingToken) or 0,
        bindingStatus = binding.status,
        bindingSource = binding.source,
        bindingButton = binding.buttonName,
        bindingSlot = binding.actionSlot or binding.slot,
        -- Canonical action-bar identity is presentation metadata only, but it
        -- lets the primary HUD card use the same local cooldown key as burst,
        -- interrupt, control and defensive cards for transformed spells.
        actionSlot = binding.actionSlot or binding.slot,
        slot = binding.actionSlot or binding.slot,
        directActionSlot = binding.directActionSlot == true,
        actionBarStateTrusted = binding.actionBarStateTrusted == true,
        requestedSpellID = binding.requestedSpellID or spellID,
        matchedSpellID = binding.matchedSpellID,
        equivalentSpellIDs = binding.equivalentSpellIDs,
        bindingBar = binding.bar,
        bindingCommand = binding.bindingCommand,
        bindingCacheGeneration = binding.cacheGeneration,
        -- The resolver already read this state while resolving the same
        -- recommendation. Keep it on the published snapshot for UI/diagnostic
        -- rendering; never use it to create a second recommendation read.
        specialActionBar = binding.specialActionBar,
        channeling = {
            active = channelingActive,
            name = message.channelingName,
            spellID = tonumber(message.channelingSpellID) or nil,
            startTimeMS = tonumber(message.channelingStartTimeMS) or nil,
            endTimeMS = tonumber(message.channelingEndTimeMS) or nil,
        },
        empowering = {
            active = empoweringActive,
            name = message.empoweringName,
            spellID = tonumber(message.empoweringSpellID) or nil,
        },
        casting = {
            active = message.castingActive == true,
            kind = message.castingKind,
            name = message.castingName,
            spellID = tonumber(message.castingSpellID) or nil,
            startTimeMS = tonumber(message.castingStartTimeMS) or nil,
            endTimeMS = tonumber(message.castingEndTimeMS) or nil,
        },
        displayState = displayState,
        monitor = message.monitor or (encoded and encoded.monitor) or {},
        encodedProtocol = encoded and encoded.protocolVersion or nil,
        encodedFlags = encoded and encoded.monitorFlags or 0,
    }
end

local function trimTransitions()
    while #transitionSources > MAX_TRANSITION_SOURCES do
        local source = table.remove(transitionSources, 1)
        transitions[source] = nil
    end
end

local function recordTransition(previous, current)
    if not previous or not current or not previous.spellID or not current.spellID then return end
    if previous.spellID == current.spellID then return end
    local source = tostring(previous.spellID)
    local target = tostring(current.spellID)
    local bucket = transitions[source]
    if not bucket then
        bucket = { total = 0, targets = {}, lastObservedAt = 0 }
        transitions[source] = bucket
        transitionSources[#transitionSources + 1] = source
        trimTransitions()
    end
    bucket.total = (tonumber(bucket.total) or 0) + 1
    bucket.lastObservedAt = current.observedAt or 0
    local entry = bucket.targets[target] or { spellID = current.spellID, count = 0, lastObservedAt = 0 }
    entry.count = (tonumber(entry.count) or 0) + 1
    entry.lastObservedAt = current.observedAt or 0
    bucket.targets[target] = entry
end

local function recordHistory(snapshot)
    if not snapshot or not snapshot.spellID then return end
    -- Consecutive refreshes of the same official recommendation are not a new
    -- transition observation.  This avoids fabricating confidence from frame rate.
    local signature = table.concat({
        tostring(snapshot.spellID), tostring(snapshot.binding), tostring(snapshot.state),
    }, ":")
    if signature == lastHistorySignature then return end
    lastHistorySignature = signature
    local previous = history[#history]
    local current = {
        spellID = snapshot.officialSpellID or snapshot.spellID,
        spellName = snapshot.officialSpellName or snapshot.spellName,
        spellIcon = snapshot.officialSpellIcon or snapshot.spellIcon,
        binding = snapshot.binding,
        state = snapshot.state,
        observedAt = snapshot.observedAt,
    }
    recordTransition(previous, current)
    history[#history + 1] = current
    while #history > MAX_HISTORY do table.remove(history, 1) end
end

function TacticalState:DescribeReason(reason)
    if not reason or reason == "" then return "无" end
    return reasonText[reason] or tostring(reason)
end

local function publishSignature(message)
    local binding = message and message.bindingInfo or {}
    local officialBinding = message and message.officialBindingInfo or {}
    return table.concat({
        tostring(message and message.state or "waiting"),
        tostring(message and message.intentState or "waiting"),
        tostring(message and message.actionCode or 0),
        tostring(message and message.actionId or ""),
        tostring(message and message.officialSpellID or message and message.spellID or 0),
        tostring(message and message.dispatchSpellID or message and message.spellID or 0),
        tostring(message and message.dispatchOrigin or "official"),
        tostring(message and message.inCombat == true),
        tostring(message and message.bindingToken or 0),
        tostring(message and message.observationOnly == true and (officialBinding.binding or officialBinding.rawBinding) or ""),
        tostring(message and message.bindingReason or ""),
        tostring(binding and binding.source or ""),
        tostring(message and message.sessionPolicy or ""),
        tostring(message and message.sessionPolicyReason or ""),
        tostring(message and message.inputFocusActive == true),
        tostring(message and message.channelingActive == true),
        tostring(message and message.empoweringActive == true),
    }, ":")
end

function TacticalState:Publish(message, encoded)
    local now = type(GetTime) == "function" and GetTime() or 0
    local signature = publishSignature(message)
    local stateChanged = signature ~= lastPublishSignature
    local heartbeatDue = latest == nil or (now - (lastPublishedAt or 0)) >= PUBLISH_HEARTBEAT_SECONDS
    if not stateChanged and not heartbeatDue then
        return latest
    end
    latest = snapshotFrom(message, encoded)
    lastPublishSignature = signature
    lastPublishedAt = now
    recordHistory(latest)
    for _, callback in pairs(listeners) do
        pcall(callback, latest)
    end
    return latest
end

function TacticalState:GetSnapshot()
    return latest
end

function TacticalState:GetHistory(limit)
    local result = {}
    local count = tonumber(limit) or #history
    for index = math.max(1, #history - count + 1), #history do
        result[#result + 1] = history[index]
    end
    return result
end

function TacticalState:GetTransitionCandidates(spellID, limit)
    local bucket = transitions[tostring(tonumber(spellID) or "")]
    local result = {}
    if not bucket then return result, 0 end
    local total = tonumber(bucket.total) or 0
    for _, entry in pairs(bucket.targets or {}) do
        local name, icon = spellInfo(entry.spellID)
        result[#result + 1] = {
            spellID = entry.spellID,
            spellName = name or tostring(entry.spellID),
            spellIcon = icon,
            observations = tonumber(entry.count) or 0,
            totalObservations = total,
            confidence = total > 0 and ((tonumber(entry.count) or 0) / total) or 0,
            lastObservedAt = entry.lastObservedAt,
            source = "observed_transition",
            advisoryOnly = true,
        }
    end
    table.sort(result, function(a, b)
        if a.observations ~= b.observations then return a.observations > b.observations end
        if a.lastObservedAt ~= b.lastObservedAt then return (a.lastObservedAt or 0) > (b.lastObservedAt or 0) end
        return (a.spellID or 0) < (b.spellID or 0)
    end)
    local maximum = math.max(0, tonumber(limit) or #result)
    while #result > maximum do table.remove(result) end
    return result, total
end

function TacticalState:GetTransitionSummary(spellID)
    local bucket = transitions[tostring(tonumber(spellID) or "")]
    local distinct = 0
    for _ in pairs((bucket and bucket.targets) or {}) do distinct = distinct + 1 end
    return {
        observedTransitions = bucket and (tonumber(bucket.total) or 0) or 0,
        distinctCandidates = distinct,
        sessionOnly = true,
    }
end

function TacticalState:Subscribe(callback)
    if type(callback) ~= "function" then return nil end
    listenerSequence = listenerSequence + 1
    listeners[listenerSequence] = callback
    return listenerSequence
end

function TacticalState:Unsubscribe(token)
    listeners[token] = nil
end
