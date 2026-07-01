local TE = _G.TacticEcho

-- v3 action-bar resolver.  This module is deliberately read-only: it never
-- writes bindings, changes action bars, or edits player macros.  It builds an
-- event-driven cache of the currently visible Blizzard default action buttons;
-- recommendation-time work is therefore a cache lookup, not another full bar
-- scan.
local Resolver = {}
TE.ActionBarBindingResolver = Resolver

Resolver.schemaVersion = 2
Resolver.lastReason = "not_scanned"
Resolver.lastScanReason = "not_scanned"
Resolver.cache = {}
Resolver.buttonCache = nil
Resolver.cacheDirty = true
Resolver.scanGeneration = 0
-- Binding updates can arrive before the client commits all keyboard/gamepad
-- mappings.  During this brief settling window, retain the last known-good
-- cache and rebuild once after bindings are stable.
Resolver.bindingSettlingUntil = 0
Resolver.bindingSettleDelay = 0.30
Resolver.bindingSettleSerial = 0
-- The current default Blizzard main/bonus/stance bars are valid v3 sources.
-- Vehicle, possession, override and pet-battle contexts replace player actions
-- and are blocked. An extra-action button is auxiliary UI: it is recorded for
-- diagnostics but does not replace the player action bar or block resolution.
Resolver.specialActionBarState = {
    active = false, reason = nil, sources = {},
    extraActionVisible = false, extraActionSources = {},
}

-- BindingToken schema 1.  Keep this list in sync with TEK binding_tokens.py.
local MAIN_KEYS = {
    Q=1,E=2,R=3,F=4,["1"]=5,["2"]=6,["3"]=7,["4"]=8,["5"]=9,
    Z=10,X=11,C=12,V=13,T=14,G=15,F1=16,F2=17,F3=18,F4=19,["`"]=20,
    MOUSEWHEELUP=21,MOUSEWHEELDOWN=22,BUTTON3=23,
}
local MODIFIERS = { [""]=0, ALT=1, CTRL=2 }
local SOURCE = { keyboard=0, wheel=1, mouse=2 }

-- Only Blizzard default bars are scanned.  The resolver keeps a state-aware
-- slot mapping from Blizzard's visible action-bar frames and also retains the
-- visible button's action attribute as a diagnostic fallback.  This matters
-- for paging and bonus/form bars: ActionButton1 can represent slot 1, 13, 25,
-- or a bonus-bar slot while its binding command remains ACTIONBUTTON1.
local NUM_BUTTONS = tonumber(NUM_ACTIONBAR_BUTTONS) or 12
local BUTTON_SPECS = {
    { prefix="ActionButton", bindingPrefix="ACTIONBUTTON", count=NUM_BUTTONS, bar="main", pageKind="main", order=10 },
    { prefix="MultiBarBottomLeftButton", bindingPrefix="MULTIACTIONBAR1BUTTON", count=NUM_BUTTONS, bar="bottom_left", page=6, order=20 },
    { prefix="MultiBarBottomRightButton", bindingPrefix="MULTIACTIONBAR2BUTTON", count=NUM_BUTTONS, bar="bottom_right", page=5, order=30 },
    { prefix="MultiBarRightButton", bindingPrefix="MULTIACTIONBAR3BUTTON", count=NUM_BUTTONS, bar="right", page=3, order=40 },
    { prefix="MultiBarLeftButton", bindingPrefix="MULTIACTIONBAR4BUTTON", count=NUM_BUTTONS, bar="left", page=4, order=50 },
    -- Retail exposes additional default bars on some layouts.  Missing frame
    -- names are harmless; they are simply skipped during a cache rebuild.
    { prefix="MultiBar5Button", bindingPrefix="MULTIACTIONBAR5BUTTON", count=NUM_BUTTONS, bar="extra_5", page=13, order=60 },
    { prefix="MultiBar6Button", bindingPrefix="MULTIACTIONBAR6BUTTON", count=NUM_BUTTONS, bar="extra_6", page=14, order=70 },
    { prefix="MultiBar7Button", bindingPrefix="MULTIACTIONBAR7BUTTON", count=NUM_BUTTONS, bar="extra_7", page=15, order=80 },
}
local STANCE_SPEC = { prefix="StanceButton", bindingPrefix="SHAPESHIFTBUTTON", count=10, bar="stance", order=90 }

local function currentMainPage()
    local page = 1
    if type(GetActionBarPage) == "function" then
        local ok, value = pcall(GetActionBarPage)
        if ok and tonumber(value) and tonumber(value) > 0 then page = tonumber(value) end
    end
    if type(GetBonusBarOffset) == "function" then
        local ok, offset = pcall(GetBonusBarOffset)
        offset = ok and tonumber(offset) or 0
        if offset and offset > 0 then page = 6 + offset end
    end
    return math.max(1, page)
end

-- Compact signature used as a missed-event safety net.  It covers every
-- state that changes which physical action slot a visible default button means.
local function actionBarStateSignature()
    local page = 1
    local bonusOffset, form = 0, 0
    if type(GetActionBarPage) == "function" then
        local ok, value = pcall(GetActionBarPage)
        if ok and tonumber(value) and tonumber(value) > 0 then page = tonumber(value) end
    end
    if type(GetBonusBarOffset) == "function" then
        local ok, value = pcall(GetBonusBarOffset)
        if ok then bonusOffset = tonumber(value) or 0 end
    end
    if type(GetShapeshiftForm) == "function" then
        local ok, value = pcall(GetShapeshiftForm)
        if ok then form = tonumber(value) or 0 end
    end
    local override = type(HasOverrideActionBar) == "function" and HasOverrideActionBar() == true or false
    local vehicle = type(HasVehicleActionBar) == "function" and HasVehicleActionBar() == true or false
    local temp = type(HasTempShapeshiftActionBar) == "function" and HasTempShapeshiftActionBar() == true or false
    return page + bonusOffset * 100 + form * 10000
        + (override and 1000000 or 0) + (vehicle and 2000000 or 0) + (temp and 4000000 or 0)
