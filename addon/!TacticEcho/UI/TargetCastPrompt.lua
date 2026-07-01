-- Compact target-frame / target-nameplate interruption cue. It is a visual
-- mirror of the read-only interrupt advisor and cannot request TEK input.
--
-- It intentionally does NOT inherit the interrupt HUD's "always visible"
-- mode. The prompt is reserved for an actionable, interruptible target cast.
local TE = _G.TacticEcho

local TargetCastPrompt = {}
TE.TargetCastPrompt = TargetCastPrompt

local frame
local lastSignature
local lastParent

local function settings()
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, _, hud = TE.Config.Normalize:All()
        return hud
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.hud = TacticEchoDB.tactics.hud or {}
    if TacticEchoDB.tactics.hud.showTargetPrompt == nil then TacticEchoDB.tactics.hud.showTargetPrompt = false end
    return TacticEchoDB.tactics.hud
end

local function hostFrame()
    if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if ok and plate then return plate end
    end
    return _G.TargetFrame or UIParent
end

local function create()
    if frame then return frame end
    frame = CreateFrame("Button", "TacticEchoTargetCastPrompt", UIParent, "BackdropTemplate")
    frame:SetSize(30, 30)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.02, 0.12, 0.90)
    frame:SetBackdropBorderColor(0.62, 0.38, 1, 1)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.key = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.key:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.key:SetTextColor(1, 1, 1)
    frame.key:SetShadowColor(0, 0, 0, 1)
    frame.key:SetShadowOffset(1, -1)
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    frame.label:SetText("打断")
    frame.label:SetTextColor(0.85, 0.70, 1)
    frame:SetScript("OnEnter", function(self)
        local item = self.payload or {}
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(item.spellName or "打断提示", 0.78, 0.65, 1)
        GameTooltip:AddLine("仅在当前目标可打断读条且技能可用时显示。", 1, 1, 1)
        GameTooltip:AddLine("目标读条：" .. tostring(item.castName or "无"), 1, 1, 1)
        GameTooltip:AddLine("建议键位：" .. tostring(item.binding or "无"), 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
    return frame
end

local function hide(prompt)
    lastSignature, lastParent = nil, nil
    prompt:Hide()
end

local function actionableInterrupt(interrupt)
    local item = interrupt and interrupt.suggestion or nil
    if not interrupt or interrupt.active ~= true then return nil end
    if not (interrupt.cast and interrupt.cast.active == true) then return nil end
    if interrupt.interruptible ~= true then return nil end
    if not item or not item.binding or item.unbound == true then return nil end
    -- The main advisor decorates this item after resolving its real action-bar
    -- binding. Suppress a prompt for a known cooldown/resource/range block.
    if item.usableState == "cooldown" or item.usableState == "resource" or item.usableState == "range"
        or item.usableState == "target" or item.usableState == "unavailable" then
        return nil
    end
    return item
end

function TargetCastPrompt:Refresh()
    -- When disabled, do not create the prompt or own an independent OnUpdate.
    -- TacticalAdvisors publishes at its existing cadence and invokes this
    -- presentation mirror only when a fresh advisory snapshot exists.
    if settings().showTargetPrompt ~= true then
        if frame then hide(frame) end
        return
    end
    local prompt = create()
    local data = TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil
    local interrupt = data and data.interrupt or nil
    local item = actionableInterrupt(interrupt)
    if not item then hide(prompt); return end

    local parent = hostFrame()
    local signature = table.concat({ tostring(item.spellID or ""), tostring(item.binding or ""), tostring((interrupt.cast or {}).name or "") }, "|")
    if prompt:GetParent() ~= parent then prompt:SetParent(parent) end
    if lastSignature ~= signature or lastParent ~= parent then
        prompt:ClearAllPoints()
        prompt:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 8, 10)
        prompt.payload = item
        prompt.payload.castName = interrupt.cast and interrupt.cast.name
        prompt.icon:SetTexture(item.spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        prompt.key:SetText(item.binding or "")
        lastSignature, lastParent = signature, parent
    end
    prompt:Show()
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, { "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED" })
watcher:SetScript("OnEvent", function() TargetCastPrompt:Refresh() end)

-- Reuse the existing advisors publisher instead of keeping a second 10 Hz loop.
if TE.TacticalAdvisors and type(TE.TacticalAdvisors.Subscribe) == "function" then
    TE.TacticalAdvisors:Subscribe(function() TargetCastPrompt:Refresh() end)
end
