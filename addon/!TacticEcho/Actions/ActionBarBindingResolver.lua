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

local function getItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil end
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, info = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(info) == "table" then
            local name = info.itemName or info.name
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    if type(GetItemInfo) == "function" then
        local ok, name = pcall(GetItemInfo, itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
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

-- Macro association remains read-only: TE never evaluates conditions or
-- executes a branch itself. The parser only determines whether the user's
-- existing visible macro button references the requested spell; TEK still
-- presses the same binding the player assigned to that button.
local function macroBodyReferencesSpell(body, spellName, spellID, semantics)
    if type(body) ~= "string" or body == "" then return false, "macro_body_unavailable" end
    semantics = type(semantics) == "table" and semantics
        or (TE.MacroSemantics and type(TE.MacroSemantics.Analyze) == "function"
            and TE.MacroSemantics:Analyze(body) or nil)
    if not (semantics and TE.MacroSemantics and type(TE.MacroSemantics.MatchSpell) == "function") then
        return false, "macro_semantics_unavailable"
    end
    -- Broad association deliberately accepts common user-authored macro forms
    -- such as [@cursor], mouseover/target conditionals, /stopcasting helpers
    -- and multi-line utility commands. The caller still verifies the exact
    -- requested spell after dispatch; no macro branch is inferred or replayed.
    return TE.MacroSemantics:MatchSpell(semantics, spellID, spellName, "broad")
end

local function macroBodyLength(body)
    return type(body) == "string" and #body or 0
end

-- P5.1 macro identity contract:
-- Retail can report a macro action's represented SpellID through
-- GetActionInfo(actionSlot). In that mode the returned numeric value is *not*
-- a macro-list index; for example, a Counter Shot macro can report 147362.
-- Treating that spell ID as GetMacroInfo(147362) is invalid and causes the
-- macro body to disappear from the resolver.
--
-- Numeric macro indexes remain the strongest identity when the action-info
-- value is within the currently valid account/character macro index ranges.
-- When it is not a valid macro index, body recovery uses a bounded, read-only
-- semantic join:
--   action slot text (the visible macro name)
--   + exact name candidates in the user's macro list
--   + the spell represented by the action slot
--   + parsed /cast spell semantics in the candidate body.
-- The resolver accepts the fallback only when exactly one candidate survives.
-- Same-name/same-spell duplicates remain intentionally ambiguous and fail
-- closed; an AddOn cannot safely infer which identical macro the slot holds.
local MAX_MACRO_INFO_INDEX_READS = 3

local function normalizeMacroIndex(value)
    local numeric = tonumber(value)
    if not numeric or numeric <= 0 then return nil end
    return math.floor(numeric)
end

local function hasMacroBody(body)
    return type(body) == "string" and body ~= ""
end

local function macroIndexLayout()
    if type(GetNumMacros) ~= "function" then return nil end
    local ok, accountCount, characterCount = safeCall(GetNumMacros)
    if not ok then return nil end
    accountCount = math.max(0, math.floor(tonumber(accountCount) or 0))
    characterCount = math.max(0, math.floor(tonumber(characterCount) or 0))
    local accountLimit = math.max(accountCount, math.floor(tonumber(MAX_ACCOUNT_MACROS) or 120))
    return {
        accountCount = accountCount,
        characterCount = characterCount,
        accountLimit = accountLimit,
        characterStart = accountLimit + 1,
        characterEnd = accountLimit + characterCount,
    }
end

local function isCurrentMacroIndex(value, layout)
    local numeric = normalizeMacroIndex(value)
    if not numeric or not layout then return false end
    if numeric >= 1 and numeric <= layout.accountCount then return true end
    return numeric >= layout.characterStart and numeric <= layout.characterEnd
end

local function macroIndexList(layout)
    local indexes = {}
    if not layout then return indexes end
    for index = 1, layout.accountCount do
        indexes[#indexes + 1] = index
    end
    for index = layout.characterStart, layout.characterEnd do
        indexes[#indexes + 1] = index
    end
    return indexes
end

local function readMacroInfoWithRetries(macroIndex)
    local snapshot = {
        macroIndex = macroIndex,
        readAttempts = 0,
        successfulReads = 0,
        firstBodyLength = 0,
        largestBodyLength = 0,
    }
    if type(GetMacroInfo) ~= "function" then
        snapshot.failureReason = "macro_info_api_unavailable"
        return snapshot
    end
    for attempt = 1, MAX_MACRO_INFO_INDEX_READS do
        local ok, macroName, icon, body = safeCall(GetMacroInfo, macroIndex)
        snapshot.readAttempts = attempt
        if ok then
            snapshot.successfulReads = snapshot.successfulReads + 1
            if type(macroName) == "string" and macroName ~= "" then
                snapshot.firstName = snapshot.firstName or macroName
                snapshot.lastName = macroName
            end
            if icon ~= nil then snapshot.lastIcon = icon end
            local bodyLength = macroBodyLength(body)
            if attempt == 1 then snapshot.firstBodyLength = bodyLength end
            if bodyLength > snapshot.largestBodyLength then snapshot.largestBodyLength = bodyLength end
            if hasMacroBody(body) then
                snapshot.macroName = macroName or snapshot.firstName
                snapshot.icon = icon or snapshot.lastIcon
                snapshot.body = body
                return snapshot
            end
        end
    end
    snapshot.failureReason = "macro_body_unavailable"
    return snapshot
end

local function readMacroSpellInfo(macroIndex)
    local result = { macroIndex = macroIndex, success = false, spellName = nil, spellID = nil }
    if type(GetMacroSpell) ~= "function" then return result end
    local ok, spellName, _, spellID = safeCall(GetMacroSpell, macroIndex)
    result.success = ok
    result.spellName = type(spellName) == "string" and spellName or nil
    result.spellID = normalizeSpellID(spellID)
    return result
end

local function setResolvedMacro(diag, snapshot, spellInfo, source, identitySource)
    diag.resolvedMacroIndex = snapshot.macroIndex
    diag.macroName = snapshot.macroName
    diag.body = snapshot.body
    diag.resolvedBodyLength = macroBodyLength(snapshot.body)
    diag.lookupSource = source
    diag.macroIdentitySource = identitySource
    diag.macroIdentityVerified = true
    diag.getMacroSpellByResolvedIndex = (spellInfo and (spellInfo.spellID or spellInfo.spellName)) or nil
    diag.getMacroSpellByResolvedIndexSpellID = spellInfo and spellInfo.spellID or nil
    return {
        macroIndex = snapshot.macroIndex,
        macroName = snapshot.macroName,
        icon = snapshot.icon,
        body = snapshot.body,
        readAttempts = snapshot.readAttempts,
        successfulReads = snapshot.successfulReads,
        spellInfo = spellInfo,
    }
end

local function directMacroIndexResolution(actionInfoID, actionText, layout, diag)
    local macroIndex = normalizeMacroIndex(actionInfoID)
    diag.actionInfoMacroIndex = macroIndex
    diag.actionInfoLooksLikeMacroIndex = isCurrentMacroIndex(macroIndex, layout)
    -- A few minimal/test client states do not expose GetNumMacros. Retain a
    -- constrained direct read only when the action button exposes no macro
    -- label at all; a named action must use the semantic fallback instead of
    -- risking a numeric SpellID collision with an unrelated macro index.
    if layout then
        if not diag.actionInfoLooksLikeMacroIndex then return nil end
    elseif type(actionText) == "string" and actionText ~= "" then
        return nil
    else
        diag.actionInfoIndexLayoutUnavailable = true
    end

    local snapshot = readMacroInfoWithRetries(macroIndex)
    diag.getMacroInfoByActionInfoIdSuccess = snapshot.successfulReads > 0 and snapshot.firstName ~= nil
    diag.getMacroInfoByActionInfoIdName = snapshot.firstName or snapshot.lastName
    diag.getMacroInfoByActionInfoIdBodyLength = snapshot.largestBodyLength
    diag.actionInfoIdFirstReadBodyLength = snapshot.firstBodyLength
    diag.actionInfoIdReadAttempts = snapshot.readAttempts
    diag.actionInfoIdSuccessfulReads = snapshot.successfulReads

    if not hasMacroBody(snapshot.body) then
        diag.failureReason = "macro_body_unavailable_action_info_id"
        return nil
    end
    -- A valid current macro index is already the exact identity of the visible
    -- action-bar macro.  `GetActionText()` may legitimately display the
    -- represented spell (for example through #showtooltip) rather than the
    -- player-assigned macro name, so a label difference is diagnostic only.
    -- Do not scan or substitute another macro index; the same-index body is
    -- the only body that may be accepted in this branch.
    if type(actionText) == "string" and actionText ~= ""
        and type(snapshot.macroName) == "string" and snapshot.macroName ~= actionText then
        diag.directIndexActionTextDiffers = true
        diag.directIndexActionText = actionText
        diag.directIndexMacroName = snapshot.macroName
    end
    local spellInfo = readMacroSpellInfo(macroIndex)
    return setResolvedMacro(
        diag,
        snapshot,
        spellInfo,
        snapshot.readAttempts > 1 and "action_info_macro_index_retry" or "action_info_macro_index",
        "action_info_macro_index"
    )
end

-- A represented SpellID can be a valid opaque macro-action handle in Retail.
-- It is never treated as a macro-list index when outside the current index
-- layout. In that shape Retail can expose an opaque action-info handle that
-- returns a macro label. Read that handle once and retain only its name as a
-- semantic join key; never use its icon/body and never treat it as a macro-list
-- entry. Final recovery still requires one real current macro index with a
-- parsed body that references the represented spell.
local function readOpaqueActionInfoHandleName(actionInfoID, diag)
    if type(diag) ~= "table" or diag.actionInfoLooksLikeMacroIndex == true then return end
    local handle = normalizeMacroIndex(actionInfoID)
    if not handle or type(GetMacroInfo) ~= "function" then return end
    local ok, macroName = safeCall(GetMacroInfo, handle)
    diag.actionInfoLabelProbeAttempted = true
    diag.actionInfoLabelProbeSuccess = ok == true
    if type(macroName) == "string" and macroName ~= "" then
        diag.getMacroInfoByActionInfoIdName = diag.getMacroInfoByActionInfoIdName or macroName
        diag.actionInfoLabelProbeName = macroName
    end
end

local function actionSpellIdentity(actionInfoID, actionMacroSpellID, actionInfoLooksLikeMacroIndex)
    local explicit = normalizeSpellID(actionMacroSpellID)
    if explicit then return explicit, "action_info_macro_spell" end
    -- When the action-info value is outside every current macro index range,
    -- Retail is representing the macro by its spell ID. This is the observed
    -- Counter Shot case (147362), and it is the semantic key for fallback.
    if not actionInfoLooksLikeMacroIndex then
        local represented = normalizeSpellID(actionInfoID)
        if represented then return represented, "action_info_represented_spell" end
    end
    return nil, nil
end

local function semanticMacroResolution(labelCandidates, representedSpellID, layout, diag)
    diag.lookupByActionText = false
    diag.lookupByActionInfoName = false
    diag.actionTextCandidateCount = 0
    diag.actionInfoNameCandidateCount = 0
    diag.displaySpellSemanticCandidateCount = 0
    diag.semanticCandidateCount = 0
    diag.semanticRejectedCount = 0
    if type(labelCandidates) ~= "table" or #labelCandidates == 0 then
        diag.failureReason = diag.failureReason or "macro_action_text_missing"
        return nil
    end
    if not representedSpellID then
        diag.failureReason = diag.failureReason or "macro_action_spell_identity_missing"
        return nil
    end
    if not layout then
        diag.failureReason = diag.failureReason or "macro_index_layout_unavailable"
        return nil
    end

    -- Labels remain the primary, read-only identity join.  A current action
    -- bar may instead display the represented spell name while the macro keeps
    -- a different player-assigned name.  That display shape is permitted only
    -- as a *secondary* bounded recovery: no macro-name label may have matched,
    -- and exactly one current macro body must reference the represented spell.
    -- This never falls back to a same-spell button or selects a macro by name.
    local labels, labelSources = {}, {}
    local actionText = nil
    for _, item in ipairs(labelCandidates) do
        local name = type(item) == "table" and item.name or nil
        local source = type(item) == "table" and item.source or nil
        if source == "action_text" and actionText == nil then actionText = name end
        if type(name) == "string" and name ~= "" and not labels[name] then
            labels[name] = true
            labelSources[name] = source
        end
    end
    if not next(labels) then
        diag.failureReason = diag.failureReason or "macro_action_text_missing"
        return nil
    end

    local expectedName = getSpellName(representedSpellID)
    local actionTextIsRepresentedSpell = type(actionText) == "string" and actionText ~= ""
        and type(expectedName) == "string" and expectedName ~= ""
        and (trim(actionText) == trim(expectedName) or trim(actionText):lower() == trim(expectedName):lower())
    diag.actionTextMatchesRepresentedSpell = actionTextIsRepresentedSpell == true

    local namedMatchesByIndex, namedMatchingIndexes = {}, {}
    local displayMatchesByIndex, displayMatchingIndexes = {}, {}
    for _, macroIndex in ipairs(macroIndexList(layout)) do
        local snapshot = readMacroInfoWithRetries(macroIndex)
        if hasMacroBody(snapshot.body) then
            local labelSource = labels[snapshot.macroName] and labelSources[snapshot.macroName] or nil
            local spellInfo = readMacroSpellInfo(macroIndex)
            local spellMatches = tonumber(spellInfo.spellID) == tonumber(representedSpellID)
            -- P5.5/P5.6 identity rule: represented SpellID and GetMacroSpell
            -- may corroborate a result, but the recovered current macro body
            -- must itself reference the requested spell.
            local bodyMatches = macroBodyReferencesSpell(snapshot.body, expectedName, representedSpellID)

            if labelSource then
                if labelSource == "action_text" then
                    diag.actionTextCandidateCount = diag.actionTextCandidateCount + 1
                elseif labelSource == "action_info_macro_name" then
                    diag.actionInfoNameCandidateCount = diag.actionInfoNameCandidateCount + 1
                end
                if bodyMatches then
                    namedMatchesByIndex[macroIndex] = {
                        snapshot = snapshot,
                        spellInfo = spellInfo,
                        spellMatches = spellMatches,
                        bodyMatches = true,
                        labelSource = labelSource,
                    }
                    namedMatchingIndexes[#namedMatchingIndexes + 1] = macroIndex
                else
                    diag.semanticRejectedCount = diag.semanticRejectedCount + 1
                end
            end

            -- Only collect broad display-semantic candidates when the visible
            -- action text is exactly the represented spell name.  They are used
            -- only when there was no exact macro-name candidate at all.
            if actionTextIsRepresentedSpell and bodyMatches then
                displayMatchesByIndex[macroIndex] = {
                    snapshot = snapshot,
                    spellInfo = spellInfo,
                    spellMatches = spellMatches,
                    bodyMatches = true,
                    labelSource = "action_text_represented_spell",
                }
                displayMatchingIndexes[#displayMatchingIndexes + 1] = macroIndex
            end
        end
    end

    local anyNamedCandidate = (diag.actionTextCandidateCount + diag.actionInfoNameCandidateCount) > 0
    local matchingIndexes, matchesByIndex, sourceMode
    if anyNamedCandidate then
        matchingIndexes, matchesByIndex, sourceMode = namedMatchingIndexes, namedMatchesByIndex, "named"
    else
        matchingIndexes, matchesByIndex, sourceMode = displayMatchingIndexes, displayMatchesByIndex, "display_spell"
        diag.displaySpellSemanticCandidateCount = #displayMatchingIndexes
    end
    diag.semanticCandidateCount = #matchingIndexes

    if #matchingIndexes == 1 then
        local candidate = matchesByIndex[matchingIndexes[1]]
        local source = candidate.labelSource
        diag.lookupByActionText = source == "action_text" or source == "action_text_represented_spell"
        diag.lookupByActionInfoName = source == "action_info_macro_name"
        diag.semanticNameSource = source
        -- The displayed spell name is an identity *condition*, not the macro
        -- name. Preserve both values in transient diagnostics for audit.
        diag.semanticLookupName = source == "action_text_represented_spell" and actionText or candidate.snapshot.macroName
        diag.semanticResolvedMacroName = candidate.snapshot.macroName
        diag.actionTextSemanticMatch = candidate.spellMatches and "macro_spell_and_body" or "macro_body"
        local lookupSource
        if source == "action_info_macro_name" then
            lookupSource = "action_info_name_unique_spell_semantic"
        elseif source == "action_text_represented_spell" then
            lookupSource = "action_text_represented_spell_unique_semantic"
        else
            lookupSource = "action_text_unique_spell_semantic"
        end
        return setResolvedMacro(diag, candidate.snapshot, candidate.spellInfo, lookupSource, lookupSource)
    end

    if #matchingIndexes > 1 then
        diag.semanticCandidateIndexes = matchingIndexes
        if sourceMode == "display_spell" then diag.displaySpellSemanticCandidateIndexes = matchingIndexes end
        diag.failureReason = "macro_semantic_identity_ambiguous"
        return nil
    end

    diag.lookupByActionText = diag.actionTextCandidateCount > 0
    diag.lookupByActionInfoName = diag.actionInfoNameCandidateCount > 0
    if anyNamedCandidate then
        diag.failureReason = "macro_semantic_identity_no_spell_match"
    elseif actionTextIsRepresentedSpell then
        diag.failureReason = "macro_display_spell_semantic_not_found"
    else
        diag.failureReason = "macro_action_text_name_not_found"
    end
    return nil
end

local function resolveMacroFromActionSlot(actionSlot, actionInfoID, actionMacroSpellID)
    local diag = {
        actionSlot = actionSlot,
        actionInfoId = actionInfoID,
        actionInfoValue = actionInfoID,
        actionMacroSpellID = normalizeSpellID(actionMacroSpellID),
        macroIdentitySource = "unresolved",
        macroIdentityVerified = false,
    }

    local okText, actionText = safeCall(GetActionText, actionSlot)
    diag.actionText = okText and actionText or nil

    local layout = macroIndexLayout()
    if layout then
        diag.accountMacroCount = layout.accountCount
        diag.characterMacroCount = layout.characterCount
        diag.characterMacroStart = layout.characterStart
    end

    local direct = directMacroIndexResolution(actionInfoID, diag.actionText, layout, diag)
    if direct then return diag end
    -- A value inside the current macro index layout is an identity claim for
    -- that exact macro only. Do not fall back to any other account/character
    -- macro name after the bounded same-index reads fail.
    if diag.actionInfoLooksLikeMacroIndex == true then return diag end
    readOpaqueActionInfoHandleName(actionInfoID, diag)

    local representedSpellID, representedSource = actionSpellIdentity(
        actionInfoID,
        actionMacroSpellID,
        diag.actionInfoLooksLikeMacroIndex == true
    )
    diag.representedSpellID = representedSpellID
    diag.representedSpellSource = representedSource
    -- Keep both permitted read-only labels when Retail exposes them. They are
    -- evaluated as one bounded identity join so a current action-text display
    -- name cannot hide the opaque-handle macro label, and two distinct surviving
    -- macros fail closed instead of selecting the first label that happened to
    -- match.
    local semanticLabels = {}
    if type(diag.actionText) == "string" and diag.actionText ~= "" then
        semanticLabels[#semanticLabels + 1] = { name = diag.actionText, source = "action_text" }
    end
    if type(diag.getMacroInfoByActionInfoIdName) == "string"
        and diag.getMacroInfoByActionInfoIdName ~= "" then
        semanticLabels[#semanticLabels + 1] = {
            name = diag.getMacroInfoByActionInfoIdName,
            source = "action_info_macro_name",
        }
    end
    diag.semanticLookupNames = {}
    for _, label in ipairs(semanticLabels) do
        diag.semanticLookupNames[#diag.semanticLookupNames + 1] = {
            name = label.name,
            source = label.source,
        }
    end
    local semantic = semanticMacroResolution(semanticLabels, representedSpellID, layout, diag)
    if semantic then return diag end

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

local function addByInventorySlot(index, slot, entry)
    slot = tonumber(slot)
    if slot ~= 13 and slot ~= 14 then return end
    index[slot] = index[slot] or {}
    index[slot][#index[slot] + 1] = entry
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
    local diag = resolveMacroFromActionSlot(base.actionSlot, actionInfoID, actionMacroSpellID)
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
    base.macroSemanticSummary = TE.MacroSemantics and type(TE.MacroSemantics.Summary) == "function"
        and TE.MacroSemantics:Summary(base.macroSemantics) or nil
    base.macroSpellID = actionMacroSpellID
    base.macroResolvedSpellID = normalizeSpellID(diag.getMacroSpellByResolvedIndex)
    -- Retail can expose a macro action as the spell it represents even when
    -- the macro body/index cannot be recovered from this client state. Keep
    -- that evidence distinct from GetMacroSpell(actionInfoId): it is a direct
    -- read of the visible player-authored action button, not a guessed macro
    -- name or a semantic reconstruction.
    base.macroActionInfoSpellID = normalizeSpellID(diag.getMacroSpellByActionInfoId)
    base.macroRepresentedSpellID = normalizeSpellID(diag.representedSpellID)
    base.macroRepresentedSpellSource = diag.representedSpellSource
    -- The P5.4 transport fallback is only for a body/index opacity gap on the
    -- actual visible button. If semantic recovery observed multiple same-name,
    -- same-spell macro bodies, identity is genuinely ambiguous and must retain
    -- P5's fail-closed result rather than bypassing it through represented-ID.
    base.macroOpaqueRepresentedSpell = base.macroRepresentedSpellID ~= nil
        and (type(base.macroBody) ~= "string" or base.macroBody == "")
        and (
            diag.failureReason == "macro_body_unavailable_action_info_id"
            or diag.failureReason == "macro_action_text_missing"
            or diag.failureReason == "macro_action_text_name_not_found"
        )
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
        if TE.MacroSemantics and type(TE.MacroSemantics.InventorySlots) == "function" then
            for _, inventorySlot in ipairs(TE.MacroSemantics:InventorySlots(entry.macroSemantics)) do
                addByInventorySlot(cache.macroByInventorySlot, inventorySlot, entry)
            end
        end
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
        entries = {}, bySpell = {}, byItem = {}, macroEntries = {}, macroBySpell = {}, macroByInventorySlot = {}, diagnostics = {},
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
    -- P5.8 HUD click proxies are static secure frames. Mark their mapping dirty
    -- rather than letting a later HUD click use an action-bar source from an
    -- earlier page/macro state. HudClickRouter will reconfigure only OOC.
    if TE.HudClickRouter and type(TE.HudClickRouter.InvalidateMappings) == "function" then
        TE.HudClickRouter:InvalidateMappings(self.lastReason)
    end
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

-- P5.5/P5.6 policy: representative action-info spell evidence is not a
-- general macro identity. It can remain only as the narrow P4 target-transport
-- compatibility shape when a visible macro body/index is genuinely opaque.
local function opaqueActionInfoCompatibilityEligible(entry)
    entry = type(entry) == "table" and entry or {}
    if entry.source ~= "macro" then return false end
    local diagnostic = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic or {}
    if diagnostic.macroIdentityVerified == true then return false end
    if entry.macroOpaqueRepresentedSpell ~= true then return false end
    local failure = diagnostic.failureReason
    return failure == "macro_body_unavailable_action_info_id"
        or failure == "macro_action_text_missing"
        or failure == "macro_action_text_name_not_found"
end

local function macroCandidateMatches(entry, spellID, spellName)
    entry = type(entry) == "table" and entry or {}
    local diagnostic = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic or {}
    -- A real numeric macro index or a unique semantic recovery must prove the
    -- requested spell from its parsed body. GetMacroSpell may corroborate that
    -- proof in diagnostics but cannot by itself bind a control/HUD source.
    if diagnostic.macroIdentityVerified == true then
        local matched, association = macroBodyReferencesSpell(entry.macroBody, spellName, spellID, entry.macroSemantics)
        if matched then return true, association or "macro_body_broad_reference" end
        return false, association or "macro_semantic_identity_no_spell_match"
    end

    -- The sole non-body path is P4 reaction target transport. The reaction
    -- layer separately requires a real BindingToken and never uses this for
    -- focus/mouseover/cursor inference, HUD manual sources, or AutoBurst.
    if opaqueActionInfoCompatibilityEligible(entry) then
        if macroSpellMatches(entry.macroSpellID, spellID, spellName) then
            return true, "action_info_macro_spell"
        end
        if macroSpellMatches(entry.macroActionInfoSpellID, spellID, spellName) then
            return true, "GetMacroSpell(actionInfoId)"
        end
        if macroSpellMatches(entry.macroRepresentedSpellID, spellID, spellName) then
            return true, "action_info_represented_spell"
        end
    end
    return false, diagnostic.failureReason or "macro_body_unavailable"
end

-- All macro-consuming layers share this compact eligibility check.  A macro
-- becomes a normal current-action-bar source only after the resolver has
-- established the current visible macro identity and parsed a body association.
-- `action_info_*` compatibility is deliberately excluded: it remains an
-- isolated P4 target-transport exception, not a general macro source.
local function bodyVerifiedMacroAssociation(association)
    if association == nil or association == "" then return true end
    association = tostring(association)
    return association:find("macro_body_", 1, true) == 1
        or association:find("macro_item_", 1, true) == 1
        or association:find("macro_inventory_", 1, true) == 1
end

function Resolver:IsVerifiedCurrentMacroSource(value, association)
    value = type(value) == "table" and value or {}
    if value.source ~= "macro" then return true, nil end
    local diagnostic = type(value.macroDiagnostic) == "table" and value.macroDiagnostic or {}
    if diagnostic.macroIdentityVerified ~= true then
        return false, "macro_identity_unverified"
    end
    if value.macroOpaqueRepresentedSpell == true then
        return false, "macro_action_info_opaque_compat"
    end
    if type(value.macroSemantics) ~= "table" then
        return false, "macro_semantics_unavailable"
    end
    local resolvedAssociation = association
    if resolvedAssociation == nil then resolvedAssociation = value.macroAssociation end
    if bodyVerifiedMacroAssociation(resolvedAssociation) ~= true then
        return false, "macro_association_not_body_verified"
    end
    return true, nil
end

function Resolver:IsAutoBurstMacroEligible(value)
    value = type(value) == "table" and value or {}
    if value.source ~= "macro" then return true, nil end
    local verified, reason = self:IsVerifiedCurrentMacroSource(value, value.macroAssociation)
    if verified ~= true then return false, reason end
    local association = tostring(value.macroAssociation or "")
    if association:find("macro_body_", 1, true) ~= 1
        and association:find("macro_inventory_", 1, true) ~= 1 then
        return false, "macro_burst_association_unverified"
    end
    if value.macroAutoBurstEligible ~= true then
        return false, "macro_burst_semantics_uneligible"
    end
    return true, nil
end


-- Diagnostics are request-scoped.  An unrelated visible macro is not evidence
-- for a requested control spell and must never be rendered as that spell's
-- "unmatched candidate".  Keep only failures whose current action-info or
-- bounded macro evidence explicitly names the requested spell.
local function macroDiagnosticRelatesToRequestedSpell(entry, spellID, spellName)
    entry = type(entry) == "table" and entry or {}
    if entry.source ~= "macro" then return false end
    local requested = tonumber(spellID)
    if not requested or requested <= 0 then return false end
    local diagnostic = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic or {}
    -- Do not put optional values in an ipairs list: Lua stops at the first
    -- nil and would silently hide a later represented SpellID diagnostic.
    local function matches(value) return tonumber(value) == requested end
    if matches(entry.macroSpellID)
        or matches(entry.macroActionInfoSpellID)
        or matches(entry.macroResolvedSpellID)
        or matches(entry.macroRepresentedSpellID)
        or matches(diagnostic.actionMacroSpellID)
        or matches(diagnostic.getMacroSpellByResolvedIndexSpellID)
        or matches(diagnostic.representedSpellID) then
        return true
    end

    -- A valid numeric action-info macro index already identifies *this* visible
    -- button, even when GetMacroInfo(index) temporarily has no body.  Preserve
    -- a request-scoped diagnostic only when the current button's action text
    -- visibly names the requested spell.  This is diagnostic evidence only:
    -- it never restores a body, never binds a macro, and never scans another
    -- macro index.  It prevents a genuine CTRL+1 trap failure from being hidden
    -- while still excluding unrelated buttons such as a BUTTON3 mount macro.
    if diagnostic.actionInfoLooksLikeMacroIndex == true
        and type(spellName) == "string" and spellName ~= ""
        and type(diagnostic.actionText) == "string" and diagnostic.actionText ~= "" then
        local actionText = trim(diagnostic.actionText):lower()
        local requestedName = trim(spellName):lower()
        if requestedName ~= "" and actionText:find(requestedName, 1, true) then
            return true
        end
    end
    return false
end

local function macroItemCandidateMatches(entry, itemID, itemName)
    if not (entry and entry.source == "macro" and TE.MacroSemantics
        and type(TE.MacroSemantics.MatchItem) == "function") then
        return false, "macro_item_semantics_unavailable"
    end
    local verified, identityReason = Resolver:IsVerifiedCurrentMacroSource(entry)
    if verified ~= true then return false, identityReason or "macro_identity_unverified" end
    local semantics = type(entry.macroSemantics) == "table" and entry.macroSemantics
        or (type(entry.macroBody) == "string" and type(TE.MacroSemantics.Analyze) == "function"
            and TE.MacroSemantics:Analyze(entry.macroBody) or nil)
    if not semantics then return false, "macro_body_unavailable" end
    -- Match only an exact existing macro body/ItemID/name association. Do not
    -- treat macro labels, icons or a macro-list entry as an action-bar source.
    return TE.MacroSemantics:MatchItem(semantics, itemID, itemName, "broad")
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
    local isMacro = entry.source == "macro"
    local semantics = entry.macroSemantics
    local macroAssociation = isMacro and association or nil
    -- Keep candidate metadata and AutoBurst on the same canonical macro
    -- contract.  Do not reproduce a looser action-info-only test here: the
    -- resolver helper excludes the P4 opaque target-transport exception.
    local macroAutoBurstEligible = true
    if isMacro then
        local eligibilityValue = {
            source = "macro",
            macroDiagnostic = entry.macroDiagnostic,
            macroOpaqueRepresentedSpell = entry.macroOpaqueRepresentedSpell == true,
            macroSemantics = semantics,
            macroAssociation = macroAssociation,
            macroAutoBurstEligible = semantics and semantics.autoBurstEligible == true,
        }
        macroAutoBurstEligible = Resolver:IsAutoBurstMacroEligible(eligibilityValue) == true
    end
    local actionBarStateTrusted = entry.actionSlot ~= nil and (
        not isMacro or macroAutoBurstEligible == true
    )
    return {
        spellID = spellID,
        slot = entry.actionSlot,
        actionSlot = entry.actionSlot,
        buttonName = entry.buttonName,
        bar = entry.bar,
        visualOrder = entry.visualOrder,
        visualX = entry.visualX,
        visualY = entry.visualY,
        source = entry.source,
        kind = entry.source,
        directActionSlot = (entry.source == "spell" or entry.source == "item") and entry.actionSlot ~= nil,
        actionBarStateTrusted = actionBarStateTrusted == true,
        matchKind = matchKind or "direct_spell",
        bindingCommand = entry.bindingCommand,
        rawBinding = entry.rawBinding,
        bindingSourceIndex = entry.bindingSourceIndex,
        parsed = parsed,
        reason = reason,
        macroID = entry.macroID,
        macroName = entry.macroName,
        macroAssociation = macroAssociation,
        macroCommand = macroAssociation,
        macroAutoBurstEligible = macroAutoBurstEligible == true,
        macroDiagnostic = entry.macroDiagnostic,
        macroSemantics = semantics,
        macroRepresentedSpellID = entry.macroRepresentedSpellID,
        macroRepresentedSpellSource = entry.macroRepresentedSpellSource,
        macroOpaqueRepresentedSpell = isMacro
            and association == "action_info_represented_spell"
            and entry.macroOpaqueRepresentedSpell == true,
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
        local matches, macroReason = macroCandidateMatches(entry, spellID, spellName)
        if not matches and macroDiagnosticRelatesToRequestedSpell(entry, spellID, spellName) then
            local diag = entry.macroDiagnostic or {}
            macroDiagnostics[#macroDiagnostics + 1] = {
                slot = entry.actionSlot,
                buttonName = entry.buttonName,
                bindingCommand = entry.bindingCommand,
                rawBinding = entry.rawBinding,
                actionInfoId = entry.actionInfoId,
                actionInfoValue = diag.actionInfoValue or entry.actionInfoId,
                actionText = diag.actionText,
                actionMacroSpellID = entry.macroSpellID or diag.actionMacroSpellID,
                macroName = entry.macroName,
                resolvedMacroIndex = entry.macroID,
                macroIdentitySource = diag.macroIdentitySource,
                macroIdentityVerified = diag.macroIdentityVerified == true,
                actionInfoMacroIndex = diag.actionInfoMacroIndex,
                actionInfoLooksLikeMacroIndex = diag.actionInfoLooksLikeMacroIndex == true,
                representedSpellID = diag.representedSpellID or entry.macroRepresentedSpellID,
                representedSpellSource = diag.representedSpellSource or entry.macroRepresentedSpellSource,
                opaqueRepresentedSpell = entry.macroOpaqueRepresentedSpell == true,
                actionTextCandidateCount = tonumber(diag.actionTextCandidateCount) or 0,
                semanticCandidateCount = tonumber(diag.semanticCandidateCount) or 0,
                semanticRejectedCount = tonumber(diag.semanticRejectedCount) or 0,
                semanticCandidateIndexes = diag.semanticCandidateIndexes,
                actionInfoIdReadAttempts = tonumber(diag.actionInfoIdReadAttempts) or 0,
                actionInfoIdSuccessfulReads = tonumber(diag.actionInfoIdSuccessfulReads) or 0,
                identityFailureReason = diag.failureReason,
                lookupSource = diag.lookupSource,
                lookupAttemptCount = tonumber(diag.lookupAttemptCount) or 0,
                lookupByActionText = diag.lookupByActionText == true,
                lookupByActionInfoName = diag.lookupByActionInfoName == true,
                actionInfoMacroName = diag.getMacroInfoByActionInfoIdName,
                resolvedBodyLength = macroBodyLength(entry.macroBody),
                resolvedSpellTokenCount = type(entry.macroSemanticSummary) == "table"
                    and tonumber(entry.macroSemanticSummary.resolvedSpellTokenCount) or 0,
                failureReason = macroReason or diag.failureReason or (entry.macroBody and "macro_spell_not_referenced" or "macro_body_unavailable"),
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
            macroCommand=selected.macroCommand, macroAutoBurstEligible=selected.macroAutoBurstEligible == true,
            macroDiagnostic=selected.macroDiagnostic, macroSemantics=selected.macroSemantics,
            matchedSpellName=selected.matchedSpellName, matchedSpellID=selected.matchedSpellID,
            requestedSpellID = spellID, matchKind = selected.matchKind,
            equivalentSpellIDs = equivalentSpellIDs, stateHash = cache.state and cache.state.stateHash or nil,
            bindingSettling = self:IsBindingSettling(), directActionSlot = selected.directActionSlot == true,
            actionBarStateTrusted = selected.actionBarStateTrusted == true,
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
            macroCommand=selected.macroCommand, macroAutoBurstEligible=selected.macroAutoBurstEligible == true,
            macroDiagnostic=selected.macroDiagnostic, macroSemantics=selected.macroSemantics,
            matchedSpellName=selected.matchedSpellName, matchedSpellID=selected.matchedSpellID,
            requestedSpellID = spellID, matchKind = selected.matchKind,
            equivalentSpellIDs = equivalentSpellIDs, stateHash = cache.state and cache.state.stateHash or nil,
            bindingSettling = self:IsBindingSettling(), directActionSlot = selected.directActionSlot == true,
            actionBarStateTrusted = selected.actionBarStateTrusted == true,
            candidates=candidates, macroDiagnostics=macroDiagnostics,
            cacheGeneration=cache.generation, cacheSummary=self:GetCacheSummary(),
            specialActionBar=specialActionBar,
        }
    end
    self.cache[spellID] = result
    self.lastReason = result.reason or "ready"
    return result, result.reason
end

local function makeItemCandidate(entry, itemID, association)
    local isMacro = entry.source == "macro"
    local macroAssociated = false
    if isMacro then
        local verified = Resolver:IsVerifiedCurrentMacroSource(entry, association)
        macroAssociated = verified == true and bodyVerifiedMacroAssociation(association) == true
    end
    return {
        itemID = itemID,
        slot = entry.actionSlot,
        actionSlot = entry.actionSlot,
        buttonName = entry.buttonName,
        bar = entry.bar,
        visualOrder = entry.visualOrder,
        visualX = entry.visualX,
        visualY = entry.visualY,
        source = entry.source,
        kind = entry.source,
        directActionSlot = entry.source == "item" and entry.actionSlot ~= nil,
        -- This says only that the current visible Blizzard button is a verified
        -- semantic source for the requested item. It grants no automatic input
        -- authority; survival remains advisory/manual-only.
        actionBarStateTrusted = entry.actionSlot ~= nil and (not isMacro or macroAssociated),
        bindingCommand = entry.bindingCommand,
        rawBinding = entry.rawBinding,
        bindingSourceIndex = entry.bindingSourceIndex,
        parsed = entry.parsedBinding,
        reason = entry.bindingError,
        macroID = entry.macroID,
        macroName = entry.macroName,
        macroAssociation = isMacro and association or nil,
        macroCommand = isMacro and association or nil,
        macroDiagnostic = entry.macroDiagnostic,
        macroSemantics = entry.macroSemantics,
        matchKind = isMacro and (association or "macro_item") or "direct_item",
    }
end

-- Resolve a visible action-bar item by ItemID. This remains a read-only mapping for survival/consumable display. Direct item buttons and existing `/use
-- <ItemID|item:ID|localized name>` macros share the same current-visible-button
-- identity policy as spell macros. This resolver does not create a BindingToken
-- for an unbound macro and never creates a TEAP/TEK path; it exists for
-- advisory display and physical HUD secure-click reuse.
function Resolver:ResolveItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return { status = "NoBinding", reason = "item_missing", bindingToken = 0, candidates = {} }, "item_missing"
    end
    local specialActionBar = self:GetSpecialActionBarState()
    if specialActionBar.active then
        return {
            itemID = itemID, status = "NoBinding", reason = specialActionBar.reason,
            bindingToken = 0, candidates = {}, macroDiagnostics = {}, specialActionBar = specialActionBar,
        }, specialActionBar.reason
    end
    self:EnsureCache("resolve_item")
    local cacheKey = "item:" .. tostring(itemID)
    local cached = self.cache[cacheKey]
    if cached then
        cached.specialActionBar = specialActionBar
        cached.bindingSettling = self:IsBindingSettling()
        return cached, cached.reason
    end

    local cache = self.buttonCache
    local itemName = getItemName(itemID)
    local candidates = {}
    for _, entry in ipairs((cache.byItem or {})[itemID] or {}) do
        candidates[#candidates + 1] = makeItemCandidate(entry, itemID, nil)
    end

    local macroSeen = {}
    for _, entry in ipairs(cache.macroEntries or {}) do
        local key = tostring(entry.buttonName) .. ":" .. tostring(entry.actionSlot)
        if not macroSeen[key] then
            local matches, association = macroItemCandidateMatches(entry, itemID, itemName)
            if matches then
                macroSeen[key] = true
                candidates[#candidates + 1] = makeItemCandidate(entry, itemID, association)
            end
        end
    end
    candidates = dedupeCandidates(candidates)
    table.sort(candidates, candidateCompare)

    local macroDiagnostics = {}
    for _, entry in ipairs(cache.macroEntries or {}) do
        local matches, macroReason = macroItemCandidateMatches(entry, itemID, itemName)
        -- Do not render every unrelated visible macro as a failed item source.
        -- Only an actual semantic ambiguity for this item would be actionable;
        -- ordinary non-references and opaque identities remain silent.
        if not matches and macroReason ~= "macro_item_not_referenced"
            and macroReason ~= "macro_identity_unverified"
            and macroReason ~= "macro_action_info_opaque_compat" then
            local diag = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic or {}
            macroDiagnostics[#macroDiagnostics + 1] = {
                slot = entry.actionSlot,
                buttonName = entry.buttonName,
                bindingCommand = entry.bindingCommand,
                rawBinding = entry.rawBinding,
                macroName = entry.macroName,
                resolvedMacroIndex = entry.macroID,
                macroIdentitySource = diag.macroIdentitySource,
                macroIdentityVerified = diag.macroIdentityVerified == true,
                actionInfoMacroIndex = diag.actionInfoMacroIndex,
                actionInfoIdReadAttempts = tonumber(diag.actionInfoIdReadAttempts) or 0,
                identityFailureReason = diag.failureReason,
                failureReason = macroReason or diag.failureReason or "macro_item_not_referenced",
            }
        end
    end

    local selected = candidates[1]
    local result
    if not selected then
        local reason = "actionbar_item_not_found"
        for _, diag in ipairs(macroDiagnostics) do
            if diag.failureReason == "macro_body_unavailable" then
                reason = "macro_body_unavailable"
                break
            end
        end
        result = {
            itemID = itemID, status = "NoBinding", reason = reason, bindingToken = 0,
            candidates = candidates, macroDiagnostics = macroDiagnostics,
            cacheGeneration = cache.generation, cacheSummary = self:GetCacheSummary(), specialActionBar = specialActionBar,
            directActionSlot = false, actionBarStateTrusted = false,
        }
    elseif not selected.parsed then
        result = {
            itemID = itemID, status = "NoBinding", reason = selected.reason or "binding_token_invalid", bindingToken = 0,
            slot = selected.slot, actionSlot = selected.actionSlot, buttonName = selected.buttonName,
            bar = selected.bar, source = selected.source, bindingCommand = selected.bindingCommand, rawBinding = selected.rawBinding,
            bindingSourceIndex = selected.bindingSourceIndex, directActionSlot = selected.directActionSlot == true,
            actionBarStateTrusted = selected.actionBarStateTrusted == true,
            macroID = selected.macroID, macroName = selected.macroName, macroAssociation = selected.macroAssociation,
            macroCommand = selected.macroCommand, macroDiagnostic = selected.macroDiagnostic,
            macroSemantics = selected.macroSemantics, matchKind = selected.matchKind,
            candidates = candidates, macroDiagnostics = macroDiagnostics,
            cacheGeneration = cache.generation, cacheSummary = self:GetCacheSummary(), specialActionBar = specialActionBar,
            bindingSettling = self:IsBindingSettling(),
        }
    else
        result = {
            itemID = itemID, status = "Ready", reason = nil,
            slot = selected.slot, actionSlot = selected.actionSlot, buttonName = selected.buttonName,
            bar = selected.bar, source = selected.source, bindingCommand = selected.bindingCommand,
            bindingSourceIndex = selected.bindingSourceIndex, binding = selected.parsed.binding,
            bindingToken = selected.parsed.token, inputType = selected.parsed.inputType,
            key = selected.parsed.key, modifier = selected.parsed.modifier,
            directActionSlot = selected.directActionSlot == true,
            actionBarStateTrusted = selected.actionBarStateTrusted == true,
            macroID = selected.macroID, macroName = selected.macroName, macroAssociation = selected.macroAssociation,
            macroCommand = selected.macroCommand, macroDiagnostic = selected.macroDiagnostic,
            macroSemantics = selected.macroSemantics, matchKind = selected.matchKind,
            candidates = candidates, macroDiagnostics = macroDiagnostics,
            cacheGeneration = cache.generation, cacheSummary = self:GetCacheSummary(), specialActionBar = specialActionBar,
            bindingSettling = self:IsBindingSettling(),
        }
    end
    self.cache[cacheKey] = result
    self.lastReason = result.reason or "ready"
    return result, result.reason
end

-- Resolve one explicitly configured equipped trinket slot.  Direct item buttons
-- and visible user macros such as `/use 13` are both accepted.  This resolver
-- never changes the macro or evaluates a branch: it only returns the existing
-- button's BindingToken.  A macro referring to both 13 and 14 is rejected so
-- callers must model each trinket as a separate explicit action.
local function currentInventoryItemID(slot)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local ok, itemID = safeCall(GetInventoryItemID, "player", slot)
    itemID = ok and tonumber(itemID) or nil
    return itemID and itemID > 0 and math.floor(itemID) or nil
end

local function inventoryMacroMatches(entry, slot)
    if not (entry and entry.source == "macro" and TE.MacroSemantics
        and type(TE.MacroSemantics.MatchInventorySlot) == "function") then
        return false, "macro_inventory_semantics_unavailable"
    end
    local verified, identityReason = Resolver:IsVerifiedCurrentMacroSource(entry)
    if verified ~= true then return false, identityReason or "macro_identity_unverified" end
    return TE.MacroSemantics:MatchInventorySlot(entry.macroSemantics, slot, "broad")
end

local function makeInventoryCandidate(entry, slot, itemID, association)
    local parsed = entry.parsedBinding
    local isMacro = entry.source == "macro"
    local semantics = entry.macroSemantics
    local macroEligible = true
    if isMacro then
        local eligibilityValue = {
            source = "macro",
            macroDiagnostic = entry.macroDiagnostic,
            macroOpaqueRepresentedSpell = entry.macroOpaqueRepresentedSpell == true,
            macroSemantics = semantics,
            macroAssociation = association,
            macroAutoBurstEligible = semantics and semantics.autoBurstEligible == true,
        }
        macroEligible = Resolver:IsAutoBurstMacroEligible(eligibilityValue) == true
    end
    return {
        itemID = itemID,
        expectedItemID = itemID,
        inventorySlot = slot,
        actionKind = "inventory",
        slot = entry.actionSlot,
        actionSlot = entry.actionSlot,
        buttonName = entry.buttonName,
        bar = entry.bar,
        visualOrder = entry.visualOrder,
        visualX = entry.visualX,
        visualY = entry.visualY,
        source = entry.source,
        kind = entry.source,
        directActionSlot = (entry.source == "item") and entry.actionSlot ~= nil,
        actionBarStateTrusted = entry.actionSlot ~= nil and (not isMacro or macroEligible == true),
        bindingCommand = entry.bindingCommand,
        rawBinding = entry.rawBinding,
        bindingSourceIndex = entry.bindingSourceIndex,
        parsed = parsed,
        reason = entry.bindingError,
        macroID = entry.macroID,
        macroName = entry.macroName,
        macroAssociation = isMacro and association or nil,
        macroCommand = isMacro and association or nil,
        macroAutoBurstEligible = macroEligible == true,
        macroDiagnostic = entry.macroDiagnostic,
        macroSemantics = semantics,
        matchKind = isMacro and (association or "macro_inventory") or "direct_inventory_item",
    }
end

function Resolver:ResolveInventorySlot(slot, expectedItemID)
    slot = tonumber(slot)
    if slot ~= 13 and slot ~= 14 then
        return { status = "NoBinding", reason = "inventory_slot_invalid", bindingToken = 0, candidates = {} }, "inventory_slot_invalid"
    end
    expectedItemID = tonumber(expectedItemID)
    expectedItemID = expectedItemID and expectedItemID > 0 and math.floor(expectedItemID) or nil
    local currentItemID = currentInventoryItemID(slot)
    if not currentItemID then
        return {
            inventorySlot = slot, expectedItemID = expectedItemID, itemID = nil,
            status = "NoBinding", reason = "inventory_item_missing", bindingToken = 0, candidates = {},
        }, "inventory_item_missing"
    end
    if expectedItemID and expectedItemID ~= currentItemID then
        return {
            inventorySlot = slot, expectedItemID = expectedItemID, itemID = currentItemID,
            status = "NoBinding", reason = "inventory_equipment_changed", bindingToken = 0, candidates = {},
        }, "inventory_equipment_changed"
    end
    local specialActionBar = self:GetSpecialActionBarState()
    if specialActionBar.active then
        return {
            inventorySlot = slot, expectedItemID = currentItemID, itemID = currentItemID,
            status = "NoBinding", reason = specialActionBar.reason, bindingToken = 0,
            candidates = {}, specialActionBar = specialActionBar,
        }, specialActionBar.reason
    end
    self:EnsureCache("resolve_inventory_slot")
    local cacheKey = "inventory_slot:" .. tostring(slot) .. ":" .. tostring(currentItemID)
    local cached = self.cache[cacheKey]
    if cached then
        cached.specialActionBar = specialActionBar
        cached.bindingSettling = self:IsBindingSettling()
        return cached, cached.reason
    end

    local cache = self.buttonCache
    local candidates = {}
    for _, entry in ipairs((cache.byItem or {})[currentItemID] or {}) do
        candidates[#candidates + 1] = makeInventoryCandidate(entry, slot, currentItemID, nil)
    end
    local macroSeen = {}
    for _, entry in ipairs((cache.macroByInventorySlot or {})[slot] or {}) do
        local key = tostring(entry.buttonName) .. ":" .. tostring(entry.actionSlot)
        if not macroSeen[key] then
            local matches, association = inventoryMacroMatches(entry, slot)
            if matches then
                macroSeen[key] = true
                candidates[#candidates + 1] = makeInventoryCandidate(entry, slot, currentItemID, association)
            end
        end
    end
    candidates = dedupeCandidates(candidates)
    table.sort(candidates, candidateCompare)

    local macroDiagnostics = {}
    for _, entry in ipairs(cache.macroEntries or {}) do
        local matches, association = inventoryMacroMatches(entry, slot)
        if not matches and association ~= "macro_inventory_slot_not_referenced"
            and association ~= "macro_identity_unverified"
            and association ~= "macro_action_info_opaque_compat" then
            macroDiagnostics[#macroDiagnostics + 1] = {
                slot = entry.actionSlot,
                buttonName = entry.buttonName,
                bindingCommand = entry.bindingCommand,
                rawBinding = entry.rawBinding,
                macroName = entry.macroName,
                resolvedMacroIndex = entry.macroID,
                macroIdentitySource = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic.macroIdentitySource or nil,
                macroIdentityVerified = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic.macroIdentityVerified == true,
                actionInfoMacroIndex = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic.actionInfoMacroIndex or nil,
                actionInfoIdReadAttempts = type(entry.macroDiagnostic) == "table" and tonumber(entry.macroDiagnostic.actionInfoIdReadAttempts) or 0,
                identityFailureReason = type(entry.macroDiagnostic) == "table" and entry.macroDiagnostic.failureReason or nil,
                failureReason = association or "macro_inventory_slot_not_referenced",
            }
        end
    end

    local selected = candidates[1]
    local result
    if not selected then
        result = {
            inventorySlot = slot, expectedItemID = currentItemID, itemID = currentItemID,
            status = "NoBinding", reason = "actionbar_inventory_slot_not_found", bindingToken = 0,
            candidates = candidates, macroDiagnostics = macroDiagnostics,
            cacheGeneration = cache.generation, cacheSummary = self:GetCacheSummary(), specialActionBar = specialActionBar,
        }
    elseif not selected.parsed then
        result = {
            inventorySlot = slot, expectedItemID = currentItemID, itemID = currentItemID,
            status = "NoBinding", reason = selected.reason or "binding_token_invalid", bindingToken = 0,
            slot = selected.slot, actionSlot = selected.actionSlot, buttonName = selected.buttonName,
            source = selected.source, bindingCommand = selected.bindingCommand, rawBinding = selected.rawBinding,
            bindingSourceIndex = selected.bindingSourceIndex, macroID = selected.macroID, macroName = selected.macroName,
            macroAssociation = selected.macroAssociation, macroCommand = selected.macroCommand,
            macroAutoBurstEligible = selected.macroAutoBurstEligible == true,
            macroDiagnostic = selected.macroDiagnostic, macroSemantics = selected.macroSemantics,
            directActionSlot = selected.directActionSlot == true, actionBarStateTrusted = selected.actionBarStateTrusted == true,
            candidates = candidates, macroDiagnostics = macroDiagnostics, cacheGeneration = cache.generation,
            cacheSummary = self:GetCacheSummary(), specialActionBar = specialActionBar,
        }
    else
        result = {
            inventorySlot = slot, expectedItemID = currentItemID, itemID = currentItemID,
            status = "Ready", reason = nil, slot = selected.slot, actionSlot = selected.actionSlot,
            buttonName = selected.buttonName, bar = selected.bar, source = selected.source,
            bindingCommand = selected.bindingCommand, bindingSourceIndex = selected.bindingSourceIndex,
            binding = selected.parsed.binding, bindingToken = selected.parsed.token,
            inputType = selected.parsed.inputType, key = selected.parsed.key, modifier = selected.parsed.modifier,
            macroID = selected.macroID, macroName = selected.macroName, macroAssociation = selected.macroAssociation,
            macroCommand = selected.macroCommand, macroAutoBurstEligible = selected.macroAutoBurstEligible == true,
            macroDiagnostic = selected.macroDiagnostic, macroSemantics = selected.macroSemantics,
            directActionSlot = selected.directActionSlot == true, actionBarStateTrusted = selected.actionBarStateTrusted == true,
            candidates = candidates, macroDiagnostics = macroDiagnostics, cacheGeneration = cache.generation,
            cacheSummary = self:GetCacheSummary(), specialActionBar = specialActionBar,
        }
    end
    self.cache[cacheKey] = result
    self.lastReason = result.reason or "ready"
    return result, result.reason
end


-- P5.8 manual HUD entry helpers. These are intentionally separate from the
-- BindingToken dispatch resolvers: a player may click a visible action button
-- even when it has no keyboard binding, while TEAP/TEK must still require a
-- normalized BindingToken. The returned button is only ever consumed by the
-- secure HUD proxy during a physical mouse click.
local function manualButtonVisible(button)
    if not button then return false end
    if type(button.IsShown) == "function" and button:IsShown() ~= true then return false end
    if type(button.IsVisible) == "function" and button:IsVisible() ~= true then return false end
    return true
end

local function verifiedManualMacroResult(result)
    if type(result) ~= "table" or result.source ~= "macro" then return true end
    local verified = Resolver:IsVerifiedCurrentMacroSource(result, result.macroAssociation)
    return verified == true
end

local function verifiedManualMacroEntry(entry)
    if type(entry) ~= "table" or entry.source ~= "macro" then return true end
    -- Cache entries have no final request association yet. Their exact spell or
    -- item association is re-proven immediately before the secure proxy uses
    -- them, so this check enforces current identity/semantics without guessing.
    local verified = Resolver:IsVerifiedCurrentMacroSource(entry)
    return verified == true
end

local function manualTargetFromResult(result, fallbackReason)
    result = type(result) == "table" and result or {}
    local special = type(result.specialActionBar) == "table" and result.specialActionBar or nil
    if verifiedManualMacroResult(result) ~= true then
        return { status = "Blocked", reason = "manual_macro_identity_unverified", resolverReason = result.reason or fallbackReason }
    end
    if special and special.active == true then
        return { status = "Blocked", reason = "manual_actionbar_special_actionbar" }
    end
    local buttonName = type(result.buttonName) == "string" and result.buttonName or nil
    if not buttonName then
        return { status = "Blocked", reason = "manual_actionbar_source_missing", resolverReason = result.reason or fallbackReason }
    end
    local button = _G[buttonName]
    if not button then
        return { status = "Blocked", reason = "manual_actionbar_button_missing", buttonName = buttonName, resolverReason = result.reason or fallbackReason }
    end
    if not manualButtonVisible(button) then
        return { status = "Blocked", reason = "manual_actionbar_button_hidden", buttonName = buttonName, resolverReason = result.reason or fallbackReason }
    end
    return {
        status = "Ready",
        button = button,
        buttonName = buttonName,
        actionSlot = tonumber(result.actionSlot or result.slot) or nil,
        inventorySlot = tonumber(result.inventorySlot) or nil,
        itemID = tonumber(result.itemID or result.expectedItemID) or nil,
        spellID = tonumber(result.spellID or result.requestedSpellID) or nil,
        source = result.source or result.kind or "actionbar",
        macroID = result.macroID,
        macroAssociation = result.macroAssociation,
        resolverStatus = result.status,
    }
end

function Resolver:ResolveManualSpell(spellID)
    local result, reason = self:ResolveSpell(spellID)
    return manualTargetFromResult(result, reason)
end

function Resolver:ResolveManualItem(itemID)
    local result, reason = self:ResolveItem(itemID)
    return manualTargetFromResult(result, reason)
end

function Resolver:ResolveManualInventorySlot(slot, expectedItemID)
    local result, reason = self:ResolveInventorySlot(slot, expectedItemID)
    return manualTargetFromResult(result, reason)
end

-- P5.10 exact HUD-source verification. A tactical card may already identify a
-- concrete visible action-bar button (for example, a hunter `[@cursor]` Trap
-- macro on CTRL+1).  Do not silently resolve that card to another copy of the
-- same spell on a different slot: re-check the current button cache and either
-- reuse that exact source or block until the normal out-of-combat HUD rebuild.
-- This remains a physical HUD click proxy only; it never creates a token,
-- changes a macro, evaluates a branch, or alters the player's target.
local function preferredHudField(item, key)
    item = type(item) == "table" and item or {}
    local bindingInfo = type(item.bindingInfo) == "table" and item.bindingInfo or {}
    local value = item[key]
    if value == nil then value = bindingInfo[key] end
    return value
end

local function preferredHudSource(item)
    local bindingInfo = type(item) == "table" and type(item.bindingInfo) == "table" and item.bindingInfo or {}
    return preferredHudField(item, "source") or (type(item) == "table" and item.bindingSource) or bindingInfo.source
end

-- A compact in-memory semantic identity for exact HUD source verification. It
-- is derived from parsed commands/tokens/targets only: the macro text itself is
-- never copied to card data or persisted. Any edit that changes a target mode,
-- spell/item token, conditional branch count, or target mutation changes this
-- signature and forces fail-closed remapping.
local function macroSemanticIdentity(semantics)
    if type(semantics) ~= "table" then return nil end
    local parts = {
        tostring(semantics.macroShape or ""),
        tostring(tonumber(semantics.actionLineCount) or 0),
        tostring(semantics.hasCastsequence == true),
        tostring(semantics.hasConditional == true),
        tostring(semantics.hasTargetMutation == true),
    }
    for _, action in ipairs(semantics.actions or {}) do
        local conditions = {}
        for _, block in ipairs(type(action.conditionBlocks) == "table" and action.conditionBlocks or {}) do
            conditions[#conditions + 1] = tostring(block)
        end
        parts[#parts + 1] = table.concat({
            tostring(action.command or ""),
            tostring(action.kind or ""),
            tostring(action.token or ""),
            tostring(tonumber(action.resolvedSpellID) or 0),
            tostring(tonumber(action.resolvedItemID) or 0),
            tostring(action.target or ""),
            tostring(tonumber(action.branchIndex) or 0),
            table.concat(conditions, "&"),
        }, "~")
    end
    for _, token in ipairs(semantics.castsequenceTokens or {}) do
        parts[#parts + 1] = "seq:" .. tostring(token)
    end
    for _, command in ipairs(semantics.targetMutationCommands or {}) do
        parts[#parts + 1] = "mut:" .. tostring(command)
    end
    return table.concat(parts, "|")
end

local function exactManualSourceIdentityMatches(item, entry)
    item = type(item) == "table" and item or {}
    entry = type(entry) == "table" and entry or {}
    local expectedSource = preferredHudSource(item)
    if type(expectedSource) == "string" and expectedSource ~= "" and entry.source ~= expectedSource then
        return false
    end
    if expectedSource ~= "macro" then return true end
    if verifiedManualMacroEntry(entry) ~= true then return false end
    local expectedMacroID = tonumber(preferredHudField(item, "macroID"))
    if expectedMacroID and tonumber(entry.macroID) ~= expectedMacroID then return false end
    local expectedSemantics = preferredHudField(item, "macroSemantics")
    local expectedIdentity = macroSemanticIdentity(expectedSemantics)
    if expectedIdentity and expectedIdentity ~= macroSemanticIdentity(entry.macroSemantics) then return false end
    return true
end

local function exactManualSpellMatch(resolver, cache, entry, spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 or type(entry) ~= "table" then return false, nil end
    local equivalents = resolver:GetEquivalentSpellIDs(spellID, cache)
    for _, equivalentID in ipairs(equivalents or {}) do
        if entry.source == "spell" and tonumber(entry.spellID) == tonumber(equivalentID) then
            return true, tonumber(equivalentID)
        end
        if entry.source == "macro" and verifiedManualMacroEntry(entry) == true then
            local matched = macroCandidateMatches(entry, equivalentID, getSpellName(equivalentID))
            if matched then return true, tonumber(equivalentID) end
        end
    end
    return false, nil
end

local function exactManualItemMatch(entry, itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 or type(entry) ~= "table" then return false end
    if entry.source == "item" and tonumber(entry.itemID) == itemID then return true end
    if entry.source == "macro" and verifiedManualMacroEntry(entry) == true then
        local matched = macroItemCandidateMatches(entry, itemID, getItemName(itemID))
        return matched == true
    end
    return false
end

local function exactManualInventoryMatch(entry, inventorySlot, itemID)
    inventorySlot = tonumber(inventorySlot)
    if inventorySlot ~= 13 and inventorySlot ~= 14 then return false end
    if entry.source == "macro" and verifiedManualMacroEntry(entry) == true then
        local matched = inventoryMacroMatches(entry, inventorySlot)
        return matched == true
    end
    if entry.source == "item" and itemID and tonumber(entry.itemID) == tonumber(itemID) then
        -- A direct equipped-item card is still tied to the current physical
        -- item identity. We do not infer a different item/slot association.
        return true
    end
    return false
end

local function exactManualHudTarget(resolver, item)
    item = type(item) == "table" and item or {}
    local buttonName = preferredHudField(item, "buttonName")
    if type(buttonName) ~= "string" or buttonName == "" then
        return { status = "Blocked", reason = "manual_actionbar_source_missing" }
    end

    local specialActionBar = resolver:GetSpecialActionBarState()
    if specialActionBar and specialActionBar.active == true then
        return { status = "Blocked", reason = "manual_actionbar_special_actionbar" }
    end
    local cache = resolver:EnsureCache("manual_exact_hud_source")
    if type(cache) ~= "table" then
        return { status = "Blocked", reason = "manual_actionbar_source_missing" }
    end

    local expectedSlot = tonumber(preferredHudField(item, "actionSlot") or preferredHudField(item, "slot"))
    local spellID = tonumber(item.spellID)
    local itemID = tonumber(item.itemID)
    local inventorySlot = tonumber(item.inventorySlot or item.itemSlot)
    if not ((spellID and spellID > 0) or (itemID and itemID > 0) or inventorySlot == 13 or inventorySlot == 14) then
        return { status = "Blocked", reason = "manual_actionbar_source_missing" }
    end

    for _, entry in ipairs(cache.entries or {}) do
        if entry.buttonName == buttonName
            and (not expectedSlot or tonumber(entry.actionSlot) == expectedSlot)
            and exactManualSourceIdentityMatches(item, entry) == true then
            local matched, matchedSpellID = false, nil
            if spellID and spellID > 0 then
                matched, matchedSpellID = exactManualSpellMatch(resolver, cache, entry, spellID)
            elseif inventorySlot == 13 or inventorySlot == 14 then
                matched = exactManualInventoryMatch(entry, inventorySlot, itemID)
            elseif itemID and itemID > 0 then
                matched = exactManualItemMatch(entry, itemID)
            end
            if matched then
                return manualTargetFromResult({
                    status = "Ready",
                    buttonName = entry.buttonName,
                    actionSlot = entry.actionSlot,
                    inventorySlot = inventorySlot,
                    itemID = itemID,
                    spellID = spellID,
                    requestedSpellID = spellID,
                    matchedSpellID = matchedSpellID,
                    source = entry.source,
                    macroID = entry.macroID,
                    macroAssociation = entry.macroAssociation,
                    macroDiagnostic = entry.macroDiagnostic,
                    macroSemantics = entry.macroSemantics,
                })
            end
        end
    end

    -- A preferred source is an identity contract, not a hint. Falling back to
    -- another matching spell/item would change the player-authored macro or
    -- target semantics. Keep the card visible but block it until OOC refresh.
    return {
        status = "Blocked",
        reason = "manual_actionbar_source_changed",
        buttonName = buttonName,
        actionSlot = expectedSlot,
    }
end

function Resolver:ResolveManualHudAction(item)
    item = type(item) == "table" and item or {}
    -- When the card came from a P5.10 manual macro/source record, it already
    -- names the exact visible Blizzard button. Verify this identity first and
    -- never redirect a click to a different same-spell button.
    if type(preferredHudField(item, "buttonName")) == "string" and preferredHudField(item, "buttonName") ~= "" then
        return exactManualHudTarget(self, item)
    end

    local inventorySlot = tonumber(item.inventorySlot or item.itemSlot)
    local itemID = tonumber(item.itemID)
    -- A trinket HUD card represents a physical 13/14 slot, not merely its
    -- current item/spell identity. Resolve that exact existing action-bar/macro
    -- source first so duplicate items, shared effects and `/use 13|14` macros
    -- preserve the player's original slot semantics.
    if inventorySlot == 13 or inventorySlot == 14 then
        return self:ResolveManualInventorySlot(inventorySlot, itemID)
    end

    local spellID = tonumber(item.spellID)
    if spellID and spellID > 0 then return self:ResolveManualSpell(spellID) end
    if itemID and itemID > 0 then return self:ResolveManualItem(itemID) end
    return { status = "Blocked", reason = "manual_actionbar_source_missing" }
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