end

local function calculatedActionSlot(spec, index)
    local page = spec.pageKind == "main" and currentMainPage() or tonumber(spec.page)
    if not page or page <= 0 then return nil end
    return tonumber(index) + ((page - 1) * NUM_BUTTONS)
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return false, nil end
    return true, a, b, c, d
end

local function safeBoolean(fn, ...)
    local ok, value = safeCall(fn, ...)
    return ok and value == true
end

local function frameIsShown(name)
    local frame = _G[name]
    if not frame or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = safeCall(frame.IsShown, frame)
    return ok and shown == true
end

-- Contexts that replace player actions are intentionally fail-closed. Normal
-- bonus/form paging is handled by currentMainPage(); vehicle, possess,
-- override and pet battle are blocked. An extra-action button is auxiliary
-- UI and remains observation-only.
local function readSpecialActionBarState()
    local sources = {}
    local extraActionSources = {}

    local function observeExtraAction(source)
        extraActionSources[#extraActionSources + 1] = source
    end

    local function state(active, reason)
        return {
            active = active == true,
            reason = reason,
            sources = sources,
            extraActionVisible = #extraActionSources > 0,
            extraActionSources = extraActionSources,
        }
    end

    local function mark(reason, source)
        sources[#sources + 1] = source
        return state(true, reason)
    end

    -- An extra-action button (for example an encounter/quest ability) is an
    -- auxiliary action. It can coexist with a fully usable player action bar,
    -- so it must be observable without fail-closing normal recommendations.
    if safeBoolean(HasExtraActionBar) then
        observeExtraAction("HasExtraActionBar")
    end
    if frameIsShown("ExtraActionBarFrame") or frameIsShown("ExtraActionButton1") then
        observeExtraAction("ExtraActionBarFrame")
    end

    if safeBoolean(UnitHasVehicleUI, "player") then
        return mark("special_actionbar_vehicle", "UnitHasVehicleUI")
    end
    if safeBoolean(HasOverrideActionBar) then
        return mark("special_actionbar_override", "HasOverrideActionBar")
    end
    if type(GetPossessBarIndex) == "function" then
        local ok, index = safeCall(GetPossessBarIndex)
        if ok and tonumber(index) and tonumber(index) > 0 then
            return mark("special_actionbar_possess", "GetPossessBarIndex")
        end
    end
    if C_PetBattles and type(C_PetBattles.IsInBattle) == "function" and safeBoolean(C_PetBattles.IsInBattle) then
        return mark("special_actionbar_pet_battle", "C_PetBattles.IsInBattle")
    end

    -- Frame fallbacks only identify contexts that replace player actions.
    -- ExtraActionBarFrame was intentionally handled above as observation-only.
    if frameIsShown("OverrideActionBar") or frameIsShown("OverrideActionBarFrame") then
        return mark("special_actionbar_override", "OverrideActionBarFrame")
    end
    if frameIsShown("PossessBarFrame") then
        return mark("special_actionbar_possess", "PossessBarFrame")
    end
    if frameIsShown("PetBattleFrame") then
        return mark("special_actionbar_pet_battle", "PetBattleFrame")
    end
    return state(false, nil)
end

local function trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function normalize(binding)
    if type(binding) ~= "string" or binding == "" then return nil, "binding_missing" end
    local raw = binding:upper():gsub("%-", "+")
    local modifier, key = raw:match("^(ALT)%+(.+)$")
    if not modifier then modifier, key = raw:match("^(CTRL)%+(.+)$") end
    if not key then key, modifier = raw, "" end
    if modifier ~= "" and (key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN" or key == "BUTTON3") then
        return nil, "mouse_modifier_unsupported"
    end
    local code = MAIN_KEYS[key]
    if not code then return nil, "binding_unsupported:" .. tostring(raw) end
    local inputType = SOURCE.keyboard
    if key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN" then inputType = SOURCE.wheel end
    if key == "BUTTON3" then inputType = SOURCE.mouse end
    return {
        binding = raw,
        token = code + (MODIFIERS[modifier] or 0) * 64 + inputType * 1024,
        inputType = inputType,
        key = key,
        modifier = modifier,
    }
end

local function getSpellName(spellID)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
        if type(info) == "string" and info ~= "" then return info end
    end
    if type(GetSpellInfo) == "function" then
        local name = GetSpellInfo(spellID)
        if type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

local function normalizeSpellID(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    if type(value) == "table" then return tonumber(value.spellID or value.spellId or value.id) end
    return nil
end

local function macroSpellMatches(spellValue, spellID, spellName)
    local numeric = normalizeSpellID(spellValue)
    if numeric and tonumber(spellID) and numeric == tonumber(spellID) then return true end
    if type(spellValue) == "string" and type(spellName) == "string" and spellValue == spellName then return true end
    return false
end

-- User-confirmed macro policy: never interpret or execute macro branches.
-- A macro button is only associated to a recommendation when Blizzard reports
-- its current macro spell or its cached body explicitly contains the localized
-- spell name / numeric SpellID.  Once associated, TEK only presses the
-- player's existing bound macro button.
local function macroBodyReferencesSpell(body, spellName, spellID)
    -- A textual macro-body fallback is intentionally stricter than Blizzard's
    -- current macro-spell APIs.  We never evaluate conditions, targets or
    -- multi-command branches.  Only one unconditioned /cast line with an
    -- exact spell name/ID is safe to associate by text alone.  Complex macros
    -- remain visible in diagnostics and can still resolve when Blizzard itself
    -- reports their current macro spell through GetMacroSpell/ActionInfo.
    if type(body) ~= "string" or body == "" then return false end
    local directArgument = nil
    local actionableLines = 0
    for raw in body:gmatch("[^\r\n]+") do
        local line = trim(raw)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local command, argument = line:match("^(%S+)%s*(.-)$")
            command = type(command) == "string" and command:lower() or nil
            argument = trim(argument)
            if command == "/cast" or command == "/use" or command == "/castsequence" then
                actionableLines = actionableLines + 1
                -- Conditional blocks, target directives and semicolon branches
                -- require macro evaluation and are never inferred here.
                if command ~= "/cast" or argument:find("[", 1, true)
                    or argument:find(";", 1, true) or argument:find("@", 1, true) then
                    return false
                end
                directArgument = argument
            end
        end
    end
    if actionableLines ~= 1 or not directArgument or directArgument == "" then return false end
    return macroSpellMatches(directArgument, spellID, spellName)
end

local function macroBodyLength(body)
    return type(body) == "string" and #body or 0
end

local function lookupMacroByName(name)
    if type(name) ~= "string" or name == "" or type(GetMacroInfo) ~= "function" then return nil end

    local okNamed, macroName, icon, body = safeCall(GetMacroInfo, name)
    if okNamed and macroName and body then
        return { macroIndex=name, macroName=macroName, icon=icon, body=body, lookup="GetMacroInfo(actionText)" }
    end

    if type(GetNumMacros) ~= "function" then return nil end
    local okCount, globalCount, characterCount = safeCall(GetNumMacros)
    if not okCount then return nil end
    globalCount = tonumber(globalCount) or 0
    characterCount = tonumber(characterCount) or 0
    for index = 1, globalCount do
        local ok, candidateName, candidateIcon, candidateBody = safeCall(GetMacroInfo, index)
        if ok and candidateName == name then
            return { macroIndex=index, macroName=candidateName, icon=candidateIcon, body=candidateBody, lookup="enumerate_global" }
        end
    end
    -- Blizzard reserves 1..120 for account macros; character macros are
    -- conventionally addressed from 121 onward.
    for index = 121, 120 + characterCount do
        local ok, candidateName, candidateIcon, candidateBody = safeCall(GetMacroInfo, index)
        if ok and candidateName == name then
            return { macroIndex=index, macroName=candidateName, icon=candidateIcon, body=candidateBody, lookup="enumerate_character" }
        end
    end
    return nil
end

local function resolveMacroFromActionSlot(actionSlot, actionInfoID)
    local diag = { actionSlot=actionSlot, actionInfoId=actionInfoID }

    local okText, actionText = safeCall(GetActionText, actionSlot)
    diag.actionText = okText and actionText or nil

    local okSpellByID, macroSpellByID = safeCall(GetMacroSpell, actionInfoID)
    diag.getMacroSpellByActionInfoId = okSpellByID and macroSpellByID or nil

    local okInfoByID, nameByID, _, bodyByID = safeCall(GetMacroInfo, actionInfoID)
    diag.getMacroInfoByActionInfoIdSuccess = okInfoByID and nameByID ~= nil
    diag.getMacroInfoByActionInfoIdBodyLength = macroBodyLength(bodyByID)
    if okInfoByID and nameByID and bodyByID then
        diag.resolvedMacroIndex = actionInfoID
        diag.macroName = nameByID
        diag.body = bodyByID
        diag.lookupSource = "actionInfoId"
        return diag
    end

    local resolved = lookupMacroByName(actionText)
    if resolved then
        diag.resolvedMacroIndex = resolved.macroIndex
        diag.macroName = resolved.macroName
        diag.body = resolved.body
        diag.lookupSource = resolved.lookup
        diag.lookupByActionText = true
        local okResolvedSpell, resolvedSpell = safeCall(GetMacroSpell, resolved.macroIndex)
        diag.getMacroSpellByResolvedIndex = okResolvedSpell and resolvedSpell or nil
        diag.resolvedBodyLength = macroBodyLength(resolved.body)
        return diag
    end

    diag.lookupByActionText = false
    diag.failureReason = (actionText and actionText ~= "") and "macro_lookup_failed" or "macro_action_text_missing"
    return diag
end

local function buttonAttributeActionSlot(button)
    if not button then return nil end
    local actionSlot = nil
    if type(button.GetAttribute) == "function" then
        local ok, value = safeCall(button.GetAttribute, button, "action")
        if ok then actionSlot = tonumber(value) end
    end
    if not actionSlot or actionSlot <= 0 then actionSlot = tonumber(button.action) end
    return actionSlot and actionSlot > 0 and actionSlot or nil
end

local function resolveButtonActionSlot(button, spec, index)
    local calculated = calculatedActionSlot(spec, index)
    local attribute = buttonAttributeActionSlot(button)
    -- The calculated mapping is authoritative for the standard Blizzard
    -- action bars because it follows paging and bonus/form offsets.  The
    -- attribute remains a fallback for API/layout variations and is recorded.
    if calculated then return calculated, "state_mapping", attribute end
    if attribute then return attribute, "button_action_attribute", attribute end
    return nil, "button_action_missing", attribute
end

local function actionInfoForButton(button, spec, index)
    local actionSlot, source, attributeSlot = resolveButtonActionSlot(button, spec, index)
    if not actionSlot then return nil, nil, nil, nil, nil, source, attributeSlot end
    local actionType, actionInfoID, subType, actionMacroSpellID = GetActionInfo(actionSlot)
    -- If Blizzard's actual visible button reports a different live action and
    -- the calculated slot is empty, retain it as a controlled diagnostic
    -- fallback rather than silently losing the currently displayed button.
    if not actionType and attributeSlot and attributeSlot ~= actionSlot then
        local attrType, attrID, attrSubType, attrMacroSpellID = GetActionInfo(attributeSlot)
        if attrType then
            return attributeSlot, attrType, attrID, attrSubType, attrMacroSpellID, "button_action_attribute_fallback", attributeSlot
        end
    end
    return actionSlot, actionType, actionInfoID, subType, actionMacroSpellID, source, attributeSlot
end

local function stanceSpellID(button, index)
    local candidates = {}
    if button and type(button.GetAttribute) == "function" then
        local okSpell, value = safeCall(button.GetAttribute, button, "spell")
        if okSpell then candidates[#candidates + 1] = value end
        local okSpellID, valueID = safeCall(button.GetAttribute, button, "spellID")
        if okSpellID then candidates[#candidates + 1] = valueID end
    end
    if button then
        candidates[#candidates + 1] = button.spellID
        candidates[#candidates + 1] = button.spell
    end
    for _, value in ipairs(candidates) do
        local normalized = normalizeSpellID(value)
        if normalized and normalized > 0 then return normalized, "stance_button" end
    end
    if type(GetShapeshiftFormInfo) == "function" then
        local ok, _, _, _, _, spellID = pcall(GetShapeshiftFormInfo, index)
        local normalized = normalizeSpellID(spellID)
        if normalized and normalized > 0 then return normalized, "GetShapeshiftFormInfo" end
    end
    return nil, "stance_spell_missing"
end

local function buttonIsVisible(button)
    if not button then return false end
    if type(button.IsShown) == "function" and not button:IsShown() then return false end
    if type(button.IsVisible) == "function" and not button:IsVisible() then return false end
    return true
end

local function buttonCoordinates(button)
    if type(button.GetCenter) ~= "function" then return nil, nil end
    local ok, x, y = safeCall(button.GetCenter, button)
    if ok then return tonumber(x), tonumber(y) end
    return nil, nil
end

local function addBySpell(index, spellID, entry)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return end
    index[spellID] = index[spellID] or {}
    index[spellID][#index[spellID] + 1] = entry
end

-- Item actions use the same visible-button and real-binding scan as spells.
-- This is read-only data for tactical survival diagnostics; it does not add an
-- item to the primary recommendation, BindingToken flow, or TEK dispatch.
local function addByItem(index, itemID, entry)
    addBySpell(index, itemID, entry)
end

local function resolveBindingPair(primaryBinding, secondaryBinding)
    -- GetBindingKey can legitimately return nil for the primary binding while
    -- a valid secondary binding exists. Do not put the pair in an array and
    -- use ipairs: Lua stops at the first nil and silently drops the second key.
    -- Explicitly probe both slots so ALT+Q / CTRL+Q secondary bindings can be
    -- normalized into the same existing BindingToken safety path.
    local rawBinding, parsedBinding, bindingError, bindingSourceIndex = nil, nil, nil, nil
    for bindingIndex = 1, 2 do
        -- Do not use `condition and primary or secondary` here: a nil primary
        -- would incorrectly fall through to secondary while still reporting
        -- bindingSourceIndex = 1.
        local candidateBinding
        if bindingIndex == 1 then
            candidateBinding = primaryBinding
        else
            candidateBinding = secondaryBinding
        end
        if candidateBinding and candidateBinding ~= "" then
            if not rawBinding then
                rawBinding = candidateBinding
                bindingSourceIndex = bindingIndex
            end
            local parsed, errorReason = normalize(candidateBinding)
            if parsed then
                return candidateBinding, parsed, nil, bindingIndex
            end
            bindingError = bindingError or errorReason
        end
    end
    return rawBinding, nil, bindingError or "binding_missing", bindingSourceIndex
end


local function buildMacroEntry(base, actionInfoID, subType, actionMacroSpellID)
    local diag = resolveMacroFromActionSlot(base.actionSlot, actionInfoID)
    diag.slot = base.actionSlot
    diag.buttonName = base.buttonName
    diag.bindingCommand = base.bindingCommand
    diag.rawBinding = base.rawBinding
    diag.subType = subType
    diag.actionMacroSpellID = actionMacroSpellID

    base.source = "macro"
    base.actionInfoId = actionInfoID
    base.macroDiagnostic = diag
    base.macroID = diag.resolvedMacroIndex or actionInfoID
    base.macroName = diag.macroName or diag.actionText
    base.macroBody = diag.body
    base.macroSemantics = TE.MacroSemantics and TE.MacroSemantics:Analyze(diag.body) or nil
    base.macroSpellID = actionMacroSpellID
    base.macroResolvedSpellID = normalizeSpellID(diag.getMacroSpellByResolvedIndex)
    base.macroActionInfoSpellID = normalizeSpellID(diag.getMacroSpellByActionInfoId)
    return base
end

local function appendEntry(cache, entry)
    cache.entries[#cache.entries + 1] = entry
    if entry.source == "macro" then cache.macroEntries[#cache.macroEntries + 1] = entry end
end

local function scanStandardButton(cache, spec, index)
    cache.scannedButtons = cache.scannedButtons + 1
    local buttonName = spec.prefix .. index
    local button = _G[buttonName]
    if not buttonIsVisible(button) then return end
    cache.visibleButtons = cache.visibleButtons + 1

    local actionSlot, actionType, actionInfoID, subType, actionMacroSpellID, slotSource, attributeSlot = actionInfoForButton(button, spec, index)
    local bindingCommand = spec.bindingPrefix .. index
    local primaryBinding, secondaryBinding
    if GetBindingKey then primaryBinding, secondaryBinding = GetBindingKey(bindingCommand) end
    local rawBinding, parsedBinding, bindingError, bindingSourceIndex = resolveBindingPair(primaryBinding, secondaryBinding)
    local x, y = buttonCoordinates(button)
    local entry = {
        buttonName = buttonName,
        bar = spec.bar,
        barOrder = spec.order,
        buttonIndex = index,
        visualOrder = spec.order * 100 + index,
        visualX = x,
        visualY = y,
        actionSlot = actionSlot,
        actionSlotSource = slotSource,
        buttonActionAttribute = attributeSlot,
        bindingCommand = bindingCommand,
        rawBinding = rawBinding,
        bindingSourceIndex = bindingSourceIndex,
        parsedBinding = parsedBinding,
        bindingError = bindingError,
        actionType = actionType,
        actionInfoId = actionInfoID,
        subType = subType,
        actionMacroSpellID = actionMacroSpellID,
    }

    if not actionSlot then
        entry.scanReason = slotSource
        cache.diagnostics[#cache.diagnostics + 1] = entry
        return
    end
    if actionType == "spell" then
        entry.source = "spell"
        entry.spellID = tonumber(actionInfoID)
        if entry.spellID then
            addBySpell(cache.bySpell, entry.spellID, entry)
            appendEntry(cache, entry)
        else
            entry.scanReason = "spell_id_missing"
            cache.diagnostics[#cache.diagnostics + 1] = entry
        end
    elseif actionType == "macro" then
        entry = buildMacroEntry(entry, actionInfoID, subType, actionMacroSpellID)
        appendEntry(cache, entry)
        addBySpell(cache.macroBySpell, entry.macroSpellID, entry)
        addBySpell(cache.macroBySpell, entry.macroResolvedSpellID, entry)
        addBySpell(cache.macroBySpell, entry.macroActionInfoSpellID, entry)
    elseif actionType == "item" then
        entry.source = "item"
        entry.itemID = tonumber(actionInfoID)
        if entry.itemID then
            addByItem(cache.byItem, entry.itemID, entry)
            appendEntry(cache, entry)
        else
            entry.scanReason = "item_id_missing"
            cache.diagnostics[#cache.diagnostics + 1] = entry
        end
    elseif actionType ~= nil then
        entry.scanReason = "action_type_ignored:" .. tostring(actionType)
        cache.diagnostics[#cache.diagnostics + 1] = entry
    end
end

local function scanStanceButton(cache, index)
    cache.scannedButtons = cache.scannedButtons + 1
    local buttonName = STANCE_SPEC.prefix .. index
    local button = _G[buttonName]
    if not buttonIsVisible(button) then return end
    cache.visibleButtons = cache.visibleButtons + 1
    local bindingCommand = STANCE_SPEC.bindingPrefix .. index
    local primaryBinding, secondaryBinding
    if GetBindingKey then primaryBinding, secondaryBinding = GetBindingKey(bindingCommand) end
    local rawBinding, parsedBinding, bindingError, bindingSourceIndex = resolveBindingPair(primaryBinding, secondaryBinding)
    local spellID, spellSource = stanceSpellID(button, index)
    local x, y = buttonCoordinates(button)
    local entry = {
        buttonName = buttonName,
        bar = STANCE_SPEC.bar,
        barOrder = STANCE_SPEC.order,
        buttonIndex = index,
        visualOrder = STANCE_SPEC.order * 100 + index,
        visualX = x,
        visualY = y,
        actionSlot = nil,
        actionSlotSource = spellSource,
        bindingCommand = bindingCommand,
        rawBinding = rawBinding,
        bindingSourceIndex = bindingSourceIndex,
        parsedBinding = parsedBinding,
        bindingError = bindingError,
        actionType = "stance",
        source = "spell",
        spellID = spellID,
        isStanceButton = true,
    }
    if spellID then
        addBySpell(cache.bySpell, spellID, entry)
        appendEntry(cache, entry)
    else
        entry.scanReason = spellSource
        cache.diagnostics[#cache.diagnostics + 1] = entry
    end
end

local function buildButtonCache(scanReason)
    local specialActionBar = readSpecialActionBarState()
    Resolver.specialActionBarState = specialActionBar
    local cache = {
        generation = Resolver.scanGeneration + 1,
        scanReason = scanReason or "manual",
        scannedAt = GetTime and GetTime() or 0,
        entries = {}, bySpell = {}, byItem = {}, macroEntries = {}, macroBySpell = {}, diagnostics = {},
        scannedButtons = 0, visibleButtons = 0,
        state = { mainPage = currentMainPage(), stateHash = actionBarStateSignature(), specialActionBar = specialActionBar },
    }
    if specialActionBar.active then
        cache.diagnostics[#cache.diagnostics + 1] = {
            scanReason = specialActionBar.reason,
            specialActionBar = specialActionBar,
        }
        return cache
    end
    for _, spec in ipairs(BUTTON_SPECS) do
        for index = 1, spec.count do scanStandardButton(cache, spec, index) end
    end
    for index = 1, STANCE_SPEC.count do scanStanceButton(cache, index) end
    return cache
end

local function candidateCompare(left, right)
    -- A valid normalized binding always outranks an unbound/unsupported copy of
    -- the same spell. This prevents an earlier visible but unusable button from
    -- hiding a later valid ALT+Q/CTRL+Q mapping.
    if (left.parsed ~= nil) ~= (right.parsed ~= nil) then
        return left.parsed ~= nil
    end
    -- The user-selected rule is current visual order, not direct-spell priority.
    -- Prefer the actual visible button coordinates when both are available:
    -- higher rows first (WoW Y grows upward), then left to right.  Fall back to
    -- stable standard-bar order when a frame has no center yet.
    if left.visualY and right.visualY and math.abs(left.visualY - right.visualY) > 8 then
        return left.visualY > right.visualY
    end
    if left.visualX and right.visualX and math.abs(left.visualX - right.visualX) > 8 then
        return left.visualX < right.visualX
    end
    if left.visualOrder ~= right.visualOrder then return left.visualOrder < right.visualOrder end
    return tostring(left.buttonName) < tostring(right.buttonName)
end

local function dedupeCandidates(entries)
    local output, seen = {}, {}
    for _, entry in ipairs(entries or {}) do
        local key = tostring(entry.buttonName) .. ":" .. tostring(entry.actionSlot)
        if not seen[key] then
            seen[key] = true
            output[#output + 1] = entry
        end
    end
    return output
end

function Resolver:Invalidate(reason)
    self.cache = {}
    self.cacheDirty = true
    self.lastReason = reason or "invalidated"
    self.lastScanReason = reason or "invalidated"
end

function Resolver:Rebuild(reason)
    self.buttonCache = buildButtonCache(reason or "manual")
    self.scanGeneration = self.buttonCache.generation
    self.cache = {}
    self.cacheDirty = false
    self.lastScanReason = self.buttonCache.scanReason
    self.lastReason = "cache_ready"
    return self.buttonCache
end

function Resolver:IsBindingSettling()
    return (GetTime and GetTime() or 0) < (self.bindingSettlingUntil or 0)
end

function Resolver:EnsureCache(reason)
    if self.cacheDirty or not self.buttonCache then return self:Rebuild(reason or "lazy") end
    -- UPDATE_BINDINGS intentionally preserves the old cache until the delayed
    -- hard invalidation below.  Do not race an incompletely committed binding.
    if self:IsBindingSettling() then return self.buttonCache end
    local cachedHash = self.buttonCache.state and self.buttonCache.state.stateHash
    local currentHash = actionBarStateSignature()
    if cachedHash ~= currentHash then
        self:Invalidate("actionbar_state_hash_changed")
        return self:Rebuild(reason or "state_hash")
    end
    return self.buttonCache
end

function Resolver:BeginBindingSettlement()
    local now = GetTime and GetTime() or 0
    self.bindingSettleSerial = (self.bindingSettleSerial or 0) + 1
    local serial = self.bindingSettleSerial
    self.bindingSettlingUntil = now + self.bindingSettleDelay
    self.lastReason = "binding_settling"
    local finalize = function()
        if Resolver.bindingSettleSerial ~= serial then return end
        Resolver.bindingSettlingUntil = 0
        Resolver:Invalidate("UPDATE_BINDINGS_settled")
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(self.bindingSettleDelay, finalize)
    else
        -- Defensive fallback for non-client test environments.
        finalize()
    end
end

function Resolver:GetSpecialActionBarState()
    local state = readSpecialActionBarState()
    self.specialActionBarState = state
    return state
end

function Resolver:GetCacheSummary()
    local cache = self:EnsureCache("summary")
    local specialActionBar = cache.state and cache.state.specialActionBar or self:GetSpecialActionBarState()
    return {
        generation = cache.generation,
        scanReason = cache.scanReason,
        scannedButtons = cache.scannedButtons,
        visibleButtons = cache.visibleButtons,
        entries = #cache.entries,
        itemCount = cache.byItem and (function()
            local total = 0
            for _ in pairs(cache.byItem) do total = total + 1 end
            return total
        end)() or 0,
        macroEntries = #cache.macroEntries,
        diagnostics = #cache.diagnostics,
        mainPage = cache.state and cache.state.mainPage or nil,
        stateHash = cache.state and cache.state.stateHash or nil,
        bindingSettling = self:IsBindingSettling(),
        bindingSettlingUntil = self.bindingSettlingUntil,
        specialActionBar = specialActionBar,
        blockedBySpecialActionBar = specialActionBar and specialActionBar.active == true or false,
    }
end

function Resolver:GetButtonCache()
    return self:EnsureCache("get_cache")
end

local function macroCandidateMatches(entry, spellID, spellName)
    if macroSpellMatches(entry.macroSpellID, spellID, spellName) then
        return true, "action_info_macro_spell"
    end
    if macroSpellMatches(entry.macroResolvedSpellID, spellID, spellName) then
        return true, "GetMacroSpell"
    end
    if macroSpellMatches(entry.macroActionInfoSpellID, spellID, spellName) then
        return true, "GetMacroSpell(actionInfoId)"
    end
    local matched = macroBodyReferencesSpell(entry.macroBody, spellName, spellID)
    if matched then return true, "macro_body_reference" end
    return false, nil
end

local function appendUnique(list, seen, value)
    value = tonumber(value)
    if value and value > 0 and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

-- Returns the requested SpellID plus safe base/override equivalents.  Reverse
-- matching is restricted to IDs already present on visible cached buttons, so
-- this never widens resolution into hidden action bars.
function Resolver:GetEquivalentSpellIDs(spellID, cache)
    spellID = tonumber(spellID)
    local ids, seen = {}, {}
    appendUnique(ids, seen, spellID)
    local function addBase(id)
        if type(FindBaseSpellByID) == "function" then
            local ok, base = pcall(FindBaseSpellByID, id)
            if ok then appendUnique(ids, seen, base) end
        end
    end
    local function addOverride(id)
        if C_Spell and type(C_Spell.GetOverrideSpell) == "function" then
            local ok, override = pcall(C_Spell.GetOverrideSpell, id, 0, false)
            if ok then appendUnique(ids, seen, override) end
        end
        if type(FindSpellOverrideByID) == "function" then
            local ok, override = pcall(FindSpellOverrideByID, id)
            if ok then appendUnique(ids, seen, override) end
        end
    end
    addBase(spellID); addOverride(spellID)
    -- One additional pass closes base -> override -> base chains without an
    -- unbounded graph walk.
    local count = #ids
    for i = 1, count do addBase(ids[i]); addOverride(ids[i]) end
    cache = cache or self.buttonCache
    if cache and cache.bySpell then
        for visibleID in pairs(cache.bySpell) do
            if not seen[visibleID] then
                local equivalent = false
                if type(FindBaseSpellByID) == "function" then
                    local ok, base = pcall(FindBaseSpellByID, visibleID)
                    equivalent = ok and seen[tonumber(base)] == true or false
                end
                if not equivalent and C_Spell and type(C_Spell.GetOverrideSpell) == "function" then
                    local ok, override = pcall(C_Spell.GetOverrideSpell, visibleID, 0, false)
                    equivalent = ok and seen[tonumber(override)] == true or false
                end
                if equivalent then appendUnique(ids, seen, visibleID) end
            end
        end
    end
    return ids
end

local function makeCandidate(entry, spellID, association, matchedSpellID, matchKind)
    local parsed = entry.parsedBinding
    local reason = entry.bindingError
    return {
        spellID = spellID,
        slot = entry.actionSlot,
        actionSlot = entry.actionSlot,
        buttonName = entry.buttonName,
        bar = entry.bar,
        visualOrder = entry.visualOrder,
        source = entry.source,
        kind = entry.source,
        directActionSlot = (entry.source == "spell" or entry.source == "item") and entry.actionSlot ~= nil,
        matchKind = matchKind or "direct_spell",
        bindingCommand = entry.bindingCommand,
        rawBinding = entry.rawBinding,
        bindingSourceIndex = entry.bindingSourceIndex,
        parsed = parsed,
        reason = reason,
        macroID = entry.macroID,
        macroName = entry.macroName,
        macroAssociation = association,
        macroCommand = association,
        macroDiagnostic = entry.macroDiagnostic,
        macroSemantics = entry.macroSemantics,
        matchedSpellName = getSpellName(matchedSpellID or spellID),
        matchedSpellID = matchedSpellID or spellID,
    }
end

-- Resolve a recommendation by SpellID.  v3 does not require ActionRegistry.
-- Direct and macro candidates come from the current ButtonCache; no scan or
-- macro API read occurs on normal recommendation ticks.
function Resolver:ResolveSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return { status="NoBinding", reason="spell_missing", bindingToken=0, candidates={} }, "spell_missing"
    end

    local specialActionBar = self:GetSpecialActionBarState()
    if specialActionBar.active then
        self.lastReason = specialActionBar.reason
        return {
            spellID = spellID,
            status = "NoBinding",
            reason = specialActionBar.reason,
            bindingToken = 0,
            candidates = {},
            macroDiagnostics = {},
            specialActionBar = specialActionBar,
            cacheSummary = self.buttonCache and self:GetCacheSummary() or nil,
            requestedSpellID = spellID, matchedSpellID = nil, matchKind = "special_actionbar_blocked",
            equivalentSpellIDs = { spellID }, stateHash = self.buttonCache and self.buttonCache.state and self.buttonCache.state.stateHash or actionBarStateSignature(),
            bindingSettling = self:IsBindingSettling(),
        }, specialActionBar.reason
    end
    if self.buttonCache and self.buttonCache.state and self.buttonCache.state.specialActionBar
        and self.buttonCache.state.specialActionBar.active then
        -- A cache built while a special bar was active must never be reused
        -- after the bar disappears, even if a client event was missed.
        self:Invalidate("special_actionbar_cleared")
    end

    self:EnsureCache("resolve")
    local cached = self.cache[spellID]
    if cached then
        -- Extra-action visibility is an observation, not a cache key. Keep
        -- the cached mapping but refresh the diagnostic state for this tick.
        cached.specialActionBar = specialActionBar
        cached.bindingSettling = self:IsBindingSettling()
        cached.stateHash = self.buttonCache and self.buttonCache.state and self.buttonCache.state.stateHash or cached.stateHash
        return cached, cached.reason
    end

    local cache = self.buttonCache
    local spellName = getSpellName(spellID)
    local equivalentSpellIDs = self:GetEquivalentSpellIDs(spellID, cache)
    local candidates = {}
    for _, equivalentID in ipairs(equivalentSpellIDs) do
        local kind = equivalentID == spellID and "direct_spell" or "spell_equivalent"
        for _, entry in ipairs(cache.bySpell[equivalentID] or {}) do
            candidates[#candidates + 1] = makeCandidate(entry, spellID, kind, equivalentID, kind)
        end
    end

    local macroSeen = {}
    local function considerMacro(entry, equivalentID)
        local key = tostring(entry.buttonName) .. ":" .. tostring(entry.actionSlot)
        if macroSeen[key] then return end
        local targetName = getSpellName(equivalentID) or spellName
        local matches, association = macroCandidateMatches(entry, equivalentID, targetName)
        if matches then
            macroSeen[key] = true
            local kind = equivalentID == spellID and association or "macro_equivalent:" .. tostring(association)
            candidates[#candidates + 1] = makeCandidate(entry, spellID, association, equivalentID, kind)
        end
    end
    for _, equivalentID in ipairs(equivalentSpellIDs) do
        for _, entry in ipairs(cache.macroBySpell[equivalentID] or {}) do considerMacro(entry, equivalentID) end
    end
    for _, entry in ipairs(cache.macroEntries or {}) do
        for _, equivalentID in ipairs(equivalentSpellIDs) do considerMacro(entry, equivalentID) end
    end

    candidates = dedupeCandidates(candidates)
    table.sort(candidates, candidateCompare)

    local macroDiagnostics = {}
    for _, entry in ipairs(cache.macroEntries or {}) do
        local matches = macroCandidateMatches(entry, spellID, spellName)
        if not matches then
            local diag = entry.macroDiagnostic or {}
            macroDiagnostics[#macroDiagnostics + 1] = {
                slot = entry.actionSlot,
                buttonName = entry.buttonName,
                bindingCommand = entry.bindingCommand,
                rawBinding = entry.rawBinding,
                actionInfoId = entry.actionInfoId,
                actionText = diag.actionText,
                actionMacroSpellID = entry.macroSpellID,
                macroName = entry.macroName,
                resolvedMacroIndex = entry.macroID,
                lookupSource = diag.lookupSource,
                resolvedBodyLength = macroBodyLength(entry.macroBody),
                failureReason = diag.failureReason or (entry.macroBody and "macro_spell_not_referenced" or "macro_body_unavailable"),
            }
        end
    end

    local selected = candidates[1]
    local result
    if not selected then
        local reason = "actionbar_spell_not_found"
        local unavailable = nil
        for _, diag in ipairs(macroDiagnostics) do
            if diag.failureReason == "macro_body_unavailable" or diag.failureReason == "macro_lookup_failed" then
                unavailable = diag.failureReason
                break
            end
        end
        if unavailable then reason = unavailable end
        result = {
            spellID=spellID, status="NoBinding", reason=reason, bindingToken=0,
            candidates=candidates, macroDiagnostics=macroDiagnostics,
            cacheGeneration=cache.generation, cacheSummary=self:GetCacheSummary(),
            requestedSpellID = spellID, matchedSpellID = nil, matchKind = "not_found",
            equivalentSpellIDs = equivalentSpellIDs, stateHash = cache.state and cache.state.stateHash or nil,
            bindingSettling = self:IsBindingSettling(), directActionSlot = false,
            specialActionBar=specialActionBar,
        }
    elseif not selected.parsed then
        result = {
            spellID=spellID, status="NoBinding", reason=selected.reason or "binding_token_invalid", bindingToken=0,
            slot=selected.slot, actionSlot=selected.actionSlot, buttonName=selected.buttonName,
            source=selected.source, bindingCommand=selected.bindingCommand, rawBinding=selected.rawBinding,
            bindingSourceIndex=selected.bindingSourceIndex,
            macroID=selected.macroID, macroName=selected.macroName, macroAssociation=selected.macroAssociation,
            macroCommand=selected.macroCommand, macroDiagnostic=selected.macroDiagnostic,
            matchedSpellName=selected.matchedSpellName, matchedSpellID=selected.matchedSpellID,
            requestedSpellID = spellID, matchKind = selected.matchKind,
            equivalentSpellIDs = equivalentSpellIDs, stateHash = cache.state and cache.state.stateHash or nil,
            bindingSettling = self:IsBindingSettling(), directActionSlot = selected.directActionSlot == true,
            candidates=candidates, macroDiagnostics=macroDiagnostics,
            cacheGeneration=cache.generation, cacheSummary=self:GetCacheSummary(),
            specialActionBar=specialActionBar,
        }
    else
        result = {
            spellID=spellID, status="Ready", reason=nil,
            slot=selected.slot, actionSlot=selected.actionSlot, buttonName=selected.buttonName,
            bar=selected.bar, source=selected.source, bindingCommand=selected.bindingCommand,
            bindingSourceIndex=selected.bindingSourceIndex,
            binding=selected.parsed.binding, bindingToken=selected.parsed.token,
            inputType=selected.parsed.inputType, key=selected.parsed.key, modifier=selected.parsed.modifier,
            macroID=selected.macroID, macroName=selected.macroName, macroAssociation=selected.macroAssociation,
            macroCommand=selected.macroCommand, macroDiagnostic=selected.macroDiagnostic,
            matchedSpellName=selected.matchedSpellName, matchedSpellID=selected.matchedSpellID,
            requestedSpellID = spellID, matchKind = selected.matchKind,
            equivalentSpellIDs = equivalentSpellIDs, stateHash = cache.state and cache.state.stateHash or nil,
            bindingSettling = self:IsBindingSettling(), directActionSlot = selected.directActionSlot == true,
            candidates=candidates, macroDiagnostics=macroDiagnostics,
            cacheGeneration=cache.generation, cacheSummary=self:GetCacheSummary(),
            specialActionBar=specialActionBar,
        }
    end
    self.cache[spellID] = result
    self.lastReason = result.reason or "ready"
    return result, result.reason
end

-- Resolve a visible action-bar item by ItemID. It is intentionally a
-- read-only mapping for survival/consumable display; no input caller uses it.
function Resolver:ResolveItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return { status = "NoBinding", reason = "item_missing", bindingToken = 0, candidates = {} }, "item_missing"
    end
    local specialActionBar = self:GetSpecialActionBarState()
    if specialActionBar.active then
        return {
            itemID = itemID, status = "NoBinding", reason = specialActionBar.reason,
            bindingToken = 0, candidates = {}, specialActionBar = specialActionBar,
        }, specialActionBar.reason
    end
    self:EnsureCache("resolve_item")
    local cacheKey = "item:" .. tostring(itemID)
    local cached = self.cache[cacheKey]
    if cached then
        cached.specialActionBar = specialActionBar
        return cached, cached.reason
    end
    local candidates = {}
    for _, entry in ipairs((self.buttonCache.byItem or {})[itemID] or {}) do
        candidates[#candidates + 1] = {
            itemID = itemID,
            slot = entry.actionSlot, actionSlot = entry.actionSlot, buttonName = entry.buttonName,
            bar = entry.bar, visualOrder = entry.visualOrder, source = "item",
            bindingCommand = entry.bindingCommand, rawBinding = entry.rawBinding,
            bindingSourceIndex = entry.bindingSourceIndex, parsed = entry.parsedBinding,
            directActionSlot = entry.actionSlot ~= nil,
            reason = entry.bindingError,
        }
    end
    candidates = dedupeCandidates(candidates)
    table.sort(candidates, candidateCompare)
    local selected = candidates[1]
    local result
    if not selected then
        result = { itemID = itemID, status = "NoBinding", reason = "actionbar_item_not_found", bindingToken = 0,
            candidates = candidates, cacheGeneration = self.buttonCache.generation, specialActionBar = specialActionBar }
    elseif not selected.parsed then
        result = { itemID = itemID, status = "NoBinding", reason = selected.reason or "binding_token_invalid", bindingToken = 0,
            slot = selected.slot, actionSlot = selected.actionSlot, buttonName = selected.buttonName,
            source = selected.source, bindingCommand = selected.bindingCommand, rawBinding = selected.rawBinding,
            bindingSourceIndex = selected.bindingSourceIndex, directActionSlot = selected.directActionSlot == true, candidates = candidates,
            cacheGeneration = self.buttonCache.generation, specialActionBar = specialActionBar }
    else
        result = { itemID = itemID, status = "Ready", reason = nil,
            slot = selected.slot, actionSlot = selected.actionSlot, buttonName = selected.buttonName,
            bar = selected.bar, source = selected.source, bindingCommand = selected.bindingCommand,
            bindingSourceIndex = selected.bindingSourceIndex, binding = selected.parsed.binding,
            bindingToken = selected.parsed.token, inputType = selected.parsed.inputType,
            key = selected.parsed.key, modifier = selected.parsed.modifier, directActionSlot = selected.directActionSlot == true, candidates = candidates,
            cacheGeneration = self.buttonCache.generation, specialActionBar = specialActionBar }
    end
    self.cache[cacheKey] = result
    return result, result.reason
end

local events = {
    "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_PAGE_CHANGED", "ACTIONBAR_UPDATE_STATE", "UPDATE_MACROS",
    "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_EXTRA_ACTIONBAR", "UPDATE_POSSESS_BAR", "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE",
}
local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, events)
watcher:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" then
        Resolver:BeginBindingSettlement()
        return
    end
    Resolver:Invalidate(event)
end)
