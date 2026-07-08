local TE = _G.TacticEcho

local SignalFrame = {}
TE.SignalFrame = SignalFrame

-- TEAP v3 uses the same 20-byte field layout and colour encoding as before.
-- Only its raster geometry is adaptive: TEK locates the fixed client-top-left
-- header (T/E/3) and derives the physical pitch at runtime.
local DEFAULT_BLOCK_SIZE = 10
local DEFAULT_BLOCK_GAP = 2
local CLIENT_ANCHOR_MARGIN_PX = 8
local MIN_BLOCK_SIZE_PX = 8
-- TEK samples at 50 ms by default. Keep TEAP freshness at the same cadence so
-- startup, manual-release recovery and combat-policy transitions do not spend
-- multiple 200 ms UI ticks waiting for a new frame.
local UPDATE_INTERVAL = 0.05
-- Match WR's practical Assisted Combat cadence for expensive recommendation
-- and binding work while keeping TEAP freshness at 50 ms for TEK sampling.
local OFFICIAL_RECOMMENDATION_REBUILD_INTERVAL = 0.10
local SESSION_POLICIES = {
    manual_keep = true,
    pause_out_of_combat = true,
    close_out_of_combat = true,
}

local frame
local blocks = {}
local elapsedSinceUpdate = 0
    -- `state` is the user/session intent. The encoded state may temporarily be
    -- non-dispatchable by auto start/stop policy or a focused text input without
    -- altering that intent.
local state = "waiting"
local sequence = 0
local frameFreshnessCounter = 0
local sessionEpoch
local lastSignature
local lastRememberedSignature
local lastMessage
local lastEncoded
local lastPaintedFields
local lastGeometrySignature
local activeBlockSize = DEFAULT_BLOCK_SIZE
local activeBlockGap = DEFAULT_BLOCK_GAP
local lastFullBuildAt = 0
local activeAnchorMargin = CLIENT_ANCHOR_MARGIN_PX
local STATE_SOUND_FILES = {
    armed = "Interface\\AddOns\\!TacticEcho\\Media\\te-armed-123.wav",
    paused = "Interface\\AddOns\\!TacticEcho\\Media\\te-paused-321.wav",
}

local function newSessionEpoch()
    local seconds = 1
    if type(GetServerTime) == "function" then seconds = GetServerTime()
    elseif type(time) == "function" then seconds = time() end
    local fraction = 0
    if type(GetTime) == "function" then fraction = math.floor((GetTime() % 1) * 1000) end
    return ((seconds + fraction) % 65535) + 1
end
sessionEpoch = newSessionEpoch()

local function ensureStore()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.signal = TacticEchoDB.signal or {}
    TacticEchoDB.signal.frames = TacticEchoDB.signal.frames or {}
    -- v2-era bySequence was unbounded and had no runtime consumer. Remove any
    -- persisted copy on load; recent frames + last retain the supported export.
    TacticEchoDB.signal.bySequence = nil
    TacticEchoDB.signal.castLockTransitions = TacticEchoDB.signal.castLockTransitions or {}
    TacticEchoDB.settings = TacticEchoDB.settings or {}
    return TacticEchoDB.signal, TacticEchoDB.settings
end

local function getSessionPolicy()
    local _, settings = ensureStore()
    local policy = settings.sessionPolicy
    if not SESSION_POLICIES[policy] then
        policy = "pause_out_of_combat"
        settings.sessionPolicy = policy
    end
    return policy
end

function SignalFrame:GetSessionPolicy()
    return getSessionPolicy()
end

function SignalFrame:SetSessionPolicy(policy)
    if not SESSION_POLICIES[policy] then return false, "invalid_session_policy" end
    local _, settings = ensureStore()
    settings.sessionPolicy = policy

    -- Apply "脱战停止" immediately when the player selects it while already
    -- out of combat. Otherwise no combat transition may arrive to convert the
    -- armed intent to the sticky paused intent requested by that policy.
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    if policy == "close_out_of_combat" and state == "armed" and not inCombat then
        self:SetState("paused")
    elseif frame and frame:IsShown() then
        self:Refresh("session_policy")
    end
    return true
end

function SignalFrame:GetSessionPolicyLabel()
    local labels = {
        manual_keep = "手动启停（脱战保持运行）",
        pause_out_of_combat = "自动启停（进战运行，脱战待命，默认）",
        close_out_of_combat = "脱战停止（进战需手动运行）",
    }
    return labels[getSessionPolicy()] or getSessionPolicy()
end

local MAX_SIGNAL_FRAMES = 60

