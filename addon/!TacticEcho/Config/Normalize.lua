-- Canonical SavedVariables normalizer.
--
-- This module is loaded before UI, HUD and advisory files. It owns defaults,
-- schema migration and bounds validation so no consumer can turn a missing
-- value into a minimum slider value with clamp(nil, minimum, maximum).
local TE = _G.TacticEcho
TE.Config = TE.Config or {}

local Defaults = TE.Config.Defaults or {}
local Normalize = {}
TE.Config.Normalize = Normalize

local function isEnum(value, allowed, fallback)
    return allowed and allowed[value] and value or fallback
end

local function boolean(value, fallback)
    if value == nil then return fallback end
    return value == true
end

local function number(value, fallback, minimum, maximum, integer)
    value = tonumber(value)
    if value == nil then value = fallback end
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    if integer then value = math.floor(value + 0.00001) end
    return value
end

local function color(value)
    value = type(value) == "table" and value or {}
    return {
        r = number(value.r or value[1], 1, 0, 1),
        g = number(value.g or value[2], 1, 0, 1),
        b = number(value.b or value[3], 1, 0, 1),
        a = number(value.a or value[4], 1, 0, 1),
    }
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end

local function root()
    TacticEchoDB = TacticEchoDB or {}
    return TacticEchoDB
end

local function normalizeTextStyle(style, defaults)
    style = type(style) == "table" and style or {}
    defaults = defaults or {}
    style.enabled = boolean(style.enabled, defaults.enabled ~= false)
    style.fontPreset = isEnum(style.fontPreset, { normal = true, highlight = true, disable = true }, defaults.fontPreset or "normal")
    style.fontSize = number(style.fontSize, defaults.fontSize or 12, 8, 30, true)
    style.scale = number(style.scale, defaults.scale or 1, 0.60, 2.00)
    style.point = isEnum(style.point, {
        TOPLEFT = true, TOPRIGHT = true, CENTER = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    }, defaults.point or "TOPRIGHT")
    style.offsetX = number(style.offsetX, defaults.offsetX or 0, -30, 30)
    style.offsetY = number(style.offsetY, defaults.offsetY or 0, -30, 30)
    if defaults.mode ~= nil or style.mode ~= nil then
        -- 1.0.38 removes the native DurationObject-digit mode. Cooldown text is
        -- always drawn by the configurable HUD badge so every card uses the
        -- same plain-seconds format and font/anchor controls.
        style.mode = "custom"
    end
    style.color = color(style.color)
    return style
end

