-- Tactic Echo tactical recommendation HUD.
-- 0.7.4: queue-oriented display with secret-value-safe fingerprints and render fail-soft.
-- It only consumes TacticalAdvisors snapshots. It does not call the official
-- recommendation API, mutate a Token, encode TEAP, or request TEK input.
local TE = _G.TacticEcho

local TacticalBoard = {}
TE.TacticalBoard = TacticalBoard

local TacticalHudModel = TE.TacticalHudModel
local TacticalIconButton = TE.TacticalIconButton
local TacticalHudLayout = TE.TacticalHudLayout
local TacticalHudAnimator = TE.TacticalHudAnimator
local TacticalHudDragHandle = TE.TacticalHudDragHandle

local board
local defenseFrame
local nodes = {}
local slotStates = {}
local MAX_BURST_CARDS = 5

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function plainBoolean(value)
    local ok, result = pcall(function()
        if value == true then return true end
        if value == false then return false end
        return nil
    end)
    return ok and result or nil
end

local function inCombatLockdown()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function applyContainerPresentation(frame, alpha, scale)
    if not frame then return end
    alpha = clamp(alpha, 0.20, 1.00)
    scale = clamp(scale, 0.60, 2.00)
    if inCombatLockdown() then
        frame.tacticEchoCombatPresentationPending = { alpha = alpha, scale = scale }
        return
    end
    frame.tacticEchoCombatPresentationPending = nil
    frame:SetAlpha(alpha)
    frame:SetScale(scale)
end

local function applyFrameShown(frame, shown)
    if not frame then return end
    shown = shown == true
    if inCombatLockdown() then
        frame.tacticEchoCombatShownPending = shown
        return
    end
    frame.tacticEchoCombatShownPending = nil
    if frame.SetShown then
        frame:SetShown(shown)
    elseif shown and frame.Show then
        frame:Show()
    elseif not shown and frame.Hide then
        frame:Hide()
    end
end

local function db()
    -- Config/Normalize.lua is the sole owner of persisted HUD defaults.  The
    -- fallback intentionally creates only containers so a partial load cannot
    -- clamp missing values to visual minimums before normalization is available.
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, _, hud = TE.Config.Normalize:All()
        return hud
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.hud = type(TacticEchoDB.tactics.hud) == "table" and TacticEchoDB.tactics.hud or {}
    return TacticEchoDB.tactics.hud
end

local function moduleShown(hud, key)
    local module = type(hud.modules) == "table" and hud.modules[key] or nil
    return not module or module.show ~= false
end

