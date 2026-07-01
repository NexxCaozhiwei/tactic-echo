-- Shared configuration defaults for Tactic Echo.
--
-- All UI, HUD and advisory modules must use this table instead of inventing
-- local fallback values. This prevents a missing SavedVariables field from
-- being coerced to a slider minimum by a renderer-specific clamp call.
local TE = _G.TacticEcho
TE.Config = TE.Config or {}

local Defaults = {
    schema = 6,
    hudSchema = 8,
    settings = {
        sessionPolicy = "pause_out_of_combat",
        protocolMode = "v3_dynamic",
        toggleHotkey = "",
    },
    hud = {
        enabled = true,
        locked = false,
        compact = false,
        layoutPreset = "queue_horizontal",
        orientation = "horizontal",
        primaryGrowth = "RIGHT",
        tacticalGrowth = "RIGHT",
        burstGrowth = "RIGHT",
        queueMode = "tactical",
        maxCandidates = 3,
        scale = 1.00,
        alpha = 1.00,
        backdropAlpha = 0.08,
        outOfCombatMode = "show",
        outOfCombatAlpha = 0.62,
        outOfCombatScale = 1.00,
        hideWhenIdle = false,
        showHistory = true,
        showKeyLabels = true,
        showStatusText = true,
        showSourceTags = true,
        -- Disabled by default: this nameplate cue is opt-in and only appears
        -- for an actionable, interruptible target cast.
        showTargetPrompt = false,
        targetPromptSchema = 2,
        showDragHandle = true,
        defenseDetached = false,
        defenseLocked = false,
        defenseScale = 1.00,
        defenseAlpha = 1.00,
        primarySize = 68,
        candidateSize = 38,
        tacticalSize = 46,
        defenseSize = 38,
        gap = 6,
    },
    text = {
        keyLabel = { enabled = true, fontPreset = "normal", fontSize = 12, scale = 1.00, point = "TOPRIGHT", offsetX = -3, offsetY = -3 },
        chargeLabel = { enabled = true, fontPreset = "normal", fontSize = 12, scale = 1.00, point = "BOTTOMRIGHT", offsetX = -3, offsetY = 3 },
        cooldownText = { enabled = true, fontPreset = "highlight", fontSize = 14, scale = 1.00, point = "CENTER", offsetX = 0, offsetY = 0 },
        -- P5: state is no longer multiplexed into the CD text. “施法 / 暂停 /
        -- 引导 / 蓄力 / 阻止 / 未绑定” has its own style and anchor.
        stateText = { enabled = true, fontPreset = "normal", fontSize = 11, scale = 1.00, point = "BOTTOMLEFT", offsetX = 3, offsetY = 3 },
    },
    moduleSizes = { main = 68, burst = 46, interrupt = 46, defense = 38 },
    appearance = {
        theme = "native", -- native Blizzard action-bar frame or minimal card surface.
        roundedIcons = true,
        showBorder = true,
        hoverHighlight = true,
        pressedHighlight = true,
        castHighlight = true,
        fadeTransitions = true,
        masque = false, -- optional: only used when Masque is installed.
    },
    tactics = {
        candidatePredictionEnabled = true,
        previewMode = "prediction",
        queuePriorityPreset = "output_first",
        interruptEnabled = true,
        controlEnabled = true,
        mobilityEnabled = true,
        defensiveEnabled = true,
        defensiveOutOfCombatStandby = true,
        burstEnabled = true,
        burstPolicy = "align",
        burstDisplayMode = "window",
        burstShowCandidates = true,
        burstHighlightPrimary = true,
        burstShowClassCooldowns = true,
        burstShowTrinkets = false,
        burstShowPotions = false,
        burstShowRacial = false,
        -- First burst card is always the window trigger. This value controls
        -- the number of following injection / trinket / potion / racial cards.
        burstMaxCandidates = 3,
        burstPotionItemID = 0,
        burstRacialSpellID = 0,
        burstCooldownDisplay = "gray",
        burstUnboundDisplay = "gray",
        interruptDisplayMode = "cast",
        controlDisplayMode = "cast",
        defensiveDisplayMode = "condition",
        defensiveDisplayHealthPercent = 45,
        defensiveHighlightHealthPercent = 30,
    },
    survival = {
        healthstoneEnabled = true,
        potionEnabled = true,
        priority = "healthstone_first",
        healthstoneItemID = 5512,
        potionItemID = 0,
        displayHealthPercent = 35,
        emergencyHealthPercent = 20,
        inCombatOnly = true,
    },
}

TE.Config.Defaults = Defaults
