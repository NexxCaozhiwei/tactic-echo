-- Shared configuration defaults for Tactic Echo.
--
-- All UI, HUD and advisory modules must use this table instead of inventing
-- local fallback values. This prevents a missing SavedVariables field from
-- being coerced to a slider minimum by a renderer-specific clamp call.
local TE = _G.TacticEcho
TE.Config = TE.Config or {}

local Defaults = {
    schema = 8,
    hudSchema = 10,
    settings = {
        sessionPolicy = "pause_out_of_combat",
        protocolMode = "v3_dynamic",
        toggleHotkey = "",
        performanceDiagnostics = false,
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
        cooldownText = { enabled = true, mode = "custom", fontPreset = "highlight", fontSize = 14, scale = 1.00, point = "CENTER", offsetX = 0, offsetY = 0 },
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
        -- P1 persists reaction configuration only. No automatic interrupt or
        -- control dispatch is attached until the later reaction milestones.
        -- Keeping these values under one dedicated branch avoids changing the
        -- existing display-only interrupt/control settings or Burst state.
        autoReaction = {
            schema = 2,
            interrupt = {
                -- P5.8 freezes the automatic-interrupt design. This branch
                -- remains visible for diagnostics, but it cannot be selected
                -- or dispatched from SavedVariables or the settings UI.
                enabled = false,
                suspended = true,
                suspensionReason = "auto_interrupt_suspended",
                -- P5.6: unknown/opaque interruptibility never authorizes input.
                -- Retained only for SavedVariables schema compatibility; the
                -- runtime requires direct API false or a positive unit event.
                compatibilityActiveCast = false,
                targetOrder = { "target", "focus", "mouseover" },
                targetEnabled = { target = true, focus = false, mouseover = false },
            },
            control = {
                enabled = false,
                aoeEnabled = false,
                targetOrder = { "target", "focus", "mouseover" },
                targetEnabled = { target = true, focus = false, mouseover = false },
            },
        },
        mobilityEnabled = true,
        defensiveEnabled = true,
        defensiveOutOfCombatStandby = true,
        burstEnabled = true,
        burstPolicy = "align",
        burstDisplayMode = "window",
        -- Phase-1 AutoBurst is opt-in.  SignalFrame "armed" remains the
        -- independent automatic-run gate; this setting only enables burst
        -- takeover when a configured window recommendation is observed.
        autoBurstEnabled = false,
        -- Sequence order and optional-step enablement are specialization-local
        -- and live in tactics.burstProfiles[specKey].autoBurstSequence.
        -- The old legacy manual-rule hand-entered SpellID test rule is intentionally
        -- retired: runtime plans always resolve through the real profile lists.
        autoBurstMode = "simple", -- simple | focused
        autoBurstDebug = true,
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