local function createBackdrop(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(0.01, 0.02, 0.035, 0.08)
end


local function savePoint(frame, prefix)
    local hud = db()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if prefix == "defense" then
        hud.defensePoint, hud.defenseRelativePoint, hud.defenseX, hud.defenseY = point, relativePoint, x, y
    else
        hud.point, hud.relativePoint, hud.x, hud.y = point, relativePoint, x, y
    end
end

local function restorePoint(frame, prefix)
    local hud = db()
    frame:ClearAllPoints()
    if prefix == "defense" then
        frame:SetPoint(hud.defensePoint or "CENTER", UIParent, hud.defenseRelativePoint or "CENTER", tonumber(hud.defenseX) or 0, tonumber(hud.defenseY) or -240)
    else
        frame:SetPoint(hud.point or "CENTER", UIParent, hud.relativePoint or "CENTER", tonumber(hud.x) or 0, tonumber(hud.y) or -150)
    end
end

local function statusText(primary)
    local visual = primary and primary.visual or {}
    local labels = {
        dispatchable = "HAD",
        primary = "官方推荐",
        display_only = "仅显示",
        blocked = "已阻断",
        error = "异常",
        paused = "暂停中",
        standby = "待命中",
        -- The icon retains the finer “引导 / 引导锁 / 蓄力 / 蓄力锁” label.
        -- The board-level line deliberately uses the shared human status term.
        channeling = "引导中",
        channeling_lock = "引导中",
        empowering = "蓄力中",
        empowering_lock = "蓄力中",
        unbound = "无绑定",
        unknown = "状态未知",
    }
    return labels[visual.visualState] or visual.label or "等待官方推荐"
end

-- Do not use tostring/table.concat directly on fields copied from a WoW API
-- snapshot.  tostring(secretNumber) can remain secret and table.concat then
-- throws before the HUD has a chance to fail soft.
local function safeFingerprintText(value, fallback)
    local ok, result = pcall(function()
        if value == nil then return fallback end
        if type(value) == "boolean" then return value and "1" or "0" end
        if type(value) == "string" then
            local length = #value
            if length < 0 then return fallback end
            return value
        end
        if type(value) == "number" then
            local number = tonumber(value)
            if type(number) ~= "number" then return fallback end
            local probe = number + 0
            if probe < -math.huge or probe > math.huge then return fallback end
            return tostring(probe)
        end
        return fallback
    end)
    return ok and type(result) == "string" and result or fallback
end

local function buildCardFingerprint(item)
    item = item or {}
    local visual = item.visual or {}
    -- Cooldown/charge values intentionally do not participate.  They are
    -- refreshed independently by TacticalIconButton:RefreshDynamic and may be
    -- unknown or secret on retail clients.
    return table.concat({
        safeFingerprintText(item.spellID, "?"),
        safeFingerprintText(item.itemID, "-"),
        safeFingerprintText(item.binding, ""),
        safeFingerprintText(item.burstRole, ""),
        safeFingerprintText(item.burstState, ""),
        safeFingerprintText(item.hidden == true, "0"),
        safeFingerprintText(item.usableState, "unknown"),
        safeFingerprintText(visual.visualState, "unknown"),
        safeFingerprintText(item.procHighlight == true, "0"),
        safeFingerprintText(item.burstOverlay == true, "0"),
        safeFingerprintText(item.castingThisSpell == true, "0"),
    }, "|")
end

local function isUrgent(item)
    local visual = item and item.visual or {}
    return visual.visualState == "blocked" or visual.visualState == "error" or visual.visualState == "paused" or visual.visualState == "unknown" or visual.visualState == "unbound"
end

local function applyCard(key, card, item, hud, moduleKey)
    if not card then return end
    if not item then
        -- Physical HUD slots are pre-created, but the data model now contains
        -- only real cards. Hide unused slots without cloning/sanitizing empty
        -- placeholders every recommendation refresh. Drop the slot fingerprint
        -- so a later reappearance with the same spell still runs Apply().
        slotStates[key] = nil
        pcall(TacticalIconButton.SetVisible, TacticalIconButton, card, false)
        return
    end
    slotStates[key] = slotStates[key] or TacticalHudAnimator:NewSlotState()
    local fingerprintOK, fingerprint = pcall(buildCardFingerprint, item)
    if not fingerprintOK then fingerprint = "safe-slot:" .. safeFingerprintText(key, "unknown") end
    local urgent = key == "primary" or isUrgent(item)
    if TacticalHudAnimator:ShouldCommit(slotStates[key], fingerprint, urgent) then
        local ok = pcall(TacticalIconButton.Apply, TacticalIconButton, card, item, hud, moduleKey)
        if not ok then
            -- Fail-soft: a single icon cannot take the full HUD down.
            pcall(TacticalIconButton.SetVisible, TacticalIconButton, card, false)
            return
        end
    else
        -- Advisor snapshots already arrive at 0.20s. Native Cooldown/Animation
        -- frames advance themselves, so only unchanged visible cards receive
        -- this light update; no second Board OnUpdate polling loop is needed.
        pcall(TacticalIconButton.RefreshDynamic, TacticalIconButton, card, item)
    end
end

local function secretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function spellMatchesCard(castSpellID, item)
    castSpellID = tonumber(castSpellID)
    local cardSpellID = tonumber(item and item.spellID)
    if not castSpellID or not cardSpellID then return false end
    if secretValue(castSpellID) or secretValue(cardSpellID) then return false end
    if castSpellID == cardSpellID then return true end

    local resolver = TE.ActionBarBindingResolver
    if resolver and type(resolver.GetEquivalentSpellIDs) == "function" then
        local ok, ids = pcall(resolver.GetEquivalentSpellIDs, resolver, cardSpellID)
        if ok and type(ids) == "table" then
            for _, equivalentID in ipairs(ids) do
                if tonumber(equivalentID) == castSpellID then return true end
            end
        end
    end

    if type(FindBaseSpellByID) == "function" then
        local okCast, castBase = pcall(FindBaseSpellByID, castSpellID)
        local okCard, cardBase = pcall(FindBaseSpellByID, cardSpellID)
        if okCast and okCard and tonumber(castBase) and tonumber(castBase) == tonumber(cardBase) then return true end
    end
    return false
end

local function maybePlayCastFeedback(card, castSpellID)
    if not card or not card.item or card.item.hidden == true then return false end
    if type(card.IsVisible) == "function" and card:IsVisible() ~= true then return false end
    if not spellMatchesCard(castSpellID, card.item) then return false end
    local ok, played = pcall(TacticalIconButton.PlayCastFeedback, TacticalIconButton, card)
    return ok and played == true
end

function TacticalBoard:PlayCastFeedbackForSpell(spellID)
    if not spellID then return false end
    if maybePlayCastFeedback(nodes.primary, spellID) then return true end
    for _, card in ipairs(nodes.tactical and nodes.tactical.burst or {}) do
        if maybePlayCastFeedback(card, spellID) then return true end
    end
    return false
end

local function bindPrimaryDrag(card)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", function(self)
        self.tacticEchoDragging = true
        if not db().locked then board:StartMoving() end
    end)
    card:SetScript("OnDragStop", function(self)
        board:StopMovingOrSizing()
        savePoint(board)
        self.tacticEchoDragging = false
        self.tacticEchoSuppressClickUntil = (type(GetTime) == "function" and GetTime() or 0) + 0.15
    end)
    card:SetScript("OnMouseUp", function(self, button)
        if self.pushedTexture then self.pushedTexture:Hide() end
        if button == "RightButton" and TE.ControlPanel then TE.ControlPanel:Show("main") end
    end)
