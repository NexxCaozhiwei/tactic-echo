-- Tactic Echo tactical HUD effects.
--
-- Presentation-only state adapter. It consumes the sanitized HUD card state
-- produced by TacticalHudModel / TacticalIconButton and never changes a
-- recommendation, binding, Token, TEAP payload or TEK input path.
--
-- The implementation deliberately uses Blizzard atlas animations rather than
-- tinting icon art. Effects are layered above the icon, can be disabled per
-- module, and are de-duplicated so a 200ms HUD refresh does not restart loops.
local TE = _G.TacticEcho

local TacticalIconEffects = {}
TE.TacticalIconEffects = TacticalIconEffects

local function number(value, fallback)
    local ok, result = pcall(function()
        local resolved = tonumber(value)
        if type(resolved) ~= "number" then return fallback end
        return resolved
    end)
    return ok and result or fallback
end

local function bool(value, fallback)
    if value == nil then return fallback == true end
    return value == true
end

local function enabled(style, key, fallback)
    style = type(style) == "table" and style or {}
    return bool(style[key], fallback)
end

local function stopGroup(group)
    if group and group.IsPlaying and group:IsPlaying() then group:Stop() end
end

local function playGroup(group)
    if not group then return end
    if group.IsPlaying and group:IsPlaying() then return end
    group:Play()
end

local function hideFrame(frame)
    if not frame then return end
    stopGroup(frame.animation)
    frame:Hide()
end

local function atlasTexture(frame, layer, atlas, sublevel)
    local texture = frame:CreateTexture(nil, layer or "OVERLAY", nil, sublevel or 0)
    texture:SetAtlas(atlas, true)
    return texture
end

local function createFlipbook(texture, rows, columns, frames, duration)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local animation = group:CreateAnimation("FlipBook")
    animation:SetOrder(1)
    animation:SetDuration(duration or 1)
    animation:SetFlipBookRows(rows or 6)
    animation:SetFlipBookColumns(columns or 5)
    animation:SetFlipBookFrames(frames or 30)
    animation:SetFlipBookFrameWidth(0)
    animation:SetFlipBookFrameHeight(0)
    return group
end

local function ensureMarching(card)
    if card.tacticEchoMarchingFrame then return card.tacticEchoMarchingFrame end
    local frame = CreateFrame("Frame", nil, card)
    frame:SetAllPoints(card)
    frame:SetFrameLevel(card:GetFrameLevel() + 9)
    frame.texture = atlasTexture(frame, "OVERLAY", "rotationhelper_ants_flipbook", 6)
    frame.texture:SetPoint("CENTER", frame, "CENTER")
    frame.animation = createFlipbook(frame.texture, 6, 5, 30, 1.0)
    frame:Hide()
    card.tacticEchoMarchingFrame = frame
    return frame
end

-- The golden Proc loop is intentionally calibrated against the blue primary
-- recommendation ants.  Users perceive these as the same outer HUD ring family:
-- Proc should be only 3px larger, not independently expanded by the atlas's
-- transparent margin.  Keeping this relationship explicit avoids a visually
-- oversized instant-cast Proc ring (for example instant Regrowth).
local PRIMARY_MARCHING_SCALE = 1.44
local PRIMARY_MARCHING_MIN_EXTENT = 58
local PROC_LOOP_OUTER_DELTA = 3

local function resizeProc(frame, card)
    if not frame or not frame.texture or not card then return end
    local buttonExtent = math.max(number(card:GetWidth(), 46), number(card:GetHeight(), 46))
    local primaryExtent = math.max(buttonExtent * PRIMARY_MARCHING_SCALE, PRIMARY_MARCHING_MIN_EXTENT)
    -- Reference the actual blue primary ring geometry and expand only 3px.
    local extent = primaryExtent + PROC_LOOP_OUTER_DELTA
    local signature = string.format("%.3f:%s", extent, tostring(buttonExtent))
    if frame.tacticEchoProcExtent == signature then return end
    frame.texture:ClearAllPoints()
    -- Match Blizzard IconFrame's optical center rather than the raw square
    -- button center, so the ring follows the native action-button contour.
    frame.texture:SetPoint("CENTER", frame, "CENTER", 0.5, -0.5)
    frame.texture:SetSize(extent, extent)
    frame.tacticEchoProcExtent = signature
end

local function ensureProc(card, key)
    if card[key] then return card[key] end
    local frame = CreateFrame("Frame", nil, card)
    frame:SetAllPoints(card)
    frame:SetFrameLevel(card:GetFrameLevel() + 10)
    frame.texture = atlasTexture(frame, "OVERLAY", "UI-HUD-ActionBar-Proc-Loop-Flipbook", 7)
    resizeProc(frame, card)
    frame.animation = createFlipbook(frame.texture, 6, 5, 30, 1.0)
    frame:Hide()
    card[key] = frame
    return frame
end

