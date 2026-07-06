-- Read-only P3 reaction observation sampler.
--
-- This module deliberately owns no OnUpdate and no event registrations. It is
-- sampled by ProtocolMonitor's existing polling cadence so target/focus/
-- mouseover and visible-nameplate cast reads have one shared observation point.
-- It cannot create BindingToken data, change the official recommendation, write
-- TEAP, call TEK, or invoke a protected spell/action.
local TE = _G.TacticEcho

local ReactionObservation = {}
TE.ReactionObservation = ReactionObservation

ReactionObservation.schemaVersion = 7
ReactionObservation.snapshot = nil

local AOE_CONTROL_THRESHOLD = 4
local NAMEPLATE_CONTROL_SCAN_SUSPENDED = true
local CONTROL_EXCLUDED_CLASSIFICATIONS = {
    elite = true,
    rareelite = true,
    worldboss = true,
}

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    if not ok then return 0 end
    local readable, number = pcall(function()
        local scalar = tonumber(value)
        if type(scalar) ~= "number" then return nil end
        local probe = scalar + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    return readable and type(number) == "number" and number or 0
end

-- Keep all values crossing Retail's secret-value boundary inside pcall. P3 is
-- display-only, so an unreadable unit/cast simply becomes non-actionable.
local function plainBoolean(value)
    local ok, result = pcall(function()
        if value == true then return true end
        if value == false then return false end
        return nil
    end)
    if not ok then return nil end
    return result
end

local function plainNumber(value)
    local ok, result = pcall(function()
        if value == nil then return nil end
        local number = tonumber(value)
        if type(number) ~= "number" then return nil end
        local probe = number + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    return ok and result or nil
end

local function plainText(value)
    local ok, result = pcall(function()
        if type(value) ~= "string" then return nil end
        local length = #value
        if length < 0 then return nil end
        return value
    end)
    return ok and type(result) == "string" and result or nil
end

local function callBoolean(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return plainBoolean(value)
end

local function callNumber(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return plainNumber(value)
end

local function callText(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return plainText(value)
end

-- P3.2: Retail may return secret/opaque spell text.  Do not use the spell
-- name as the proof that a cast record exists: the API result arity is already
-- enough to distinguish a complete UnitCastingInfo/UnitChannelInfo record from
-- an empty no-cast return.  The original text never crosses this helper.
local function packReturns(...)
    return select("#", ...), ...
end

local function apiRecordPresent(apiOk, arity, requiredArity)
    if apiOk ~= true then return false end
    local count = plainNumber(arity)
    return type(count) == "number" and count >= (requiredArity or 1)
end

local function readCastingInfoRecord(unit)
    if type(UnitCastingInfo) ~= "function" then return nil end
    -- pcall adds one leading success value; `packReturns` preserves the API
    -- result count without inspecting or materialising the secret cast name.
    local ok, arity, _name, _text, _texture, _start, _finish, _trade, _castID, noInterrupt, sid = pcall(function()
        return packReturns(UnitCastingInfo(unit))
    end)
    if apiRecordPresent(ok, arity, 9) then
        return {
            kind = "cast",
            spellID = sid,
            startTimeMS = plainNumber(_start),
            endTimeMS = plainNumber(_finish),
            notInterruptible = noInterrupt,
            evidence = "unit_casting_info_arity",
            apiReturnArity = plainNumber(arity),
        }
    end
    return nil
end

local function readChannelInfoRecord(unit)
    if type(UnitChannelInfo) ~= "function" then return nil end
    local ok, arity, _name, _text, _texture, _start, _finish, _trade, noInterrupt, sid = pcall(function()
        return packReturns(UnitChannelInfo(unit))
    end)
    if apiRecordPresent(ok, arity, 8) then
        return {
            kind = "channel",
            spellID = sid,
            startTimeMS = plainNumber(_start),
            endTimeMS = plainNumber(_finish),
            notInterruptible = noInterrupt,
            evidence = "unit_channel_info_arity",
            apiReturnArity = plainNumber(arity),
        }
    end
    return nil
end

-- P3.3: Current Retail clients can hide or make parts of the direct unit-cast
-- record opaque on some live targets, while Blizzard's own target/focus/nameplate
-- castbar has already resolved the visible "shield / no-shield" state.  This is
-- strictly a display fallback: read only ordinary scalar fields inside pcall and
-- never retain names, raw frame objects, macro text or dispatch permission.
--
-- The native frame is intentionally only a *secondary* source.  UnitCastingInfo /
-- UnitChannelInfo stays authoritative whenever its record can be read.  The native
-- castbar is only used to prove an active visible cast or to fill an otherwise
-- unreadable interruptibility bit for the same target.  No event registration,
-- OnUpdate chain, token construction or transport write is added here.
local function safeObjectField(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function safeMethodBoolean(object, methodName)
    local method = safeObjectField(object, methodName)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, object)
    if not ok then return nil end
    return plainBoolean(value)
end


local function safeMethodText(object, methodName)
    local method = safeObjectField(object, methodName)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, object)
    if not ok then return nil end
    return plainText(value)
end

local function safeMethodList(object, methodName)
    local method = safeObjectField(object, methodName)
    if type(method) ~= "function" then return {} end
    local ok, values = pcall(function() return { method(object) } end)
    return ok and type(values) == "table" and values or {}
end

local function nativeFrameActive(frame)
    if frame == nil then return false, nil end
    -- Blizzard and popular unit-frame templates use both old (`casting`) and
    -- newer (`isCasting` / `isActiveCast`) scalar names. Read every ordinary
    -- scalar/method in a pcall and require an affirmative cast state; merely
    -- being shown is never enough because spell bars can remain visible during
    -- their fade animation after a cast has ended.
    local casting = plainBoolean(safeObjectField(frame, "casting"))
        or plainBoolean(safeObjectField(frame, "isCasting"))
        or safeMethodBoolean(frame, "IsCasting")
    local channeling = plainBoolean(safeObjectField(frame, "channeling"))
        or plainBoolean(safeObjectField(frame, "isChanneling"))
        or safeMethodBoolean(frame, "IsChanneling")
    local empowering = plainBoolean(safeObjectField(frame, "empowering"))
        or plainBoolean(safeObjectField(frame, "isEmpowering"))
        or safeMethodBoolean(frame, "IsEmpowering")
    local activeCast = plainBoolean(safeObjectField(frame, "isActiveCast"))
        or safeMethodBoolean(frame, "IsActiveCast")
    local active = casting == true or channeling == true or empowering == true or activeCast == true
    if active ~= true then return false, nil end
    if empowering == true then return true, "empower" end
    return true, channeling == true and "channel" or "cast"
end

local function normalizedNativeBarType(value)
    local text = plainText(value)
    if not text then return nil end
    local ok, lower = pcall(string.lower, text)
    return ok and plainText(lower) or nil
end

-- `showShield` on Blizzard cast bars is a *configuration* flag: it means the
-- template is allowed to render a shield when one is needed.  It is not the
-- per-cast visibility state.  P4.3 field capture proved it can remain true on
-- a cast that is successfully interrupted, so P4.4 only accepts the actual
-- shield widget visibility (`BorderShield:IsShown()` / equivalent) as visual
-- interruptibility evidence.
local SHIELD_FIELD_NAMES = {
    "BorderShield", "borderShield", "Shield", "shield", "InterruptShield",
    "interruptShield", "UninterruptibleShield", "uninterruptibleShield",
    "NotInterruptibleShield", "notInterruptibleShield",
}

local SHIELD_GLOBAL_SUFFIXES = {
    "BorderShield", "BorderShieldFrame", "Shield", "InterruptShield",
    "UninterruptibleShield", "NotInterruptibleShield",
}

local function appendShieldWidget(out, widget, label)
    if widget ~= nil then out[#out + 1] = { widget = widget, label = label } end
end

-- Current Retail templates do not always expose BorderShield as a direct Lua
-- field. Scan only named/atlased children and regions whose identifiers are
-- explicitly shield-related; generic castbar decoration is never treated as a
-- steel-bar proof. This remains read-only and retains no frame object.
local function shieldIdentifier(value)
    local text = plainText(value)
    if not text then return false end
    local ok, lower = pcall(string.lower, text)
    if not ok or type(lower) ~= "string" then return false end
    return string.find(lower, "shield", 1, true) ~= nil
        or string.find(lower, "uninterruptible", 1, true) ~= nil
        or string.find(lower, "notinterruptible", 1, true) ~= nil
end

local function appendSemanticShieldWidgets(out, frame)
    for _, child in ipairs(safeMethodList(frame, "GetChildren")) do
        local name = safeMethodText(child, "GetName")
        if shieldIdentifier(name) then appendShieldWidget(out, child, "child:" .. tostring(name)) end
    end
    for _, region in ipairs(safeMethodList(frame, "GetRegions")) do
        local name = safeMethodText(region, "GetName")
        local atlas = safeMethodText(region, "GetAtlas")
        local texture = safeMethodText(region, "GetTexture")
        if shieldIdentifier(name) or shieldIdentifier(atlas) or shieldIdentifier(texture) then
            local label = name or atlas or texture or "shield_region"
            appendShieldWidget(out, region, "region:" .. tostring(label))
        end
    end
end

local function nativeShieldShown(frame, globalPrefix)
    -- Prefer parent-key access, then probe the well-known global child names
    -- used by Blizzard's target/focus spell bars.  The latter matters on
    -- current Retail templates where the shield is not consistently exposed as
    -- a Lua parent-key even though the child widget itself is still visible.
    local candidates = {}
    for _, field in ipairs(SHIELD_FIELD_NAMES) do
        appendShieldWidget(candidates, safeObjectField(frame, field), field)
    end
    if type(globalPrefix) == "string" and globalPrefix ~= "" then
        for _, suffix in ipairs(SHIELD_GLOBAL_SUFFIXES) do
            appendShieldWidget(candidates, safeObjectField(_G, globalPrefix .. suffix), globalPrefix .. suffix)
        end
    end
    local frameName = safeMethodText(frame, "GetName")
    if frameName and frameName ~= globalPrefix then
        for _, suffix in ipairs(SHIELD_GLOBAL_SUFFIXES) do
            appendShieldWidget(candidates, safeObjectField(_G, frameName .. suffix), frameName .. suffix)
        end
    end
    appendSemanticShieldWidgets(candidates, frame)

    local hiddenField = nil
    for _, candidate in ipairs(candidates) do
        local shown = safeMethodBoolean(candidate.widget, "IsShown")
        if shown == nil then shown = safeMethodBoolean(candidate.widget, "IsVisible") end
        if shown == true then return true, candidate.label end
        if shown == false and hiddenField == nil then hiddenField = candidate.label end
    end
    if hiddenField then return false, hiddenField end
    return nil, nil
end

-- P5.3 native shield probe: A current Retail nameplate castbar can retain its scalar
-- `notInterruptible` / `isUninterruptible` value across another player (or an
-- NPC) ending a cast and the same unit immediately beginning a new cast. That
-- scalar is useful diagnostic data, but it is not an independently visible
-- steel-bar proof. Treating scalar-only `true` as a hard steel bar made the
-- P3 prompt disappear for an otherwise visible second cast.
--
-- Evidence policy for the read-only observer:
--   * direct UnitCastingInfo/UnitChannelInfo `notInterruptible` remains exact;
--   * an actually visible Blizzard shield remains a hard steel-bar conclusion;
--   * a visible shield absence / explicit native false remains interruptible;
--   * native scalar-only true is deliberately downgraded to unknown so P3
--     displays the existing *unverified* (bindingToken=0) probe instead of
--     silently suppressing the prompt.
--
-- P4/P5 must continue to require a direct or visibly-proven result before any
-- automatic path is considered. This helper returns ordinary scalars only and
-- does not retain the castbar object itself.
local function nativeNotInterruptible(frame, globalPrefix)
    local shownShield, shieldField = nativeShieldShown(frame, globalPrefix)
    if shownShield == true then
        return true, "native_visible_shield:" .. tostring(shieldField or "shield"), true, true, true, shieldField
    end
    if shownShield == false then
        return false, "native_visible_no_shield:" .. tostring(shieldField or "shield"), false, true, false, shieldField
    end

    -- A native scalar false is a useful positive result (no steel bar). A
    -- scalar true remains diagnostic-only because live nameplate templates may
    -- retain it across an external interrupt / recast boundary.
    for _, field in ipairs({ "notInterruptible", "isUninterruptible" }) do
        local value = plainBoolean(safeObjectField(frame, field))
        if value == false then return false, "native_scalar_false:" .. field, false, false, nil, nil end
        if value == true then return nil, "native_scalar_true_unverified:" .. field, false, false, nil, nil end
    end
    for _, field in ipairs({ "interruptible", "isInterruptible" }) do
        local value = plainBoolean(safeObjectField(frame, field))
        if value == true then return false, "native_scalar_interruptible:" .. field, false, false, nil, nil end
        if value == false then return nil, "native_scalar_not_interruptible_unverified:" .. field, false, false, nil, nil end
    end

    for _, methodName in ipairs({ "IsUninterruptible", "GetIsUninterruptible" }) do
        local value = safeMethodBoolean(frame, methodName)
        if value == false then return false, "native_method_interruptible:" .. methodName, false, false, nil, nil end
        if value == true then return nil, "native_method_uninterruptible_unverified:" .. methodName, false, false, nil, nil end
    end
    for _, methodName in ipairs({ "IsInterruptible", "GetIsInterruptible", "IsCastInterruptible" }) do
        local value = safeMethodBoolean(frame, methodName)
        if value == true then return false, "native_method_interruptible:" .. methodName, false, false, nil, nil end
        if value == false then return nil, "native_method_not_interruptible_unverified:" .. methodName, false, false, nil, nil end
    end

    -- `showShield` only controls whether the template supports drawing a
    -- shield. It must never grant or veto automatic dispatch by itself.
    local showShieldConfig = plainBoolean(safeObjectField(frame, "showShield"))
    if showShieldConfig == true then
        return nil, "native_showShield_config_true", false, false, nil, nil
    end
    if showShieldConfig == false then
        return nil, "native_showShield_config_false", false, false, nil, nil
    end

    -- `barType` identifies a castbar template/style, not the current cast's
    -- interruptibility.  It is retained as diagnostics only and can never
    -- grant or veto automatic dispatch by itself.
    local kind = normalizedNativeBarType(safeObjectField(frame, "barType"))
    if kind then
        return nil, "native_bar_type_unverified:" .. kind, false, false, nil, nil
    end
    return nil, "native_interruptibility_unresolved", false, false, nil, nil
end

local function appendNativeCastbar(out, frame, label, globalPrefix)
    if frame ~= nil then
        out[#out + 1] = { frame = frame, label = label, globalPrefix = globalPrefix }
    end
end

local function nativeCastbarCandidates(unit)
    local out = {}
    if unit == "target" then
        appendNativeCastbar(out, safeObjectField(_G, "TargetFrameSpellBar"), "TargetFrameSpellBar", "TargetFrameSpellBar")
        local targetFrame = safeObjectField(_G, "TargetFrame")
        appendNativeCastbar(out, safeObjectField(targetFrame, "spellbar"), "TargetFrame.spellbar", "TargetFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(targetFrame, "SpellBar"), "TargetFrame.SpellBar", "TargetFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(targetFrame, "Spellbar"), "TargetFrame.Spellbar", "TargetFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(targetFrame, "castingBar"), "TargetFrame.castingBar", "TargetFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(targetFrame, "CastBar"), "TargetFrame.CastBar", "TargetFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(targetFrame, "castBar"), "TargetFrame.castBar", "TargetFrameSpellBar")
    elseif unit == "focus" then
        appendNativeCastbar(out, safeObjectField(_G, "FocusFrameSpellBar"), "FocusFrameSpellBar", "FocusFrameSpellBar")
        local focusFrame = safeObjectField(_G, "FocusFrame")
        appendNativeCastbar(out, safeObjectField(focusFrame, "spellbar"), "FocusFrame.spellbar", "FocusFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(focusFrame, "SpellBar"), "FocusFrame.SpellBar", "FocusFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(focusFrame, "Spellbar"), "FocusFrame.Spellbar", "FocusFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(focusFrame, "castingBar"), "FocusFrame.castingBar", "FocusFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(focusFrame, "CastBar"), "FocusFrame.CastBar", "FocusFrameSpellBar")
        appendNativeCastbar(out, safeObjectField(focusFrame, "castBar"), "FocusFrame.castBar", "FocusFrameSpellBar")
    end

    -- Nameplate castbars cover target/focus when their fixed unit-frame bar is
    -- disabled, and are the only native visual source for a mouseover unit.
    local api = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(api) == "function" then
        local ok, plate = pcall(api, unit)
        if ok and plate ~= nil then
            local unitFrame = safeObjectField(plate, "UnitFrame")
            appendNativeCastbar(out, safeObjectField(unitFrame, "castBar"), "NamePlate.UnitFrame.castBar")
            appendNativeCastbar(out, safeObjectField(unitFrame, "CastBar"), "NamePlate.UnitFrame.CastBar")
            appendNativeCastbar(out, safeObjectField(unitFrame, "castingBar"), "NamePlate.UnitFrame.castingBar")
            appendNativeCastbar(out, safeObjectField(unitFrame, "SpellBar"), "NamePlate.UnitFrame.SpellBar")
            appendNativeCastbar(out, safeObjectField(unitFrame, "spellbar"), "NamePlate.UnitFrame.spellbar")
            appendNativeCastbar(out, safeObjectField(plate, "castBar"), "NamePlate.castBar")
            appendNativeCastbar(out, safeObjectField(plate, "CastBar"), "NamePlate.CastBar")
            appendNativeCastbar(out, safeObjectField(plate, "SpellBar"), "NamePlate.SpellBar")
        end
    end
    return out
end

local function readNativeCastbarRecord(unit)
    for _, candidate in ipairs(nativeCastbarCandidates(unit)) do
        local active, kind = nativeFrameActive(candidate.frame)
        if active == true then
            local notInterruptible, interruptibilityEvidence, steelConfirmed, shieldKnown, shieldVisible, shieldSource = nativeNotInterruptible(candidate.frame, candidate.globalPrefix)
            return {
                kind = kind,
                spellID = safeObjectField(candidate.frame, "spellID"),
                startTimeMS = plainNumber(safeObjectField(candidate.frame, "startTime"))
                    or plainNumber(safeObjectField(candidate.frame, "startTimeMS")),
                endTimeMS = plainNumber(safeObjectField(candidate.frame, "endTime"))
                    or plainNumber(safeObjectField(candidate.frame, "endTimeMS")),
                notInterruptible = notInterruptible,
                evidence = "native_castbar:" .. candidate.label,
                apiReturnArity = nil,
                nativeCastbar = true,
                nativeBarSource = candidate.label,
                nativeInterruptibilityEvidence = interruptibilityEvidence,
                nativeSteelConfirmed = steelConfirmed == true,
                nativeShieldKnown = shieldKnown == true,
                nativeShieldVisible = shieldVisible == true,
                nativeShieldSource = shieldSource,
            }
        end
    end
    return nil
end

local function readCast(unit)
    local apiRecord = readCastingInfoRecord(unit) or readChannelInfoRecord(unit)
    local nativeRecord = readNativeCastbarRecord(unit)
    local record = apiRecord or nativeRecord
    if not record then
        return {
            active = false,
            kind = nil,
            spellID = nil,
            startTimeMS = nil,
            endTimeMS = nil,
            interruptibleKnown = false,
            interruptible = false,
            directInterruptibilityKnown = false,
            nativeInterruptibilityKnown = false,
            interruptibilitySource = "unknown",
            evidence = "no_complete_cast_record",
            interruptibilityEvidence = "none",
            apiReturnArity = nil,
            nativeCastbar = false,
            nativeBarSource = nil,
            nativeInterruptibilityEvidence = nil,
            nativeSteelConfirmed = false,
            nativeShieldKnown = false,
            nativeShieldVisible = false,
            nativeShieldSource = nil,
            continuity = "none",
        }
    end

    -- Do not write this as `apiRecord and plainBoolean(...) or nil`: Lua's
    -- `and/or` idiom collapses the authoritative ordinary `false` value into
    -- nil.  Here false is the decisive proof that the current API cast is
    -- interruptible, so retain it exactly.
    local directNotInterruptible = nil
    if apiRecord ~= nil then
        directNotInterruptible = plainBoolean(apiRecord.notInterruptible)
    end
    local resolvedNotInterruptible = directNotInterruptible
    local directInterruptibilityKnown = directNotInterruptible ~= nil
    local nativeInterruptibilityKnown = false
    local evidence = record.evidence
    local interruptibilityEvidence = directInterruptibilityKnown and "unit_api"
        or (apiRecord and "unit_api_opaque" or (nativeRecord and nativeRecord.nativeInterruptibilityEvidence or "unresolved"))

    -- A direct UnitCastingInfo / UnitChannelInfo boolean is authoritative.  If
    -- it is opaque, the current native cast bar may only contribute an explicit
    -- per-cast visual result (actual shield shown/hidden) or an explicit native
    -- interruptibility method. `showShield` configuration never participates.
    if resolvedNotInterruptible == nil and nativeRecord then
        local nativeNotInterruptible = plainBoolean(nativeRecord.notInterruptible)
        if nativeNotInterruptible ~= nil then
            resolvedNotInterruptible = nativeNotInterruptible
            nativeInterruptibilityKnown = true
            interruptibilityEvidence = nativeRecord.nativeInterruptibilityEvidence or "native_explicit"
            evidence = tostring(evidence or "cast_record") .. "+native_interrupt_state"
        end
    end

    return {
        active = true,
        kind = record.kind,
        -- The spell name is deliberately never retained in the snapshot or SavedVariables.
        spellID = plainNumber(record.spellID) or (nativeRecord and plainNumber(nativeRecord.spellID) or nil),
        startTimeMS = plainNumber(record.startTimeMS) or (nativeRecord and plainNumber(nativeRecord.startTimeMS) or nil),
        endTimeMS = plainNumber(record.endTimeMS) or (nativeRecord and plainNumber(nativeRecord.endTimeMS) or nil),
        interruptibleKnown = resolvedNotInterruptible ~= nil,
        interruptible = resolvedNotInterruptible == false,
        directInterruptibilityKnown = directInterruptibilityKnown,
        nativeInterruptibilityKnown = nativeInterruptibilityKnown,
        interruptibilitySource = directInterruptibilityKnown and "unit_api"
            or (nativeInterruptibilityKnown and "native" or "unknown"),
        evidence = evidence,
        interruptibilityEvidence = interruptibilityEvidence,
        apiReturnArity = plainNumber(record.apiReturnArity),
        nativeCastbar = nativeRecord ~= nil,
        nativeBarSource = nativeRecord and nativeRecord.nativeBarSource or nil,
        -- Keep the native evidence separately.  When UnitCastingInfo exists
        -- but its notInterruptible value is opaque, P4 needs to distinguish an
        -- actual visible shield/no-shield result from unverified diagnostics
        -- without ever retaining a castbar frame.
        nativeInterruptibilityEvidence = nativeRecord and nativeRecord.nativeInterruptibilityEvidence or nil,
        nativeSteelConfirmed = nativeRecord and nativeRecord.nativeSteelConfirmed == true or false,
        nativeShieldKnown = nativeRecord and nativeRecord.nativeShieldKnown == true or false,
        nativeShieldVisible = nativeRecord and nativeRecord.nativeShieldVisible == true or false,
        nativeShieldSource = nativeRecord and nativeRecord.nativeShieldSource or nil,
        continuity = "live",
    }

end

-- The legacy native castbar may briefly report inactive during the visual reset
-- after somebody else interrupts it, even though a new cast begins on the next
-- shared poll. Keep one short presentation-only bridge for target/focus/
-- mouseover. The bridge deliberately downgrades interruptibility to unknown;
-- it never revives a confirmed cast as an automatic / confirmed interrupt.
local TRANSIENT_CAST_GAP_SECONDS = 0.22
local transientCastPresence = {}

-- P4 needs a one-shot identity even when Retail hides a cast name or its exact
-- timestamps.  Maintain a scalar generation per observed unit source.  The
-- generation advances only when the raw (pre-bridge) cast state transitions
-- inactive -> active or when readable identity fields change.  The P3 bridge
-- can therefore keep a visual prompt continuous without causing P4 to treat a
-- later cast as the old already-offered cast.
local function readableCastIdentity(cast)
    cast = type(cast) == "table" and cast or {}
    local spellID = math.floor(plainNumber(cast.spellID) or 0)
    local start = math.floor(plainNumber(cast.startTimeMS) or 0)
    local finish = math.floor(plainNumber(cast.endTimeMS) or 0)
    if spellID == 0 and start == 0 and finish == 0 then return nil end
    return table.concat({ tostring(cast.kind or "cast"), tostring(spellID), tostring(start), tostring(finish) }, ":")
end

local function stabilizeCastPresence(source, cast)
    cast = type(cast) == "table" and cast or {}
    if source == "nameplate" then return cast end
    local time = now()
    local state = transientCastPresence[source] or { serial = 0, rawActive = false }
    if cast.active == true then
        local identity = readableCastIdentity(cast)
        if state.rawActive ~= true or (identity ~= nil and identity ~= state.identity) then
            state.serial = (tonumber(state.serial) or 0) + 1
        end
        state.rawActive = true
        state.identity = identity or state.identity
        state.observedAt = time
        state.kind = cast.kind
        transientCastPresence[source] = state
        cast.castSerial = state.serial
        return cast
    end

    -- Record a real raw gap even when the short P3 display bridge is returned
    -- below.  The next live cast receives a new serial, preventing P4's
    -- one-attempt-per-cast latch from suppressing it.
    if state.rawActive == true then
        state.rawActive = false
        state.identity = nil
        state.gapObservedAt = time
    end
    local observedAt = plainNumber(state.observedAt)
    if observedAt and time >= observedAt and (time - observedAt) <= TRANSIENT_CAST_GAP_SECONDS then
        transientCastPresence[source] = state
        return {
            active = true,
            kind = state.kind,
            spellID = nil,
            startTimeMS = nil,
            endTimeMS = nil,
            castSerial = state.serial,
            interruptibleKnown = false,
            interruptible = false,
            directInterruptibilityKnown = false,
            nativeInterruptibilityKnown = false,
            interruptibilitySource = "unknown",
            evidence = "transient_native_castbar_gap",
            interruptibilityEvidence = "transient_gap_unverified",
            nativeInterruptibilityEvidence = nil,
            apiReturnArity = nil,
            nativeCastbar = false,
            nativeBarSource = nil,
            nativeSteelConfirmed = false,
            nativeShieldKnown = false,
            nativeShieldVisible = false,
            nativeShieldSource = nil,
            continuity = "transient_gap_hold",
        }
    end
    transientCastPresence[source] = nil
    return cast
end

local function readUnit(unit, source)
    local exists = callBoolean(UnitExists, unit)
    if exists ~= true then
        return {
            source = source,
            exists = false,
            existsKnown = exists ~= nil,
            hostile = false,
            hostileKnown = false,
            alive = false,
            aliveKnown = false,
            isPlayer = false,
            classification = nil,
            bossLike = false,
            controlEligible = false,
            cast = { active = false, interruptibleKnown = false, interruptible = false, evidence = "unit_missing" },
        }
    end

    local dead = callBoolean(UnitIsDeadOrGhost, unit)
    local hostile = callBoolean(UnitCanAttack, "player", unit)
    local isPlayer = callBoolean(UnitIsPlayer, unit)
    local classification = callText(UnitClassification, unit)
    local unitLevel = callNumber(UnitLevel, unit)
    local bossByApi = callBoolean(UnitIsBossMob, unit)
    local bossLike = bossByApi == true or unitLevel == -1 or CONTROL_EXCLUDED_CLASSIFICATIONS[classification or ""] == true
    local alive = dead == false
    local controlEligible = hostile == true and alive == true and (
        isPlayer == true or (isPlayer == false and bossLike ~= true and classification ~= nil)
    )

    return {
        source = source,
        exists = true,
        existsKnown = exists ~= nil,
        hostile = hostile == true,
        hostileKnown = hostile ~= nil,
        alive = alive == true,
        aliveKnown = dead ~= nil,
        isPlayer = isPlayer == true,
        classification = classification,
        bossLike = bossLike == true,
        controlEligible = controlEligible == true,
        cast = stabilizeCastPresence(source, readCast(unit)),
    }
end

local function nameplateUnitToken(plate)
    if type(plate) ~= "table" then return nil end
    local direct = plainText(plate.namePlateUnitToken)
    if direct then return direct end
    local frame = plate.UnitFrame
    return type(frame) == "table" and plainText(frame.unit) or nil
end

local function readNameplateControlCastCount()
    if NAMEPLATE_CONTROL_SCAN_SUSPENDED == true then
        return {
            active = false,
            qualifyingCount = 0,
            inspectedCount = 0,
            threshold = AOE_CONTROL_THRESHOLD,
            reason = "nameplate_control_scan_suspended",
        }
    end
    local api = C_NamePlate and C_NamePlate.GetNamePlates
    if type(api) ~= "function" then
        return {
            active = false,
            qualifyingCount = 0,
            inspectedCount = 0,
            threshold = AOE_CONTROL_THRESHOLD,
            reason = "nameplate_api_unavailable",
        }
    end
    local ok, plates = pcall(api, false)
    if not ok or type(plates) ~= "table" then
        return {
            active = false,
            qualifyingCount = 0,
            inspectedCount = 0,
            threshold = AOE_CONTROL_THRESHOLD,
            reason = "nameplate_read_failed",
        }
    end

    local qualifying, inspected, seen = 0, 0, {}
    for _, plate in ipairs(plates) do
        local token = nameplateUnitToken(plate)
        if token and not seen[token] then
            seen[token] = true
            local unit = readUnit(token, "nameplate")
            inspected = inspected + 1
            local cast = unit.cast or {}
            -- Group-control scanning deliberately counts only visible hostile
            -- non-elite/non-boss units whose cast is explicitly known to be
            -- non-interruptible. Unknown cast properties are never promoted.
            if unit.controlEligible == true
                and cast.active == true
                and cast.interruptibleKnown == true
                and cast.interruptible == false then
                qualifying = qualifying + 1
            end
        end
    end

    return {
        active = qualifying >= AOE_CONTROL_THRESHOLD,
        qualifyingCount = qualifying,
        inspectedCount = inspected,
        threshold = AOE_CONTROL_THRESHOLD,
        reason = qualifying >= AOE_CONTROL_THRESHOLD and "threshold_met" or "below_threshold",
    }
end

function ReactionObservation:Refresh()
    local sources = {
        target = readUnit("target", "target"),
        focus = readUnit("focus", "focus"),
        mouseover = readUnit("mouseover", "mouseover"),
    }
    local aoe = readNameplateControlCastCount()
    self.snapshot = {
        schema = self.schemaVersion,
        observedAt = now(),
        source = "protocol_monitor_shared_poll",
        readOnly = true,
        dispatchAllowed = false,
        sources = sources,
        aoe = aoe,
    }
    return self.snapshot
end

function ReactionObservation:Sample()
    return self.snapshot or self:Refresh()
end