end

local function ensureBoard()
    if board then return board end
    board = CreateFrame("Frame", "TacticEchoTacticalBoard", UIParent, "BackdropTemplate")
    board:SetFrameStrata("MEDIUM")
    board:SetMovable(true)
    board:EnableMouse(true)
    board:SetClampedToScreen(true)
    createBackdrop(board)
    restorePoint(board)

    defenseFrame = CreateFrame("Frame", "TacticEchoDefenseBoard", board, "BackdropTemplate")
    defenseFrame:SetFrameStrata("MEDIUM")
    defenseFrame:SetMovable(true)
    defenseFrame:EnableMouse(true)
    defenseFrame:SetClampedToScreen(true)
    createBackdrop(defenseFrame)

    board.handle = TacticalHudDragHandle:Create(board,
        function() if not db().locked then board:StartMoving() end end,
        function() board:StopMovingOrSizing(); savePoint(board) end,
        function() if TE.ControlPanel then TE.ControlPanel:Show("general") end end,
        "主队列抓手")
    board.handle:SetPoint("LEFT", board, "LEFT", -18, 0)

    defenseFrame.handle = TacticalHudDragHandle:Create(defenseFrame,
        function() if not db().defenseLocked then defenseFrame:StartMoving() end end,
        function() defenseFrame:StopMovingOrSizing(); savePoint(defenseFrame, "defense") end,
        function() if TE.ControlPanel then TE.ControlPanel:Show("defense") end end,
        "防御队列抓手")
    defenseFrame.handle:SetPoint("LEFT", defenseFrame, "LEFT", -18, 0)

    nodes.primary = TacticalIconButton:Create(board, nil, 68, "main_toggle")
    bindPrimaryDrag(nodes.primary)
    nodes.candidates = {}
    for index = 1, 3 do nodes.candidates[index] = TacticalIconButton:Create(board, nil, 38, "none") end
    nodes.tactical = {
        interrupt = TacticalIconButton:Create(board, nil, 46, "manual_action"),
        burst = {},
        control = TacticalIconButton:Create(board, nil, 46, "manual_action"),
        mobility = TacticalIconButton:Create(board, nil, 46, "none"),
    }
    for index = 1, MAX_BURST_CARDS do
        nodes.tactical.burst[index] = TacticalIconButton:Create(board, nil, 46, "manual_action")
    end
    nodes.defense = {}
    for index = 1, 4 do nodes.defense[index] = TacticalIconButton:Create(defenseFrame, nil, 38, "manual_action") end

    -- Right-click navigation is intentionally visual-only.  It opens the
    -- matching settings page but never changes a recommendation, binding,
    -- token or TEAP frame.
    nodes.primary.settingsPage = "main"
    for _, card in ipairs(nodes.candidates) do card.settingsPage = "main" end
    nodes.tactical.interrupt.settingsPage = "interrupt"
    nodes.tactical.control.settingsPage = "interrupt"
    nodes.tactical.mobility.settingsPage = "interrupt"
    for _, card in ipairs(nodes.tactical.burst) do card.settingsPage = "burst" end
    for _, card in ipairs(nodes.defense) do card.settingsPage = "defense" end

    board.statusText = board:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    board.statusText:SetJustifyH("LEFT")
    board.statusText:SetTextColor(0.76, 0.84, 0.96)
    board.statusText:Hide()

    board:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and TE.ControlPanel then TE.ControlPanel:Show("general") end
    end)
    defenseFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and TE.ControlPanel then TE.ControlPanel:Show("general") end
    end)
    return board
