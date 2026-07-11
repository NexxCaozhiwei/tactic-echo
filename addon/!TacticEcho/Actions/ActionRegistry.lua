local TE = _G.TacticEcho

local ActionRegistry = {}
TE.ActionRegistry = ActionRegistry

local actionsById = {}
local actionIdsBySpellId = {}

ActionRegistry.catalogVersion = 2
ActionRegistry.catalogFingerprint = "648482895f1293f5"
ActionRegistry.catalogFingerprint16 = 25732

local function register(action)
    actionsById[action.actionId] = action
    for _, spellID in ipairs(action.spellIDs or {}) do
        actionIdsBySpellId[spellID] = action.actionId
    end
end

register({
    actionId = "PALADIN_RETRIBUTION_JUDGMENT",
    class = "PALADIN",
    specIndex = 3,
    displayName = "审判",
    actionCode = 1,
    spellIDs = { 20271 },
    macroStrategy = "fallback_spell_names",
    macroCastSpellIDs = { 24275, 20271 },
    macroName = "TE_Judgment",
    groundMode = "none",
    category = "generator",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-01; Hammer of Wrath can appear as a Judgment stage, so macrotext tries Hammer of Wrath before Judgment.",
})

register({
    actionId = "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE",
    class = "PALADIN",
    specIndex = 3,
    displayName = "公正之剑",
    actionCode = 2,
    spellIDs = { 184575 },
    macroStrategy = "single_spell_name",
    macroName = "TE_BladeJustice",
    groundMode = "none",
    category = "generator",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-03.",
})

register({
    actionId = "PALADIN_RETRIBUTION_DIVINE_STORM",
    class = "PALADIN",
    specIndex = 3,
    displayName = "神圣风暴",
    actionCode = 3,
    spellIDs = { 53385 },
    macroStrategy = "single_spell_name",
    macroName = "TE_DivineStorm",
    groundMode = "none",
    category = "spender",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-03.",
})

register({
    actionId = "PALADIN_RETRIBUTION_TEMPLAR_STRIKE",
    class = "PALADIN",
    specIndex = 3,
    displayName = "圣殿骑士打击",
    actionCode = 4,
    spellIDs = { 407480, 406647 },
    macroStrategy = "primary_spell_name_manual_verify",
    macroName = "TE_TemplarStrike",
    groundMode = "none",
    category = "generator",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-03.",
})

register({
    actionId = "PALADIN_RETRIBUTION_HAMMER_OF_WRATH",
    class = "PALADIN",
    specIndex = 3,
    displayName = "愤怒之锤",
    actionCode = 5,
    spellIDs = { 24275 },
    macroStrategy = "fallback_spell_names",
    macroCastSpellIDs = { 24275, 20271 },
    macroName = "TE_HammerWrath",
    groundMode = "none",
    category = "execute",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-03; shares the Judgment-stage fallback macro with the Judgment action.",
})

register({
    actionId = "PALADIN_RETRIBUTION_WAKE_OF_ASHES",
    class = "PALADIN",
    specIndex = 3,
    displayName = "灰烬觉醒",
    actionCode = 6,
    spellIDs = { 255937 },
    macroStrategy = "single_spell_name",
    macroName = "TE_WakeAshes",
    groundMode = "none",
    category = "cooldown",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-01.",
})

register({
    actionId = "PALADIN_RETRIBUTION_DIVINE_TOLL",
    class = "PALADIN",
    specIndex = 3,
    displayName = "圣洁鸣钟",
    actionCode = 7,
    spellIDs = { 375576 },
    macroStrategy = "single_spell_name",
    macroName = "TE_DivineToll",
    groundMode = "none",
    category = "cooldown",
    compatibility = "Observed in WoW 12.0.7 zhCN target dummy test.",
})

register({
    actionId = "PALADIN_RETRIBUTION_HAMMER_OF_LIGHT",
    class = "PALADIN",
    specIndex = 3,
    displayName = "圣光之锤",
    actionCode = 8,
    spellIDs = { 427453 },
    macroStrategy = "cast_override_spell_name",
    macroCastSpellID = 255937,
    macroName = "TE_HammerLight",
    groundMode = "none",
    category = "cooldown",
    compatibility = "Observed in WoW 12.0.7 zhCN target dummy test.",
})

register({
    actionId = "PALADIN_RETRIBUTION_FINAL_VERDICT",
    class = "PALADIN",
    specIndex = 3,
    displayName = "最终审判",
    actionCode = 9,
    spellIDs = { 383328 },
    macroStrategy = "single_spell_name",
    macroName = "TE_FinalVerdict",
    groundMode = "none",
    category = "spender",
    compatibility = "Observed in WoW 12.0.7 zhCN P0-01.",
})

register({
    actionId = "PALADIN_RETRIBUTION_EXECUTION_SENTENCE",
    class = "PALADIN",
    specIndex = 3,
    displayName = "处决宣判",
    actionCode = 10,
    spellIDs = { 343527 },
    macroStrategy = "single_spell_name",
    macroName = "TE_ExecutionSentence",
    groundMode = "none",
    category = "spender",
    compatibility = "Observed in WoW 12.0.7 zhCN manual verification; C_AssistedCombat.GetNextCastSpell returned 343527.",
})

function ActionRegistry:GetAction(actionId)
    return actionsById[actionId]
end

function ActionRegistry:FindBySpellID(spellID)
    local actionId = actionIdsBySpellId[spellID]
    if not actionId then
        return nil
    end
    return actionsById[actionId]
end

function ActionRegistry:ResolveRecommendation(result)
    if not TE.RecommendationResult:IsUsable(result) then
        return nil, "recommendation_not_usable"
    end

    local action = self:FindBySpellID(result.spellID)
    if not action then
        return nil, "spell_unmapped"
    end

    local matches, reason = TE.Context:MatchesAction(action, {
        class = result.class,
        specIndex = result.specIndex,
    })
    if not matches then
        return nil, reason
    end

    return action
end

function ActionRegistry:ListActions()
    return actionsById
end

function ActionRegistry:ListActiveActions(context)
    local active = {}
    context = context or TE.Context:GetPlayer()

    for actionId, action in pairs(actionsById) do
        if TE.Context:MatchesAction(action, context) then
            active[actionId] = action
        end
    end

    return active
end

function ActionRegistry:Validate()
    local codes = {}
    local spellIds = {}
    for actionId, action in pairs(actionsById) do
        if codes[action.actionCode] then
            return false, "duplicate_action_code:" .. tostring(action.actionCode)
        end
        codes[action.actionCode] = actionId
        if #(action.spellIDs or {}) > 1 and not action.macroStrategy then
            return false, "macro_strategy_required:" .. tostring(actionId)
        end
        for _, spellID in ipairs(action.spellIDs or {}) do
            if spellIds[spellID] and spellIds[spellID] ~= actionId then
                return false, "ambiguous_spell_id:" .. tostring(spellID)
            end
            spellIds[spellID] = actionId
        end
    end
    return true, "ok"
end
