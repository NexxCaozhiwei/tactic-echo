local TE = _G.TacticEcho

local SignalEncoder = {}
TE.SignalEncoder = SignalEncoder

SignalEncoder.protocolVersion = 3
SignalEncoder.commitByte = 165
local bitlib = bit or bit32

local stateCodes = {
    waiting = 0,
    armed = 1,
    paused = 2,
    blocked = 3,
    error = 4,
    channeling = 5,
    empowering = 6,
    manual_hold = 7,
}

local function byte(value)
    value = tonumber(value) or 0
    value = math.floor(value)
    return value % 256
end

local function wordLow(value)
    return byte(value)
end

local function wordHigh(value)
    return byte(math.floor((tonumber(value) or 0) / 256))
end

-- AutoBurst decisions carry a live bindingInfo table while SignalFrame builds
-- a frame. SavedVariables and diagnostics only need a small immutable audit
-- record; never persist the resolver object or macro diagnostics wholesale.
local function burstPlanMetadata(value)
    if type(value) ~= "table" then return nil end
    return {
        planId = tonumber(value.planId) or nil,
        ruleId = type(value.ruleId) == "string" and value.ruleId or nil,
        direction = value.direction == "post" and "post" or (value.direction == "pre" and "pre" or nil),
        mode = value.mode == "focused" and "focused" or (value.mode == "simple" and "simple" or nil),
        stepRole = value.stepRole == "window" and "window" or (value.stepRole == "injection" and "injection" or nil),
        actionKind = value.dispatchActionKind == "inventory" and "inventory" or (value.dispatchActionKind == "spell" and "spell" or nil),
        inventorySlot = tonumber(value.dispatchInventorySlot) or nil,
        itemID = tonumber(value.dispatchItemID) or nil,
        dispatchAttempt = tonumber(value.dispatchAttempt) or nil,
        reason = type(value.reason) == "string" and value.reason or nil,
        kind = value.kind == "candidate" and "candidate" or (value.kind == "hold" and "hold" or nil),
        preCombatBridge = value.preCombatBridge == true,
    }
end

-- P4 reaction audit metadata mirrors the existing Burst sanitizer. The live
-- binding object stays inside SignalFrame only; diagnostics retain scalar route
-- facts and never include macro text or a new input channel.
local function reactionPlanMetadata(value)
    if type(value) ~= "table" then return nil end
    return {
        kind = value.kind == "candidate" and "candidate" or (value.kind == "hold" and "hold" or nil),
        reactionKind = value.reactionKind == "interrupt" and "interrupt" or nil,
        source = value.source == "focus" and "focus" or (value.source == "mouseover" and "mouseover" or (value.source == "target" and "target" or nil)),
        spellID = tonumber(value.dispatchSpellID) or nil,
        routeMode = type(value.routeMode) == "string" and value.routeMode or nil,
        macroManagedTarget = value.macroManagedTarget == true,
        macroPriorityChain = value.macroPriorityChain == true,
        reason = type(value.reason) == "string" and value.reason or nil,
    }
end

function SignalEncoder:GetStateCode(state)
    return stateCodes[state] or stateCodes.error
end

function SignalEncoder:Crc16(fields)
    if not bitlib then
        error("bit_library_unavailable")
    end
    local crc = 65535
    for index = 1, #fields do
        crc = bitlib.bxor(crc, bitlib.lshift(byte(fields[index]), 8))
        for _ = 1, 8 do
            if bitlib.band(crc, 32768) ~= 0 then
                crc = bitlib.band(bitlib.bxor(bitlib.lshift(crc, 1), 0x1021), 65535)
            else
                crc = bitlib.band(bitlib.lshift(crc, 1), 65535)
            end
        end
    end
    return crc
end