local function normalizeModule(hud, key)
    local defaults = Defaults.text or {}
    local style = type(hud.modules[key]) == "table" and hud.modules[key] or {}
    style.show = boolean(style.show, true)
    style.iconSize = number(style.iconSize, (Defaults.moduleSizes or {})[key] or 38, key == "main" and 44 or 28, key == "main" and 120 or 88, true)
    style.keyLabel = normalizeTextStyle(style.keyLabel, defaults.keyLabel)
    style.chargeLabel = normalizeTextStyle(style.chargeLabel, defaults.chargeLabel)
    style.cooldownText = normalizeTextStyle(style.cooldownText, defaults.cooldownText)
    style.stateText = normalizeTextStyle(style.stateText, defaults.stateText)
    style.cooldownSwipe = type(style.cooldownSwipe) == "table" and style.cooldownSwipe or {}
    style.cooldownSwipe.enabled = boolean(style.cooldownSwipe.enabled, true)
    style.cooldownSwipe.alpha = number(style.cooldownSwipe.alpha, 0.55, 0, 0.95)
    style.cooldownSwipe.reverse = boolean(style.cooldownSwipe.reverse, false)
    style.gcdSwipe = type(style.gcdSwipe) == "table" and style.gcdSwipe or {}
    style.gcdSwipe.enabled = boolean(style.gcdSwipe.enabled, true)
    style.gcdSwipe.alpha = number(style.gcdSwipe.alpha, 0.38, 0, 0.95)
    style.gcdSwipe.reverse = boolean(style.gcdSwipe.reverse, style.cooldownSwipe.reverse == true)
    style.highlight = type(style.highlight) == "table" and style.highlight or {}
    style.highlight.enabled = boolean(style.highlight.enabled, true)
    style.highlight.proc = boolean(style.highlight.proc, true)
    style.highlight.emergency = boolean(style.highlight.emergency, true)
    -- Native-style visual cues are layered outside the icon. They are
    -- presentation-only and may be disabled independently for each module.
    style.effects = type(style.effects) == "table" and style.effects or {}
    style.effects.enabled = boolean(style.effects.enabled, true)
    style.effects.marching = boolean(style.effects.marching, true)
    style.effects.proc = boolean(style.effects.proc, true)
    style.effects.interrupt = boolean(style.effects.interrupt, true)
    style.effects.burst = boolean(style.effects.burst, true)
    style.effects.mobility = boolean(style.effects.mobility, true)
    style.effects.hotkeyFlash = boolean(style.effects.hotkeyFlash, true)
    style.effects.channelFill = boolean(style.effects.channelFill, true)
    style.appearance = type(style.appearance) == "table" and style.appearance or {}
    local appearanceDefaults = Defaults.appearance or {}
    style.appearance.theme = isEnum(style.appearance.theme, { native = true, minimal = true }, appearanceDefaults.theme or "native")
    style.appearance.roundedIcons = boolean(style.appearance.roundedIcons, appearanceDefaults.roundedIcons ~= false)
    style.appearance.showBorder = boolean(style.appearance.showBorder, appearanceDefaults.showBorder ~= false)
    style.appearance.hoverHighlight = boolean(style.appearance.hoverHighlight, appearanceDefaults.hoverHighlight ~= false)
    style.appearance.pressedHighlight = boolean(style.appearance.pressedHighlight, appearanceDefaults.pressedHighlight ~= false)
    style.appearance.castHighlight = boolean(style.appearance.castHighlight, appearanceDefaults.castHighlight ~= false)
    style.appearance.fadeTransitions = boolean(style.appearance.fadeTransitions, appearanceDefaults.fadeTransitions ~= false)
    style.appearance.masque = boolean(style.appearance.masque, appearanceDefaults.masque == true)
    hud.modules[key] = style
    return style
end

