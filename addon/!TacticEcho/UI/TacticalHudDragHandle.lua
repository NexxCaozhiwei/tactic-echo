-- Dedicated draggable grip for a tactical HUD container.
local TE = _G.TacticEcho

local TacticalHudDragHandle = {}
TE.TacticalHudDragHandle = TacticalHudDragHandle

local function showTip(owner, title, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:SetText(title, 0.80, 0.92, 1)
    for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
end

function TacticalHudDragHandle:Create(parent, onStart, onStop, onSettings, label)
    local handle = CreateFrame("Button", nil, parent)
    handle:SetSize(16, 40)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() if onStart then onStart() end end)
    handle:SetScript("OnDragStop", function() if onStop then onStop() end end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and onSettings then onSettings() end
    end)
    local dots = {}
    for row = 1, 4 do
        for column = 1, 2 do
            local dot = handle:CreateTexture(nil, "OVERLAY")
            dot:SetSize(2, 2)
            dot:SetPoint("CENTER", handle, "CENTER", (column - 1.5) * 5, (row - 2.5) * 6)
            dot:SetColorTexture(0.62, 0.76, 0.92, 0.78)
            dots[#dots + 1] = dot
        end
    end
    handle:SetScript("OnEnter", function(self)
        showTip(self, label or "HUD 抓手", { "左键拖动位置", "右键打开 HUD 布局设置" })
    end)
    handle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return handle
end