-- `rotationhelper_ants_flipbook` contains substantial transparent padding around
-- its visible moving border.  The padding is not identical for every HUD intent:
-- the blue/white primary cue must stay tight to the native IconFrame, while the
-- gold mobility/gap-closer cue needs a larger texture extent to make its visible
-- ants reach the same contour.  Never share one scale between these effects.
local MARCHING_SCALE_BY_INTENT = {
    primary = 1.44,    -- blue/white primary recommendation: native-frame fit
    interrupt = 1.52,  -- red interruption cue: slight visual clearance
    burst = 1.58,      -- purple burst cue: deliberate emphasis
    mobility = 1.78,   -- gold gap-closer cue: compensates flipbook padding
}
local MARCHING_MIN_EXTENT_BY_INTENT = {
    primary = 58,
    interrupt = 62,
    burst = 64,
    mobility = 72,
}

local function resizeMarching(frame, card, intent)
    if not frame or not card then return end
    intent = MARCHING_SCALE_BY_INTENT[intent] and intent or "primary"
    local buttonExtent = math.max(number(card:GetWidth(), 46), number(card:GetHeight(), 46))
    local scale = MARCHING_SCALE_BY_INTENT[intent]
    local minExtent = MARCHING_MIN_EXTENT_BY_INTENT[intent]
    local extent = math.max(buttonExtent * scale, minExtent)
    -- The native IconFrame has a small optical center offset.  Keep it for all
    -- crawl variants so only the texture extent differs by effect type.
    local signature = string.format("%s:%.3f:%s", intent, extent, tostring(buttonExtent))
    if frame.tacticEchoMarchingExtent == signature then return end
    frame.texture:ClearAllPoints()
    frame.texture:SetPoint("CENTER", frame, "CENTER", 0.5, -0.5)
    frame.texture:SetSize(extent, extent)
    frame.tacticEchoMarchingExtent = signature
end

local function setMarching(card, intent)
    local frame = ensureMarching(card)
    intent = intent or "none"
    local color = {
        primary = { 1.00, 1.00, 1.00, false },
        interrupt = { 1.00, 0.28, 0.08, true },
        burst = { 0.74, 0.26, 1.00, true },
        mobility = { 1.00, 0.86, 0.22, true },
    }
    local picked = color[intent]
    if not picked then
        hideFrame(frame)
        return
    end
    resizeMarching(frame, card, intent)
    frame.texture:SetDesaturated(picked[4] == true)
    frame.texture:SetVertexColor(picked[1], picked[2], picked[3], 1)
    frame:Show()
    playGroup(frame.animation)
end

local function setProc(card, key, visible, color)
    local frame = ensureProc(card, key)
    -- HUD modules may resize at runtime. Re-evaluate the Proc ring geometry
    -- whenever it is applied, while the signature avoids redundant work.
    resizeProc(frame, card)
    if visible ~= true then
        hideFrame(frame)
        return
    end
    local red, green, blue, desaturate = 1, 1, 1, false
    if color then
        red, green, blue, desaturate = color[1], color[2], color[3], color[4] == true
    end
    frame.texture:SetDesaturated(desaturate)
    frame.texture:SetVertexColor(red, green, blue, 1)
    frame:Show()
    playGroup(frame.animation)
end

local function ensureHotkeyFlash(card)
    if card.tacticEchoHotkeyFlash then return card.tacticEchoHotkeyFlash end
    local group = card.hotkey:CreateAnimationGroup()
    local up = group:CreateAnimation("Alpha")
    up:SetOrder(1)
    up:SetDuration(0.09)
    up:SetFromAlpha(0.25)
    up:SetToAlpha(1.00)
    local down = group:CreateAnimation("Alpha")
    down:SetOrder(2)
    down:SetDuration(0.14)
    down:SetFromAlpha(1.00)
    down:SetToAlpha(0.78)
    group:SetScript("OnFinished", function() if card.hotkey then card.hotkey:SetAlpha(1) end end)
    card.tacticEchoHotkeyFlash = group
    return group
end

local function maybeFlashHotkey(card, item, style)
    local old = card.tacticEchoLastUsableState
    local current = item and item.usableState or "unknown"
    local hasKey = card.hotkey and card.hotkey:GetText() and card.hotkey:GetText() ~= ""
    if enabled(style, "hotkeyFlash", true) and hasKey and old ~= nil and old ~= "ready" and current == "ready" then
        local group = ensureHotkeyFlash(card)
        group:Stop()
        group:Play()
    end
    card.tacticEchoLastUsableState = current
end

local function ensureChannelFill(card)
    if card.tacticEchoChannelFill then return card.tacticEchoChannelFill end
    local frame = CreateFrame("Frame", nil, card)
    frame:SetAllPoints(card)
    frame:SetFrameLevel(card:GetFrameLevel() + 5)
    frame:SetClipsChildren(true)

    frame.innerGlow = atlasTexture(frame, "ARTWORK", "UI-HUD-ActionBar-Channel-InnerGlow", 2)
    frame.innerGlow:SetPoint("CENTER", frame, "CENTER")
    frame.fill = atlasTexture(frame, "ARTWORK", "UI-HUD-ActionBar-Channel-Fill", 3)
    frame.fill:SetBlendMode("ADD")
    frame.fill:SetPoint("CENTER", frame, "CENTER", 42, 0)

    frame.animation = frame.fill:CreateAnimationGroup()
    frame.translation = frame.animation:CreateAnimation("Translation")
    frame.translation:SetOrder(1)
    local fade = frame.animation:CreateAnimation("Alpha")
    fade:SetOrder(2)
    fade:SetDuration(0.14)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    frame.animation:SetScript("OnFinished", function() frame:Hide() end)
    frame:Hide()
    card.tacticEchoChannelFill = frame
    return frame