end

local function renderInternal(self, snapshot)
    local panel = ensureBoard()
    local hud = db()
    if hud.enabled ~= true then applyFrameShown(panel, false); applyFrameShown(defenseFrame, false); return end

    local modelOK, model = pcall(TacticalHudModel.Build, TacticalHudModel, snapshot or {}, hud)
    if not modelOK or type(model) ~= "table" then
        -- Keep a small, recoverable primary slot visible rather than clearing the HUD.
        model = {
            primary = { spellName = "战术 HUD", hidden = false, kind = "primary", visual = { visualState = "unknown", label = "未知", reason = "HUD 数据模型不可用", alpha = 0.56, borderColor = { 0.60, 0.52, 0.78, 1 }, overlay = "unknown" } },
            candidates = {}, tactical = {}, defense = {}, meta = {}, fingerprint = "safe_model",
        }
        model.tactical = { burst = {} }
    end

    for _, item in ipairs(model.candidates or {}) do item.hidden = true end
    if model.tactical then
        if model.tactical.interrupt then model.tactical.interrupt.hidden = true end
        if model.tactical.control then model.tactical.control.hidden = true end
        if model.tactical.mobility then model.tactical.mobility.hidden = true end
        if hud.compact == true or hud.queueMode == "primary" then
            for _, item in ipairs(model.tactical.burst or {}) do item.hidden = true end
        end
    end
    for _, item in ipairs(model.defense or {}) do item.hidden = true end

    -- Per-module HUD switches affect only presentation.  They deliberately run
    -- after queue-mode filtering so queue policy remains independent from what
    -- the player chooses to see.
    if not moduleShown(hud, "main") then
        if model.primary then model.primary.hidden = true end
        for _, item in ipairs(model.candidates or {}) do item.hidden = true end
    end
    if not moduleShown(hud, "burst") and model.tactical then
        for _, item in ipairs(model.tactical.burst or {}) do item.hidden = true end
    end
    if not moduleShown(hud, "interrupt") and model.tactical then
        if model.tactical.interrupt then model.tactical.interrupt.hidden = true end
        if model.tactical.control then model.tactical.control.hidden = true end
        if model.tactical.mobility then model.tactical.mobility.hidden = true end
    end
    if not moduleShown(hud, "defense") then
        for _, item in ipairs(model.defense or {}) do item.hidden = true end
    end

    local primary = model.primary
    local outOfCombat = (snapshot and snapshot.context and plainBoolean(snapshot.context.inCombat) == false)
        or (snapshot and snapshot.primary and plainBoolean(snapshot.primary.inCombat) == false)
    if outOfCombat and hud.outOfCombatMode == "hide" then
        applyFrameShown(panel, false); applyFrameShown(defenseFrame, false); return
    end
    local function hasVisibleCard()
        if primary and primary.hidden ~= true and primary.spellID then return true end
        for _, item in ipairs(model.candidates or {}) do if item and item.hidden ~= true and item.spellID then return true end end
        local interrupt = model.tactical and model.tactical.interrupt
        if interrupt and interrupt.hidden ~= true and (interrupt.spellID or interrupt.itemID) then return true end
        for _, item in ipairs(model.tactical and model.tactical.burst or {}) do
            if item and item.hidden ~= true and (item.spellID or item.itemID) then return true end
        end
        local control = model.tactical and model.tactical.control
        if control and control.hidden ~= true and (control.spellID or control.itemID) then return true end
        local mobility = model.tactical and model.tactical.mobility
        if mobility and mobility.hidden ~= true and (mobility.spellID or mobility.itemID) then return true end
        for _, item in ipairs(model.defense or {}) do if item and item.hidden ~= true and (item.spellID or item.itemID) then return true end end
        return false
    end
    if hud.hideWhenIdle == true and not hasVisibleCard() then
        applyFrameShown(panel, false); applyFrameShown(defenseFrame, false); return
    end
    if not hasVisibleCard() then
        applyFrameShown(panel, false); applyFrameShown(defenseFrame, false); return
    end
    -- Global and out-of-combat presentation are separate. "dim" uses the
    -- user-controlled multipliers; "show" leaves the HUD exactly at its
    -- configured global size/opacity.
    local alpha = hud.alpha
    local scale = hud.scale
    local defenseAlpha = hud.defenseAlpha
    local defenseScale = hud.defenseScale
    if outOfCombat and hud.outOfCombatMode == "dim" then
        alpha = alpha * hud.outOfCombatAlpha
        scale = scale * hud.outOfCombatScale
        defenseAlpha = defenseAlpha * hud.outOfCombatAlpha
        defenseScale = defenseScale * hud.outOfCombatScale
    end

    applyCard("primary", nodes.primary, primary, hud, "main")
    for index, card in ipairs(nodes.candidates or {}) do
        applyCard("candidate:" .. index, card, (model.candidates or {})[index], hud, "main")
    end
    applyCard("tactical:interrupt", nodes.tactical.interrupt, model.tactical and model.tactical.interrupt, hud, "interrupt")
    for index, card in ipairs(nodes.tactical.burst or {}) do
        applyCard("tactical:burst:" .. index, card, (model.tactical and model.tactical.burst or {})[index], hud, "burst")
    end
    applyCard("tactical:control", nodes.tactical.control, model.tactical and model.tactical.control, hud, "interrupt")
    applyCard("tactical:mobility", nodes.tactical.mobility, model.tactical and model.tactical.mobility, hud, "interrupt")
    for index, card in ipairs(nodes.defense or {}) do
        applyCard("defense:" .. index, card, (model.defense or {})[index], hud, "defense")
    end

    board.statusText:SetText(statusText(primary))
    applyFrameShown(board.statusText, hud.showStatusText ~= false and primary and primary.hidden ~= true)
    TacticalHudLayout:Apply(board, defenseFrame, nodes, hud)
    -- TacticalHudLayout owns coordinates and base sizing. Apply effective
    -- combat-state presentation afterward so its internal layout cache never
    -- needs to re-anchor cards simply because alpha / scale changed.
    applyContainerPresentation(panel, alpha, scale)
    if hud.defenseDetached == true then
        applyContainerPresentation(defenseFrame, defenseAlpha, defenseScale)
    else
        applyContainerPresentation(defenseFrame, 1, 1)
    end

    local hasDefense = false
    for _, item in ipairs(model.defense) do if item and item.hidden ~= true then hasDefense = true; break end end
    applyFrameShown(defenseFrame, hasDefense)
    applyFrameShown(panel, true)
