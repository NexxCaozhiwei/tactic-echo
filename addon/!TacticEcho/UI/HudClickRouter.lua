-- Tactic Echo P5.8 HUD manual-click router.
--
-- A tactical HUD icon is normally presentation-only. P5.8 adds a deliberately
-- narrow manual entry: the icon may proxy one already-visible Blizzard default
-- action button (direct spell/item button or a resolver-recognized macro). The
-- proxy has no generated key binding, never edits a macro, and never
-- invokes an action-bar button programmatically. WoW executes the existing action only from the user's
-- physical left click on this SecureActionButtonTemplate.
local TE = _G.TacticEcho

local HudClickRouter = {}
TE.HudClickRouter = HudClickRouter

HudClickRouter.schemaVersion = 1
HudClickRouter.cards = setmetatable({}, { __mode = "k" })

local REASON_TEXT = {
    manual_actionbar_source_missing = "未找到可复用的当前可见默认动作条来源",
    manual_actionbar_button_missing = "已识别来源对应的动作条按钮不存在",
    manual_actionbar_button_hidden = "对应动作条按钮当前不可见",
    manual_actionbar_special_actionbar = "特殊动作条期间禁止复用 HUD 点击",
    manual_actionbar_resolver_unavailable = "动作条识别器尚未就绪",
    manual_actionbar_rebind_out_of_combat = "动作条来源已变化，需要脱战后重建 HUD 点击映射",
    manual_actionbar_source_changed = "该 HUD 图标原动作条来源已变化，需要脱战后重新识别",
    manual_macro_identity_unverified = "该宏的当前动作条身份无法唯一确认，HUD 点击已阻止",
    hud_card_hidden = "该 HUD 图标当前未显示",
}

local function inCombatLockdown()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    value = ok and tonumber(value) or nil
    return value and value >= 0 and value or 0
end