local function normalizeQueueOrder(value)
    if type(value) ~= "table" then return nil end
    local valid = { emergency = true, interrupt = true, primary = true, burst = true, control = true, mobility = true, candidate = true }
    local out, seen = {}, {}
    for _, bucket in ipairs(value) do
        if valid[bucket] and not seen[bucket] then
            out[#out + 1] = bucket
            seen[bucket] = true
        end
    end
    return #out > 0 and out or nil
end

-- Automatic reaction settings are configuration-only in 1.0.39 P1.
-- Normalize them centrally so the settings UI, future macro resolver, and
-- future runtime reaction layer all share one stable target-source contract.
local REACTION_TARGET_SOURCES = { target = true, focus = true, mouseover = true }
local REACTION_TARGET_ORDER = { "target", "focus", "mouseover" }

local function normalizeReactionTargetOrder(value, fallback)
    local source = type(value) == "table" and value or fallback
    local out, seen = {}, {}
    for _, key in ipairs(source or {}) do
        if REACTION_TARGET_SOURCES[key] and not seen[key] then
            out[#out + 1] = key
            seen[key] = true
        end
    end
    for _, key in ipairs(REACTION_TARGET_ORDER) do
        if not seen[key] then
            out[#out + 1] = key
            seen[key] = true
        end
    end
    return out
end

local function normalizeReactionTargetEnabled(value, fallback)
    value = type(value) == "table" and value or {}
    fallback = type(fallback) == "table" and fallback or {}
    local out = {}
    for _, key in ipairs(REACTION_TARGET_ORDER) do
        out[key] = boolean(value[key], fallback[key] == true)
    end
    return out
end

local function normalizeAutoReaction(tactics, defaults)
    local defaultReaction = type(defaults.autoReaction) == "table" and defaults.autoReaction or {}
    local reaction = type(tactics.autoReaction) == "table" and tactics.autoReaction or {}
    reaction.schema = 2

    local defaultInterrupt = type(defaultReaction.interrupt) == "table" and defaultReaction.interrupt or {}
    local interrupt = type(reaction.interrupt) == "table" and reaction.interrupt or {}
    -- P5.8: automatic interrupt is deliberately unavailable. Force this on
    -- every normalization pass so an older SavedVariables value cannot revive
    -- the retired reaction -> TEAP -> TEK candidate path.
    interrupt.enabled = false
    interrupt.suspended = true
    interrupt.suspensionReason = "auto_interrupt_suspended"
    -- P5.6 migration: old SavedVariables may retain this key as true, but an
    -- opaque `notInterruptible` value is never dispatch authority. Preserve the
    -- key for schema compatibility while normalizing its active value to false.
    interrupt.compatibilityActiveCast = false
    interrupt.targetOrder = normalizeReactionTargetOrder(interrupt.targetOrder, defaultInterrupt.targetOrder)
    interrupt.targetEnabled = normalizeReactionTargetEnabled(interrupt.targetEnabled, defaultInterrupt.targetEnabled)
    reaction.interrupt = interrupt

    local defaultControl = type(defaultReaction.control) == "table" and defaultReaction.control or {}
    local control = type(reaction.control) == "table" and reaction.control or {}
    control.enabled = boolean(control.enabled, defaultControl.enabled == true)
    control.aoeEnabled = boolean(control.aoeEnabled, defaultControl.aoeEnabled == true)
    control.targetOrder = normalizeReactionTargetOrder(control.targetOrder, defaultControl.targetOrder)
    control.targetEnabled = normalizeReactionTargetEnabled(control.targetEnabled, defaultControl.targetEnabled)
    reaction.control = control

    tactics.autoReaction = reaction
    return reaction
end

local function normalizeHud(tactics)
    local defaults = Defaults.hud or {}
    tactics.hud = type(tactics.hud) == "table" and tactics.hud or {}
    local hud = tactics.hud
    local priorSchema = tonumber(hud.settingsSchema) or 0
    local knownClampBug = priorSchema < (Defaults.hudSchema or 4)
        and tonumber(hud.scale) == 0.60
        and tonumber(hud.alpha) == 0.20

    -- Values without TEUI controls in 0.8.3 could only reach these lower
    -- bounds through the erroneous clamp(nil, minimum, maximum) path. Repair
    -- that exact signature once, without rewriting legitimate user values.
    if knownClampBug then
        hud.scale, hud.alpha = defaults.scale, defaults.alpha
        if tonumber(hud.defenseScale) == 0.60 then hud.defenseScale = defaults.defenseScale end
        if tonumber(hud.defenseAlpha) == 0.20 then hud.defenseAlpha = defaults.defenseAlpha end
        if tonumber(hud.primarySize) == 44 then hud.primarySize = defaults.primarySize end
        if tonumber(hud.candidateSize) == 26 then hud.candidateSize = defaults.candidateSize end
        if tonumber(hud.tacticalSize) == 28 then hud.tacticalSize = defaults.tacticalSize end
        if tonumber(hud.defenseSize) == 28 then hud.defenseSize = defaults.defenseSize end
        if tonumber(hud.gap) == 2 then hud.gap = defaults.gap end
        if type(hud.modules) == "table" then
            for key, size in pairs(Defaults.moduleSizes or {}) do
                local module = hud.modules[key]
                local minimum = key == "main" and 44 or 28
                if type(module) == "table" and tonumber(module.iconSize) == minimum then module.iconSize = size end
            end
        end
        if hud.outOfCombatMode == "dim" then hud.outOfCombatMode = "show" end
    end

    -- 1.0.38 unifies every visible cooldown number under the HUD label. Native
    -- DurationObject digits use Blizzard's own MM:SS formatter and bypass the
    -- per-module text controls, so even an explicit legacy `duration` setting
    -- is migrated to the single configurable plain-seconds renderer.
    if priorSchema < 10 and type(hud.modules) == "table" then
        for _, key in ipairs({ "main", "burst", "interrupt", "defense" }) do
            local module = hud.modules[key]
            if type(module) == "table" then
                local cooldownText = type(module.cooldownText) == "table" and module.cooldownText or {}
                cooldownText.mode = "custom"
                module.cooldownText = cooldownText
            end
        end
    end

    -- 0.8.4 enabled the target/nameplate interrupt cue by default. It mirrored
    -- the interrupt module's always-visible state and could leave an icon on a
    -- nameplate with no actionable cast. Disable that legacy default once; users
    -- can explicitly enable the stricter cue from TEUI afterwards.
    if (tonumber(hud.targetPromptSchema) or 0) < 2 then
        hud.showTargetPrompt = false
        hud.targetPromptSchema = 2
    end

    hud.enabled = boolean(hud.enabled, defaults.enabled)
    hud.locked = boolean(hud.locked, defaults.locked)
    hud.compact = boolean(hud.compact, defaults.compact)
    hud.layoutPreset = isEnum(hud.layoutPreset, { queue_horizontal = true, queue_vertical = true, surround = true }, defaults.layoutPreset)
    hud.orientation = hud.layoutPreset == "queue_vertical" and "vertical" or "horizontal"
    hud.primaryGrowth = isEnum(hud.primaryGrowth, { RIGHT = true, LEFT = true, UP = true, DOWN = true }, defaults.primaryGrowth)
    hud.tacticalGrowth = isEnum(hud.tacticalGrowth, { RIGHT = true, LEFT = true, UP = true, DOWN = true }, defaults.tacticalGrowth)
    hud.burstGrowth = isEnum(hud.burstGrowth, { RIGHT = true, LEFT = true, UP = true, DOWN = true }, defaults.burstGrowth)
    hud.queueMode = isEnum(hud.queueMode, { primary = true, queue = true, tactical = true }, defaults.queueMode)
    hud.maxCandidates = number(hud.maxCandidates, defaults.maxCandidates, 1, 3, true)
    hud.scale = number(hud.scale, defaults.scale, 0.60, 2.00)
    hud.alpha = number(hud.alpha, defaults.alpha, 0.20, 1.00)
    hud.backdropAlpha = number(hud.backdropAlpha, defaults.backdropAlpha, 0, 1)
    hud.outOfCombatMode = isEnum(hud.outOfCombatMode, { show = true, dim = true, hide = true }, defaults.outOfCombatMode)
    hud.outOfCombatAlpha = number(hud.outOfCombatAlpha, defaults.outOfCombatAlpha, 0.20, 1.00)
    hud.outOfCombatScale = number(hud.outOfCombatScale, defaults.outOfCombatScale, 0.60, 2.00)
    hud.fadeOutOfCombat = hud.outOfCombatMode == "dim" -- retained for old integrations only.
    hud.hideWhenIdle = boolean(hud.hideWhenIdle, defaults.hideWhenIdle)
    hud.showHistory = boolean(hud.showHistory, defaults.showHistory)
    hud.showKeyLabels = boolean(hud.showKeyLabels, defaults.showKeyLabels)
    hud.showStatusText = boolean(hud.showStatusText, defaults.showStatusText)
    hud.showSourceTags = boolean(hud.showSourceTags, defaults.showSourceTags)
    hud.showTargetPrompt = boolean(hud.showTargetPrompt, defaults.showTargetPrompt)
    hud.targetPromptSchema = 2
    hud.showDragHandle = boolean(hud.showDragHandle, defaults.showDragHandle)
    hud.defenseDetached = boolean(hud.defenseDetached, defaults.defenseDetached)
    hud.defenseLocked = boolean(hud.defenseLocked, defaults.defenseLocked)
    hud.defenseScale = number(hud.defenseScale, defaults.defenseScale, 0.60, 2.00)
    hud.defenseAlpha = number(hud.defenseAlpha, defaults.defenseAlpha, 0.20, 1.00)
    hud.primarySize = number(hud.primarySize, defaults.primarySize, 44, 120, true)
    hud.candidateSize = number(hud.candidateSize, defaults.candidateSize, 26, 88, true)
    hud.tacticalSize = number(hud.tacticalSize, defaults.tacticalSize, 28, 88, true)
    hud.defenseSize = number(hud.defenseSize, defaults.defenseSize, 28, 88, true)
    hud.gap = number(hud.gap, defaults.gap, 2, 24, true)

    hud.modules = type(hud.modules) == "table" and hud.modules or {}
    local main = normalizeModule(hud, "main")
    normalizeModule(hud, "burst")
    normalizeModule(hud, "interrupt")
    normalizeModule(hud, "defense")
    hud.keyLabel = main.keyLabel -- legacy diagnostic / profile compatibility.
    hud.settingsSchema = Defaults.hudSchema or 5
    return hud, priorSchema
end

local function normalizeTactics(tactics, priorHudSchema)
    local defaults = Defaults.tactics or {}
    tactics.candidatePredictionEnabled = boolean(tactics.candidatePredictionEnabled, defaults.candidatePredictionEnabled)
    tactics.previewMode = isEnum(tactics.previewMode, { prediction = true, history = true }, defaults.previewMode)
    tactics.queuePriorityPreset = isEnum(tactics.queuePriorityPreset, { output_first = true, safety_first = true }, defaults.queuePriorityPreset)
    tactics.queueOrder = normalizeQueueOrder(tactics.queueOrder)
    tactics.interruptEnabled = boolean(tactics.interruptEnabled, defaults.interruptEnabled)
    tactics.controlEnabled = boolean(tactics.controlEnabled, defaults.controlEnabled)
    -- Existing display-only interrupt/control booleans are intentionally
    -- preserved. The new autoReaction branch is opt-in and carries no runtime
    -- input behavior in this P1 release.
    normalizeAutoReaction(tactics, defaults)
    tactics.mobilityEnabled = boolean(tactics.mobilityEnabled, defaults.mobilityEnabled)
    tactics.defensiveEnabled = boolean(tactics.defensiveEnabled, defaults.defensiveEnabled)
    tactics.defensiveOutOfCombatStandby = boolean(tactics.defensiveOutOfCombatStandby, defaults.defensiveOutOfCombatStandby)
    tactics.burstEnabled = boolean(tactics.burstEnabled, defaults.burstEnabled)
    tactics.burstPolicy = isEnum(tactics.burstPolicy, { immediate = true, align = true, hold = true }, defaults.burstPolicy)
    tactics.burstDisplayMode = isEnum(tactics.burstDisplayMode, { always = true, window = true, highlight = true, compact = true }, defaults.burstDisplayMode)
    tactics.autoBurstEnabled = boolean(tactics.autoBurstEnabled, defaults.autoBurstEnabled)
    tactics.autoBurstMode = isEnum(tactics.autoBurstMode, { simple = true, focused = true }, defaults.autoBurstMode)
    tactics.autoBurstDebug = boolean(tactics.autoBurstDebug, defaults.autoBurstDebug)
    -- 1.0.26 retires the global legacy manual-rule manual rule.  Settings are now
    -- stored by specialization as stable sequence step identities; deleting
    -- these old values prevents a stale hand-entered SpellID from silently
    -- overriding the real profile after upgrade.
    tactics.autoBurstDirection = nil
    tactics.autoBurstWindowSpellID = nil
    tactics.autoBurstInjectionSpellID = nil
    tactics.autoBurstInjectionKind = nil
    tactics.autoBurstInjectionTrinketSlot = nil
    tactics.autoBurstTrinketOffGCDExplicit = nil
    tactics.autoBurstUseProfileFallback = nil
    tactics.burstShowCandidates = boolean(tactics.burstShowCandidates, defaults.burstShowCandidates)
    tactics.burstHighlightPrimary = boolean(tactics.burstHighlightPrimary, defaults.burstHighlightPrimary)
    tactics.burstShowClassCooldowns = boolean(tactics.burstShowClassCooldowns, defaults.burstShowClassCooldowns)
    tactics.burstShowTrinkets = boolean(tactics.burstShowTrinkets, defaults.burstShowTrinkets)
    tactics.burstShowPotions = boolean(tactics.burstShowPotions, defaults.burstShowPotions)
    tactics.burstShowRacial = boolean(tactics.burstShowRacial, defaults.burstShowRacial)
    -- Number of post-window cards. The window trigger itself always owns slot 1.
    tactics.burstMaxCandidates = number(tactics.burstMaxCandidates, defaults.burstMaxCandidates, 0, 4, true)
    tactics.burstPotionItemID = number(tactics.burstPotionItemID, defaults.burstPotionItemID, 0, 99999999, true)
    tactics.burstRacialSpellID = number(tactics.burstRacialSpellID, defaults.burstRacialSpellID, 0, 99999999, true)
    tactics.burstCooldownDisplay = isEnum(tactics.burstCooldownDisplay, { gray = true, hide = true }, defaults.burstCooldownDisplay)
    tactics.burstUnboundDisplay = isEnum(tactics.burstUnboundDisplay, { gray = true, hide = true }, defaults.burstUnboundDisplay)
    tactics.interruptDisplayMode = isEnum(tactics.interruptDisplayMode, { always = true, cast = true, highlight = true }, defaults.interruptDisplayMode)
    tactics.controlDisplayMode = isEnum(tactics.controlDisplayMode, { always = true, cast = true, highlight = true }, defaults.controlDisplayMode)
    tactics.defensiveDisplayMode = isEnum(tactics.defensiveDisplayMode, { always = true, condition = true, highlight = true }, defaults.defensiveDisplayMode)

    local allLegacyThresholdsAtMinimum = tonumber(tactics.defensiveDisplayHealthPercent) == 5
        and tonumber(tactics.defensiveHighlightHealthPercent) == 5
        and type(tactics.survival) == "table"
        and tonumber(tactics.survival.displayHealthPercent) == 5
        and tonumber(tactics.survival.emergencyHealthPercent) == 5
    if allLegacyThresholdsAtMinimum and (tonumber(priorHudSchema) or 0) < (Defaults.hudSchema or 4) then
        tactics.defensiveDisplayHealthPercent = defaults.defensiveDisplayHealthPercent
        tactics.defensiveHighlightHealthPercent = defaults.defensiveHighlightHealthPercent
        tactics.survival.displayHealthPercent = (Defaults.survival or {}).displayHealthPercent
        tactics.survival.emergencyHealthPercent = (Defaults.survival or {}).emergencyHealthPercent
    end
    tactics.defensiveDisplayHealthPercent = number(tactics.defensiveDisplayHealthPercent, defaults.defensiveDisplayHealthPercent, 5, 100, true)
    tactics.defensiveHighlightHealthPercent = number(tactics.defensiveHighlightHealthPercent, defaults.defensiveHighlightHealthPercent, 5, 100, true)

    local survivalDefaults = Defaults.survival or {}
    tactics.survival = type(tactics.survival) == "table" and tactics.survival or {}
    local survival = tactics.survival
    survival.healthstoneEnabled = boolean(survival.healthstoneEnabled, survivalDefaults.healthstoneEnabled)
    survival.potionEnabled = boolean(survival.potionEnabled, survivalDefaults.potionEnabled)
    survival.priority = isEnum(survival.priority, { healthstone_first = true, potion_first = true }, survivalDefaults.priority)
    survival.healthstoneItemID = number(survival.healthstoneItemID, survivalDefaults.healthstoneItemID, 1, 99999999, true)
    survival.potionItemID = number(survival.potionItemID, survivalDefaults.potionItemID, 0, 99999999, true)
    survival.displayHealthPercent = number(survival.displayHealthPercent, survivalDefaults.displayHealthPercent, 5, 100, true)
    survival.emergencyHealthPercent = number(survival.emergencyHealthPercent, survivalDefaults.emergencyHealthPercent, 5, 100, true)
    survival.inCombatOnly = boolean(survival.inCombatOnly, survivalDefaults.inCombatOnly)
    tactics.burstProfiles = type(tactics.burstProfiles) == "table" and tactics.burstProfiles or {}
    tactics.settingsSchema = Defaults.schema or 5
    return tactics
end

function Normalize:All()
    local database = root()
    database.settings = type(database.settings) == "table" and database.settings or {}
    local settings = database.settings
    local defaults = Defaults.settings or {}
    settings.sessionPolicy = isEnum(settings.sessionPolicy, { manual_keep = true, pause_out_of_combat = true, close_out_of_combat = true }, defaults.sessionPolicy)
    settings.protocolMode = type(settings.protocolMode) == "string" and settings.protocolMode or defaults.protocolMode
    settings.toggleHotkey = type(settings.toggleHotkey) == "string" and settings.toggleHotkey or defaults.toggleHotkey

    database.tactics = type(database.tactics) == "table" and database.tactics or {}
    local tactics = database.tactics
    local hud, priorHudSchema = normalizeHud(tactics)
    normalizeTactics(tactics, priorHudSchema)
    return settings, tactics, hud
end

function Normalize:ResetVisuals()
    local _, tactics, hud = self:All()
    local defaults = Defaults.hud or {}
    local preserved = {
        point = hud.point, relativePoint = hud.relativePoint, x = hud.x, y = hud.y,
        defensePoint = hud.defensePoint, defenseRelativePoint = hud.defenseRelativePoint,
        defenseX = hud.defenseX, defenseY = hud.defenseY,
    }
    for key, value in pairs(defaults) do hud[key] = copy(value) end
    for key, value in pairs(preserved) do hud[key] = value end
    hud.modules = {}
    hud.keyLabel = nil
    local normalizedHud = normalizeHud(tactics)
    return normalizedHud
end
