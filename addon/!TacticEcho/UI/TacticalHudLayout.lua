-- Tactical HUD positioning and persistent layout rules.
-- Presentation only.  Every visible card is placed through a common bounded
-- coordinate pass so changing queue direction, hiding a module, or using
-- mixed icon sizes cannot leave cards outside the HUD or on top of each other.
local TE = _G.TacticEcho

local TacticalHudLayout = {}
TE.TacticalHudLayout = TacticalHudLayout
local TacticalIconButton = TE.TacticalIconButton

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function inCombatLockdown()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function clear(frame)
    if frame then frame:ClearAllPoints() end
end

local function directionVector(direction)
    if direction == "LEFT" then return -1, 0 end
    if direction == "UP" then return 0, -1 end
    if direction == "DOWN" then return 0, 1 end
    return 1, 0
end

local function setContainerBackdrop(frame, alpha)
    if not frame or not frame.SetBackdropColor then return end
    frame:SetBackdropColor(0.01, 0.02, 0.035, clamp(alpha, 0, 1))
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0) end
end

local function cardShown(card)
    return card and type(card.IsShown) == "function" and card:IsShown()
end

local function visibleCount(items)
    local count = 0
    for _, item in ipairs(items or {}) do if cardShown(item) then count = count + 1 end end
    return count
end

local function moduleSize(hud, key, fallback, minimum, maximum)
    local module = type(hud.modules) == "table" and hud.modules[key] or nil
    return clamp(module and module.iconSize or fallback, minimum, maximum)
end