local function safeText(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback or "未知原因"
end

local function callCardScript(card, script, ...)
    if not card or type(card.GetScript) ~= "function" then return end
    local handler = card:GetScript(script)
    if type(handler) == "function" then pcall(handler, card, ...) end
end

local function setCardState(card, ready, reason, source)
    if not card then return end
    card.manualClickReady = ready == true
    card.manualClickReason = reason
    card.manualClickReasonText = REASON_TEXT[reason] or safeText(reason, "HUD 点击当前不可用")
    card.manualClickSource = source
end

local function hideLayerFrame(frame, secure)
    if not frame then return end
    if secure == true and inCombatLockdown() then
        if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
        return
    end
    if frame.Hide then pcall(frame.Hide, frame) end
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
end

local function showLayerFrame(frame, secure)
    if not frame then return end
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
    if secure == true and inCombatLockdown() and frame.IsShown and not frame:IsShown() then return end
    if frame.Show then pcall(frame.Show, frame) end
end

local function hideInputLayer(layer)
    if not layer then return end
    if inCombatLockdown() then
        -- SecureActionButtonTemplate visibility is protected in combat. Keep the
        -- old proxy untouched and cover it with the non-secure blocker so stale
        -- mappings fail closed until the next out-of-combat refresh can hide it.
        hideLayerFrame(layer.proxy, true)
        showLayerFrame(layer.blocker, false)
        return
    end
    hideLayerFrame(layer.proxy, true)
    hideLayerFrame(layer.blocker, false)
end

local function reportBlocked(card)
    if not card then return end
    local timestamp = now()
    if timestamp - (tonumber(card.manualClickLastNoticeAt) or 0) < 0.9 then return end
    card.manualClickLastNoticeAt = timestamp
    local message = "Tactic Echo HUD：" .. safeText(card.manualClickReasonText, "当前技能没有可靠的动作条来源，不能执行。")
    if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        UIErrorsFrame:AddMessage(message, 1, 0.30, 0.25, 1.0)
    elseif TE and type(TE.Print) == "function" then
        TE:Print(message)
    end
end

local function targetSignature(target)
    return table.concat({
        tostring(target and target.buttonName or "none"),
        tostring(target and target.actionSlot or 0),
        tostring(target and target.source or "unknown"),
        tostring(target and target.inventorySlot or 0),
        tostring(target and target.itemID or 0),
    }, ":")
end

local function itemSignature(item)
    item = type(item) == "table" and item or {}
    local bindingInfo = type(item.bindingInfo) == "table" and item.bindingInfo or {}
    local buttonName = item.buttonName or bindingInfo.buttonName
    local actionSlot = item.actionSlot or item.slot or bindingInfo.actionSlot or bindingInfo.slot
    local source = item.source or item.bindingSource or bindingInfo.source
    local macroID = item.macroID or bindingInfo.macroID
    local macroDiagnostic = type(item.macroDiagnostic) == "table" and item.macroDiagnostic
        or (type(bindingInfo.macroDiagnostic) == "table" and bindingInfo.macroDiagnostic or {})
    return table.concat({
        tostring(tonumber(item.spellID) or 0),
        tostring(tonumber(item.itemID) or 0),
        tostring(tonumber(item.inventorySlot or item.itemSlot) or 0),
        tostring(buttonName or ""),
        tostring(tonumber(actionSlot) or 0),
        tostring(source or ""),
        tostring(tonumber(macroID) or 0),
        tostring(macroDiagnostic.macroIdentityVerified == true),
        tostring(item.hidden == true), tostring(item.empty == true),
    }, ":")
end

local function clearSecureTarget(proxy)
    if not proxy or inCombatLockdown() then return false end
    proxy:SetAttribute("type", nil)
    proxy:SetAttribute("clickbutton", nil)
    proxy:SetAttribute("type1", nil)
    proxy:SetAttribute("clickbutton1", nil)
    proxy.tacticEchoTarget = nil
    proxy.tacticEchoSignature = nil
    return true
end

local function configureSecureTarget(proxy, target, signature)
    if not proxy or not target or not target.button or inCombatLockdown() then return false end
    -- `click` delegates to the original secure Blizzard button. No spell/item
    -- attributes are synthesized here, so the macro/action target semantics
    -- remain exactly those of the action-bar button the player already owns.
    proxy:SetAttribute("type", "click")
    proxy:SetAttribute("clickbutton", target.button)
    proxy:SetAttribute("type1", "click")
    proxy:SetAttribute("clickbutton1", target.button)
    proxy.tacticEchoTarget = target.button
    proxy.tacticEchoSignature = signature
    return true
end

local function resolveTarget(item)
    local resolver = TE.ActionBarBindingResolver
    if not (resolver and type(resolver.ResolveManualHudAction) == "function") then
        return { status = "Blocked", reason = "manual_actionbar_resolver_unavailable" }
    end
    local ok, target = pcall(resolver.ResolveManualHudAction, resolver, item)
    if not ok or type(target) ~= "table" then
        return { status = "Blocked", reason = "manual_actionbar_source_missing" }
    end
    return target
end

function HudClickRouter:Attach(card)
    if not card or card.hudInteractionRole ~= "manual_action" or self.cards[card] then return end

    -- Keep secure frames as UIParent siblings. They never become children of a
    -- dynamic HUD card, which avoids making HUD layout/animation a protected
    -- action path. Their geometry is established once at normal UI creation.
    local proxy = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    -- This is a UIParent sibling by design, but it must be above the card's
    -- presentation strata. Register both physical edges so the proxy follows
    -- the user's ActionButtonUseKeyDown client preference instead of silently
    -- failing on clients that execute default action buttons on mouse-down.
    proxy:SetFrameStrata("HIGH")
    proxy:SetFrameLevel(1)
    if type(proxy.SetToplevel) == "function" then proxy:SetToplevel(true) end
    proxy:SetAllPoints(card)
    proxy:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    proxy:EnableMouse(true)
    clearSecureTarget(proxy)
    proxy:Hide()

    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetFrameStrata("HIGH")
    blocker:SetFrameLevel(2)
    if type(blocker.SetToplevel) == "function" then blocker:SetToplevel(true) end
    blocker:SetAllPoints(card)
    blocker:EnableMouse(true)
    if type(blocker.RegisterForClicks) == "function" then blocker:RegisterForClicks("AnyDown", "AnyUp") end
    blocker:Hide()

    local layer = { proxy = proxy, blocker = blocker, dirty = true, visible = false }
    self.cards[card] = layer
    card.hudClickLayer = layer
    setCardState(card, false, "manual_actionbar_source_missing", nil)

    proxy:SetScript("OnEnter", function() callCardScript(card, "OnEnter") end)
    proxy:SetScript("OnLeave", function() callCardScript(card, "OnLeave") end)
    proxy:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and TE.ManualActionPriority and type(TE.ManualActionPriority.Begin) == "function" then
            TE.ManualActionPriority:Begin("hud", proxy.tacticEchoButtonName or "hud_action")
        end
        callCardScript(card, "OnMouseDown", button)
    end)
    proxy:SetScript("OnMouseUp", function(_, button) callCardScript(card, "OnMouseUp", button) end)

    blocker:SetScript("OnEnter", function() callCardScript(card, "OnEnter") end)
    blocker:SetScript("OnLeave", function() callCardScript(card, "OnLeave") end)
    blocker:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then reportBlocked(card) end
        callCardScript(card, "OnMouseDown", button)
    end)
    blocker:SetScript("OnMouseUp", function(_, button) callCardScript(card, "OnMouseUp", button) end)
    blocker:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then reportBlocked(card) end
    end)
