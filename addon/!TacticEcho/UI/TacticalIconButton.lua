-- Tactic Echo tactical HUD icon component.
--
-- Display-only presentation component. It never changes recommendations,
-- bindings, Token/TEAP data, or TEK input. Native action-bar presentation is
-- optional and failure-tolerant: atlas/mask errors fall back to a visible icon.
local TE = _G.TacticEcho
-- Dynamic effect ownership: TacticalIconEffects.lua
local TacticalIconEffects = TE.TacticalIconEffects

local TacticalIconButton = {}
TE.TacticalIconButton = TacticalIconButton

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Force a plain arithmetic/comparison probe before using a numeric API value.
local function safeNumber(value)
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

local function safeText(value, fallback)
    local ok, result = pcall(function()
        if value == nil then return fallback or "" end
        if type(value) == "string" then
            local length = #value
            if length < 0 then return fallback or "" end
            return value
        end
        if type(value) == "boolean" then return value and "true" or "false" end
        local number = safeNumber(value)
        if number ~= nil then return tostring(number) end
        return fallback or ""
    end)
    return ok and type(result) == "string" and result or (fallback or "")
end

local function clamp(value, minimum, maximum)
    value = safeNumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

-- This affects HUD text only. It intentionally does not change the resolver,
-- token format, TEAP payload, or TEK modifier policy.
local function formatBinding(binding)
    local value = safeText(binding, "")
    if value == "" then return "" end
    value = value:upper():gsub("%-", "+"):gsub("%s+", "")
    local hasShift, hasCtrl, hasAlt = false, false, false
    local changed = true
    while changed do
        changed = false
        local rest = value:match("^SHIFT%+(.+)$")
        if rest then hasShift, value, changed = true, rest, true end
        rest = value:match("^CTRL%+(.+)$") or value:match("^CONTROL%+(.+)$")
        if rest then hasCtrl, value, changed = true, rest, true end
        rest = value:match("^ALT%+(.+)$")
        if rest then hasAlt, value, changed = true, rest, true end
    end
    value = value:gsub("%+", "")
    return (hasShift and "S" or "") .. (hasCtrl and "C" or "") .. (hasAlt and "A" or "") .. value
end

local function setColor(texture, color)
    color = color or { 0.20, 0.28, 0.40, 1 }
    if texture and texture.SetColorTexture then
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

local function applyBorder(card, color)
    -- Native mode intentionally does not tint or expose any WHITE8X8 border.
    -- Blizzard's IconFrame atlas is the sole static frame in that mode.
    if card and card.resolvedAppearance and card.resolvedAppearance.theme == "native" then
        return
    end
    color = color or { 0.20, 0.28, 0.40, 0.92 }
    if card.SetBackdropBorderColor then
        card:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    end
    if card.border and card.border.SetBackdropBorderColor then
        card.border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function createBackdrop(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.01, 0.02, 0.03, 0.90)
    frame:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.92)
end

local function safeShown(frame, shown)
    if frame and frame.SetShown then pcall(frame.SetShown, frame, shown == true) end
end

-- Native IconFrame needs a visible rim between the spell art and the outer
-- action-button contour.  Keep spell art slightly inside the button while the
-- background, native border, hover/cast overlays and Proc rings remain on the
-- outer action-button geometry.  This prevents the icon from visually touching
-- the frame and leaves room for the rounded native bevel.
local ICON_INSET = 3

local function applyIconPlaneGeometry(texture, parent, inset)
    if not texture or not parent then return end
    inset = math.max(0, tonumber(inset) or 0)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end
local function applyActionButtonBorderGeometry(texture, parent, size)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    texture:SetSize(size + 1, size)
end

local function createRoundedActionIconMask(parent, size, ...)
    if not parent or type(parent.CreateMaskTexture) ~= "function" then return nil end
    local ok, mask = pcall(parent.CreateMaskTexture, parent, nil, "ARTWORK")
    if not ok or not mask then return nil end
    local maskSize = math.floor((clamp(size, 20, 160) * 1.5) + 0.5)
    mask:SetPoint("CENTER", parent, "CENTER", 0, 0)
    mask:SetSize(maskSize, maskSize)
    local applied = pcall(mask.SetAtlas, mask, "UI-HUD-ActionBar-IconFrame-Mask", false)
    if not applied then
        mask:Hide()
        return nil
    end
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if texture and type(texture.AddMaskTexture) == "function" then
            pcall(texture.AddMaskTexture, texture, mask)
        end
    end
    return mask
end

local function resolveAppearance(module)
    local style = type(module) == "table" and module.appearance or {}
    return {
        theme = style.theme == "minimal" and "minimal" or "native",
        roundedIcons = style.roundedIcons ~= false,
        showBorder = style.showBorder ~= false,
        hoverHighlight = style.hoverHighlight ~= false,
        pressedHighlight = style.pressedHighlight ~= false,
        castHighlight = style.castHighlight ~= false,
        fadeTransitions = style.fadeTransitions ~= false,
        masque = style.masque == true,
    }
end

local function tryApplyMasque(card, enabled)
    if not card or enabled ~= true or card.masqueApplied then return end
    if not LibStub then return end
    local ok, masque = pcall(LibStub, "Masque", true)
    if not ok or not masque or type(masque.Group) ~= "function" then return end
    local groupOK, group = pcall(masque.Group, masque, "Tactic Echo")
    if not group or groupOK == false or type(group.AddButton) ~= "function" then return end
    local applied = pcall(group.AddButton, group, card, {
        Icon = card.icon,
        Cooldown = card.cooldown,
        ChargeCooldown = card.chargeCooldown,
        HotKey = card.hotkey,
        Count = card.chargeText,
        Normal = card.nativeBorder,
        Pushed = card.pushedTexture,
        Highlight = card.hoverTexture,
    })
    if applied then card.masqueApplied = true end
end

local function playVisibilityFade(card, targetAlpha, show)
    if not card or not card.fadeGroup then return false end
    card.fadeTo = clamp(targetAlpha, 0.05, 1)
    if show then card:Show() end
    local anim = card.fadeAlpha
    if not anim then return false end
    card.fadeGroup:Stop()
    anim:SetFromAlpha(card:GetAlpha() or 1)
    anim:SetToAlpha(card.fadeTo)
    card.fadeGroup:Play()
    return true
end

local function setVisible(card, visible, alpha)
    if not card then return end
    if visible ~= true then
        if card.fadeGroup and card.resolvedAppearance and card.resolvedAppearance.fadeTransitions then
            card.fadeTo = 0
            card.fadeGroup:Stop()
            card.fadeAlpha:SetFromAlpha(card:GetAlpha() or 1)
            card.fadeAlpha:SetToAlpha(0)
            card.fadeGroup:Play()
        else
            card:Hide()
        end
        return
    end
    local targetAlpha = clamp(alpha, 0.05, 1.00)
    if card.resolvedAppearance and card.resolvedAppearance.fadeTransitions and card:IsShown() then
        playVisibilityFade(card, targetAlpha, true)
    else
        card:SetAlpha(targetAlpha)
        card:Show()
    end
    if card.icon then card.icon:SetAlpha(1); card.icon:Show() end