end

local function renderSafeFallback(message)
    local panel = ensureBoard()
    local hud = db()
    local item = {
        spellName = "战术 HUD",
        hidden = false,
        kind = "primary",
        binding = "",
        usableState = "unknown",
        visual = {
            visualState = "unknown", label = "未知", reason = "HUD 渲染安全模式：" .. safeFingerprintText(message, "未知错误"),
            alpha = 0.56, borderColor = { 0.60, 0.52, 0.78, 1 }, overlay = "unknown", glow = "none",
        },
    }
    pcall(TacticalIconButton.Apply, TacticalIconButton, nodes.primary, item, hud, "main")
    for _, card in ipairs(nodes.candidates or {}) do pcall(TacticalIconButton.SetVisible, TacticalIconButton, card, false) end
    pcall(TacticalIconButton.SetVisible, TacticalIconButton, nodes.tactical.interrupt, false)
    for _, card in ipairs(nodes.tactical.burst or {}) do pcall(TacticalIconButton.SetVisible, TacticalIconButton, card, false) end
    pcall(TacticalIconButton.SetVisible, TacticalIconButton, nodes.tactical.control, false)
    pcall(TacticalIconButton.SetVisible, TacticalIconButton, nodes.tactical.mobility, false)
    for _, card in ipairs(nodes.defense or {}) do pcall(TacticalIconButton.SetVisible, TacticalIconButton, card, false) end
    if board.statusText then
        board.statusText:SetText("HUD 安全模式")
        applyFrameShown(board.statusText, true)
    end
    applyFrameShown(defenseFrame, false)
    applyFrameShown(panel, true)