function SignalEncoder:Encode(message)
    local sequence = tonumber(message.sequence) or 0
    local freshness = tonumber(message.frameFreshnessCounter) or 0
    local sessionEpoch = tonumber(message.sessionEpoch) or 0
    local flags = 0
    if message.inCombat then
        flags = flags + 1
    end
    if message.observationOnly then
        flags = flags + 2
    end
    -- v3 non-breaking monitor extension.  Existing TEK readers ignore these
    -- reserved bits; newer readers expose them for diagnostics only.
    local monitorFlags = 0
    if TE.ProtocolMonitor and type(TE.ProtocolMonitor.GetFlags) == "function" then
        monitorFlags = select(1, TE.ProtocolMonitor:GetFlags(message.monitor)) or 0
    end
    flags = flags + monitorFlags
    -- v3 reserved bits 5/6 are auditable dispatch-origin markers. They do not
    -- create extra transports: TEK still validates the same BindingToken and
    -- all existing protocol gates before any input is attempted.
    local dispatchOrigin = message.dispatchOrigin
    if dispatchOrigin ~= "burst" and dispatchOrigin ~= "reaction" then dispatchOrigin = "official" end
    if dispatchOrigin == "burst" then flags = flags + 32 end
    if dispatchOrigin == "reaction" then flags = flags + 64 end

    local fields = {
        84,
        69,
        self.protocolVersion,
        self:GetStateCode(message.state),
        wordLow(sessionEpoch),
        wordHigh(sessionEpoch),
        wordLow(sequence),
        wordHigh(sequence),
        wordLow(freshness),
        wordHigh(freshness),
        byte(message.actionCode),
        byte(TE.ActionRegistry.catalogVersion),
        wordLow(TE.ActionRegistry.catalogFingerprint16),
        wordHigh(TE.ActionRegistry.catalogFingerprint16),
        wordLow(message.bindingToken or 0),
        wordHigh(message.bindingToken or 0),
        byte(flags),
    }

    local crc = self:Crc16(fields)
    fields[#fields + 1] = wordLow(crc)
    fields[#fields + 1] = wordHigh(crc)
    fields[#fields + 1] = self.commitByte

    return {
        protocolVersion = self.protocolVersion,
        sessionEpoch = sessionEpoch,
        actionCatalogVersion = TE.ActionRegistry.catalogVersion,
        catalogFingerprint = TE.ActionRegistry.catalogFingerprint16,
        bindingToken = message.bindingToken or 0,
        binding = message.binding,
        bindingReason = message.bindingReason,
        bindingSource = message.bindingInfo and message.bindingInfo.source or nil,
        bindingButton = message.bindingInfo and message.bindingInfo.buttonName or nil,
        bindingSlot = message.bindingInfo and (message.bindingInfo.actionSlot or message.bindingInfo.slot) or nil,
        bindingCacheGeneration = message.bindingInfo and message.bindingInfo.cacheGeneration or nil,
        macroName = message.bindingInfo and message.bindingInfo.macroName or nil,
        macroId = message.bindingInfo and message.bindingInfo.macroID or nil,
        macroCommand = message.bindingInfo and message.bindingInfo.macroCommand or nil,
        macroAssociation = message.bindingInfo and message.bindingInfo.macroAssociation or nil,
        inputFocusActive = message.inputFocusActive or false,
        inputFocusReason = message.inputFocusReason,
        channelingActive = message.channelingActive or false,
        channelingName = message.channelingName,
        channelingSpellID = message.channelingSpellID,
        empoweringActive = message.empoweringActive or false,
        empoweringName = message.empoweringName,
        empoweringSpellID = message.empoweringSpellID,
        sessionPolicy = message.sessionPolicy,
        sessionPolicyReason = message.sessionPolicyReason,
        intentState = message.intentState,
        legacyCatalogReason = message.legacyCatalogReason,
        monitor = message.monitor,
        monitorFlags = monitorFlags,
        dispatchOrigin = dispatchOrigin,
        officialSpellID = message.officialSpellID,
        dispatchSpellID = message.dispatchSpellID,
        dispatchActionKind = message.dispatchActionKind,
        dispatchInventorySlot = message.dispatchInventorySlot,
        dispatchItemID = message.dispatchItemID,
        burstPlan = burstPlanMetadata(message.burstPlan),
        reaction = reactionPlanMetadata(message.reactionPlan),
        frameFreshnessCounter = freshness,
        fields = fields,
        state = message.state,
        sequence = sequence,
        actionCode = message.actionCode,
        actionId = message.actionId,
        spellID = message.spellID,
        inCombat = message.inCombat,
        preCombatBurstBridge = message.preCombatBurstBridge == true,
        observationOnly = message.observationOnly,
        checksum = crc,
    }
end