local function remember(encoded, reason)
    local signature = table.concat({
        tostring(encoded.sequence or 0),
        tostring(encoded.state or "unknown"),
        tostring(reason or "tick"),
    }, ":")
    if signature == lastRememberedSignature then return end
    lastRememberedSignature = signature

    local store = ensureStore()
    local record = {
        schemaVersion = 2,
        component = "TE",
        eventType = "signal_frame",
        protocolVersion = encoded.protocolVersion,
        sessionEpoch = encoded.sessionEpoch,
        frameFreshnessCounter = encoded.frameFreshnessCounter,
        catalogVersion = encoded.actionCatalogVersion,
        catalogFingerprint = encoded.catalogFingerprint,
        bindingToken = encoded.bindingToken,
        binding = encoded.binding,
        bindingReason = encoded.bindingReason,
        bindingSource = encoded.bindingSource,
        bindingButton = encoded.bindingButton,
        bindingSlot = encoded.bindingSlot,
        bindingCacheGeneration = encoded.bindingCacheGeneration,
        macroName = encoded.macroName,
        macroId = encoded.macroId,
        macroCommand = encoded.macroCommand,
        inputFocusActive = encoded.inputFocusActive,
        inputFocusReason = encoded.inputFocusReason,
        channelingActive = encoded.channelingActive,
        channelingName = encoded.channelingName,
        channelingSpellID = encoded.channelingSpellID,
        empoweringActive = encoded.empoweringActive,
        empoweringName = encoded.empoweringName,
        empoweringSpellID = encoded.empoweringSpellID,
        sessionPolicy = encoded.sessionPolicy,
        sessionPolicyReason = encoded.sessionPolicyReason,
        actionRegistryReason = encoded.legacyCatalogReason,
        monitor = encoded.monitor,
        monitorFlags = encoded.monitorFlags,
        dispatchOrigin = encoded.dispatchOrigin,
        officialSpellID = encoded.officialSpellID,
        dispatchSpellID = encoded.dispatchSpellID,
        burstPlan = encoded.burstPlan,
        reaction = encoded.reaction,
        observedAt = date("%Y-%m-%d %H:%M:%S"),
        elapsed = GetTime and GetTime() or 0,
        reason = reason,
        state = encoded.state,
        intentState = encoded.intentState,
        sequence = encoded.sequence,
        actionCode = encoded.actionCode,
        actionId = encoded.actionId,
        spellID = encoded.spellID,
        inCombat = encoded.inCombat,
        dispatchState = encoded.observationOnly and "observation_only" or encoded.state,
        checksum = encoded.checksum,
        fields = encoded.fields,
    }
    store.last = record
    store.frames[#store.frames + 1] = record
    while #store.frames > MAX_SIGNAL_FRAMES do table.remove(store.frames, 1) end
end

-- UIParent dimensions are expressed in WoW UI units, while TEK samples
-- physical desktop pixels.  Keep each cell at least eight physical pixels
-- wide and keep the strip anchored at an eight-pixel client inset regardless
-- of UI scale.  Gap may visually collapse at extreme scaling; TEK's v3
-- header locator intentionally supports a zero-pixel physical gap.
local function currentGeometry()
    local scale = 1
    if UIParent and type(UIParent.GetEffectiveScale) == "function" then
        scale = tonumber(UIParent:GetEffectiveScale()) or 1
    end
    if scale <= 0 then scale = 1 end

    local blockSize = math.max(DEFAULT_BLOCK_SIZE, math.ceil(MIN_BLOCK_SIZE_PX / scale))
    local blockGap = math.max(0, DEFAULT_BLOCK_GAP)
    local anchorMargin = math.max(0, math.ceil(CLIENT_ANCHOR_MARGIN_PX / scale))
    return blockSize, blockGap, anchorMargin, scale
end

local function applyGeometry()
    if not frame then return end
    local blockSize, blockGap, anchorMargin, scale = currentGeometry()
    local signature = table.concat({ blockSize, blockGap, anchorMargin, string.format("%.4f", scale) }, ":")
    if signature == lastGeometrySignature then return end
    lastGeometrySignature = signature

    activeBlockSize = blockSize
    activeBlockGap = blockGap
    activeAnchorMargin = anchorMargin

    frame:SetSize((blockSize + blockGap) * 20 - blockGap, blockSize)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", anchorMargin, -anchorMargin)

    for index, block in ipairs(blocks) do
        block:SetSize(blockSize, blockSize)
        block:ClearAllPoints()
        block:SetPoint("LEFT", frame, "LEFT", (index - 1) * (blockSize + blockGap), 0)
    end
end

function SignalFrame:GetGeometry()
    return {
        anchor = "client_top_left",
        anchorMargin = activeAnchorMargin,
        blockSize = activeBlockSize,
        blockGap = activeBlockGap,
        blockCount = 20,
    }
end

local function paint(encoded)
    applyGeometry()
    local fields = encoded.fields or {}
    -- TEAP freshness advances every 50 ms, but most stable frames change only
    -- freshness/CRC bytes. Cache the previous field values so WoW only updates
    -- textures whose encoded colour actually changed.
    lastPaintedFields = lastPaintedFields or {}
    local count = math.min(#fields, #blocks)
    for index = 1, count do
        local value = tonumber(fields[index]) or 0
        if lastPaintedFields[index] ~= value then
            local block = blocks[index]
            if block then
                local red = value / 255
                block:SetColorTexture(red, 1 - red, 17 / 255, 1)
            end
            lastPaintedFields[index] = value
        end
    end
    for index = count + 1, #lastPaintedFields do
        lastPaintedFields[index] = nil
    end
end

local function createFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "TacticEchoSignalFrame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:Hide()
    for index = 1, 20 do
        local block = frame:CreateTexture(nil, "ARTWORK")
        block:SetColorTexture(0, 0, 0, 1)
        blocks[index] = block
    end
    applyGeometry()
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceUpdate = elapsedSinceUpdate + elapsed
        if elapsedSinceUpdate < UPDATE_INTERVAL then return end
        elapsedSinceUpdate = 0
        SignalFrame:Refresh("tick")
    end)
    return frame
end

function SignalFrame:SetState(nextState)
    local previousState = state
    state = nextState or "waiting"
    -- Every state, including waiting, remains continuously observable through
    -- the 20-block TEAP strip.  Hiding the frame after a single disarmed paint
    -- made a deliberate plugin stop indistinguishable from signal loss and
    -- caused TEK to fall into screen-read recovery rather than a clean
    -- non-dispatchable state.
    createFrame():Show()
    if state ~= previousState and STATE_SOUND_FILES[state] and type(PlaySoundFile) == "function" then
        pcall(PlaySoundFile, STATE_SOUND_FILES[state], "SFX")
    end
    -- P5.8: SetState("armed") does not authorize any out-of-combat Burst
    -- path. AutoBurst itself enforces the in-combat boundary before it can
    -- create a capture, plan or candidate.
    self:Refresh("state")
end

function SignalFrame:GetState()
    return state
end

-- Forward declarations: the effective-state accessor is defined before the
-- helper implementations below, but must retain their local bindings.
local isTextInputActive
local getPlayerCastLockInfo
-- Cast locks are event-derived safety gates.  They retain only display-safe
-- spell identity metadata; no lock detail enters TEAP state coding or TEK
-- dispatch decisions.  `castGUID` remains opaque and is only used in-memory
-- to fail closed when a terminal Channel or Empower event does not match the
-- active cast that established the lock.
local playerCastLock = {
    active = false,
    kind = nil,
    source = nil,
    castGUID = nil,
    name = nil,
    spellID = nil,
    startTimeMS = nil,
    endTimeMS = nil,
}

local function castLockReason(castLock)
    if castLock and castLock.active == true and castLock.kind == "empower" then
        return "player_empowering"
    end
    return "player_channeling"
end

-- Field 4 carries a dedicated lock state while a player channel or Empower is
-- active.  These states are still non-dispatchable; they exist so TEK can
-- distinguish an active cast lock from a generic paused frame without adding
-- any new input path or timing behavior.
local function castLockState(castLock)
    if castLock and castLock.active == true and castLock.kind == "empower" then
        return "empowering"
    end
    return "channeling"
end

function SignalFrame:GetEffectiveState()
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    if state ~= "armed" then return state, nil end
    local inputFocusActive, inputFocusReason = isTextInputActive()
    if inputFocusActive then return "manual_hold", inputFocusReason end
    local castLock = self:GetCastLockInfo()
    if castLock.active then return castLockState(castLock), castLockReason(castLock) end
    local policy = getSessionPolicy()
    -- pause_out_of_combat is the auto start/stop policy: it preserves the armed
    -- intent and only encodes a non-dispatchable paused TEAP frame while out of
    -- combat. Display layers present that reason as standby, not manual pause.
    if not inCombat and policy == "pause_out_of_combat" then return "paused", "out_of_combat_auto_standby" end
    -- close_out_of_combat is event-driven: PLAYER_REGEN_ENABLED changes the
    -- intent itself to paused. That paused intent remains sticky through the
    -- next PLAYER_REGEN_DISABLED until the user explicitly arms TE again.
    return "armed", nil
end

local function shownFrame(name)
    local candidate = _G[name]
    return candidate and type(candidate.IsShown) == "function" and candidate:IsShown()
end

local function frameHasKeyboardFocus(candidate)
    if not candidate then return false end
    if type(candidate.HasFocus) == "function" and candidate:HasFocus() then return true end
    if type(candidate.IsShown) == "function" and candidate:IsShown() then
        local name = type(candidate.GetName) == "function" and candidate:GetName() or ""
        if type(name) == "string" and name:find("EditBox", 1, true) then return true end
    end
    return false
end

isTextInputActive = function()
    if type(ChatEdit_GetActiveWindow) == "function" then
        local active = ChatEdit_GetActiveWindow()
        if active then return true, "chat_input_active" end
    end
    for _, focusApi in ipairs({ GetCurrentKeyBoardFocus, GetCurrentKeyboardFocus }) do
        if type(focusApi) == "function" then
            local focused = focusApi()
            if focused then return true, "keyboard_focus_active" end
        end
    end
    for index = 1, 10 do
        if frameHasKeyboardFocus(_G["ChatFrame" .. index .. "EditBox"]) then return true, "chat_editbox_active" end
    end
    if shownFrame("MacroFrame") then return true, "macro_editor_active" end
    if shownFrame("KeyBindingFrame") then return true, "keybinding_editor_active" end
    for index = 1, 4 do
        local popup = _G["StaticPopup" .. index]
        local edit = _G["StaticPopup" .. index .. "EditBox"]
        if frameHasKeyboardFocus(edit) then return true, "static_popup_edit_active" end
        if popup and type(popup.IsShown) == "function" and popup:IsShown() then return true, "static_popup_active" end
    end
    return false, nil
end

function SignalFrame:IsInputFocusActive()
    return isTextInputActive()
end

-- Channel / Empower safety remains event-driven: events keep the fail-closed
-- pause in place even if one display API omits a transient detail.  `UnitChannelInfo`
-- returns `isEmpowered` for Empower casts, so it must never be allowed to
-- reclassify or overwrite a dedicated Empower lock as an ordinary channel.
-- Neither path changes the TEAP protocol.
local MAX_CAST_LOCK_TRANSITIONS = 60

local function plainChannelNumber(value)
    local ok, number = pcall(function()
        local converted = tonumber(value)
        if type(converted) ~= "number" or converted <= 0 then return nil end
        return converted
    end)
    return ok and number or nil
end

local function plainBoolean(value)
    local ok, result = pcall(function()
        return value == true
    end)
    return ok and result == true
end

local function plainCastGUID(value)
    local ok, result = pcall(function()
        if type(value) ~= "string" then return nil end
        -- Secret or otherwise non-ordinary strings fail this probe inside the
        -- protected block.  In that case terminal events cannot unlock an
        -- event-owned lock and the dispatch path stays fail-closed.
        if #value <= 0 then return nil end
        return value
    end)
    return ok and result or nil
end

local function matchingCastGUID(left, right)
    if left == nil or right == nil then return false end
    local ok, matches = pcall(function()
        return left == right
    end)
    return ok and matches == true
end

local function castLockSnapshot()
    return {
        active = playerCastLock.active == true,
        kind = playerCastLock.kind,
        source = playerCastLock.source,
        spellID = plainChannelNumber(playerCastLock.spellID),
        hasCastGUID = playerCastLock.castGUID ~= nil,
    }
end

-- This is local SavedVariables diagnostics only. It intentionally records
-- neither raw castGUID nor timing data, and never enters TEAP/TEK payloads.
local function rememberCastLockTransition(eventName, outcome, before, eventSpellID)
    local store = ensureStore()
    local transitions = store.castLockTransitions
    local after = castLockSnapshot()
    local record = {
        schemaVersion = 1,
        component = "TE",
        eventType = "cast_lock_transition",
        observedAt = date("%Y-%m-%d %H:%M:%S"),
        elapsed = GetTime and GetTime() or 0,
        event = eventName,
        outcome = outcome,
        eventSpellID = plainChannelNumber(eventSpellID),
        beforeActive = before and before.active == true or false,
        beforeKind = before and before.kind or nil,
        beforeSource = before and before.source or nil,
        beforeSpellID = before and before.spellID or nil,
        beforeHasCastGUID = before and before.hasCastGUID == true or false,
        afterActive = after.active,
        afterKind = after.kind,
        afterSource = after.source,
        afterSpellID = after.spellID,
        afterHasCastGUID = after.hasCastGUID,
    }
    store.lastCastLockTransition = record
    transitions[#transitions + 1] = record
    while #transitions > MAX_CAST_LOCK_TRANSITIONS do table.remove(transitions, 1) end
end

local function readUnitChannelInfo(fallbackSpellID)
    if type(UnitChannelInfo) ~= "function" then return nil, false end
    -- Retail returns: name, displayName, textureID, startTimeMS, endTimeMS,
    -- isTradeskill, notInterruptible, spellID, isEmpowered, numEmpowerStages.
    local ok, name, _, _, startTimeMS, endTimeMS, _, _, spellID, isEmpowered = pcall(UnitChannelInfo, "player")
    if not ok then return nil, true end
    if not name then return nil, true end
    local empowered = plainBoolean(isEmpowered)
    return {
        active = true,
        kind = empowered and "empower" or "channel",
        isEmpowered = empowered,
        name = name,
        spellID = plainChannelNumber(spellID) or plainChannelNumber(fallbackSpellID),
        startTimeMS = plainChannelNumber(startTimeMS),
        endTimeMS = plainChannelNumber(endTimeMS),
    }, true
end

local function clearPlayerCastLock(expectedKind)
    if expectedKind and playerCastLock.kind ~= expectedKind then return false end
    playerCastLock.active = false
    playerCastLock.kind = nil
    playerCastLock.source = nil
    playerCastLock.castGUID = nil
    playerCastLock.name = nil
    playerCastLock.spellID = nil
    playerCastLock.startTimeMS = nil
    playerCastLock.endTimeMS = nil
    return true
end

local function applyChannelMetadata(live, fallbackSpellID)
    if live then
        playerCastLock.name = live.name
        playerCastLock.spellID = live.spellID
        playerCastLock.startTimeMS = live.startTimeMS
        playerCastLock.endTimeMS = live.endTimeMS
    else
        playerCastLock.name = nil
        playerCastLock.spellID = plainChannelNumber(fallbackSpellID) or playerCastLock.spellID
        playerCastLock.startTimeMS = nil
        playerCastLock.endTimeMS = nil
    end
end

local function applyEmpowerMetadata(live, fallbackSpellID)
    if live and live.isEmpowered == true then
        playerCastLock.name = live.name
        playerCastLock.spellID = live.spellID or plainChannelNumber(fallbackSpellID) or playerCastLock.spellID
        playerCastLock.startTimeMS = live.startTimeMS
        playerCastLock.endTimeMS = live.endTimeMS
    else
        playerCastLock.spellID = plainChannelNumber(fallbackSpellID) or playerCastLock.spellID
    end
end

local function beginPlayerChannelLock(castGUID, spellID)
    local live = select(1, readUnitChannelInfo(spellID))
    if live and live.isEmpowered == true then
        -- Some client paths can expose an Empower through UnitChannelInfo.
        -- Never overwrite an Empower lock with the generic channel handler.
        return false, "ignored_empowered_channel_event"
    end
    if playerCastLock.active == true and playerCastLock.kind == "empower" and not live then
        -- Do not let an unenriched generic event overwrite a live Empower.
        return false, "preserved_empower_lock"
    end
    local normalizedGUID = plainCastGUID(castGUID)
    playerCastLock.active = true
    playerCastLock.kind = "channel"
    playerCastLock.source = normalizedGUID and "event" or "api"
    playerCastLock.castGUID = normalizedGUID
    applyChannelMetadata(live, spellID)
    return true, "channel_started"
end

local function adoptPlayerChannelLock(live)
    if not live or live.isEmpowered == true then return false end
    if playerCastLock.active == true and playerCastLock.kind == "empower" then return false end
    playerCastLock.active = true
    playerCastLock.kind = "channel"
    playerCastLock.source = "api"
    playerCastLock.castGUID = nil
    applyChannelMetadata(live, live.spellID)
    return true
end

local function updatePlayerChannelLock(castGUID, spellID)
    local live = select(1, readUnitChannelInfo(spellID))
    if live and live.isEmpowered == true then
        return false, "ignored_empowered_channel_event"
    end
    if playerCastLock.active == true and playerCastLock.kind == "empower" and not live then
        return false, "preserved_empower_lock"
    end
    if playerCastLock.active ~= true or playerCastLock.kind ~= "channel" then
        return beginPlayerChannelLock(castGUID, spellID)
    end
    local normalizedGUID = plainCastGUID(castGUID)
    if playerCastLock.castGUID ~= nil and normalizedGUID ~= nil
        and not matchingCastGUID(playerCastLock.castGUID, normalizedGUID) then
        -- A delayed update from channel A must not mutate a newer channel B.
        return false, "ignored_stale_channel_update"
    end
    if playerCastLock.castGUID == nil and normalizedGUID ~= nil then
        playerCastLock.castGUID = normalizedGUID
        playerCastLock.source = "event"
    end
    applyChannelMetadata(live, spellID)
    return true, "channel_updated"
end

local function clearPlayerChannelLock(castGUID)
    if playerCastLock.active ~= true or playerCastLock.kind ~= "channel" then return false, "no_active_channel_lock" end
    if matchingCastGUID(playerCastLock.castGUID, castGUID) then
        return clearPlayerCastLock("channel"), "channel_cleared"
    end
    -- A lock adopted only from UnitChannelInfo has no event GUID. It may be
    -- released only after the same API confirms the channel is gone; this
    -- avoids both a permanent fallback lock and an unrelated terminal event
    -- clearing a live cast.
    if playerCastLock.source == "api" and playerCastLock.castGUID == nil then
        local live, queryAvailable = readUnitChannelInfo(playerCastLock.spellID)
        if queryAvailable and not live then return clearPlayerCastLock("channel"), "channel_api_fallback_cleared" end
    end
    return false, "channel_terminal_guid_mismatch"
end

local function beginPlayerEmpowerLock(castGUID, spellID)
    local normalizedGUID = plainCastGUID(castGUID)
    playerCastLock.active = true
    playerCastLock.kind = "empower"
    playerCastLock.source = normalizedGUID and "event" or "api"
    playerCastLock.castGUID = normalizedGUID
    playerCastLock.name = nil
    playerCastLock.spellID = plainChannelNumber(spellID)
    playerCastLock.startTimeMS = nil
    playerCastLock.endTimeMS = nil
    return true, "empower_started"
end

local function adoptPlayerEmpowerLock(live)
    if not live or live.isEmpowered ~= true then return false end
    playerCastLock.active = true
    playerCastLock.kind = "empower"
    playerCastLock.source = "api"
    playerCastLock.castGUID = nil
    applyEmpowerMetadata(live, live.spellID)
    return true
end

local function updatePlayerEmpowerLock(castGUID, spellID)
    if playerCastLock.active ~= true or playerCastLock.kind ~= "empower" then
        -- An UPDATE without a usable START still has to stop dispatch. Start a
        -- new fail-closed lock rather than treating the update as harmless.
        return beginPlayerEmpowerLock(castGUID, spellID)
    end
    local normalizedGUID = plainCastGUID(castGUID)
    if playerCastLock.castGUID ~= nil and normalizedGUID ~= nil
        and not matchingCastGUID(playerCastLock.castGUID, normalizedGUID) then
        -- A different Empower event must not mutate or unlock the active lock.
        return false, "ignored_stale_empower_update"
    end
    if playerCastLock.castGUID == nil and normalizedGUID ~= nil then
        playerCastLock.castGUID = normalizedGUID
        playerCastLock.source = "event"
    end
    playerCastLock.spellID = plainChannelNumber(spellID) or playerCastLock.spellID
    return true, "empower_updated"
end

local function clearPlayerEmpowerLock(castGUID)
    if playerCastLock.active ~= true or playerCastLock.kind ~= "empower" then return false, "no_active_empower_lock" end
    if matchingCastGUID(playerCastLock.castGUID, castGUID) then
        return clearPlayerCastLock("empower"), "empower_cleared"
    end
    -- As with channel fallback, a GUID-less API-only observation can clear only
    -- after UnitChannelInfo no longer reports an Empower cast. Event-owned
    -- locks remain fail-closed on any GUID mismatch.
    if playerCastLock.source == "api" and playerCastLock.castGUID == nil then
        local live, queryAvailable = readUnitChannelInfo(playerCastLock.spellID)
        if queryAvailable and (not live or live.isEmpowered ~= true) then
            return clearPlayerCastLock("empower"), "empower_api_fallback_cleared"
        end
    end
    return false, "empower_terminal_guid_mismatch"
end

getPlayerCastLockInfo = function()
    local live, queryAvailable = readUnitChannelInfo(playerCastLock.spellID)
    if live and live.isEmpowered == true then
        -- A real Empower sample always wins over the generic channel probe. If
        -- EMPOWER_START arrived first, preserve its GUID; if it did not, adopt
        -- an API-only fail-closed fallback until an event can promote it.
        if playerCastLock.active ~= true or playerCastLock.kind ~= "empower" then
            adoptPlayerEmpowerLock(live)
        elseif playerCastLock.source == "api" then
            applyEmpowerMetadata(live, live.spellID)
        end
    elseif live then
        -- Ordinary channels are tracked separately. An event-owned Empower lock
        -- is never downgraded to a channel by a transient API sample.
        if playerCastLock.active ~= true then
            adoptPlayerChannelLock(live)
        elseif playerCastLock.kind == "channel" then
            applyChannelMetadata(live, live.spellID)
        elseif playerCastLock.kind == "empower" and playerCastLock.source == "api" then
            adoptPlayerChannelLock(live)
        end
    elseif queryAvailable and playerCastLock.active == true and playerCastLock.source == "api" then
        -- API-only fallback locks are allowed to self-clear only after the
        -- source API confirms no active cast. Event-owned locks require their
        -- matching terminal event so a one-frame query gap cannot reopen TEK.
        clearPlayerCastLock(playerCastLock.kind)
    end

    if playerCastLock.active ~= true then return { active = false } end
    return {
        active = true,
        kind = playerCastLock.kind,
        name = playerCastLock.name,
        spellID = playerCastLock.spellID,
        startTimeMS = playerCastLock.startTimeMS,
        endTimeMS = playerCastLock.endTimeMS,
    }
end

local function readUnitCastingInfo()
    if type(UnitCastingInfo) ~= "function" then return { active = false } end
    local ok, name, _, _, startTimeMS, endTimeMS, _, _, _, spellID = pcall(UnitCastingInfo, "player")
    if not ok or not name then return { active = false } end
    return {
        active = true,
        kind = "cast",
        name = name,
        spellID = plainChannelNumber(spellID),
        startTimeMS = plainChannelNumber(startTimeMS),
        endTimeMS = plainChannelNumber(endTimeMS),
    }
end

local lastCastDisplayInfo = { active = false }

local function getPlayerCastDisplayInfo(castLock)
    castLock = castLock or getPlayerCastLockInfo()
    if castLock and castLock.active == true then
        return {
            active = true,
            kind = castLock.kind,
            name = castLock.name,
            spellID = castLock.spellID,
            startTimeMS = castLock.startTimeMS,
            endTimeMS = castLock.endTimeMS,
        }
    end
    return readUnitCastingInfo()
end

function SignalFrame:GetCastDisplayInfo()
    return lastCastDisplayInfo or { active = false }
end

function SignalFrame:GetCastLockDiagnostics()
    local store = ensureStore()
    local copied = {}
    for index, record in ipairs(store.castLockTransitions or {}) do
        copied[index] = {
            schemaVersion = record.schemaVersion,
            component = record.component,
            eventType = record.eventType,
            observedAt = record.observedAt,
            elapsed = record.elapsed,
            event = record.event,
            outcome = record.outcome,
            eventSpellID = record.eventSpellID,
            beforeActive = record.beforeActive,
            beforeKind = record.beforeKind,
            beforeSource = record.beforeSource,
            beforeSpellID = record.beforeSpellID,
            beforeHasCastGUID = record.beforeHasCastGUID,
            afterActive = record.afterActive,
            afterKind = record.afterKind,
            afterSource = record.afterSource,
            afterSpellID = record.afterSpellID,
            afterHasCastGUID = record.afterHasCastGUID,
        }
    end
    return copied
end

function SignalFrame:GetCastLockInfo()
    return getPlayerCastLockInfo()
end

function SignalFrame:BuildMessage(reason)
    -- All dispatchable candidates use one scheduler contract: each fresh
    -- `armed` TEAP frame can reach TEK, where the shared global rate limiter
    -- decides the physical input frequency. AutoBurst only changes the selected
    -- action and waits for exact confirmation before advancing its plan; it does
    -- not receive a separate one-shot or retry-limited delivery path. Ordinary
    -- casts retain the same armed cadence, while channel/empower are explicit
    -- non-dispatch states for both official and Burst candidates.
    -- The official recommendation is preserved as immutable source metadata.
    -- AutoBurst may provide a separate DispatchCandidate, but it never mutates
    -- this result or creates a parallel binding/token path.
    local official = TE.RecommendationAdapter:ReadOfficial()
    local officialSpellID = official and tonumber(official.spellID) or nil
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    local outputState = state
    local sessionPolicy = getSessionPolicy()
    local sessionPolicyReason = nil
    local inputFocusActive, inputFocusReason = isTextInputActive()
    local castLock = getPlayerCastLockInfo()
    local castDisplay = getPlayerCastDisplayInfo(castLock)
    lastCastDisplayInfo = castDisplay
    local channeling = castLock.active == true and castLock.kind == "channel" and castLock or { active = false }
    local empowering = castLock.active == true and castLock.kind == "empower" and castLock or { active = false }
    local monitor = TE.ProtocolMonitor and TE.ProtocolMonitor:Sample() or nil
    local runtimeReason = nil
    local manualPriority = TE.ManualActionPriority and type(TE.ManualActionPriority.GetActive) == "function"
        and TE.ManualActionPriority:GetActive() or { active = false }

    if state == "armed" then
        if manualPriority.active == true then
            -- A physical HUD/default-actionbar mouse click always wins over a
            -- queued TEAP/TEK candidate. This does not synthesize input; it
            -- exposes the existing manual_hold protocol state with no token.
            outputState = "manual_hold"
            runtimeReason = manualPriority.reason or "manual_click_priority"
        elseif inputFocusActive then
            outputState = "manual_hold"
            runtimeReason = inputFocusReason
        elseif castLock.active then
            outputState = castLockState(castLock)
            runtimeReason = castLockReason(castLock)
        elseif not inCombat and sessionPolicy == "pause_out_of_combat" then
            outputState = "paused"
            sessionPolicyReason = "out_of_combat_auto_standby"
            runtimeReason = sessionPolicyReason
        end
    end

    local autoDecision
    if inCombat and TE.AutoBurst and type(TE.AutoBurst.Evaluate) == "function" then
        local context = TE.Context and TE.Context:GetPlayer() or {}
        local ok, decision = pcall(TE.AutoBurst.Evaluate, TE.AutoBurst, official, {
            context = context,
            inCombat = inCombat,
            intentState = state,
            effectiveState = outputState,
            runtimeReason = runtimeReason or inputFocusReason or sessionPolicyReason,
            -- AutoBurst handoff holds advance only on the normal 50 ms transport
            -- scheduler. Event/state refreshes still paint a hold, but cannot
            -- compress a multi-frame TEK freshness fence into a few milliseconds.
            transportHandoffTick = reason == "tick",
            primary = official,
        })
        if ok and type(decision) == "table" then
            autoDecision = decision
        elseif not ok and TE.AutoBurst and type(TE.AutoBurst.ReportFault) == "function" then
            -- A fault during an already-created Burst plan must not accidentally
            -- release its window into the ordinary dispatch path. Abort the
            -- current plan into its departure lock and emit a non-dispatch
            -- observation frame. A plan-less fault still leaves the normal
            -- official path unchanged.
            TE.AutoBurst:ReportFault("evaluate_error:" .. tostring(decision))
            -- Snapshot ownership before Abort clears transient capture state.
            -- A front-window capture is semantically equivalent to a live plan
            -- for fallback safety: its official token must not leak after a
            -- failed evaluator tick.
            local heldBeforeAbort = false
            if type(TE.AutoBurst.GetSnapshot) == "function" then
                local snapshotOk, snapshot = pcall(TE.AutoBurst.GetSnapshot, TE.AutoBurst)
                heldBeforeAbort = snapshotOk and type(snapshot) == "table"
                    and (snapshot.active == true
                        or snapshot.requireWindowDeparture == true
                        or snapshot.preWindowCaptureActive == true)
            end
            if type(TE.AutoBurst.Abort) == "function" then
                pcall(TE.AutoBurst.Abort, TE.AutoBurst, "evaluator_fault", false)
            end
            local holdsWindow = heldBeforeAbort
            if type(TE.AutoBurst.GetSnapshot) == "function" then
                local snapshotOk, snapshot = pcall(TE.AutoBurst.GetSnapshot, TE.AutoBurst)
                holdsWindow = holdsWindow or (snapshotOk and type(snapshot) == "table"
                    and (snapshot.active == true
                        or snapshot.requireWindowDeparture == true
                        or snapshot.preWindowCaptureActive == true))
            end
            if holdsWindow then
                autoDecision = {
                    kind = "hold",
                    dispatchOrigin = "burst",
                    observationOnly = true,
                    reason = "burst_evaluator_fault_hold",
                }
            end
        end
    end

    -- P4 automatic interrupts are a separate ordinary scheduler decision.
    -- AutoReaction never sends input itself: it only selects an already
    -- validated P2 binding route. SignalFrame keeps AutoBurst ownership first;
    -- the user-selected policy is that a live Burst plan/pre-window capture
    -- suppresses automatic interrupt attempts and leaves P3 highlighting only.
    local reactionDecision
    if TE.AutoReaction and type(TE.AutoReaction.Evaluate) == "function" then
        local autoBurstSnapshot
        if TE.AutoBurst and type(TE.AutoBurst.GetSnapshot) == "function" then
            local snapshotOK, snapshot = pcall(TE.AutoBurst.GetSnapshot, TE.AutoBurst)
            if snapshotOK and type(snapshot) == "table" then autoBurstSnapshot = snapshot end
        end
        local reactionOK, decision = pcall(TE.AutoReaction.Evaluate, TE.AutoReaction, {
            inCombat = inCombat,
            intentState = state,
            effectiveState = outputState,
            runtimeReason = runtimeReason or inputFocusReason or sessionPolicyReason,
            monitor = monitor,
            autoBurstSnapshot = autoBurstSnapshot,
            autoBurstDecision = autoDecision,
        })
        if reactionOK and type(decision) == "table" then
            reactionDecision = decision
        end
    end

    -- P5.8 has no out-of-combat Burst transport exception. Session policy
    -- remains authoritative until combat begins; therefore no AutoBurst result
    -- may elevate the protocol envelope while `inCombat` is false.
    local preCombatBurstBridgeFrame = false

    local explicitObservationOnly = reason == "observe_once"
    -- AutoBurst uses a hold only to suppress the ordinary recommendation while
    -- its own bounded plan waits for GCD/confirmation/revalidation.  It is not
    -- a user pause.  Encoding the old hold as state="paused" caused TEK to
    -- reject it and, worse, fed that paused state back into AutoBurst on the
    -- next BuildMessage call, permanently self-latching the plan.
    local burstHoldObservation = autoDecision and autoDecision.kind == "hold"
        and autoDecision.observationOnly == true
    local reactionHoldObservation = reactionDecision and reactionDecision.kind == "hold"
        and reactionDecision.observationOnly == true
    local manualPriorityObservation = manualPriority and manualPriority.active == true
    local observationOnly = explicitObservationOnly or burstHoldObservation or reactionHoldObservation or manualPriorityObservation

    local dispatchOrigin = "official"
    local dispatchSpellID = officialSpellID
    local dispatchActionKind = "spell"
    local dispatchInventorySlot = nil
    local dispatchItemID = nil
    local bindingInfo, bindingReason
    -- A live burst hold intentionally has no dispatch token.  Preserve a
    -- separate read-only official binding for HUD/diagnostics so the official
    -- icon never changes to “无绑定” merely because AutoBurst is waiting for a
    -- GCD/confirmation boundary.
    local officialBindingInfo, officialBindingReason
    if autoDecision and autoDecision.kind == "candidate" then
        dispatchOrigin = "burst"
        dispatchSpellID = tonumber(autoDecision.dispatchSpellID)
        dispatchActionKind = autoDecision.dispatchActionKind == "inventory" and "inventory" or "spell"
        dispatchInventorySlot = tonumber(autoDecision.dispatchInventorySlot)
        dispatchItemID = tonumber(autoDecision.dispatchItemID)
        bindingInfo = autoDecision.bindingInfo
        runtimeReason = runtimeReason or "burst_dispatch_candidate"
    elseif autoDecision and autoDecision.kind == "hold" then
        -- Keep the real output state intact.  TEAP observation_only prevents
        -- TEK from validating the intentionally empty BindingToken or falling
        -- through to the official action, without turning the whole runtime
        -- into a paused/manual state.
        dispatchOrigin = "burst"
        dispatchSpellID = nil
        dispatchActionKind = "hold"
        runtimeReason = autoDecision.reason or runtimeReason or "burst_hold"
    elseif reactionDecision and reactionDecision.kind == "candidate" then
        dispatchOrigin = "reaction"
        dispatchSpellID = tonumber(reactionDecision.dispatchSpellID)
        dispatchActionKind = "spell"
        bindingInfo = reactionDecision.bindingInfo
        runtimeReason = reactionDecision.reason or runtimeReason or "reaction_interrupt_candidate"
    elseif reactionDecision and reactionDecision.kind == "hold" then
        -- Compatibility path for an older AddOn candidate that already changed
        -- into an observation hold. P4.4 keeps a stable candidate alive
        -- until cast exit and lets TEK dedupe that stable sequence after output.
        dispatchOrigin = "reaction"
        dispatchSpellID = nil
        dispatchActionKind = "hold"
        runtimeReason = reactionDecision.reason or runtimeReason or "reaction_interrupt_hold"
    end

    if manualPriorityObservation then
        -- Do this after both candidate selectors so even a previously queued
        -- Burst/Reaction decision cannot retain a live token during a direct
        -- click. `official` is used as the protocol metadata fallback; the
        -- manual_hold state + actionCode=0 + BindingToken=0 are the hard gate.
        dispatchOrigin = "official"
        dispatchSpellID = nil
        dispatchActionKind = "manual_hold"
        dispatchInventorySlot = nil
        dispatchItemID = nil
        bindingInfo = nil
        runtimeReason = manualPriority.reason or "manual_click_priority"
    end

    if dispatchSpellID and not bindingInfo then
        bindingInfo, bindingReason = TE.ActionBarBindingResolver:ResolveSpell(dispatchSpellID)
    end
    if officialSpellID then
        if dispatchOrigin == "official" and bindingInfo then
            officialBindingInfo, officialBindingReason = bindingInfo, bindingReason
        else
            -- A Burst/Reaction candidate or observation hold must not replace
            -- the normal recommendation's read-only HUD binding metadata.
            officialBindingInfo, officialBindingReason = TE.ActionBarBindingResolver:ResolveSpell(officialSpellID)
        end
    end
    local legacyCatalogReason = dispatchSpellID and "generic_binding_token_path" or nil

    if outputState == "armed" and not observationOnly
        and (not bindingInfo or bindingInfo.status ~= "Ready" or (tonumber(bindingInfo.bindingToken) or 0) == 0) then
        outputState = "blocked"
    end

    local actionCode = 0
    local actionId = nil
    if explicitObservationOnly then outputState = "paused" end

    runtimeReason = runtimeReason or inputFocusReason or sessionPolicyReason or bindingReason
    -- `sequence` identifies a fresh dispatch opportunity, not a logical Burst
    -- step.  A waiting AutoBurst plan can legitimately need several physical
    -- attempts while its exact confirmation remains pending (for example an
    -- inventory action presented during a GCD).  Older TEK builds deduped Burst
    -- candidates by sequence even though their freshness changed, so retaining a
    -- stable sequence silently converted a configured 5 Hz/20 Hz delivery policy
    -- into one physical press.  Give every dispatchable armed frame a fresh
    -- sequence for both official and Burst candidates; the current TEK global
    -- rate limiter remains the only physical-input frequency governor.
    local signatureOfficialSpellID = officialSpellID
    if (autoDecision and autoDecision.kind == "candidate" and dispatchOrigin == "burst")
        or (reactionDecision and reactionDecision.kind == "candidate" and dispatchOrigin == "reaction") then
        signatureOfficialSpellID = 0
    end
    local signature = table.concat({
        tostring(outputState), tostring(dispatchOrigin), tostring(dispatchActionKind), tostring(actionCode), tostring(signatureOfficialSpellID), tostring(dispatchSpellID),
        tostring(dispatchInventorySlot or 0), tostring(dispatchItemID or 0), tostring(bindingInfo and bindingInfo.bindingToken or 0), tostring(inCombat),
        tostring(inputFocusActive), tostring(sessionPolicy), tostring(runtimeReason),
        tostring(castLock.active == true), tostring(castLock.kind or "none"), tostring(castLock.spellID or 0),
        tostring(autoDecision and autoDecision.planId or 0), tostring(autoDecision and autoDecision.stepRole or "none"),
        tostring(autoDecision and autoDecision.dispatchAttempt or 0), tostring(observationOnly),
        tostring(reactionDecision and reactionDecision.reactionKind or "none"), tostring(reactionDecision and reactionDecision.source or "none"),
        tostring(reactionDecision and reactionDecision.castKey or "none"), tostring(reactionDecision and reactionDecision.routeMode or "none"),
        tostring(manualPriorityObservation), tostring(manualPriority and manualPriority.kind or "none"), tostring(manualPriority and manualPriority.source or "none"),
    }, ":")
    -- P4.4 reaction candidates intentionally retain one stable sequence while
    -- the observed cast remains active. TEK records a successful reaction
    -- sequence and suppresses only its duplicate frames; this keeps the request
    -- visible long enough for cross-process sampling without producing repeated
    -- physical-output calls. Official and Burst candidates retain their fresh-frame
    -- delivery policy.
    local stableReactionCandidate = reactionDecision and reactionDecision.kind == "candidate"
        and dispatchOrigin == "reaction"
        and reactionDecision.deliveryStable == true
    local freshDispatchableFrame = outputState == "armed"
        and observationOnly ~= true
        and bindingInfo ~= nil
        and bindingInfo.status == "Ready"
        and (tonumber(bindingInfo.bindingToken) or 0) ~= 0
        and stableReactionCandidate ~= true
    if freshDispatchableFrame then
        sequence = sequence + 1
        lastSignature = signature
    elseif signature ~= lastSignature then
        sequence = sequence + 1
        lastSignature = signature
    elseif reason == "manual" then
        sequence = sequence + 1
        lastSignature = signature
    end

    return {
        state = outputState,
        intentState = state,
        sessionEpoch = sessionEpoch,
        sequence = sequence,
        frameFreshnessCounter = frameFreshnessCounter,
        actionCode = actionCode,
        actionId = actionId,
        -- Legacy spellID remains the actual dispatch spell for tools that read
        -- only one field.  officialSpellID and dispatchSpellID make the two
        -- sources explicit for HUD, SavedVariables and diagnostics.
        spellID = dispatchSpellID,
        officialSpellID = officialSpellID,
        dispatchSpellID = dispatchSpellID,
        dispatchActionKind = dispatchActionKind,
        dispatchInventorySlot = dispatchInventorySlot,
        dispatchItemID = dispatchItemID,
        dispatchOrigin = dispatchOrigin,
        burstPlan = autoDecision,
        reactionPlan = reactionDecision,
        reactionDeliveryStable = stableReactionCandidate == true,
        inCombat = inCombat,
        preCombatBurstBridge = preCombatBurstBridgeFrame,
        observationOnly = observationOnly,
        unresolvedReason = runtimeReason or bindingReason,
        bindingReason = runtimeReason or bindingReason,
        legacyCatalogReason = legacyCatalogReason,
        actionRegistryReason = legacyCatalogReason,
        bindingToken = bindingInfo and bindingInfo.bindingToken or 0,
        binding = bindingInfo and (bindingInfo.binding or bindingInfo.rawBinding) or nil,
        bindingInfo = bindingInfo,
        officialBindingInfo = officialBindingInfo,
        officialBindingReason = officialBindingReason,
        observationReason = burstHoldObservation and autoDecision and autoDecision.reason
            or (reactionHoldObservation and reactionDecision and reactionDecision.reason or nil),
        inputFocusActive = inputFocusActive,
        inputFocusReason = inputFocusReason,
        manualHoldActive = outputState == "manual_hold",
        manualPriority = manualPriority,
        manualPriorityActive = manualPriorityObservation == true,
        channelingActive = channeling.active or false,
        channelingName = channeling.name,
        channelingSpellID = channeling.spellID,
        channelingStartTimeMS = channeling.startTimeMS,
        channelingEndTimeMS = channeling.endTimeMS,
        empoweringActive = empowering.active or false,
        empoweringName = empowering.name,
        empoweringSpellID = empowering.spellID,
        castingActive = castDisplay.active == true,
        castingKind = castDisplay.kind,
        castingName = castDisplay.name,
        castingSpellID = castDisplay.spellID,
        castingStartTimeMS = castDisplay.startTimeMS,
        castingEndTimeMS = castDisplay.endTimeMS,
        sessionPolicy = sessionPolicy,
        sessionPolicyReason = sessionPolicyReason,
        monitor = monitor,
    }
end
function SignalFrame:GetLastMessage()
    return lastMessage
end

function SignalFrame:GetLastEncoded()
    return lastEncoded
end

local REUSABLE_OFFICIAL_TICK_STATES = {
    waiting = true,
    armed = true,
    paused = true,
    blocked = true,
    channeling = true,
    empowering = true,
}

local function reusableOfficialTickMessage(message)
    if type(message) ~= "table" then return false end
    if REUSABLE_OFFICIAL_TICK_STATES[message.state] ~= true then return false end
    if message.observationOnly == true then return false end
    if message.dispatchOrigin == "burst" or message.dispatchOrigin == "reaction" then return false end
    return true
end

local function cloneMessageForFreshness(message)
    local copy = {}
    for key, value in pairs(message) do copy[key] = value end
    return copy
end

function SignalFrame:Refresh(reason)
    frameFreshnessCounter = (frameFreshnessCounter + 1) % 65536
    local now = type(GetTime) == "function" and GetTime() or 0
    local canReuse = reason == "tick"
        and reusableOfficialTickMessage(lastMessage)
        and (now - (lastFullBuildAt or 0)) < OFFICIAL_RECOMMENDATION_REBUILD_INTERVAL
    local message = canReuse and cloneMessageForFreshness(lastMessage) or self:BuildMessage(reason)
    if not canReuse then lastFullBuildAt = now end
    message.frameFreshnessCounter = frameFreshnessCounter
    local encoded = TE.SignalEncoder:Encode(message)
    lastMessage = message
    lastEncoded = encoded
    paint(encoded)
    remember(encoded, message.unresolvedReason or reason)
    if TE.TacticalState and type(TE.TacticalState.Publish) == "function" then
        TE.TacticalState:Publish(message, encoded)
    end
    return encoded
end

function SignalFrame:ShowOnce()
    createFrame():Show()
    return self:Refresh("observe_once")
end

function SignalFrame:ResetSession()
    sessionEpoch = newSessionEpoch()
    sequence = 0
    frameFreshnessCounter = 0
    lastSignature = nil
    lastRememberedSignature = nil
    lastPaintedFields = nil
end

-- Login starts the TEAP color signal in an explicit paused state. This is
-- deliberately not an armed intent: TEK can observe a live, fresh paused frame
-- immediately after login, but it cannot dispatch until the player explicitly
-- starts dynamic linking through the existing UI, hotkey, or /tesignal armed.
function SignalFrame:ShowPausedOnLogin()
    state = "paused"
    createFrame():Show()
    return self:Refresh("player_login_paused")
end

local loginWatcher = CreateFrame("Frame")
TE:RegisterEventSafe(loginWatcher, "PLAYER_LOGIN")
loginWatcher:SetScript("OnEvent", function()
    SignalFrame:ShowPausedOnLogin()
end)

local policyWatcher = CreateFrame("Frame")
TE:RegisterEventsSafe(policyWatcher, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
policyWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and state == "armed" and getSessionPolicy() == "close_out_of_combat" then
        -- "脱战停止" is a visible, sticky paused intent.  It intentionally
        -- remains paused when combat begins again and requires a manual arm;
        -- unlike the historical waiting state it never hides or withdraws the
        -- TEAP strip.
        SignalFrame:SetState("paused")
        return
    end
    if frame and frame:IsShown() then
        -- manual_keep stays armed across combat changes; pause_out_of_combat is
        -- auto start/stop and encodes standby out of combat without mutating the
        -- user's armed intent; close_out_of_combat remains paused after the
        -- branch above until a manual arm.
        SignalFrame:Refresh("combat_policy")
    end
end)

-- Channel and Empower events force an immediate refresh so TEK sees the
-- dedicated fail-closed cast-lock state without waiting for the normal 200 ms
-- UI tick.
-- Both lock kinds now keep their own castGUID boundaries. A late terminal
-- event from cast A cannot clear a newer cast B, and UnitChannelInfo's
-- isEmpowered flag cannot recast an Empower lock as an ordinary channel.
local castLockWatcher = CreateFrame("Frame")
for _, event in ipairs({
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_SUCCEEDED",
}) do
    TE:RegisterEventSafe(castLockWatcher, event)
end
castLockWatcher:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local before = castLockSnapshot()
    local changed, outcome = false, "ignored_cast_event"
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        changed, outcome = beginPlayerChannelLock(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        changed, outcome = updatePlayerChannelLock(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- A matching terminal event clears only the active channel lock.
        -- Refresh then publishes the next actual state; TEK remains fail-closed
        -- until it sees a fresh armed frame.
        changed, outcome = clearPlayerChannelLock(castGUID)
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        changed, outcome = beginPlayerEmpowerLock(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        changed, outcome = updatePlayerEmpowerLock(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        changed, outcome = clearPlayerEmpowerLock(castGUID)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        if playerCastLock.active == true and playerCastLock.kind == "empower" then
            changed, outcome = clearPlayerEmpowerLock(castGUID)
        elseif playerCastLock.active == true and playerCastLock.kind == "channel" then
            changed, outcome = clearPlayerChannelLock(castGUID)
        else
            outcome = "no_active_cast_lock"
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Success alone is never authoritative for either cast kind. Waiting
        -- for matching STOP / FAILED / INTERRUPTED prevents a prior cast's
        -- late success event from clearing the next cast's safety lock.
        if spellID and TE.TacticalBoard and type(TE.TacticalBoard.PlayCastFeedbackForSpell) == "function" then
            pcall(TE.TacticalBoard.PlayCastFeedbackForSpell, TE.TacticalBoard, spellID)
        end
        outcome = "ignored_success"
    end

    rememberCastLockTransition(event, outcome or (changed and "changed" or "unchanged"), before, spellID)
    if frame and frame:IsShown() then
        SignalFrame:Refresh("player_cast_lock_state")
    end
end)