end

local function stopChannelFill(card)
    local frame = card and card.tacticEchoChannelFill
    if not frame then return end
    stopGroup(frame.animation)
    frame:Hide()
    card.tacticEchoChannelSignature = nil
end

local function startChannelFill(card, item)
    if not (item and item.castingThisSpell == true and item.channeling == true) then
        stopChannelFill(card)
        return
    end
    if type(GetTime) ~= "function" then return end
    local startMS = number(item.castingStartTimeMS, nil)
    local endMS = number(item.castingEndTimeMS, nil)
    if not startMS or not endMS or tonumber(item.castingSpellID) ~= tonumber(item.spellID) then
        stopChannelFill(card)
        return
    end
    local signature = tostring(item.spellID) .. ":" .. tostring(startMS) .. ":" .. tostring(endMS)
    if card.tacticEchoChannelSignature == signature and card.tacticEchoChannelFill and card.tacticEchoChannelFill:IsShown() then return end

    local duration = (endMS - startMS) / 1000
    local elapsed = GetTime() - (startMS / 1000)
    local remaining = duration - elapsed
    if duration <= 0 or remaining <= 0 then
        stopChannelFill(card)
        return
    end

    local frame = ensureChannelFill(card)
    local fullWidth = math.max(number(card:GetWidth(), 46) * 1.55, 64)
    frame.fill:SetSize(fullWidth, math.max(number(card:GetHeight(), 46) * 1.55, 64))
    frame.innerGlow:SetSize(fullWidth, math.max(number(card:GetHeight(), 46) * 1.55, 64))
    local progress = math.max(0, math.min(1, elapsed / duration))
    local startX = 42 - (84 * progress)
    frame.fill:ClearAllPoints()
    frame.fill:SetPoint("CENTER", frame, "CENTER", startX, 0)
    frame.translation:SetOffset(-84 * (1 - progress), 0)
    frame.translation:SetDuration(remaining)
    frame.animation:Stop()
    frame.fill:SetAlpha(1)
    frame.innerGlow:SetAlpha(1)
    frame:Show()
    frame.animation:Play()
    card.tacticEchoChannelSignature = signature
end

local function resolveIntent(item, visual, style)
    local effects = visual and visual.effects or {}
    if effects.interrupt == true and enabled(style, "interrupt", true) then return "interrupt" end
    if effects.burst == true and enabled(style, "burst", true) then return "burst" end
    if effects.mobility == true and enabled(style, "mobility", true) then return "mobility" end
    if effects.marching == true and enabled(style, "marching", true) then return "primary" end
    return "none"
end

function TacticalIconEffects:Apply(card, item, visual, style)
    if not card then return end
    style = type(style) == "table" and style or {}
    visual = type(visual) == "table" and visual or {}
    item = type(item) == "table" and item or {}
    local effects = type(visual.effects) == "table" and visual.effects or {}
    local isEnabled = enabled(style, "enabled", true)
    local intent = isEnabled and resolveIntent(item, visual, style) or "none"
    local proc = isEnabled and enabled(style, "proc", true) and effects.proc == true
    local channelFill = isEnabled and enabled(style, "channelFill", true) and effects.channelFill == true

    -- A fixed per-card signature prevents continuous 0.20s refreshes from
    -- stopping and restarting the same Blizzard flipbook.
    local signature = table.concat({ intent, proc and "1" or "0", channelFill and "1" or "0" }, ":")
    if card.tacticEchoEffectSignature ~= signature then
        setMarching(card, intent)
        setProc(card, "tacticEchoProcFrame", proc, nil)
        card.tacticEchoEffectSignature = signature
    else
        -- Icon size can change independently of state. Keep the crawling
        -- border correctly scaled without restarting its animation.
        if intent ~= "none" then resizeMarching(card.tacticEchoMarchingFrame, card, intent) end
    end

    if channelFill then startChannelFill(card, item) else stopChannelFill(card) end
    maybeFlashHotkey(card, item, style)
    card.tacticEchoEffectSummary = intent ~= "none" and intent or (proc and "proc" or "none")
end

function TacticalIconEffects:Refresh(card, item, visual, style)
    self:Apply(card, item, visual, style)
end

function TacticalIconEffects:Clear(card)
    if not card then return end
    hideFrame(card.tacticEchoMarchingFrame)
    hideFrame(card.tacticEchoProcFrame)
    stopChannelFill(card)
    if card.tacticEchoHotkeyFlash then card.tacticEchoHotkeyFlash:Stop() end
    if card.hotkey then card.hotkey:SetAlpha(1) end
    card.tacticEchoEffectSignature = nil
    card.tacticEchoEffectSummary = nil
    card.tacticEchoLastUsableState = nil
end