local function appendPlacement(placements, card, x, y, size, group)
    if not cardShown(card) then return false end
    size = math.floor(size)
    TacticalIconButton:SetSize(card, size)
    placements[#placements + 1] = { card = card, x = x, y = y, size = size, group = group }
    return true
end

local function boundsFor(placements, group)
    local bounds = nil
    for _, placement in ipairs(placements or {}) do
        if not group or placement.group == group then
            local right, bottom = placement.x + placement.size, placement.y + placement.size
            if not bounds then
                bounds = { minX = placement.x, minY = placement.y, maxX = right, maxY = bottom }
            else
                bounds.minX = math.min(bounds.minX, placement.x)
                bounds.minY = math.min(bounds.minY, placement.y)
                bounds.maxX = math.max(bounds.maxX, right)
                bounds.maxY = math.max(bounds.maxY, bottom)
            end
        end
    end
    return bounds
end

local function applyPlacements(board, placements)
    local bounds = boundsFor(placements) or { minX = 0, minY = 0, maxX = 100, maxY = 68 }
    local shiftX = bounds.minX < 0 and -bounds.minX or 0
    local shiftY = bounds.minY < 0 and -bounds.minY or 0
    for _, placement in ipairs(placements or {}) do
        clear(placement.card)
        placement.card:SetPoint("TOPLEFT", board, "TOPLEFT", placement.x + shiftX, -(placement.y + shiftY))
    end
    return math.max(100, bounds.maxX - bounds.minX), math.max(68, bounds.maxY - bounds.minY)
end

local function clearNodePoints(nodes)
    if nodes.primary then clear(nodes.primary) end
    for _, card in ipairs(nodes.candidates or {}) do clear(card) end
    local tactical = nodes.tactical or {}
    clear(tactical.interrupt)
    for _, card in ipairs(tactical.burst or {}) do clear(card) end
    clear(tactical.control)
    clear(tactical.mobility)
end

local function layoutQueue(nodes, hud)
    local placements = {}
    local gap = clamp(hud.gap, 2, 24)
    local primarySize = moduleSize(hud, "main", hud.primarySize, 44, 120)
    local candidateSize = clamp(hud.candidateSize, 26, 88)
    local mainDirection = hud.primaryGrowth or "RIGHT"
    local dx, dy = directionVector(mainDirection)
    local primaryVisible = appendPlacement(placements, nodes.primary, 0, 0, primarySize, "main")

    local x, y
    if primaryVisible then
        if dx > 0 then x, y = primarySize + gap, math.floor((primarySize - candidateSize) / 2)
        elseif dx < 0 then x, y = -gap - candidateSize, math.floor((primarySize - candidateSize) / 2)
        elseif dy > 0 then x, y = math.floor((primarySize - candidateSize) / 2), primarySize + gap
        else x, y = math.floor((primarySize - candidateSize) / 2), -gap - candidateSize end
    else
        x, y = 0, 0
    end
    for _, card in ipairs(nodes.candidates or {}) do
        if appendPlacement(placements, card, x, y, candidateSize, "main") then
            x = x + dx * (candidateSize + gap)
            y = y + dy * (candidateSize + gap)
        end
    end

    local base = boundsFor(placements, "main") or { minX = 0, minY = 0, maxX = 0, maxY = 0 }

    -- Burst and interrupt/control are separate HUD modules, not entries in one
    -- shared tactical queue.  The earlier combined list placed
    -- interrupt -> burst -> control -> mobility in the same row/column, so a
    -- vertical tactical direction made the Burst card look like part of the
    -- interrupt/control stack.  Keep Burst in its own lane; retain the selected
    -- tactical growth direction only for the interrupt/control/mobility lane.
    local function laneExtent(entries, direction)
        local dx, dy = directionVector(direction)
        local width, height, count = 0, 0, 0
        for _, entry in ipairs(entries or {}) do
            if cardShown(entry.card) then
                local size = moduleSize(hud, entry.key, hud.tacticalSize, 28, 88)
                count = count + 1
                if dx ~= 0 then
                    width = width + size + (count > 1 and gap or 0)
                    height = math.max(height, size)
                else
                    width = math.max(width, size)
                    height = height + size + (count > 1 and gap or 0)
                end
            end
        end
        return width, height, count
    end

    local function appendLane(entries, laneX, laneY, direction)
        local width, height, count = laneExtent(entries, direction)
        if count == 0 then return 0 end
        local dx, dy = directionVector(direction)
        local cursorX, cursorY = laneX, laneY
        -- LEFT/UP lanes are laid out inside a precomputed positive rectangle so
        -- they remain below the primary queue instead of growing into it.
        if dx < 0 then cursorX = laneX + width end
        if dy < 0 then cursorY = laneY + height end
        for _, entry in ipairs(entries or {}) do
            if cardShown(entry.card) then
                local size = moduleSize(hud, entry.key, hud.tacticalSize, 28, 88)
                if dx < 0 then cursorX = cursorX - size end
                if dy < 0 then cursorY = cursorY - size end
                appendPlacement(placements, entry.card, cursorX, cursorY, size, "tactical")
                if dx > 0 then cursorX = cursorX + size + gap
                elseif dx < 0 then cursorX = cursorX - gap
                elseif dy > 0 then cursorY = cursorY + size + gap
                else cursorY = cursorY - gap end
            end
        end
        return height
    end

    local burstLane = {}
    for _, card in ipairs(nodes.tactical and nodes.tactical.burst or {}) do
        burstLane[#burstLane + 1] = { card = card, key = "burst" }
    end
    local interruptControlLane = {
        { card = nodes.tactical and nodes.tactical.interrupt, key = "interrupt" },
        { card = nodes.tactical and nodes.tactical.control, key = "interrupt" },
        { card = nodes.tactical and nodes.tactical.mobility, key = "interrupt" },
    }

    local laneY = base.maxY + 10
    local burstHeight = appendLane(burstLane, base.minX, laneY, hud.burstGrowth or "RIGHT")
    if burstHeight > 0 then laneY = laneY + burstHeight + 10 end
    appendLane(interruptControlLane, base.minX, laneY, hud.tacticalGrowth or "RIGHT")
    return placements
end

local function layoutSurround(nodes, hud)
    if not cardShown(nodes.primary) or visibleCount(nodes.tactical and nodes.tactical.burst or {}) > 1 then
        -- Surround has only one safe burst anchor. A multi-card burst queue
        -- deliberately falls back to the bounded queue layout instead of
        -- overlaying followers on interrupt/control cards.
        return layoutQueue(nodes, hud)
    end
    local placements = {}
    local gap = clamp(hud.gap, 2, 24)
    local primarySize = moduleSize(hud, "main", hud.primarySize, 44, 120)
    local candidateSize = clamp(hud.candidateSize, 26, 88)
    local interruptSize = moduleSize(hud, "interrupt", hud.tacticalSize, 28, 88)
    local burstSize = moduleSize(hud, "burst", hud.tacticalSize, 28, 88)
    local center = math.max(interruptSize, burstSize) + gap
    appendPlacement(placements, nodes.primary, center, center, primarySize, "main")

    local candidateX = center
    local candidateY = center + primarySize + gap
    for _, card in ipairs(nodes.candidates or {}) do
        if appendPlacement(placements, card, candidateX, candidateY, candidateSize, "main") then
            candidateX = candidateX + candidateSize + gap
        end
    end

    appendPlacement(placements, nodes.tactical and nodes.tactical.interrupt, center + math.floor((primarySize - interruptSize) / 2), 0, interruptSize, "tactical")
    appendPlacement(placements, nodes.tactical and nodes.tactical.burst and nodes.tactical.burst[1], center + primarySize + gap, center + math.floor((primarySize - burstSize) / 2), burstSize, "tactical")
    appendPlacement(placements, nodes.tactical and nodes.tactical.control, 0, center + math.floor((primarySize - interruptSize) / 2), interruptSize, "tactical")
    appendPlacement(placements, nodes.tactical and nodes.tactical.mobility, center + math.floor((primarySize - interruptSize) / 2), candidateY + candidateSize + gap, interruptSize, "tactical")
    return placements
end

local function layoutDefenseInline(board, defenseFrame, nodes, hud, baseWidth, baseHeight)
    defenseFrame:SetParent(board)
    local defenseSize = moduleSize(hud, "defense", hud.defenseSize, 28, 88)
    local gap = clamp(hud.gap, 2, 24)
    for _, card in ipairs(nodes.defense or {}) do clear(card) end
    local x = 0
    for _, card in ipairs(nodes.defense or {}) do
        if cardShown(card) then
            TacticalIconButton:SetSize(card, defenseSize)
            card:SetPoint("TOPLEFT", defenseFrame, "TOPLEFT", x, 0)
            x = x + defenseSize + gap
        end
    end
    local width = math.max(1, x > 0 and x - gap or defenseSize)
    defenseFrame:ClearAllPoints()
    defenseFrame:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -(baseHeight + 12))
    defenseFrame:SetSize(width, defenseSize)
    defenseFrame:SetScale(1)
    defenseFrame:SetAlpha(1)
    defenseFrame.handle:Hide()
    return math.max(baseWidth, width), baseHeight + 12 + defenseSize
end

local function restoreDefensePoint(defenseFrame, hud)
    defenseFrame:ClearAllPoints()
    defenseFrame:SetPoint(hud.defensePoint or "CENTER", UIParent, hud.defenseRelativePoint or "CENTER", tonumber(hud.defenseX) or 0, tonumber(hud.defenseY) or -240)
end

local function layoutDefenseDetached(defenseFrame, nodes, hud)
    defenseFrame:SetParent(UIParent)
    defenseFrame:SetFrameStrata("MEDIUM")
    local defenseSize = moduleSize(hud, "defense", hud.defenseSize, 28, 88)
    local gap = clamp(hud.gap, 2, 24)
    for _, card in ipairs(nodes.defense or {}) do clear(card) end
    local x = 0
    for _, card in ipairs(nodes.defense or {}) do
        if cardShown(card) then
            TacticalIconButton:SetSize(card, defenseSize)
            card:SetPoint("TOPLEFT", defenseFrame, "TOPLEFT", x, 0)
            x = x + defenseSize + gap
        end
    end
    defenseFrame:SetSize(math.max(1, x > 0 and x - gap or defenseSize), defenseSize)
    restoreDefensePoint(defenseFrame, hud)
    defenseFrame:SetScale(clamp(hud.defenseScale, 0.60, 2.00))
    defenseFrame:SetAlpha(clamp(hud.defenseAlpha, 0.20, 1.00))
    defenseFrame.handle:SetShown(hud.defenseLocked ~= true and hud.showDragHandle ~= false)
end

local function layoutFingerprint(nodes, hud)
    local function shownMarker(card) return cardShown(card) and "1" or "0" end
    return table.concat({
        tostring(hud.layoutPreset or "queue_horizontal"), tostring(hud.primaryGrowth or "RIGHT"), tostring(hud.tacticalGrowth or "RIGHT"), tostring(hud.burstGrowth or "RIGHT"),
        tostring(clamp(hud.gap, 2, 24)), tostring(moduleSize(hud, "main", hud.primarySize, 44, 120)),
        tostring(clamp(hud.candidateSize, 26, 88)), tostring(moduleSize(hud, "burst", hud.tacticalSize, 28, 88)),
        tostring(moduleSize(hud, "interrupt", hud.tacticalSize, 28, 88)), tostring(moduleSize(hud, "defense", hud.defenseSize, 28, 88)),
        tostring(clamp(hud.scale, 0.60, 2.00)), tostring(clamp(hud.backdropAlpha, 0, 1)),
        tostring(hud.locked == true), tostring(hud.showDragHandle ~= false), tostring(hud.defenseDetached == true),
        tostring(hud.defenseLocked == true), tostring(clamp(hud.defenseScale, 0.60, 2.00)), tostring(clamp(hud.defenseAlpha, 0.20, 1.00)),
        shownMarker(nodes.primary), shownMarker(nodes.candidates and nodes.candidates[1]), shownMarker(nodes.candidates and nodes.candidates[2]), shownMarker(nodes.candidates and nodes.candidates[3]),
        shownMarker(nodes.tactical and nodes.tactical.interrupt),
        shownMarker(nodes.tactical and nodes.tactical.burst and nodes.tactical.burst[1]),
        shownMarker(nodes.tactical and nodes.tactical.burst and nodes.tactical.burst[2]),
        shownMarker(nodes.tactical and nodes.tactical.burst and nodes.tactical.burst[3]),
        shownMarker(nodes.tactical and nodes.tactical.burst and nodes.tactical.burst[4]),
        shownMarker(nodes.tactical and nodes.tactical.burst and nodes.tactical.burst[5]),
        shownMarker(nodes.tactical and nodes.tactical.control), shownMarker(nodes.tactical and nodes.tactical.mobility),
        shownMarker(nodes.defense and nodes.defense[1]), shownMarker(nodes.defense and nodes.defense[2]),
        shownMarker(nodes.defense and nodes.defense[3]), shownMarker(nodes.defense and nodes.defense[4]),
    }, "|")
end

function TacticalHudLayout:Apply(board, defenseFrame, nodes, hud)
    if not board or not nodes or not hud then return false end
    local fingerprint = layoutFingerprint(nodes, hud)
    -- The fingerprint includes backdrop, scale and drag-handle inputs. Avoid
    -- repeating SetBackdropColor/SetScale/SetShown when no card or layout state
    -- has changed; renderInternal still applies transient combat alpha/scale.
    if board.tacticEchoLayoutFingerprint == fingerprint then return false end
    if inCombatLockdown() then
        -- Once HUD manual-click layers have introduced secure siblings, the
        -- board can be on a protected/tainted path in combat. Defer all layout
        -- mutations, including SetScale/SetPoint/SetSize/SetShown, until the
        -- next out-of-combat render.
        board.tacticEchoLayoutDirty = true
        board.tacticEchoPendingLayoutFingerprint = fingerprint
        return false
    end
    setContainerBackdrop(board, hud.backdropAlpha)
    board:SetScale(clamp(hud.scale, 0.60, 2.00))
    board.handle:SetShown(hud.locked ~= true and hud.showDragHandle ~= false)
    clearNodePoints(nodes)

    local placements
    if hud.layoutPreset == "surround" then
        placements = layoutSurround(nodes, hud)
    else
        -- queue_horizontal and queue_vertical both use the selected growth
        -- direction; vertical is the default preset choice, not a clipping mode.
        placements = layoutQueue(nodes, hud)
    end
    local width, height = applyPlacements(board, placements)

    local hasDefense = visibleCount(nodes.defense) > 0
    if hasDefense then
        if hud.defenseDetached == true then
            layoutDefenseDetached(defenseFrame, nodes, hud)
        else
            width, height = layoutDefenseInline(board, defenseFrame, nodes, hud, width, height)
        end
    else
        defenseFrame:Hide()
    end

    board:SetSize(math.max(100, width), math.max(68, height))
    if board.statusText then
        clear(board.statusText)
        board.statusText:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 0, -4)
    end
    board.tacticEchoLayoutFingerprint = fingerprint
    board.tacticEchoLayoutDirty = nil
    board.tacticEchoPendingLayoutFingerprint = nil
    return true