end

function HudClickRouter:SetCardVisible(card, visible)
    local layer = card and self.cards[card]
    if not layer then return end
    visible = visible == true
    if layer.visible ~= visible then layer.dirty = true end
    layer.visible = visible
    if not visible then
        -- Out of combat, hide both sibling layers with the card. In combat,
        -- protect against stale secure clicks by leaving the blocker over any
        -- still-shown proxy until secure visibility can be changed safely.
        hideInputLayer(layer)
        setCardState(card, false, "hud_card_hidden", nil)
    else
        -- Until Configure resolves an exact current source, the blocker owns
        -- the visible surface and reports why this HUD icon cannot execute.
        showLayerFrame(layer.proxy, true)
        showLayerFrame(layer.blocker, false)
    end
end

function HudClickRouter:Configure(card, item, visible)
    local layer = card and self.cards[card]
    if not layer then return end
    visible = visible == true
    local signature = itemSignature(item)
    if layer.visible ~= visible then layer.dirty = true end
    layer.visible = visible
    if not visible then
        hideInputLayer(layer)
        setCardState(card, false, "hud_card_hidden", nil)
        return
    end
    showLayerFrame(layer.proxy, true)
    if layer.dirty ~= true and layer.itemSignature == signature then return end

    local target = resolveTarget(item)
    layer.itemSignature = signature
    layer.dirty = false
    if target.status ~= "Ready" then
        if not inCombatLockdown() then clearSecureTarget(layer.proxy) end
        showLayerFrame(layer.blocker, false)
        setCardState(card, false, target.reason or "manual_actionbar_source_missing", nil)
        return
    end

    local mappedSignature = targetSignature(target)
    if inCombatLockdown() then
        -- Attributes cannot be retargeted in combat. Existing exact mappings
        -- remain usable; every mismatch is covered by the blocker until the
        -- player leaves combat, rather than risking a click on a prior button.
        if layer.proxy.tacticEchoSignature == mappedSignature and layer.proxy.tacticEchoTarget == target.button then
            layer.proxy.tacticEchoButtonName = target.buttonName
            hideLayerFrame(layer.blocker, false)
            setCardState(card, true, nil, target)
        else
            showLayerFrame(layer.blocker, false)
            setCardState(card, false, "manual_actionbar_rebind_out_of_combat", nil)
        end
        return
    end

    if configureSecureTarget(layer.proxy, target, mappedSignature) then
        layer.proxy.tacticEchoButtonName = target.buttonName
        hideLayerFrame(layer.blocker, false)
        setCardState(card, true, nil, target)
    else
        showLayerFrame(layer.blocker, false)
        setCardState(card, false, "manual_actionbar_source_missing", nil)
    end
end

function HudClickRouter:InvalidateMappings(reason)
    for card, layer in pairs(self.cards) do
        if card and layer then
            layer.dirty = true
            layer.invalidateReason = reason or "actionbar_invalidated"
        end
    end
end
