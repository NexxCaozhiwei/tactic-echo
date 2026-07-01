local TE = _G.TacticEcho

-- Read-only macro classifier. It never evaluates arbitrary macro conditions,
-- never edits macros and never creates a new dispatch path. Resolver callers
-- may use its diagnostic result to explain an existing Blizzard action slot.
local MacroSemantics = {}
TE.MacroSemantics = MacroSemantics

local function trim(value) return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function commandAndArg(line)
    local command, rest = trim(line):match("^(%S+)%s*(.-)$")
    return command and command:lower() or nil, trim(rest)
end
local function targetMode(arg)
    if arg:find("@mouseover", 1, true) then return "mouseover" end
    if arg:find("@focus", 1, true) then return "focus" end
    if arg:find("@targettarget", 1, true) then return "targettarget" end
    if arg:find("@player", 1, true) then return "player" end
    return "target"
end

local function stripLeadingConditions(arg)
    local value = trim(arg)
    local removed = false
    while value:sub(1, 1) == "[" do
        local block = value:match("^%b[]")
        if not block then break end
        value = trim(value:sub(#block + 1))
        removed = true
    end
    return value, removed
end

function MacroSemantics:Analyze(body)
    local result = {
        supported = false,
        dispatchable = false,
        directSlotEligible = false,
        commands = {},
        targets = {},
        unsupported = {},
        hasCastsequence = false,
        hasConditional = false,
        hasMultipleActionLines = false,
    }
    for raw in tostring(body or ""):gmatch("[^\r\n]+") do
        local line = trim(raw)
        if line ~= "" and line:sub(1,1) ~= "#" then
            local command, arg = commandAndArg(line)
            if command == "/cast" or command == "/use" then
                local effectiveArg, hasConditions = stripLeadingConditions(arg)
                local entry = { command=command, arg=arg, effectiveArg=effectiveArg, hasConditions=hasConditions, target=targetMode(arg) }
                if command == "/use" and (effectiveArg == "13" or effectiveArg == "14") then entry.kind = "trinket_slot" else entry.kind = command == "/use" and "item_or_spell" or "spell" end
                result.commands[#result.commands + 1] = entry
                result.targets[entry.target] = true
                result.hasConditional = result.hasConditional or hasConditions or arg:find(";", 1, true) ~= nil
            elseif command == "/castsequence" then
                result.hasCastsequence = true
                result.unsupported[#result.unsupported + 1] = "castsequence_display_only"
            elseif command and command:sub(1,1) == "/" then
                result.unsupported[#result.unsupported + 1] = command
            end
        end
    end
    result.supported = #result.commands > 0
    result.hasMultipleActionLines = #result.commands > 1
    -- Macros are never independently executed by TE.  A direct body-to-spell
    -- association is only safe for one unconditioned /cast line; all other
    -- shapes remain diagnostics unless Blizzard reports the active macro spell.
    local only = result.commands[1]
    result.directSlotEligible = result.supported and not result.hasCastsequence
        and not result.hasMultipleActionLines and not result.hasConditional
        and only and only.command == "/cast" and only.target == "target"
    result.dispatchable = result.directSlotEligible == true
    result.targetSummary = next(result.targets) and table.concat((function() local t={} for k in pairs(result.targets) do t[#t+1]=k end table.sort(t) return t end)(), ",") or "none"
    return result
end