end

function TacticalHudLayout:Reset(hud)
    hud.layoutPreset = "queue_horizontal"
    hud.orientation = "horizontal"
    hud.primaryGrowth = "RIGHT"
    hud.tacticalGrowth = "RIGHT"
    hud.burstGrowth = "RIGHT"
    hud.primarySize = 68
    hud.candidateSize = 38
    hud.tacticalSize = 46
    hud.defenseSize = 38
    hud.gap = 6
    hud.scale = 1
    hud.alpha = 1
    hud.backdropAlpha = 0.08
    hud.outOfCombatMode = "show"
    hud.outOfCombatAlpha = 0.62
    hud.outOfCombatScale = 1
    hud.defenseScale = 1
    hud.defenseAlpha = 1
    hud.defenseDetached = false
    hud.locked = false
    hud.defenseLocked = false
    hud.showDragHandle = true
    hud.modules = type(hud.modules) == "table" and hud.modules or {}
    for key, size in pairs({ main = hud.primarySize, burst = hud.tacticalSize, interrupt = hud.tacticalSize, defense = hud.defenseSize }) do
        hud.modules[key] = type(hud.modules[key]) == "table" and hud.modules[key] or {}
        hud.modules[key].show = true
        hud.modules[key].iconSize = size
    end
    hud.point, hud.relativePoint, hud.x, hud.y = "CENTER", "CENTER", 0, -150
    hud.defensePoint, hud.defenseRelativePoint, hud.defenseX, hud.defenseY = "CENTER", "CENTER", 0, -240
end