end
local function setIcon(card, texture)
    if not card or not card.icon then return end
    local applied = false
    if texture ~= nil then applied = pcall(card.icon.SetTexture, card.icon, texture) end
    if not applied then pcall(card.icon.SetTexture, card.icon, QUESTION_ICON) end
    if texture == nil then pcall(card.icon.SetTexture, card.icon, QUESTION_ICON) end
    pcall(card.icon.SetTexCoord, card.icon, 0.08, 0.92, 0.08, 0.92)
    pcall(card.icon.SetVertexColor, card.icon, 1, 1, 1, 1)
    card.icon:SetAlpha(1)
    card.icon:Show()
end

local function normalizeColor(value)
    value = type(value) == "table" and value or {}
    return safeNumber(value.r or value[1]) or 1,
        safeNumber(value.g or value[2]) or 1,
        safeNumber(value.b or value[3]) or 1,
        safeNumber(value.a or value[4]) or 1
end

local VALID_POINTS = {
    TOPLEFT = true, TOPRIGHT = true, CENTER = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function resolveModuleStyle(hud, moduleKey)
    hud = type(hud) == "table" and hud or {}
    local modules = type(hud.modules) == "table" and hud.modules or {}
    local style = type(modules[moduleKey or "main"]) == "table" and modules[moduleKey or "main"] or {}
    -- Keep 0.7.6 saved variables valid for the main queue.
    if moduleKey == "main" and type(style.keyLabel) ~= "table" and type(hud.keyLabel) == "table" then
        style.keyLabel = hud.keyLabel
    end
    return style
end

local function textStyle(style, defaults)
    style = type(style) == "table" and style or {}
    defaults = defaults or {}
    local color = style.color or defaults.color or { r = 1, g = 1, b = 1, a = 1 }
    return {
        enabled = style.enabled ~= false,
        fontSize = clamp(style.fontSize, 8, 30),
        scale = clamp(style.scale, 0.60, 2.00),
        point = VALID_POINTS[style.point] and style.point or (defaults.point or "CENTER"),
        offsetX = safeNumber(style.offsetX) or (defaults.offsetX or 0),
        offsetY = safeNumber(style.offsetY) or (defaults.offsetY or 0),
        color = color,
        fontPreset = style.fontPreset or defaults.fontPreset or "normal",
    }
end

local function applyFontStyle(fontString, style, defaults)
    if not fontString then return end
    local resolved = textStyle(style, defaults)
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local flags = resolved.fontPreset == "disable" and "" or "OUTLINE"
    fontString:SetFont(font, resolved.fontSize, flags)
    local red, green, blue, alpha = normalizeColor(resolved.color)
    fontString:SetTextColor(red, green, blue, alpha)
    fontString:SetScale(resolved.scale)
    fontString:ClearAllPoints()
    fontString:SetPoint(resolved.point, fontString:GetParent(), resolved.point, resolved.offsetX, resolved.offsetY)
    fontString:SetShown(resolved.enabled)
    return resolved
end

local function styleMarker(value)
    local number = safeNumber(value)
    if number ~= nil then return string.format("%.3f", number) end
    if value == true then return "1" end
    if value == false then return "0" end
    return value == nil and "-" or safeText(value, "-")
end

local function textStyleMarker(style)
    style = type(style) == "table" and style or {}
    local color = type(style.color) == "table" and style.color or {}
    return table.concat({
        styleMarker(style.enabled), styleMarker(style.fontSize), styleMarker(style.scale),
        styleMarker(style.point), styleMarker(style.offsetX), styleMarker(style.offsetY),
        styleMarker(style.fontPreset), styleMarker(style.mode), styleMarker(color.r or color[1]), styleMarker(color.g or color[2]),
        styleMarker(color.b or color[3]), styleMarker(color.a or color[4]),
    }, ":")
end

local function cooldownStyleMarker(style)
    style = type(style) == "table" and style or {}
    return table.concat({ styleMarker(style.enabled), styleMarker(style.alpha), styleMarker(style.reverse) }, ":")
end

local function cooldownData(item, prefix)
    prefix = prefix or "cooldown"
    local known = item and item[prefix .. "Known"] == true
    local start = safeNumber(item and item[prefix .. "Start"])
    local duration = safeNumber(item and item[prefix .. "Duration"])
    return known and start ~= nil and duration ~= nil and duration > 0, start, duration
end

local function sameCooldown(startA, durationA, startB, durationB)
    if startA == nil or durationA == nil or startB == nil or durationB == nil then return false end
    return math.abs(startA - startB) <= 0.05 and math.abs(durationA - durationB) <= 0.05
end

local function configureCooldown(frame, style)
    local enabled = type(style) ~= "table" or style.enabled ~= false
    local alpha = clamp(type(style) == "table" and style.alpha or 0.55, 0, 0.95)
    local reverse = type(style) == "table" and style.reverse == true
    if frame.SetDrawSwipe then frame:SetDrawSwipe(enabled) end
    if frame.SetDrawEdge then frame:SetDrawEdge(false) end
    if frame.SetDrawBling then frame:SetDrawBling(false) end
    if frame.SetReverse then frame:SetReverse(reverse) end
    if frame.SetHideCountdownNumbers then frame:SetHideCountdownNumbers(true) end
    frame:SetAlpha(enabled and alpha or 0)
    return enabled, reverse
end

local function showCooldown(frame, start, duration, enabled)
    if not enabled or start == nil or duration == nil or duration <= 0 then
        frame:Hide()
        return false
    end
    local ok = pcall(function()
        frame:SetCooldown(start, duration)
        frame:Show()
    end)
    if not ok then frame:Hide() end
    return ok
end

-- Current protected-cooldown clients do not permit tainted addon code to call
-- Cooldown:SetCooldown() with secret start/duration values.  The safe display
-- path is a DurationObject passed directly to Blizzard's native cooldown frame.
-- This code is presentation-only: it never materializes, compares, stores or
-- forwards the raw duration into tactical state, recommendations, TEAP or TEK.
local function setNativeCountdownNumbers(frame, shown)
    if frame and frame.SetHideCountdownNumbers then
        pcall(frame.SetHideCountdownNumbers, frame, shown ~= true)
    end
end

local function hideCooldown(frame)
    if not frame then return end
    setNativeCountdownNumbers(frame, false)
    frame:Hide()
end

local function publicCooldownActivity(item)
    item = type(item) == "table" and item or {}
    local actionSlot = safeNumber(item.actionSlot or item.slot)

    -- A directly mapped action-bar slot is the authoritative cooldown source
    -- for transformed/overridden skills. This matters for burst followers: the
    -- planner may carry the base SpellID while the visible slot currently holds
    -- its override, so querying C_Spell by the base ID can incorrectly report
    -- "ready" and leave the secondary card without a rendered cooldown.
    local canUseActionSlot = actionSlot and (item.itemID or item.directActionSlot == true or item.actionBarStateTrusted == true)
    if canUseActionSlot and C_ActionBar and type(C_ActionBar.GetActionCooldown) == "function" then
        local ok, active, onGCD = pcall(function()
            local info = C_ActionBar.GetActionCooldown(actionSlot)
            if type(info) ~= "table" then return nil, nil end
            local isActive, isOnGCD = info.isActive, info.isOnGCD
            if isActive ~= true and isActive ~= false then isActive = nil end
            if isOnGCD ~= true and isOnGCD ~= false then isOnGCD = nil end
            return isActive, isOnGCD
        end)
        if ok and (active ~= nil or onGCD ~= nil) then return active, onGCD end
    end

    -- The shared resolver exposes public activity flags for spell, inventory
    -- and ItemID cooldown identities. Prefer these after an action-slot check;
    -- unbound trinkets/potions otherwise have no spell route to consult.
    if item.cooldownActive == true or item.cooldownActive == false
        or item.cooldownOnGCD == true or item.cooldownOnGCD == false then
        return item.cooldownActive, item.cooldownOnGCD
    end

    local spellID = safeNumber(item.spellID)
    if not (spellID and C_Spell and type(C_Spell.GetSpellCooldown) == "function") then return nil, nil end
    local ok, active, onGCD = pcall(function()
        local info = C_Spell.GetSpellCooldown(spellID)
        if type(info) ~= "table" then return nil, nil end
        local isActive = info.isActive
        local isOnGCD = info.isOnGCD
        if isActive ~= true and isActive ~= false then isActive = nil end
        if isOnGCD ~= true and isOnGCD ~= false then isOnGCD = nil end
        return isActive, isOnGCD
    end)
    if not ok then return nil, nil end
    return active, onGCD
end

local function showDurationObjectCooldown(frame, item, enabled, ignoreGCD, showNumbers)
    item = type(item) == "table" and item or {}
    local spellID = safeNumber(item.spellID)
    local itemID = safeNumber(item.itemID)
    local actionSlot = safeNumber(item.actionSlot or item.slot)
    if enabled ~= true or not frame or (spellID == nil and itemID == nil and actionSlot == nil) then
        hideCooldown(frame)
        return false, "disabled", false
    end
    if not (frame.SetCooldownFromDurationObject) then
        hideCooldown(frame)
        return false, "duration_api_unavailable", false
    end

    local active = publicCooldownActivity(item)
    -- The state collector can safely classify a follower as cooling down even
    -- when the protected API does not expose a public isActive boolean for that
    -- exact SpellID. Keep probing the native DurationObject in that case;
    -- otherwise the second burst-injection icon can retain a hidden cooldown
    -- until a structural card change happens.
    local cooldownHint = item.usableState == "cooldown" or item.cooldownActive == true
    if active == false and cooldownHint ~= true then
        hideCooldown(frame)
        return false, "ready", false
    end

    local ok, rendered, renderMode, nativeNumbersVisible = pcall(function()
        local duration, durationSource
        -- Items may be unbound. Ask the shared resolver for a client-native
        -- item DurationObject first; it remains inside this renderer and never
        -- crosses into the sanitized HUD model. Action-bar DurationObjects stay
        -- as the portable fallback for bound items and transformed spells.
        if (itemID or actionSlot) and TE.CooldownResolver and type(TE.CooldownResolver.GetDurationObject) == "function" then
            local resolverOK, resolved, resolvedSource = pcall(TE.CooldownResolver.GetDurationObject, TE.CooldownResolver, item)
            if resolverOK then
                duration, durationSource = resolved, resolvedSource
            end
        end
        local canUseActionSlot = actionSlot and (item.itemID or item.directActionSlot == true or item.actionBarStateTrusted == true)
        if duration == nil and canUseActionSlot and C_ActionBar and type(C_ActionBar.GetActionCooldownDuration) == "function" then
            duration = C_ActionBar.GetActionCooldownDuration(actionSlot)
            durationSource = duration ~= nil and "actionbar_duration" or nil
        end
        if duration == nil and spellID and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function" then
            if ignoreGCD == true then
                -- Retain a no-argument fallback for clients that do not expose
                -- the optional ignore-GCD parameter yet.
                local ignoredOK, ignoredDuration = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
                if ignoredOK then duration = ignoredDuration else duration = C_Spell.GetSpellCooldownDuration(spellID) end
            else
                duration = C_Spell.GetSpellCooldownDuration(spellID)
            end
            durationSource = duration ~= nil and "spell_duration" or durationSource
        end
        if duration == nil then return false, "duration_render_failed", false end

        -- Keep all authoritative DurationObject countdown digits inside the
        -- native cooldown frame.  The source still follows a strict priority:
        -- direct action-bar slot first, then the spell/item DurationObject.
        -- No protected duration crosses the HUD model and the custom badge is
        -- suppressed whenever native digits are visible.
        local useNativeNumbers = showNumbers == true
        setNativeCountdownNumbers(frame, useNativeNumbers)
        frame:SetCooldownFromDurationObject(duration, true)
        -- Some client builds restore native countdown digits when the duration
        -- object is attached; force the selected policy again after assignment.
        setNativeCountdownNumbers(frame, useNativeNumbers)
        frame:Show()
        local renderMode = "duration_object"
        if useNativeNumbers then
            if durationSource == "actionbar_duration" then
                renderMode = "duration_object_actionbar"
            elseif durationSource == "item_duration" then
                renderMode = "duration_object_item"
            else
                renderMode = "duration_object_spell"
            end
        end
        return true, renderMode, useNativeNumbers
    end)
    if not ok or rendered ~= true then
        hideCooldown(frame)
        return false, "duration_render_failed", false
    end
    return true, renderMode or "duration_object", nativeNumbersVisible == true
end

local function cooldownTextMode(style)
    style = type(style) == "table" and style or {}
    return ({ auto = true, custom = true, duration = true })[style.mode] and style.mode or "auto"
end

local function cooldownPresentationSignature(item, spellStyle, gcdStyle, cooldownTextStyle)
    item = item or {}
    return table.concat({
        styleMarker(item.spellID), styleMarker(item.itemID), styleMarker(item.inventorySlot), styleMarker(item.actionSlot or item.slot), styleMarker(item.directActionSlot), styleMarker(item.actionBarStateTrusted),
        styleMarker(item.usableState), styleMarker(item.iconState and item.iconState.availability),
        styleMarker(item.cooldownKnown), styleMarker(item.cooldownStart),
        styleMarker(item.cooldownDuration), styleMarker(item.cooldownActive), styleMarker(item.cooldownOnGCD), styleMarker(item.cooldownFallback), styleMarker(item.cooldownSource), styleMarker(item.cooldownIdentityKey),
        styleMarker(item.gcdKnown), styleMarker(item.gcdStart), styleMarker(item.gcdDuration),
        styleMarker(item.gcdActive), styleMarker(item.chargeCooldownKnown), styleMarker(item.chargeCooldownStart), styleMarker(item.chargeCooldownDuration), styleMarker(item.chargeCooldownRemaining),
        styleMarker(item.charges), styleMarker(item.maxCharges),
        cooldownStyleMarker(spellStyle), cooldownStyleMarker(gcdStyle), textStyleMarker(cooldownTextStyle),
    }, "|")
end

local function updateCooldown(card, item, spellStyle, gcdStyle)
    local signature = cooldownPresentationSignature(item, spellStyle, gcdStyle, card.resolvedCooldownStyle)
    if card.cooldownPresentationSignature == signature then
        return card.lastCooldownKnown == true,
            card.lastGcdShown == true,
            card.lastGlobalOnly == true,
            card.lastNativeCooldownRendered == true,
            card.lastNativeCountdownVisible == true
    end

    local spellEnabled, reverse = configureCooldown(card.cooldown, spellStyle)
    local gcdEnabled = configureCooldown(card.gcdCooldown, gcdStyle)
    local spellKnown, spellStart, spellDuration = cooldownData(item, "cooldown")
    local gcdKnown, gcdStart, gcdDuration = cooldownData(item, "gcd")
    local actionSlot = safeNumber(item and (item.actionSlot or item.slot))
    local preferNativeActionbar = actionSlot ~= nil and item and item.directActionSlot == true
    local textMode = cooldownTextMode(card.resolvedCooldownStyle)
    local nativeNumbersRequested = textMode ~= "custom"

    -- Direct action-bar cards use Blizzard's own DurationObject as the first
    -- authority.  This avoids a local spell estimate or base/override SpellID
    -- sample producing digits that differ from the visible action-bar button.
    local globalOnly = not preferNativeActionbar
        and spellKnown and gcdKnown and sameCooldown(spellStart, spellDuration, gcdStart, gcdDuration)
    local spellShown, nativeSpell, nativeNumbersVisible = false, false, false
    local spellMode, gcdMode = "numeric", "numeric"

    if preferNativeActionbar then
        nativeSpell, spellMode, nativeNumbersVisible = showDurationObjectCooldown(
            card.cooldown,
            item,
            spellEnabled,
            true,
            nativeNumbersRequested
        )
        -- A direct action-bar DurationObject is exact and always wins. Only
        -- when that renderer is genuinely unavailable/failed (not when it
        -- explicitly reports ready) may a sanitized local/API timer provide a
        -- last-resort visual fallback.
        if nativeSpell ~= true and spellKnown == true and spellMode ~= "ready" then
            spellShown = showCooldown(card.cooldown, spellStart, spellDuration, spellEnabled and not globalOnly)
            setNativeCountdownNumbers(card.cooldown, false)
        end
    else
        -- Spell and item DurationObjects are also authoritative client timers;
        -- displaying their native numbers fixes the protected-value path for
        -- unbound skills, macros and potion/category cooldowns. Numeric model
        -- values are retained only as a compatibility fallback.
        nativeSpell, spellMode, nativeNumbersVisible = showDurationObjectCooldown(
            card.cooldown,
            item,
            spellEnabled,
            true,
            nativeNumbersRequested
        )
        if nativeSpell ~= true and spellKnown == true and spellMode ~= "ready" then
            spellShown = showCooldown(card.cooldown, spellStart, spellDuration, spellEnabled and not globalOnly)
            setNativeCountdownNumbers(card.cooldown, false)
        end
    end

    local gcdCanRender = gcdEnabled and not spellShown and not nativeSpell and not globalOnly
    local gcdShown = showCooldown(card.gcdCooldown, gcdStart, gcdDuration, gcdCanRender)
    local nativeGcd = false
    if gcdKnown ~= true and nativeSpell ~= true then
        nativeGcd, gcdMode = showDurationObjectCooldown(card.gcdCooldown, { spellID = 61304 }, gcdEnabled, false, false)
    else
        setNativeCountdownNumbers(card.gcdCooldown, false)
    end

    local chargeKnown = item and item.chargeCooldownKnown == true
    local cStart = safeNumber(item and item.chargeCooldownStart)
    local cDuration = safeNumber(item and item.chargeCooldownDuration)
    if chargeKnown and cStart ~= nil and cDuration ~= nil and cDuration > 0 then
        pcall(function()
            if card.chargeCooldown.SetReverse then card.chargeCooldown:SetReverse(reverse) end
            setNativeCountdownNumbers(card.chargeCooldown, false)
            card.chargeCooldown:SetCooldown(cStart, cDuration)
            card.chargeCooldown:Show()
        end)
    else
        card.chargeCooldown:Hide()
    end

    card.cooldownRenderMode = nativeSpell and spellMode
        or nativeGcd and "duration_object_gcd"
        or spellShown and "numeric"
        or gcdShown and "numeric_gcd"
        or (spellMode ~= "numeric" and spellMode)
        or gcdMode
    card.nativeCountdownVisible = nativeNumbersVisible == true
    card.cooldownPresentationSignature = signature
    card.lastCooldownKnown = spellKnown == true
    card.lastGcdShown = (gcdShown or nativeGcd) == true
    card.lastGlobalOnly = globalOnly == true
    card.lastNativeCooldownRendered = (nativeSpell or nativeGcd) == true
    card.lastNativeCountdownVisible = nativeNumbersVisible == true
    return spellKnown, gcdShown or nativeGcd, globalOnly, nativeSpell or nativeGcd, nativeNumbersVisible
end

local function updateChargeEdge(card, item)
    local charges = safeNumber(item and item.charges)
    local maxCharges = safeNumber(item and item.maxCharges)
    local partial = charges ~= nil and maxCharges ~= nil and maxCharges > 0 and charges < maxCharges
    -- The native charge Cooldown edge is sufficient in native mode.  The old
    -- rectangular WHITE8X8 charge outline is reserved for minimal mode.
    local showMinimalEdge = partial and card.resolvedAppearance and card.resolvedAppearance.theme ~= "native"
    if showMinimalEdge then card.chargeEdge:Show() else card.chargeEdge:Hide() end
end

local function updateHighlight(card, item, style)
    local options = type(style) == "table" and style or {}
    local proc = item and (item.procHighlight == true or item.burstOverlay == true)
    local emergency = item and (item.severity == "emergency" or item.survivalEmergency == true)
    local enabled = options.enabled ~= false
    local shown = enabled and ((options.proc ~= false and proc) or (options.emergency ~= false and emergency))
    -- Proc/emergency colour is represented by TacticalIconEffects in native
    -- mode.  Do not add a rectangular self-drawn outline over Blizzard's frame.
    if not shown or (card.resolvedAppearance and card.resolvedAppearance.theme == "native") then
        card.highlight:Hide()
        return
    end
    if card.highlight.SetBackdropBorderColor then
        if emergency then
            card.highlight:SetBackdropBorderColor(1.00, 0.22, 0.16, 0.98)
        else
            card.highlight:SetBackdropBorderColor(1.00, 0.78, 0.16, 0.96)
        end
    end
    card.highlight:Show()
end

local function cooldownText(item)
    item = type(item) == "table" and item or {}
    local remaining = safeNumber(item.cooldownRemaining)
    -- The model normally supplies a sanitized remaining value. Keep a public
    -- numeric start/duration fallback for cards that receive a fresh cooldown
    -- sample before the next state-collector projection. Never inspect a
    -- DurationObject here; protected values stay inside Blizzard's native
    -- renderer, which now owns their own countdown digits.
    if remaining == nil then
        local start, duration = safeNumber(item.cooldownStart), safeNumber(item.cooldownDuration)
        if start and duration and duration > 0 and GetTime then
            local now = safeNumber(GetTime())
            if now then remaining = math.max(0, (start + duration) - now) end
        end
    end
    if remaining == nil or remaining <= 0 then return "" end
    if remaining >= 10 then return tostring(math.floor(remaining + 0.5)) end
    return string.format("%.1f", remaining)
end

local function tooltipLines(item, visual, card)
    item, visual = item or {}, visual or {}
    local state = item.iconState or {}
    local stateLabel = safeText(visual.stateLabel, "")
    if stateLabel == "" then
        local stateNames = {
            dispatchable = "可用", primary = "推荐", preview = "预览", advisory = "提示", cooldown = "冷却中",
        }
        stateLabel = stateNames[visual.visualState] or safeText(visual.visualState, "未知")
    end
    local lines = {
        "类型：" .. safeText(item.kind, "提示"),
        "状态：" .. stateLabel,
        "原因：" .. safeText(visual.reason or item.unusableReason, "无"),
        item.previewOnly and "仅预览/提示；不参与派发。" or "官方主推荐显示；仍需原有安全链路通过。",
    }
    local binding = safeText(item.binding, "")
    lines[#lines + 1] = binding ~= "" and ("现实按键：" .. binding) or "现实按键：无绑定"
    if visual.sourceLabel then lines[#lines + 1] = "来源：" .. safeText(visual.sourceLabel, "提示") end
    if item.itemID then
        lines[#lines + 1] = "物品 ID：" .. safeText(item.itemID, "未知")
        if safeNumber(item.itemCount) then lines[#lines + 1] = "背包数量：" .. tostring(safeNumber(item.itemCount)) end
        if item.inventorySlot then
            lines[#lines + 1] = "装备槽位：" .. tostring(safeNumber(item.inventorySlot) or "未知")
            lines[#lines + 1] = "饰品冷却由装备槽位 API 读取；仅 HUD 提示。"
        else
            lines[#lines + 1] = "物品冷却由 ItemID / 类别 API 读取；只读，不参与派发。"
        end
    end
    if item.bindingSourceIndex == 2 then lines[#lines + 1] = "绑定来源：副绑定" end
    if item.defensiveProfileKey then
        lines[#lines + 1] = "防御配置：" .. safeText(item.defensiveProfileKey, "未知")
        lines[#lines + 1] = "配置来源：" .. safeText(item.defensiveProfileSource, "未知")
    end
    if item.defensiveType then lines[#lines + 1] = "防御类型：" .. safeText(item.defensiveType, "未知") end
    local defensivePriority = safeNumber(item.defensivePriority)
    if defensivePriority then lines[#lines + 1] = "防御优先级：" .. tostring(math.floor(defensivePriority)) end
    if item.defensiveConditionText then lines[#lines + 1] = "技能条件：" .. safeText(item.defensiveConditionText, "未知") end
    local charges, maxCharges = safeNumber(item.charges), safeNumber(item.maxCharges)
    if charges ~= nil and maxCharges ~= nil then lines[#lines + 1] = "充能：" .. tostring(charges) .. "/" .. tostring(maxCharges) end
    if item.cooldownKnown == true then
        local text = cooldownText(item)
        lines[#lines + 1] = "冷却：" .. (text ~= "" and (text .. " 秒") or "就绪")
        if item.cooldownSource then
            local sourceText = {
                spell_api = "技能 API",
                spell_api_confirmation = "技能 API（施法后确认）",
                spell_api_ooc_resync = "技能 API（脱战重同步）",
                local_tracker_observed = "本地追踪（已观测技能 CD，原生 CD 不可渲染时兜底）",
                local_tracker_cached = "本地追踪（脱战缓存，原生 CD 不可渲染时兜底）",
                inventory_item_cooldown = "装备槽位冷却 API（饰品）",
                inventory_item_fallback = "当前装备 ItemID 冷却 API（饰品槽位回退）",
                item_cooldown = "物品类别冷却 API（药水/物品）",
                container_item_cooldown = "容器物品冷却 API（兼容回退）",
                legacy_item_cooldown = "旧版物品冷却 API（兼容回退）",
            }
            lines[#lines + 1] = "CD 数值来源：" .. (sourceText[item.cooldownSource] or safeText(item.cooldownSource, "未知"))
        end
        if item.cooldownFallback == true then
            lines[#lines + 1] = "CD 兜底：原生 DurationObject 不可用时，已采用施法事件追踪；后续技能 API 会自动校正。"
        end
        if item.cooldownConfirmationPending == true then
            lines[#lines + 1] = "CD 校验：施法后正在等待动作条/技能 API 确认。"
        end
        if item.inventorySlot and item.cooldownSource == "inventory_item_fallback" then
            lines[#lines + 1] = "饰品校验：槽位 API 暂未确认，已采用当前装备 ItemID 的活动冷却"
        elseif item.inventorySlot and item.cooldownItemFallbackActive == true then
            lines[#lines + 1] = "饰品校验：装备槽位与当前装备 ItemID 冷却均已确认"
        end
    elseif item.cooldownActive == true then
        lines[#lines + 1] = "冷却：进行中（由游戏原生转盘和倒计时渲染）"
    elseif state.cooldownUnknownReason then
        lines[#lines + 1] = "冷却：状态由游戏原生界面渲染"
    end
    local gcdRemaining = safeNumber(item.gcdRemaining)
    if item.gcdKnown == true and gcdRemaining and gcdRemaining > 0 then
        lines[#lines + 1] = "公共冷却：" .. string.format("%.1f", gcdRemaining) .. " 秒"
    elseif item.gcdActive == true then
        lines[#lines + 1] = "公共冷却：进行中（原生转盘）"
    end
    if card and card.cooldownRenderMode then
        local modeText = {
            duration_object_actionbar = "动作条 DurationObject 原生 CD（数字与动作条一致）",
            duration_object_spell = "技能 DurationObject 原生 CD",
            duration_object_item = "物品 DurationObject 原生 CD",
            duration_object = "DurationObject 原生 CD",
            duration_object_gcd = "DurationObject 原生共 CD",
            numeric = "普通数值技能 CD",
            numeric_gcd = "普通数值共 CD",
            duration_api_unavailable = "客户端缺少 DurationObject 冷却 API",
            duration_render_failed = "DurationObject 冷却渲染失败",
        }
        lines[#lines + 1] = "CD 转盘渲染：" .. (modeText[card.cooldownRenderMode] or "未激活")
    end
    if item.procHighlight == true then lines[#lines + 1] = "触发效果：已高亮" end
    if item.castingThisSpell == true then lines[#lines + 1] = item.channeling and "正在引导该技能" or "正在施放该技能" end
    if item.burstState then lines[#lines + 1] = "爆发状态：" .. safeText(item.burstState, "未知") end
    if item.advisoryCondition then lines[#lines + 1] = "触发依据：" .. safeText(item.advisoryCondition, "未知") end
    if item.targetChecked == true then
        if item.rangeBlocked == true then
            lines[#lines + 1] = "距离：超出技能距离"
        elseif item.targetInvalid == true then
            lines[#lines + 1] = "目标：不可用"
        else
            lines[#lines + 1] = "距离：已检查"
        end
    end
    if item.resourceBlocked == true then lines[#lines + 1] = "资源：当前不足" end
    if item.burstRole then lines[#lines + 1] = "爆发队列位置：" .. safeText(item.burstRole, "后续") end
    if card and card.tacticEchoEffectSummary and card.tacticEchoEffectSummary ~= "none" then
        local labels = { primary = "暴雪风格跑马边框", proc = "Proc 光效", interrupt = "打断光效", burst = "爆发光效", mobility = "突进光效" }
        lines[#lines + 1] = "视觉提示：" .. (labels[card.tacticEchoEffectSummary] or card.tacticEchoEffectSummary)
    end
    lines[#lines + 1] = "状态源：" .. safeText(state.source or item.source, "战术快照")
    return lines
end

local function showTooltip(card)
    if not GameTooltip then return end
    local item, visual = card.item or {}, card.visual or {}
    GameTooltip:SetOwner(card, "ANCHOR_CURSOR")
    GameTooltip:SetText(safeText(item.spellName or visual.label, "战术图标"), 0.80, 0.92, 1)
    for _, line in ipairs(tooltipLines(item, visual, card)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
end

function TacticalIconButton:Create(parent, name, size)
    -- This construction intentionally mirrors UIFrameFactory.CreateBaseIcon:
    -- background + icon + masked icon plane + clipped cooldowns + one Atlas
    -- border frame.  The old card border system is retained only for minimal
    -- mode and is never part of the native rendering path.
    local card = CreateFrame("Button", name, parent, "BackdropTemplate")
    card.size = size or 42
    card:SetSize(card.size, card.size)
    card:EnableMouse(true)
    card:SetFrameStrata("MEDIUM")
    createBackdrop(card)

    card.nativeBackground = card:CreateTexture(nil, "BACKGROUND", nil, 0)
    card.nativeBackground:SetAllPoints(card)
    pcall(card.nativeBackground.SetAtlas, card.nativeBackground, "UI-HUD-ActionBar-IconFrame-Background")

    card.icon = card:CreateTexture(nil, "ARTWORK", nil, 0)
    applyIconPlaneGeometry(card.icon, card, ICON_INSET)
    card.icon:SetTexture(QUESTION_ICON)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.icon:SetDesaturated(false)
    card.icon:SetVertexColor(1, 1, 1, 1)
    card.icon:Show()

    card.overlay = card:CreateTexture(nil, "ARTWORK", nil, 1)
    applyIconPlaneGeometry(card.overlay, card, ICON_INSET)
    card.overlay:SetColorTexture(0, 0, 0, 0)

    -- One mask owns the native icon plane.  Masking background, icon and
    -- presentation overlay together avoids square background/overlay leaks.
    card.roundMask = createRoundedActionIconMask(card, card.size, card.nativeBackground, card.icon, card.overlay)
    card.roundMaskEnabled = card.roundMask ~= nil
    card.iconInset = ICON_INSET

    -- Legacy minimal-mode border. It remains structurally separate from the
    -- native Atlas border frame and is hidden whenever theme == native.
    card.border = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.border:SetAllPoints(card)
    card.border:SetFrameLevel(card:GetFrameLevel() + 3)
    if card.border.SetBackdrop then
        card.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        card.border:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.92)
    end

    card.highlight = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.highlight:SetAllPoints(card)
    card.highlight:SetFrameLevel(card:GetFrameLevel() + 7)
    if card.highlight.SetBackdrop then
        card.highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
        card.highlight:SetBackdropBorderColor(1.00, 0.78, 0.16, 0.96)
    end
    card.highlight:Hide()

    -- Cooldowns are inset and clipped exactly as the reference factory does.
    card.cooldownContainer = CreateFrame("Frame", nil, card)
    card.cooldownContainer:SetAllPoints(card)
    card.cooldownContainer:SetClipsChildren(true)
    card.cooldownContainer:SetFrameLevel(card:GetFrameLevel() + 1)

    local function setupCooldown(frame, level, drawSwipe, drawEdge)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -4)
        frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4, 4)
        frame:SetFrameLevel(card.cooldownContainer:GetFrameLevel() + level)
        if frame.SetDrawSwipe then frame:SetDrawSwipe(drawSwipe) end
        if frame.SetDrawEdge then frame:SetDrawEdge(drawEdge) end
        if frame.SetDrawBling then frame:SetDrawBling(false) end
        if frame.SetHideCountdownNumbers then frame:SetHideCountdownNumbers(true) end
        frame:Hide()
    end

    card.gcdCooldown = CreateFrame("Cooldown", nil, card.cooldownContainer, "CooldownFrameTemplate")
    setupCooldown(card.gcdCooldown, 1, true, false)
    card.gcdCooldown:SetFrameLevel(card.cooldownContainer:GetFrameLevel() + 1)
    card.cooldown = CreateFrame("Cooldown", nil, card.cooldownContainer, "CooldownFrameTemplate")
    setupCooldown(card.cooldown, 2, true, false)
    card.cooldown:SetFrameLevel(card.cooldownContainer:GetFrameLevel() + 2)
    card.chargeCooldown = CreateFrame("Cooldown", nil, card.cooldownContainer, "CooldownFrameTemplate")
    setupCooldown(card.chargeCooldown, 3, false, true)
    card.chargeCooldown:SetFrameLevel(card.cooldownContainer:GetFrameLevel() + 3)

    card.chargeEdge = CreateFrame("Frame", nil, card, "BackdropTemplate")
    card.chargeEdge:SetAllPoints(card)
    card.chargeEdge:SetFrameLevel(card:GetFrameLevel() + 4)
    if card.chargeEdge.SetBackdrop then
        card.chargeEdge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        card.chargeEdge:SetBackdropBorderColor(0.22, 0.86, 0.95, 0.82)
    end
    card.chargeEdge:Hide()

    -- Native border is a dedicated frame above cooldowns.  Do not place the
    -- texture directly on the card: creation order otherwise permits cooldown
    -- swipes and effect layers to visually mingle with the border.
    card.nativeBorderFrame = CreateFrame("Frame", nil, card)
    card.nativeBorderFrame:SetAllPoints(card)
    card.nativeBorderFrame:SetFrameLevel(card:GetFrameLevel() + 4)
    card.nativeBorder = card.nativeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    applyActionButtonBorderGeometry(card.nativeBorder, card, card.size)
    pcall(card.nativeBorder.SetAtlas, card.nativeBorder, "UI-HUD-ActionBar-IconFrame")

    card.castTexture = card.nativeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    applyActionButtonBorderGeometry(card.castTexture, card, card.size)
    pcall(card.castTexture.SetAtlas, card.castTexture, "UI-HUD-ActionBar-IconFrame-Mouseover")
    card.castTexture:SetVertexColor(1.00, 0.82, 0.25, 0.78)
    card.castTexture:Hide()

    card.pushedTexture = card.nativeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    applyActionButtonBorderGeometry(card.pushedTexture, card, card.size)
    pcall(card.pushedTexture.SetAtlas, card.pushedTexture, "UI-HUD-ActionBar-IconFrame-Down")
    card.pushedTexture:Hide()

    card.hoverTexture = card.nativeBorderFrame:CreateTexture(nil, "HIGHLIGHT", nil, 0)
    applyActionButtonBorderGeometry(card.hoverTexture, card, card.size)
    pcall(card.hoverTexture.SetAtlas, card.hoverTexture, "UI-HUD-ActionBar-IconFrame-Mouseover")
    card.hoverTexture:Hide()

    card.fadeGroup = card:CreateAnimationGroup()
    card.fadeAlpha = card.fadeGroup:CreateAnimation("Alpha")
    card.fadeAlpha:SetDuration(0.10)
    card.fadeAlpha:SetSmoothing("OUT")
    card.fadeGroup:SetScript("OnFinished", function()
        if card.fadeTo and card.fadeTo <= 0 then card:Hide() else card:SetAlpha(card.fadeTo or 1) end
    end)

    -- Text uses a dedicated overlay frame rather than the card directly.
    -- Visual unavailable overlays remain masked inside the icon plane; cooldown
    -- swipes stay above that plane; all player-readable labels are then pinned
    -- above cooldowns, Atlas frames and animated Proc/Glow effects.
    card.textOverlayFrame = CreateFrame("Frame", nil, card)
    card.textOverlayFrame:SetAllPoints(card)
    card.textOverlayFrame:SetFrameLevel(card:GetFrameLevel() + 20)
    card.textOverlayFrame:EnableMouse(false)

    card.hotkey = card.textOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.hotkey:SetJustifyH("RIGHT")
    card.hotkey:SetShadowColor(0, 0, 0, 1)
    card.hotkey:SetShadowOffset(1, -1)
    card.chargeText = card.textOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.chargeText:SetJustifyH("RIGHT")
    card.chargeText:SetShadowColor(0, 0, 0, 1)
    card.chargeText:SetShadowOffset(1, -1)
    -- P5 text layers are deliberately independent. Source labels remain in
    -- the existing left-top slot; cooldown numbers stay central; runtime state
    -- (“施法 / 暂停 / 引导 / 蓄力 / 阻止 / 未绑定”) has its own bottom-left anchor.
    card.sourceText = card.textOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.sourceText:SetPoint("TOPLEFT", card.textOverlayFrame, "TOPLEFT", 4, -4)
    card.sourceText:SetShadowColor(0, 0, 0, 1)
    card.sourceText:SetShadowOffset(1, -1)
    card.label = card.sourceText -- legacy source-label alias for integrations.
    card.cooldownText = card.textOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.cooldownText:SetJustifyH("CENTER")
    card.cooldownText:SetShadowColor(0, 0, 0, 1)
    card.cooldownText:SetShadowOffset(1, -1)
    card.badge = card.cooldownText -- TacticalIconButton.badge remains the CD alias.
    card.stateText = card.textOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.stateText:SetJustifyH("LEFT")
    card.stateText:SetShadowColor(0, 0, 0, 1)
    card.stateText:SetShadowOffset(1, -1)

    card:SetScript("OnEnter", function(self)
        if self.resolvedAppearance and self.resolvedAppearance.theme == "native" and self.resolvedAppearance.hoverHighlight then safeShown(self.hoverTexture, true) end
        showTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        safeShown(self.hoverTexture, false)
        safeShown(self.pushedTexture, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    card:SetScript("OnMouseDown", function(self)
        if self.resolvedAppearance and self.resolvedAppearance.theme == "native" and self.resolvedAppearance.pressedHighlight then safeShown(self.pushedTexture, true) end
    end)
    card:SetScript("OnMouseUp", function(self) safeShown(self.pushedTexture, false) end)
    card:Hide()
    return card
end

function TacticalIconButton:SetSize(card, size)
    size = clamp(size, 20, 160)
    card.size = size
    card:SetSize(size, size)
    if card.roundMask then
        local maskSize = math.floor((size * 1.5) + 0.5)
        card.roundMask:SetSize(maskSize, maskSize)
    end
    if card.nativeBorder then applyActionButtonBorderGeometry(card.nativeBorder, card, size) end
    if card.castTexture then applyActionButtonBorderGeometry(card.castTexture, card, size) end
    if card.pushedTexture then applyActionButtonBorderGeometry(card.pushedTexture, card, size) end
    if card.hoverTexture then applyActionButtonBorderGeometry(card.hoverTexture, card, size) end
end

function TacticalIconButton:ApplyTextSettings(card, hud, moduleKey)
    local module = resolveModuleStyle(hud, moduleKey)
    card.styleModule = module
    local marker = table.concat({
        textStyleMarker(module.keyLabel), textStyleMarker(module.chargeLabel), textStyleMarker(module.cooldownText), textStyleMarker(module.stateText),
    }, "|")
    if card.textSettingsMarker ~= marker then
        card.resolvedKeyStyle = applyFontStyle(card.hotkey, module.keyLabel, {
            point = "TOPRIGHT", offsetX = -3, offsetY = -3, fontPreset = "normal",
        })
        card.resolvedChargeStyle = applyFontStyle(card.chargeText, module.chargeLabel, {
            point = "BOTTOMRIGHT", offsetX = -3, offsetY = 3, fontPreset = "normal",
        })
        card.resolvedCooldownStyle = applyFontStyle(card.badge, module.cooldownText, {
            point = "CENTER", offsetX = 0, offsetY = 0, fontPreset = "highlight",
        })
        card.resolvedStateStyle = applyFontStyle(card.stateText, module.stateText, {
            point = "BOTTOMLEFT", offsetX = 3, offsetY = 3, fontPreset = "normal",
        })
        card.textSettingsMarker = marker
    end
    card.resolvedSwipeStyle = type(module.cooldownSwipe) == "table" and module.cooldownSwipe or {}
    card.resolvedGcdSwipeStyle = type(module.gcdSwipe) == "table" and module.gcdSwipe or {}
    card.resolvedHighlightStyle = type(module.highlight) == "table" and module.highlight or {}
    card.resolvedEffectStyle = type(module.effects) == "table" and module.effects or {}
    card.resolvedAppearance = resolveAppearance(module)
    local appearance = card.resolvedAppearance
    local native = appearance.theme == "native"
    -- Rendering systems are mutually exclusive.  In native mode only Blizzard
    -- atlas assets remain visible; no legacy Backdrop or WHITE8X8 frame may
    -- contribute a second rectangular outline.
    safeShown(card.nativeBackground, native)
    safeShown(card.nativeBorder, native and appearance.showBorder)
    safeShown(card.border, (not native) and appearance.showBorder)
    safeShown(card.highlight, false)
    safeShown(card.chargeEdge, false)
    if card.SetBackdropColor then
        card:SetBackdropColor(0.01, 0.02, 0.03, native and 0 or 0.90)
    end
    if card.SetBackdropBorderColor then
        card:SetBackdropBorderColor(0, 0, 0, native and 0 or 0.92)
    end
    if card.border and card.border.SetBackdropBorderColor and native then
        card.border:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if card.roundMask then safeShown(card.roundMask, appearance.roundedIcons) end
    -- Masque owns its own skin layers.  It is intentionally disabled while
    -- the native atlas theme is selected so the two border systems cannot mix.
    tryApplyMasque(card, appearance.masque and not native)
end

function TacticalIconButton:Apply(card, item, hud, moduleKey)
    item = item or {}
    local visual = item.visual or {
        visualState = "unknown", alpha = 0.56, label = "未知",
        borderColor = { 0.60, 0.52, 0.78, 1 }, overlay = "unknown", glow = "none",
    }
    card.item, card.visual, card.hud, card.moduleKey = item, visual, hud or {}, moduleKey or "main"
    self:ApplyTextSettings(card, card.hud, card.moduleKey)

    local visible = item.hidden ~= true and item.empty ~= true
    setVisible(card, visible, visual.alpha or 1)
    if not visible then
        if TacticalIconEffects and type(TacticalIconEffects.Clear) == "function" then TacticalIconEffects:Clear(card) end
        return
    end

    setIcon(card, item.spellIcon or item.icon)
    card.icon:SetDesaturated(
        visual.desaturate == true
        or item.usableState == "unavailable"
        or item.usableState == "resource"
        or item.usableState == "range"
        or item.usableState == "target"
        or item.usableState == "unknown"
    )

    applyBorder(card, visual.borderColor)
    safeShown(card.castTexture, card.resolvedAppearance and card.resolvedAppearance.theme == "native" and card.resolvedAppearance.castHighlight and item.castingThisSpell == true)
    local overlayColors = {
        blocked = { 0.32, 0.02, 0.02, 0.58 },
        error = { 0.22, 0.05, 0.28, 0.44 },
        unknown = { 0.12, 0.07, 0.18, 0.40 },
        unbound = { 0.06, 0.08, 0.10, 0.48 },
        paused = { 0.28, 0.18, 0.02, 0.46 },
        none = { 0, 0, 0, 0 },
    }
    -- Preserve the explicit error presentation even if a legacy visual payload
    -- omitted its overlay field; error is a known state, never an “unknown”.
    local overlayKey = visual.visualState == "error" and "error" or (visual.overlay or "none")
    setColor(card.overlay, overlayColors[overlayKey] or overlayColors.none)
    -- Source tags and runtime state are independent P5 layers.  Hiding source
    -- labels no longer hides safety state, and state text never replaces a CD.
    -- Cast-lock states, including visual.visualState == "empowering" or visual.visualState == "empowering_lock",
    -- remain state-layer context rather than source-label text.
    card.label:SetText(card.hud.showSourceTags ~= false and safeText(visual.sourceLabel or visual.label, "") or "")
    local keyHidden = card.hud.showKeyLabels == false or not card.resolvedKeyStyle or card.resolvedKeyStyle.enabled == false
    card.hotkey:SetText(keyHidden and "" or formatBinding(item.binding))
    self:RefreshDynamic(card, item)
end

function TacticalIconButton:RefreshDynamic(card, item)
    if not card or not card:IsShown() then return end
    item = item or card.item or {}
    -- Keep the card's display-only snapshot current even when the structural
    -- fingerprint did not change, so numeric countdown text and tooltips do not
    -- retain an older 200ms sample between advisor publications.
    card.item = item
    if item.visual then card.visual = item.visual end
    local visual = card.visual or item.visual or {}
    self:ApplyTextSettings(card, card.hud or {}, card.moduleKey or "main")
    if card.icon then card.icon:SetAlpha(1); card.icon:Show() end

    local charges, maxCharges = safeNumber(item.charges), safeNumber(item.maxCharges)
    local stackCount = safeNumber(item.itemCount)
    if card.resolvedChargeStyle and card.resolvedChargeStyle.enabled ~= false then
        if charges and maxCharges and maxCharges > 0 then
            card.chargeText:SetText(string.format("%d/%d", charges, maxCharges))
        elseif stackCount ~= nil and stackCount >= 0 then
            -- Consumable followers (potion etc.) expose their bag count in the
            -- same dedicated stack/charge label without overloading the CD text.
            card.chargeText:SetText(tostring(math.floor(stackCount)))
        else
            card.chargeText:SetText("")
        end
    else
        card.chargeText:SetText("")
    end
    updateChargeEdge(card, item)
    updateHighlight(card, item, card.resolvedHighlightStyle)
    local cooldownKnown, gcdShown, globalOnly, nativeCooldownRendered, nativeCountdownVisible = updateCooldown(card, item, card.resolvedSwipeStyle, card.resolvedGcdSwipeStyle)
    card.nativeCooldownRendered = nativeCooldownRendered == true
    card.nativeCountdownVisible = nativeCountdownVisible == true
    local cooldownMode = cooldownTextMode(card.resolvedCooldownStyle)

    -- CD text no longer multiplexes state labels. It remains central and is
    -- shown whenever a reliable own-CD/charge value exists, even if the card is
    -- also paused, casting, unbound or blocked.
    if not card.resolvedCooldownStyle or card.resolvedCooldownStyle.enabled == false
        or card.nativeCountdownVisible == true or cooldownMode == "duration" then
        -- Direct action-bar DurationObjects render Blizzard's own countdown
        -- digits. Keeping the custom badge empty prevents a second, potentially
        -- different number from being drawn over the authoritative timer.
        card.badge:SetText("")
    else
        local ownCooldown = (globalOnly ~= true) and (
            cooldownKnown == true or item.cooldownKnown == true
            or item.usableState == "cooldown" or item.cooldownActive == true
            or nativeCooldownRendered == true
        )
        local chargeRemaining = safeNumber(item.chargeCooldownRemaining)
        local chargeCooling = item.chargeCooldownKnown == true and chargeRemaining ~= nil and chargeRemaining > 0
        if chargeCooling then
            card.badge:SetText(chargeRemaining >= 10 and tostring(math.floor(chargeRemaining + 0.5)) or string.format("%.1f", chargeRemaining))
        elseif ownCooldown then
            -- Never use a generic “cooling” label as the normal combat path.
            -- A local tracker/resolver supplies a numeric time when safe; an
            -- empty label is preferable to false precision.
            card.badge:SetText(cooldownText(item))
        elseif globalOnly == true or gcdShown == true then
            -- Pure GCD is intentionally unlabeled; its swipe is still visible.
            card.badge:SetText("")
        else
            card.badge:SetText("")
        end
    end

    local stateLabel = safeText(visual.stateLabel or "", "")
    local stateEnabled = card.hud.showStatusText ~= false and card.resolvedStateStyle and card.resolvedStateStyle.enabled ~= false
    card.stateText:SetText(stateEnabled and stateLabel or "")
    card.label:SetText(card.hud.showSourceTags ~= false and safeText(visual.sourceLabel or visual.label, "") or "")


    if TacticalIconEffects and type(TacticalIconEffects.Refresh) == "function" then
        TacticalIconEffects:Refresh(card, item, visual, card.resolvedEffectStyle)
    end
end

function TacticalIconButton:SetVisible(card, visible, alpha)
    setVisible(card, visible, alpha)
    if visible ~= true and TacticalIconEffects and type(TacticalIconEffects.Clear) == "function" then
        TacticalIconEffects:Clear(card)
    end
end
