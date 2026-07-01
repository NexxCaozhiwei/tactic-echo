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
        frameFreshnessCounter = freshness,
        fields = fields,
        state = message.state,
        sequence = sequence,
        actionCode = message.actionCode,
        actionId = message.actionId,
        spellID = message.spellID,
        inCombat = message.inCombat,
        observationOnly = message.observationOnly,
        checksum = crc,
    }
end