end

function TacticalBoard:Render(snapshot)
    local ok, result = pcall(renderInternal, self, snapshot)
    if ok then return result end
    self.lastRenderError = safeFingerprintText(result, "HUD 渲染异常")
    renderSafeFallback(self.lastRenderError)
end

function TacticalBoard:SetEnabled(value)
    db().enabled = value == true
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetLocked(value)
    db().locked = value == true
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetCompact(value)
    -- Compact keeps only primary + status; it never changes settings center state.
    db().compact = value == true
    local hud = db()
    if hud.compact then
        hud.layoutPreset = "queue_horizontal"
        hud.showHistory = false
    end
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetOrientation(value)
    local hud = db()
    hud.orientation = value == "vertical" and "vertical" or "horizontal"
    hud.layoutPreset = hud.orientation == "vertical" and "queue_vertical" or "queue_horizontal"
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetLayoutPreset(value)
    local hud = db()
    if ({ queue_horizontal = true, queue_vertical = true, surround = true })[value] then
        hud.layoutPreset = value
        hud.orientation = value == "queue_vertical" and "vertical" or "horizontal"
    end
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetDefenseDetached(value)
    db().defenseDetached = value == true
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetScale(value)
    db().scale = clamp(value, 0.60, 2.00)
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:SetAlpha(value)
    db().alpha = clamp(value, 0.20, 1.00)
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:ResetLayout()
    local hud = db()
    TacticalHudLayout:Reset(hud)
    restorePoint(board or ensureBoard())
    restorePoint(defenseFrame, "defense")
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:Toggle()
    self:SetEnabled(not db().enabled)
end

function TacticalBoard:Show()
    db().enabled = true
    self:Render(TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil)
end

function TacticalBoard:Hide()
    db().enabled = false
    applyFrameShown(board, false)
    applyFrameShown(defenseFrame, false)
end

-- No RegisterEvent calls in tactical HUD modules. Field testing found taint
-- chains on some clients. Snapshot subscription is read-only and guarded.
if TE.TacticalAdvisors and type(TE.TacticalAdvisors.Subscribe) == "function" then
    TE.TacticalAdvisors:Subscribe(function(snapshot)
        local ok = pcall(TacticalBoard.Render, TacticalBoard, snapshot)
        if not ok then return end
    end)
end

ensureBoard()

SLASH_TACTICECHOHUD1 = "/tehud"
SlashCmdList.TACTICECHOHUD = function(message)
    local command = string.lower(message or "")
    if command == "show" then TacticalBoard:Show()
    elseif command == "hide" then TacticalBoard:Hide()
    elseif command == "lock" then TacticalBoard:SetLocked(true)
    elseif command == "unlock" then TacticalBoard:SetLocked(false)
    elseif command == "compact" then TacticalBoard:SetCompact(not db().compact)
    elseif command == "vertical" then TacticalBoard:SetLayoutPreset("queue_vertical")
    elseif command == "horizontal" then TacticalBoard:SetLayoutPreset("queue_horizontal")
    elseif command == "surround" then TacticalBoard:SetLayoutPreset("surround")
    elseif command == "defense" then TacticalBoard:SetDefenseDetached(not db().defenseDetached)
    elseif command == "reset" then TacticalBoard:ResetLayout()
    elseif command == "settings" and TE.ControlPanel then TE.ControlPanel:Show("tactics", "layout")
    else TacticalBoard:Toggle() end
end
