local TE = _G.TacticEcho

-- Read-only macro classifier. It never evaluates or rewrites macro branches,
-- never creates a new dispatch path, and never synthesizes a macro. It only
-- explains whether an already-visible Blizzard macro button references a
-- requested spell so the existing BindingToken path can press that same button.
local MacroSemantics = {}
TE.MacroSemantics = MacroSemantics

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function commandAndArg(line)
    local command, rest = trim(line):match("^(%S+)%s*(.-)$")
    return command and command:lower() or nil, trim(rest)
end

local function escapePattern(value)
    return tostring(value or ""):gsub("([^%w])", "%%%1")
end

local function targetMode(arg)
    arg = tostring(arg or "")
    if arg:find("@cursor", 1, true) then return "cursor" end
    if arg:find("@mouseover", 1, true) then return "mouseover" end
    if arg:find("@focus", 1, true) then return "focus" end
    if arg:find("@targettarget", 1, true) then return "targettarget" end
    if arg:find("@player", 1, true) then return "player" end
    if arg:find("@pet", 1, true) then return "pet" end
    return "target"
end

local function leadingConditionBlocks(arg)
    local value = trim(arg)
    local blocks = {}
    while value:sub(1, 1) == "[" do
        local block = value:match("^%b[]")
        if not block then break end
        blocks[#blocks + 1] = block
        value = trim(value:sub(#block + 1))
    end
    return blocks, value
end

local function stripLeadingConditions(arg)
    local blocks, value = leadingConditionBlocks(arg)
    return value, #blocks > 0
end

-- Macro semicolon branches are only split outside condition brackets. The
-- result remains descriptive; TE never attempts to evaluate which branch is
-- live for the player.
local function splitBranches(arg)
    local value = tostring(arg or "")
    local output, startAt, depth = {}, 1, 0
    for index = 1, #value do
        local ch = value:sub(index, index)
        if ch == "[" then
            depth = depth + 1
        elseif ch == "]" and depth > 0 then
            depth = depth - 1
        elseif ch == ";" and depth == 0 then
            output[#output + 1] = trim(value:sub(startAt, index - 1))
            startAt = index + 1
        end
    end
    output[#output + 1] = trim(value:sub(startAt))
    return output
end

local function normalizeActionToken(value)
    value = trim(value)
    value = value:gsub("^!+", "")
    value = trim(value)
    return value ~= "" and value or nil
end

-- Macro body association normally compares the requested spell's localized
-- name with the token written in the player's existing macro.  Retail can
-- occasionally expose a usable macro body while the requested spell name is
-- not materialized through the name API at that same moment.  Resolve each
-- /cast token to an ordinary SpellID during the event-driven action-bar scan
-- as a read-only fallback.  This neither evaluates macro conditions nor
-- changes the macro; it only removes locale/name-materialization dependence
-- from association of an already-visible macro button.
local spellTokenIDCache = {}
local function resolveSpellTokenID(token)
    token = normalizeActionToken(token)
    if not token then return nil end

    local numeric = tonumber(token)
    if numeric and numeric > 0 then return numeric end

    local cached = spellTokenIDCache[token]
    if cached ~= nil then return cached end

    local resolved = nil
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, token)
        if ok and type(info) == "table" then
            resolved = tonumber(info.spellID or info.spellId or info.id)
        end
    end
    if (not resolved or resolved <= 0) and type(GetSpellInfo) == "function" then
        local ok, _, _, _, _, _, legacySpellID = pcall(GetSpellInfo, token)
        if ok then resolved = tonumber(legacySpellID) end
    end

    -- Cache only positive scalar IDs.  A temporary name/API materialization
    -- gap must be retried after the normal action-bar invalidation cycle,
    -- rather than becoming a session-long negative association.
    if resolved and resolved > 0 then
        spellTokenIDCache[token] = resolved
        return resolved
    end
    return nil
end

local function useKind(token)
    local slot = tonumber(token)
    if slot == 13 or slot == 14 then return "item_slot" end
    return "spell_or_item"
end

-- Target-management commands can make a macro behave differently from the
-- apparent /cast target route.  They remain Blizzard-owned: TE never evaluates
-- the command order, edits the macro or replays individual lines.  A later
-- automatic-reaction layer may nevertheless press the player's existing macro
-- binding when the macro contains only one requested spell identity and no
-- /castsequence.  In that case the macro, rather than TE, owns target acquire,
-- fallback and restoration behavior for the single hardware-equivalent press.
local TARGET_MUTATION_COMMANDS = {
    ["/assist"] = true,
    ["/clearfocus"] = true,
    ["/cleartarget"] = true,
    ["/focus"] = true,
    ["/target"] = true,
    ["/targetenemy"] = true,
    ["/targetexact"] = true,
    ["/targetfriend"] = true,
    ["/targetlastenemy"] = true,
    ["/targetlastfriend"] = true,
    ["/targetlasttarget"] = true,
    ["/targetmarker"] = true,
    ["/targetnearest"] = true,
    ["/targetnearestenemy"] = true,
    ["/targetnearestfriend"] = true,
}

local function addUnique(list, seen, value)
    value = trim(value)
    if value ~= "" and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function tokenMatchesSpell(token, spellID, spellName, resolvedSpellID)
    token = normalizeActionToken(token)
    if not token then return false end
    local wantedSpellID = tonumber(spellID)
    local resolved = tonumber(resolvedSpellID) or resolveSpellTokenID(token)
    if resolved and wantedSpellID and resolved == wantedSpellID then return true end
    local numeric = tonumber(token)
    if numeric and wantedSpellID and numeric == wantedSpellID then return true end
    if type(spellName) ~= "string" or spellName == "" then return false end
    if token == spellName or token:lower() == spellName:lower() then return true end
    -- Legacy rank display and localized macro forms can append a parenthetical
    -- suffix. Match only a suffix, never a partial substring.
    local pattern = "^" .. escapePattern(spellName) .. "%s*%b()$"
    return token:match(pattern) ~= nil
end

local function appendAction(result, command, rawArg, branchArg, branchIndex)
    local conditionBlocks, effectiveArg = leadingConditionBlocks(branchArg)
    local hasConditions = #conditionBlocks > 0
    local token = normalizeActionToken(effectiveArg)
    if not token then return end
    local kind = command == "/use" and useKind(token) or "spell"
    local entry = {
        command = command,
        arg = rawArg,
        branchArg = branchArg,
        branchIndex = branchIndex,
        effectiveArg = effectiveArg,
        token = token,
        -- This ordinary scalar is a read-only name-materialization fallback.
        -- It is intentionally not a dispatch credential and is never persisted
        -- with macro text.
        resolvedSpellID = kind == "spell" and resolveSpellTokenID(token) or nil,
        kind = kind,
        hasConditions = hasConditions,
        -- Preserve all leading condition blocks.  A single Blizzard /cast line
        -- can encode a left-to-right target cascade such as
        -- [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead].  The
        -- parser remains descriptive; P4 later only accepts one narrow,
        -- explicitly modelled cascade and never evaluates arbitrary branches.
        conditionBlocks = conditionBlocks,
        target = targetMode(branchArg),
    }
    result.actions[#result.actions + 1] = entry
    result.commands[#result.commands + 1] = entry -- legacy diagnostic alias.
    result.targets[entry.target] = true
    result.hasConditional = result.hasConditional or hasConditions or branchIndex > 1
    if kind ~= "item_slot" then addUnique(result.spellTokens, result._spellTokenSeen, token) end
end

local function appendCastsequence(result, rawArg)
    result.hasCastsequence = true
    local effectiveArg, hadConditions = stripLeadingConditions(rawArg)
    result.hasConditional = result.hasConditional or hadConditions or effectiveArg:find(";", 1, true) ~= nil
    -- reset= is macro control syntax, not a spell token. Parsing it is only used
    -- for diagnostics / broad association; execution still stays in Blizzard.
    effectiveArg = trim((effectiveArg:gsub("^reset=[^%s]+%s+", "")))
    for _, token in ipairs(splitBranches(effectiveArg)) do
        for part in token:gmatch("[^,]+") do
            local normalized = normalizeActionToken(part)
            if normalized then addUnique(result.castsequenceTokens, result._castsequenceTokenSeen, normalized) end
        end
    end
    result.unsupported[#result.unsupported + 1] = "castsequence_requires_current_macro_spell_or_broad_policy"
end

local function sortedKeys(source)
    local output = {}
    for key in pairs(source or {}) do output[#output + 1] = key end
    table.sort(output)
    return output
end

function MacroSemantics:Analyze(body)
    local result = {
        supported = false,
        dispatchable = false,
        directSlotEligible = false,
        broadReferenceEligible = false,
        autoBurstEligible = false,
        commands = {},
        actions = {},
        targets = {},
        unsupported = {},
        utilityCommands = {},
        targetMutationCommands = {},
        spellTokens = {},
        castsequenceTokens = {},
        hasCastsequence = false,
        hasConditional = false,
        hasMultipleActionLines = false,
        hasTargetMutation = false,
        actionLineCount = 0,
        macroShape = "empty",
        _spellTokenSeen = {},
        _castsequenceTokenSeen = {},
        _targetMutationSeen = {},
    }

    for raw in tostring(body or ""):gmatch("[^\r\n]+") do
        local line = trim(raw)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local command, arg = commandAndArg(line)
            if command == "/cast" or command == "/use" then
                result.actionLineCount = result.actionLineCount + 1
                local branches = splitBranches(arg)
                for branchIndex, branchArg in ipairs(branches) do
                    appendAction(result, command, arg, branchArg, branchIndex)
                end
                if #branches > 1 then result.hasConditional = true end
            elseif command == "/castsequence" then
                result.actionLineCount = result.actionLineCount + 1
                appendCastsequence(result, arg)
            elseif command and command:sub(1, 1) == "/" then
                result.utilityCommands[#result.utilityCommands + 1] = command
                if TARGET_MUTATION_COMMANDS[command] == true then
                    result.hasTargetMutation = true
                    addUnique(result.targetMutationCommands, result._targetMutationSeen, command)
                end
            end
        end
    end

    result.supported = #result.actions > 0 or #result.castsequenceTokens > 0
    result.hasMultipleActionLines = result.actionLineCount > 1
    local only = result.actions[1]
    -- Retained for old diagnostics and strict policy explanation. It is no
    -- longer the only route for a macro to resolve to a visible binding.
    result.directSlotEligible = #result.actions == 1 and not result.hasCastsequence
        and not result.hasMultipleActionLines and not result.hasConditional
        and only and only.command == "/cast" and only.target == "target"
    result.dispatchable = result.directSlotEligible == true
    result.broadReferenceEligible = result.supported == true
    result.autoBurstEligible = result.supported == true
    if result.hasCastsequence then
        result.macroShape = "castsequence"
    elseif #result.spellTokens == 1 then
        result.macroShape = "single_spell_macro"
    elseif #result.spellTokens > 1 then
        result.macroShape = "multi_spell_macro"
    elseif #result.actions > 0 then
        result.macroShape = "use_or_item_macro"
    end
    result.targetSummary = next(result.targets) and table.concat(sortedKeys(result.targets), ",") or "none"
    result._spellTokenSeen = nil
    result._castsequenceTokenSeen = nil
    result._targetMutationSeen = nil
    return result
end

-- Returns whether a macro body can be associated to an expected spell. The
-- strict policy accepts only a body whose executable spell references all point
-- to that exact spell. The broad policy accepts a direct textual reference in a
-- user-authored macro, including common conditional/target branches and
-- castsequences. It does not choose or execute a branch; the later state
-- machine still requires a confirmed cast/CD transition for the exact step.
function MacroSemantics:MatchSpell(semantics, spellID, spellName, policy)
    semantics = type(semantics) == "table" and semantics or {}
    policy = policy == "strict" and "strict" or "broad"
    local matchedActions, otherActions, matchedSequence = 0, 0, 0
    for _, action in ipairs(semantics.actions or {}) do
        if action.kind ~= "item_slot" then
            if tokenMatchesSpell(action.token, spellID, spellName) then
                matchedActions = matchedActions + 1
            else
                otherActions = otherActions + 1
            end
        end
    end
    for _, token in ipairs(semantics.castsequenceTokens or {}) do
        if tokenMatchesSpell(token, spellID, spellName) then matchedSequence = matchedSequence + 1 end
    end

    if matchedActions > 0 and otherActions == 0 and semantics.hasCastsequence ~= true then
        return true, "macro_body_single_spell"
    end
    if policy == "broad" and (matchedActions > 0 or matchedSequence > 0) then
        if semantics.hasCastsequence == true then return true, "macro_body_broad_castsequence" end
        if otherActions > 0 then return true, "macro_body_broad_multi_spell" end
        return true, "macro_body_broad_reference"
    end
    if matchedSequence > 0 then return false, "macro_castsequence_requires_current_macro_spell" end
    if matchedActions > 0 and otherActions > 0 then return false, "macro_body_ambiguous_spell_branch" end
    return false, "macro_spell_not_referenced"
end

-- A narrow, descriptive parser for the one integration macro shape that can
-- safely expose a deterministic unit-route cascade to P4:
--
--   /cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] Spell
--
-- It deliberately refuses modifiers, combat state, help/self/pet routes,
-- target mutations, /castsequence and any unknown condition.  This does not
-- evaluate a macro branch.  It only records the player-authored priority order
-- so P4 can later fail closed when an earlier macro branch would take over.
local PRIORITY_ROUTE_ORDER = { "mouseover", "focus", "target" }

local function strictPriorityClauseRoute(block)
    if type(block) ~= "string" or block:sub(1, 1) ~= "[" or block:sub(-1) ~= "]" then
        return nil
    end
    local body = trim(block:sub(2, -2))
    if body == "" then return nil end

    local route = "target"
    local sawRoute, sawHarm, sawNodead = false, false, false
    local seen = {}
    for rawToken in body:gmatch("[^,]+") do
        local token = trim(rawToken):lower()
        if token == "" or seen[token] then return nil end
        seen[token] = true
        if token:sub(1, 1) == "@" then
            local unit = token:sub(2)
            if (unit ~= "mouseover" and unit ~= "focus" and unit ~= "target") or sawRoute then
                return nil
            end
            route, sawRoute = unit, true
        elseif token == "exists" then
            -- Optional only.  harm/nodead still remain mandatory below.
        elseif token == "harm" then
            sawHarm = true
        elseif token == "nodead" then
            sawNodead = true
        else
            return nil
        end
    end
    if sawHarm ~= true or sawNodead ~= true then return nil end
    return route
end

local function strictPriorityRouteChain(semantics, spellID, spellName)
    if type(semantics) ~= "table" then return nil end
    if semantics.actionLineCount ~= 1 or semantics.hasCastsequence == true or semantics.hasTargetMutation == true then
        return nil
    end

    local clauses, seen = {}, {}
    local actions = type(semantics.actions) == "table" and semantics.actions or {}
    if #actions <= 0 then return nil end
    for _, action in ipairs(actions) do
        if action.kind ~= "spell" or action.command ~= "/cast"
            or tokenMatchesSpell(action.token, spellID, spellName) ~= true then
            return nil
        end
        local blocks = type(action.conditionBlocks) == "table" and action.conditionBlocks or {}
        if #blocks <= 0 then return nil end
        for _, block in ipairs(blocks) do
            local route = strictPriorityClauseRoute(block)
            if not route or seen[route] then return nil end
            seen[route] = true
            clauses[#clauses + 1] = route
        end
    end

    if #clauses ~= #PRIORITY_ROUTE_ORDER then return nil end
    for index, route in ipairs(PRIORITY_ROUTE_ORDER) do
        if clauses[index] ~= route then return nil end
    end
    return clauses
end

local function hasConditionalCascade(actions)
    for _, action in ipairs(type(actions) == "table" and actions or {}) do
        if type(action.conditionBlocks) == "table" and #action.conditionBlocks > 1 then
            return true
        end
    end
    return false
end

-- Returns the target routes used by executable actions that reference one
-- requested spell. This stays descriptive: it never decides which conditional
-- branch is currently true and never executes a macro. P2 interrupt/control
-- mapping consumes this metadata only to distinguish the player-authored
-- @focus / @mouseover / @cursor buttons from a normal current-target button.
function MacroSemantics:DescribeSpellRoutes(semantics, spellID, spellName)
    semantics = type(semantics) == "table" and semantics or {}
    local out = {
        recognized = false,
        routes = {},
        routeSet = {},
        matchedActionCount = 0,
        otherSpellActionCount = 0,
        hasCastsequence = semantics.hasCastsequence == true,
        hasTargetMutation = semantics.hasTargetMutation == true,
        targetMutationCommands = semantics.targetMutationCommands or {},
        castsequenceMatched = false,
        singleRoute = false,
        singleSpellTargetSwitchFallback = false,
        singleSpellTargetMutation = false,
        macroManagedTargetAuto = false,
        macroPriorityChainAuto = false,
        priorityRouteOrder = {},
        conditionalCascadeOpaque = false,
        autoRouteMode = nil,
        reason = "macro_spell_not_referenced",
    }
    local seen = {}
    local function addRoute(route)
        if not seen[route] then
            seen[route] = true
            out.routes[#out.routes + 1] = route
            out.routeSet[route] = true
        end
    end
    for _, action in ipairs(semantics.actions or {}) do
        if action.kind ~= "item_slot" then
            if tokenMatchesSpell(action.token, spellID, spellName) then
                out.recognized = true
                out.matchedActionCount = out.matchedActionCount + 1
                addRoute(action.target or "target")
            else
                out.otherSpellActionCount = out.otherSpellActionCount + 1
            end
        end
    end
    for _, token in ipairs(semantics.castsequenceTokens or {}) do
        if tokenMatchesSpell(token, spellID, spellName) then
            out.recognized = true
            out.castsequenceMatched = true
        end
    end

    -- Adjacent condition blocks are a priority cascade in one Blizzard /cast
    -- action, not a single @mouseover route.  Accept only the exact known
    -- mouseover -> focus -> target shape; every other cascade remains manual
    -- only rather than being accidentally promoted as its first branch.
    local priorityChain = strictPriorityRouteChain(semantics, spellID, spellName)
    if priorityChain then
        out.macroPriorityChainAuto = true
        out.priorityRouteOrder = priorityChain
        out.routes, out.routeSet, seen = {}, {}, {}
        for _, route in ipairs(priorityChain) do addRoute(route) end
    elseif hasConditionalCascade(semantics.actions) then
        out.conditionalCascadeOpaque = true
    end

    out.singleRoute = #out.routes == 1 and out.castsequenceMatched ~= true
        and out.conditionalCascadeOpaque ~= true
    -- A common interrupt/control pattern is: cast @focus when available,
    -- temporarily acquire an enemy, cast the same skill on that target, then
    -- restore the previous target.  The author explicitly owns that behavior
    -- in the macro.  For a same-spell, non-/castsequence macro, ReactionBindings
    -- may mark the existing macro button as a macro-managed automatic route.
    -- TE still does not infer a branch or issue target commands itself; it only
    -- presses the player's visible bound macro as one atomic normal input.
    out.singleSpellTargetSwitchFallback = out.recognized == true
        and out.hasCastsequence ~= true
        and out.castsequenceMatched ~= true
        and out.matchedActionCount > 0
        and out.otherSpellActionCount == 0
        and out.routeSet.focus == true
        and out.routeSet.target == true
        and out.hasTargetMutation == true
    out.singleSpellTargetMutation = out.recognized == true
        and out.hasCastsequence ~= true
        and out.castsequenceMatched ~= true
        and out.matchedActionCount > 0
        and out.otherSpellActionCount == 0
        and out.hasTargetMutation == true
    out.macroManagedTargetAuto = out.singleSpellTargetMutation == true
    if out.macroPriorityChainAuto then
        out.autoRouteMode = "macro_priority_chain"
    elseif out.macroManagedTargetAuto then
        out.autoRouteMode = "macro_managed_target"
    elseif out.singleRoute and out.otherSpellActionCount == 0 and out.hasCastsequence ~= true then
        out.autoRouteMode = "explicit_route"
    end
    if out.recognized then
        if out.hasCastsequence or out.castsequenceMatched then
            out.reason = "macro_castsequence_route_opaque"
        elseif out.matchedActionCount <= 0 then
            out.reason = "macro_action_route_unavailable"
        elseif out.macroPriorityChainAuto then
            out.reason = "macro_priority_chain_auto"
        elseif out.conditionalCascadeOpaque then
            out.reason = "macro_conditional_chain_opaque"
        elseif out.singleSpellTargetSwitchFallback then
            out.reason = "macro_target_switch_fallback_auto"
        elseif out.macroManagedTargetAuto then
            out.reason = "macro_target_mutation_auto"
        elseif out.otherSpellActionCount > 0 then
            out.reason = "macro_multi_spell_route_ambiguous"
        elseif #out.routes ~= 1 then
            out.reason = "macro_target_route_ambiguous"
        else
            out.reason = "macro_single_target_route"
        end
    end
    return out
end

-- Returns whether a macro visibly references exactly one equipped trinket slot.
-- The resolver never decides which conditional macro branch is true.  This only
-- associates the player's existing action-bar macro button with one explicit
-- Phase-1.5 trinket step.  A macro containing both /use 13 and /use 14 is
-- deliberately rejected: dual-trinket behavior must be modeled as two explicit
-- actions rather than hidden inside one opaque input.
function MacroSemantics:MatchInventorySlot(semantics, slot, policy)
    semantics = type(semantics) == "table" and semantics or {}
    slot = tonumber(slot)
    if slot ~= 13 and slot ~= 14 then return false, "inventory_slot_invalid" end
    policy = policy == "strict" and "strict" or "broad"
    local matched, otherSlot = 0, false
    for _, action in ipairs(semantics.actions or {}) do
        if action.kind == "item_slot" then
            local actionSlot = tonumber(action.token)
            if actionSlot == slot then
                matched = matched + 1
            elseif actionSlot == 13 or actionSlot == 14 then
                otherSlot = true
            end
        end
    end
    if matched <= 0 then return false, "macro_inventory_slot_not_referenced" end
    if otherSlot then return false, "macro_multiple_trinket_slots" end
    if policy == "strict" and semantics.hasCastsequence == true then
        return false, "macro_castsequence_not_allowed_for_inventory"
    end
    -- Broad mode intentionally permits target/condition branches and spell
    -- utility lines.  The later action state machine still needs this exact
    -- equipped slot's own cooldown transition to confirm success.
    return true, policy == "strict" and "macro_inventory_slot" or "macro_inventory_slot_broad"
end

function MacroSemantics:InventorySlots(semantics)
    semantics = type(semantics) == "table" and semantics or {}
    local slots, seen = {}, {}
    for _, action in ipairs(semantics.actions or {}) do
        if action.kind == "item_slot" then
            local slot = tonumber(action.token)
            if (slot == 13 or slot == 14) and not seen[slot] then
                seen[slot] = true
                slots[#slots + 1] = slot
            end
        end
    end
    table.sort(slots)
    return slots
end

function MacroSemantics:Summary(semantics)
    semantics = type(semantics) == "table" and semantics or {}
    return {
        supported = semantics.supported == true,
        directSlotEligible = semantics.directSlotEligible == true,
        broadReferenceEligible = semantics.broadReferenceEligible == true,
        autoBurstEligible = semantics.autoBurstEligible == true,
        macroShape = semantics.macroShape,
        actionLineCount = tonumber(semantics.actionLineCount) or 0,
        spellTokenCount = #(semantics.spellTokens or {}),
        resolvedSpellTokenCount = (function()
            local total = 0
            for _, action in ipairs(semantics.actions or {}) do
                if tonumber(action.resolvedSpellID) then total = total + 1 end
            end
            return total
        end)(),
        castsequenceTokenCount = #(semantics.castsequenceTokens or {}),
        hasConditional = semantics.hasConditional == true,
        hasCastsequence = semantics.hasCastsequence == true,
        hasTargetMutation = semantics.hasTargetMutation == true,
        targetMutationCommands = semantics.targetMutationCommands or {},
        targetSummary = semantics.targetSummary,
    }
end
