-- Tactic Echo settings center (TEUI v2).
-- The four current pages cover runtime, HUD, AutoBurst and profiles. This file
-- only changes settings/presentation and never creates a recommendation,
-- BindingToken, TEAP frame or TEK input request.
local TE = _G.TacticEcho

local ControlPanel = {}
TE.ControlPanel = ControlPanel

local frame
local normalHeader
local normalNavigation
local normalMain
local normalFooter
local compactView
local activePage = "general"
local panes = {}
local profilesAdvancedExpanded = false
local navButtons = {}
local labels = {}
local controls = {}
local controlBuildScope
local profileNameBox
local elapsedSinceRefresh = 0
local hotkeyOwner
local hotkeyCapture
local pendingToggleHotkey
local pendingApplyAfterCombat = false
local autoBurstHotkeyOwner
local autoBurstHotkeyCapture
local pendingAutoBurstHotkey
local pendingAutoBurstApplyAfterCombat = false
local pendingCompactPositionSave = false
local compactToggleButton

local PANEL_WIDTH = 1080
local PANEL_HEIGHT = 710
local NAV_WIDTH = 224
local COMPACT_WIDTH = 280
local COMPACT_HEIGHT = 38
local REFRESH_INTERVAL = 0.25

-- The settings pages use a fixed two-column grid.  The original TEUI v2
-- controls still used the old 672px layout coordinates after the panel was
-- widened, so wide left-column selectors physically overlapped the right
-- column.  Keep every page inside this explicit scroll-child width.
local CONTENT_PANE_WIDTH = 720
local CONTENT_PANE_HEIGHT = 3200
local CONTENT_MARGIN = 14
local LEFT_X = 14
local RIGHT_X = 376
local COLUMN_GUTTER = 18
local CONTROL_LABEL_WIDTH = 126
local CONTROL_GAP = 8

local PAGE_META = {
    general = { label = "常规", description = "运行状态、手动启停 / 脱战策略与 Tactic Echo 自身快捷键。" },
    hud = { label = "HUD", description = "主键与自动爆发队列的显示、大小、方向和常用外观。" },
    burst = { label = "自动爆发", description = "自动爆发开关、执行模式、当前专精顺序与技能列表。" },
    profiles = { label = "配置文件", description = "保存、载入和管理配置；范围自动切换位于高级设置。" },
}

local NAV_ORDER = { "general", "hud", "burst", "profiles" }
local LEGACY_PAGE_ALIAS = {
    main = "hud", tactics = "hud", interrupt = "hud", control = "hud",
    defense = "hud", defensive = "hud", actionbar = "general",
    safety = "general", monitor = "general", debug = "general",
}
PAGE_META.hud.description = "主键与自动爆发 HUD 的显示、图标大小、队列模式、标签和布局。"

local COLOR_PRESETS = {
    white = { label = "白色", color = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 } },
    yellow = { label = "金色", color = { r = 1.00, g = 0.82, b = 0.16, a = 1.00 } },
    cyan = { label = "青色", color = { r = 0.25, g = 0.90, b = 1.00, a = 1.00 } },
    green = { label = "绿色", color = { r = 0.45, g = 1.00, b = 0.55, a = 1.00 } },
    orange = { label = "橙色", color = { r = 1.00, g = 0.48, b = 0.16, a = 1.00 } },
    red = { label = "红色", color = { r = 1.00, g = 0.28, b = 0.28, a = 1.00 } },
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function copyColor(value, fallback)
    value = type(value) == "table" and value or fallback or COLOR_PRESETS.white.color
    return {
        r = clamp(value.r or value[1], 0, 1),
        g = clamp(value.g or value[2], 0, 1),
        b = clamp(value.b or value[3], 0, 1),
        a = clamp(value.a or value[4], 0, 1),
    }
end

local function colorKey(value)
    value = copyColor(value)
    local best, bestDistance = "white", math.huge
    for key, preset in pairs(COLOR_PRESETS) do
        local c = preset.color
        local distance = math.abs(value.r - c.r) + math.abs(value.g - c.g) + math.abs(value.b - c.b) + math.abs(value.a - c.a)
        if distance < bestDistance then best, bestDistance = key, distance end
    end
    return best
end

local function root()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.ui = type(TacticEchoDB.ui) == "table" and TacticEchoDB.ui or {}
    TacticEchoDB.ui.settingsCenter = type(TacticEchoDB.ui.settingsCenter) == "table" and TacticEchoDB.ui.settingsCenter or {}
    local store = TacticEchoDB.ui.settingsCenter
    if TacticEchoDB.ui.settingsCenter.minimized == nil then TacticEchoDB.ui.settingsCenter.minimized = false end
    store.burstSubpage = nil
    store.compact = type(store.compact) == "table" and store.compact or {}
    return store
end

local function ensureSettings()
    -- Config/Normalize.lua is the only persisted-settings default owner. This
    -- emergency path creates just the container and intentionally does not
    -- normalize fields a second time with UI-specific values.
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local settings = select(1, TE.Config.Normalize:All())
        return settings
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.settings = type(TacticEchoDB.settings) == "table" and TacticEchoDB.settings or {}
    return TacticEchoDB.settings
end

local function ensureTextStyle(style, defaults)
    style = type(style) == "table" and style or {}
    defaults = defaults or {}
    if style.enabled == nil then style.enabled = defaults.enabled ~= false end
    style.fontPreset = ({ normal = true, highlight = true, disable = true })[style.fontPreset] and style.fontPreset or (defaults.fontPreset or "normal")
    style.fontSize = clamp(style.fontSize, 8, 30)
    style.scale = clamp(style.scale, 0.60, 2.00)
    style.point = ({ TOPLEFT = true, TOPRIGHT = true, CENTER = true, BOTTOMLEFT = true, BOTTOMRIGHT = true })[style.point]
        and style.point or (defaults.point or "TOPRIGHT")
    style.offsetX = tonumber(style.offsetX) or (defaults.offsetX or -3)
    style.offsetY = tonumber(style.offsetY) or (defaults.offsetY or -3)
    if defaults.mode ~= nil or style.mode ~= nil then
        -- Native DurationObject digits are no longer selectable: the HUD owns
        -- all CD text so its font, anchor and integer-seconds format stay
        -- consistent across burst, interrupt and defense cards.
        style.mode = "custom"
    end
    style.color = copyColor(style.color, defaults.color or COLOR_PRESETS.white.color)
    style.colorKey = COLOR_PRESETS[style.colorKey] and style.colorKey or colorKey(style.color)
    return style
end

local function ensureModuleStyle(hud, key)
    hud.modules = type(hud.modules) == "table" and hud.modules or {}
    local module = type(hud.modules[key]) == "table" and hud.modules[key] or {}
    local mainLegacy = key == "main" and type(hud.keyLabel) == "table" and hud.keyLabel or nil
    module.keyLabel = ensureTextStyle(module.keyLabel or mainLegacy, {
        enabled = true, fontPreset = "normal", fontSize = 12, scale = 1,
        point = "TOPRIGHT", offsetX = -3, offsetY = -3, color = COLOR_PRESETS.white.color,
    })
    module.chargeLabel = ensureTextStyle(module.chargeLabel, {
        enabled = true, fontPreset = "normal", fontSize = 12, scale = 1,
        point = "BOTTOMRIGHT", offsetX = -3, offsetY = 3, color = COLOR_PRESETS.white.color,
    })
    module.cooldownText = ensureTextStyle(module.cooldownText, {
        enabled = true, mode = "custom", fontPreset = "highlight", fontSize = 14, scale = 1,
        point = "CENTER", offsetX = 0, offsetY = 0, color = COLOR_PRESETS.white.color,
    })
    module.stateText = ensureTextStyle(module.stateText, {
        enabled = true, fontPreset = "normal", fontSize = 11, scale = 1,
        point = "BOTTOMLEFT", offsetX = 3, offsetY = 3, color = COLOR_PRESETS.white.color,
    })
    module.cooldownSwipe = type(module.cooldownSwipe) == "table" and module.cooldownSwipe or {}
    if module.cooldownSwipe.enabled == nil then module.cooldownSwipe.enabled = true end
    module.cooldownSwipe.alpha = clamp(module.cooldownSwipe.alpha, 0, 0.95)
    if module.cooldownSwipe.alpha == 0 then module.cooldownSwipe.alpha = 0.55 end
    if module.cooldownSwipe.reverse == nil then module.cooldownSwipe.reverse = false end

    module.gcdSwipe = type(module.gcdSwipe) == "table" and module.gcdSwipe or {}
    if module.gcdSwipe.enabled == nil then module.gcdSwipe.enabled = true end
    module.gcdSwipe.alpha = clamp(module.gcdSwipe.alpha, 0, 0.95)
    if module.gcdSwipe.alpha == 0 then module.gcdSwipe.alpha = 0.38 end
    if module.gcdSwipe.reverse == nil then module.gcdSwipe.reverse = module.cooldownSwipe.reverse == true end

    module.highlight = type(module.highlight) == "table" and module.highlight or {}
    if module.highlight.enabled == nil then module.highlight.enabled = true end
    if module.highlight.proc == nil then module.highlight.proc = true end
    if module.highlight.emergency == nil then module.highlight.emergency = true end
    module.effects = type(module.effects) == "table" and module.effects or {}
    if module.effects.enabled == nil then module.effects.enabled = true end
    if module.effects.marching == nil then module.effects.marching = true end
    if module.effects.proc == nil then module.effects.proc = true end
    if module.effects.interrupt == nil then module.effects.interrupt = true end
    if module.effects.burst == nil then module.effects.burst = true end
    if module.effects.mobility == nil then module.effects.mobility = true end
    if module.effects.hotkeyFlash == nil then module.effects.hotkeyFlash = true end
    if module.effects.channelFill == nil then module.effects.channelFill = true end

    -- Module visibility is strictly presentation-only.  It never disables the
    -- underlying advisory planner, primary recommendation, or binding scan.
    if module.show == nil then module.show = true end
    local fallbackSize = key == "main" and hud.primarySize
        or (key == "defense" and hud.defenseSize or hud.tacticalSize)
    local minimum = key == "main" and 44 or 28
    local maximum = key == "main" and 120 or 88
    module.iconSize = math.floor(clamp(module.iconSize or fallbackSize, minimum, maximum))

    hud.modules[key] = module
    if key == "main" then hud.keyLabel = module.keyLabel end -- 0.7.6 compatibility.
    return module
end

local function ensureTactics()
    -- Config/Normalize.lua supplies the one canonical tactical/HUD schema.
    -- Keeping this fallback container-only prevents load order from creating a
    -- second, conflicting default map inside the settings UI.
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, tactics, hud = TE.Config.Normalize:All()
        return tactics, hud
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    TacticEchoDB.tactics.hud = type(TacticEchoDB.tactics.hud) == "table" and TacticEchoDB.tactics.hud or {}
    return TacticEchoDB.tactics, TacticEchoDB.tactics.hud
end

-- 兼容说明：规范器仍维护 hud.keyLabel.fontSize、hud.keyLabel.point 这一旧字段的迁移映射；
-- 新界面统一通过 ensureModuleStyle(hud, "main")、ensureModuleStyle(hud, "burst")、
-- ensureModuleStyle(hud, "interrupt") 与 ensureModuleStyle(hud, "defense") 访问模块样式。

local function getModuleStyle(key)
    local _, hud = ensureTactics()
    return ensureModuleStyle(hud, key)
end

local function setModuleIconSize(key, value)
    local _, hud = ensureTactics()
    local style = ensureModuleStyle(hud, key)
    local minimum = key == "main" and 44 or 28
    local maximum = key == "main" and 120 or 88
    value = math.floor(clamp(value, minimum, maximum))
    style.iconSize = value
    -- Retain legacy aggregate values for profiles and older diagnostics.  The
    -- layout renderer reads the module values first, then these fallbacks.
    if key == "main" then
        hud.primarySize = value
    elseif key == "defense" then
        hud.defenseSize = value
    elseif key == "burst" or key == "interrupt" then
        hud.tacticalSize = value
    end
end

local function panelBackdrop(target, r, g, b, a, br, bg, bb, ba)
    if not target or not target.SetBackdrop then return end
    target:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    target:SetBackdropColor(r or 0.015, g or 0.02, b or 0.035, a or 0.94)
    target:SetBackdropBorderColor(br or 0.18, bg or 0.28, bb or 0.40, ba or 1)
end

local function setButtonVisual(button, active)
    if not button or not button.SetBackdropColor then return end
    if active then
        button:SetBackdropColor(0.11, 0.20, 0.36, 1)
        button:SetBackdropBorderColor(0.98, 0.76, 0.22, 1)
        if button.text then button.text:SetTextColor(1.00, 0.90, 0.36) end
    else
        button:SetBackdropColor(0.025, 0.035, 0.06, 0.92)
        button:SetBackdropBorderColor(0.16, 0.22, 0.32, 0.95)
        if button.text then button.text:SetTextColor(0.90, 0.92, 0.96) end
    end
end

local function fullWidth(x, desired)
    return math.max(40, math.min(tonumber(desired) or (CONTENT_PANE_WIDTH - x - CONTENT_MARGIN), CONTENT_PANE_WIDTH - x - CONTENT_MARGIN))
end

local function columnEnd(x)
    if (tonumber(x) or 0) >= RIGHT_X - 8 then
        return CONTENT_PANE_WIDTH - CONTENT_MARGIN
    end
    return RIGHT_X - COLUMN_GUTTER
end

local function controlWidth(x, desired)
    local available = columnEnd(x) - x - CONTROL_LABEL_WIDTH - CONTROL_GAP
    return math.max(72, math.min(tonumber(desired) or 170, available))
end

local function createText(parent, template, x, y, width, text)
    local value = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    x = tonumber(x) or CONTENT_MARGIN
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y or -14)
    value:SetWidth(fullWidth(x, width))
    value:SetJustifyH("LEFT")
    value:SetWordWrap(true)
    if text then value:SetText(text) end
    return value
end

local function createLine(parent, x, y, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.38, 0.42, 0.50, 0.65)
    x = tonumber(x) or CONTENT_MARGIN
    line:SetSize(fullWidth(x, width), 1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y or -14)
    return line
end

local function createSection(parent, title, y)
    local text = createText(parent, "GameFontNormalLarge", CONTENT_MARGIN, y, CONTENT_PANE_WIDTH - CONTENT_MARGIN * 2, title)
    text:SetTextColor(0.90, 0.94, 1.00)
    createLine(parent, CONTENT_MARGIN, y - 28, CONTENT_PANE_WIDTH - CONTENT_MARGIN * 2)
    return y - 44
end

local function createActionButton(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 116, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    panelBackdrop(button, 0.025, 0.035, 0.06, 0.92, 0.16, 0.22, 0.32, 0.95)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetWidth((width or 116) - 8)
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text or "按钮")
    button:SetScript("OnEnter", function(self) setButtonVisual(self, true) end)
    button:SetScript("OnLeave", function(self) setButtonVisual(self, self.selected == true) end)
    button:SetScript("OnClick", function() if callback then callback() end end)
    setButtonVisual(button, false)
    return button
end

local function registerControl(refresh)
    controls[#controls + 1] = { refresh = refresh, scope = controlBuildScope }
end

local function refreshControls(scope)
    for _, entry in ipairs(controls) do
        if type(entry) == "table" and type(entry.refresh) == "function"
            and (entry.scope == nil or entry.scope == scope) then
            pcall(entry.refresh)
        end
    end
end

local function createCheckbox(parent, text, x, y, getter, setter, tooltipText)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local labelWidth = math.max(120, columnEnd(x) - (x + 30))
    check.label = createText(parent, "GameFontHighlight", x + 30, y - 4, labelWidth, text)
    if tooltipText then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 0.80, 0.92, 1)
            GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local function refresh()
        local ok, value = pcall(getter)
        check:SetChecked(ok and value == true)
    end
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true)
        refresh()
        ControlPanel:ApplyVisuals(false)
    end)
    registerControl(refresh)
    refresh()
    return check
end

local function createChoice(parent, label, x, y, width, choices, getter, setter)
    local caption = createText(parent, "GameFontHighlight", x, y - 4, CONTROL_LABEL_WIDTH, label)
    local buttonWidth = controlWidth(x, width)
    local button = createActionButton(parent, "", x + CONTROL_LABEL_WIDTH + CONTROL_GAP, y, buttonWidth, function()
        local current = getter()
        local index = 1
        for candidateIndex, candidate in ipairs(choices) do
            if candidate.value == current then index = candidateIndex; break end
        end
        index = (index % #choices) + 1
        setter(choices[index].value)
        ControlPanel:ApplyVisuals(false)
    end)
    local function refresh()
        local current = getter()
        local shown = tostring(current or "-")
        for _, candidate in ipairs(choices) do
            if candidate.value == current then shown = candidate.label; break end
        end
        button.text:SetText(shown)
    end
    registerControl(refresh)
    refresh()
    return button, caption
end

local function createColorChoice(parent, label, x, y, getter, setter)
    local choices = {}
    for key, preset in pairs(COLOR_PRESETS) do
        choices[#choices + 1] = { value = key, label = preset.label }
    end
    table.sort(choices, function(left, right) return left.label < right.label end)
    return createChoice(parent, label, x, y, 150, choices, getter, setter)
end

local function cycleNumber(value, step, minimum, maximum)
    value = (tonumber(value) or minimum) + step
    if value > maximum then value = minimum end
    if value < minimum then value = maximum end
    return value
end

local function createNumberStepper(parent, label, x, y, width, getter, setter, step, minimum, maximum, suffix)
    createText(parent, "GameFontHighlight", x, y - 4, CONTROL_LABEL_WIDTH, label)
    local valueWidth = math.max(38, math.min(tonumber(width) or 56, 64))
    local minusX = x + CONTROL_LABEL_WIDTH + CONTROL_GAP
    local minus = createActionButton(parent, "-", minusX, y, 28, function()
        setter(cycleNumber(getter(), -(step or 1), minimum or 0, maximum or 100))
        ControlPanel:ApplyVisuals(false)
    end)
    local valueText = createText(parent, "GameFontHighlightSmall", minusX + 36, y - 5, valueWidth, "")
    local plus = createActionButton(parent, "+", minusX + 44 + valueWidth, y, 28, function()
        setter(cycleNumber(getter(), step or 1, minimum or 0, maximum or 100))
        ControlPanel:ApplyVisuals(false)
    end)
    local function refresh()
        valueText:SetText(tostring(getter() or "-") .. (suffix or ""))
    end
    registerControl(refresh)
    refresh()
    return minus, plus
end

local function createReadout(parent, key, title, x, y, width, template)
    local resolvedWidth = width or (CONTENT_PANE_WIDTH - CONTENT_MARGIN * 2)
    local caption = createText(parent, "GameFontHighlight", x, y, resolvedWidth, title)
    local value = createText(parent, template or "GameFontHighlightSmall", x, y - 24, resolvedWidth, "等待刷新")
    -- Runtime diagnostics are allowed to wrap, so reserve two text lines by
    -- default. Builders place the next section after this fixed readable block.
    value:SetHeight(38)
    labels[key] = value
    return caption, value
end

local function setLabel(key, value)
    if labels[key] then labels[key]:SetText(value or "-") end
end

local function createEditBox(parent, label, x, y, width, initialText)
    createText(parent, "GameFontHighlight", x, y - 4, CONTROL_LABEL_WIDTH, label)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(controlWidth(x, width), 24)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + CONTROL_LABEL_WIDTH + CONTROL_GAP, y + 1)
    box:SetText(initialText or "")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function panelSpellInfo(spellID)
    spellID = tonumber(spellID)
    if not spellID then return tostring(spellID or "-"), nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name or tostring(spellID), info.iconID or info.icon end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok and name then return name, icon end
    end
    return tostring(spellID), nil
end

local function panelStatus(message)
    setLabel("footerStatus", message or "设置已更新。")
end

-- Shared priority-list editor. Each row is a self-contained priority card:
-- skill identity is on the top line and the order / enablement controls are on
-- the second line. Rows are pooled and refreshed in place so sorting does not
-- recreate the TEUI page or overlap controls.
local function createSpellPriorityEditor(parent, title, description, y, options)
    options = options or {}
    local ROW_HEIGHT = 62
    local ROW_GAP = 6
    local BUTTON_Y = -32
    local typeLabels = { selfheal = "自疗", minor = "轻减伤", major = "大减伤", emergency = "保命" }

    y = createSection(parent, title, y)
    createText(parent, "GameFontDisableSmall", 14, y, 720, description or "")
    local topY = y - 38
    local maxRows = math.max(1, tonumber(options.maxRows) or 6)
    local rows = {}

    for index = 1, maxRows do
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetSize(696, ROW_HEIGHT)
        panelBackdrop(row, 0.012, 0.018, 0.032, 0.92, 0.14, 0.20, 0.30, 0.96)
        row.index = index

        row.number = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.number:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
        row.number:SetWidth(24)
        row.number:SetJustifyH("RIGHT")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -6)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetWidth(400)
        row.name:SetJustifyH("LEFT")

        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.source:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -10)
        row.source:SetWidth(150)
        row.source:SetJustifyH("RIGHT")

        row.up = createActionButton(row, "上", 12, BUTTON_Y, 58, function()
            if not row.entry or not options.move then return end
            local ok, reason = options.move(row.entry.spellID, -1)
            panelStatus(ok and "优先级已上移。" or ("无法上移：" .. tostring(reason or "边界")))
            ControlPanel:ApplyVisuals(true)
        end)
        row.down = createActionButton(row, "下", 78, BUTTON_Y, 58, function()
            if not row.entry or not options.move then return end
            local ok, reason = options.move(row.entry.spellID, 1)
            panelStatus(ok and "优先级已下移。" or ("无法下移：" .. tostring(reason or "边界")))
            ControlPanel:ApplyVisuals(true)
        end)
        row.remove = createActionButton(row, options.removeLabel or "停用", 144, BUTTON_Y, 70, function()
            if not row.entry then return end
            local ok, reason
            if options.remove then
                ok, reason = options.remove(row.entry.spellID, row.entry)
            elseif options.setEnabled then
                ok, reason = options.setEnabled(row.entry.spellID, false)
            end
            panelStatus(ok and "技能已从当前优先策略停用。" or ("操作失败：" .. tostring(reason or "未知")))
            ControlPanel:ApplyVisuals(true)
        end)

        row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enabled:SetPoint("TOPLEFT", row, "TOPLEFT", 236, -29)
        row.enabled.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.enabled.label:SetPoint("LEFT", row.enabled, "RIGHT", 2, 0)
        row.enabled.label:SetWidth(180)
        row.enabled.label:SetJustifyH("LEFT")
        row.enabled:SetScript("OnClick", function(button)
            if not row.entry or not options.setEnabled then return end
            local ok, reason = options.setEnabled(row.entry.spellID, button:GetChecked() == true)
            panelStatus(ok and "技能触发优先级已更新。" or ("更新失败：" .. tostring(reason or "未知")))
            ControlPanel:ApplyVisuals(true)
        end)
        rows[index] = row
    end

    local status = createText(parent, "GameFontDisableSmall", 14, topY - 48, 700, "")
    local customCaption, customBox, addButton
    if options.add then
        customCaption = createText(parent, "GameFontHighlight", 14, topY - 80, 126, "自定义 SpellID")
        customBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        customBox:SetAutoFocus(false)
        customBox:SetSize(118, 24)
        customBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 148, topY - 78)
        customBox:SetText("")
        customBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        customBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        addButton = createActionButton(parent, options.addLabel or "添加当前专精已知技能", 280, topY - 80, 192, function()
            local value = tonumber(customBox:GetText())
            local ok, reason = options.add(value)
            if ok then customBox:SetText("") end
            panelStatus(ok and "自定义当前专精技能已加入列表。" or ("无法添加：" .. tostring(reason or "未知")))
            ControlPanel:ApplyVisuals(true)
        end)
    end

    local showRestore = options.showRestore ~= false and type(options.restore) == "function"
    local resetButton
    if showRestore then
        resetButton = createActionButton(parent, options.resetLabel or "恢复当前专精默认", 14, topY - 116, 220, function()
            local ok, reason = options.restore()
            panelStatus(ok and "当前专精列表已恢复默认。" or ("恢复失败：" .. tostring(reason or "未知")))
            ControlPanel:ApplyVisuals(true)
        end)
    end

    local function refresh()
        local entries, profileKey, reason, profile = {}, nil, nil, nil
        if options.getEntries then entries, profileKey, reason, profile = options.getEntries() end
        local visible = 0
        for _, row in ipairs(rows) do
            local entry = entries and entries[row.index] or nil
            row.entry = entry
            if entry then
                visible = visible + 1
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, topY - (visible - 1) * (ROW_HEIGHT + ROW_GAP))
                row.number:SetText(tostring(visible) .. ".")
                local name, icon = panelSpellInfo(entry.spellID)
                row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.name:SetText(name .. "  |cff7f8c9a(" .. tostring(entry.spellID) .. ")|r")
                local isEnabled = entry.enabled ~= false
                row.name:SetTextColor(isEnabled and 1.00 or 0.48, isEnabled and 0.82 or 0.52, isEnabled and 0.18 or 0.60)
                row.enabled:SetChecked(isEnabled)
                row.enabled.label:SetText(options.enabledLabel or "触发优先级")
                local source = entry.custom and "自定义" or "专精默认"
                if entry.type then source = source .. " / " .. (typeLabels[entry.type] or tostring(entry.type)) end
                row.source:SetText(source)
                row.remove.text:SetText(entry.custom and "移除" or (options.removeLabel or "停用"))
                row:SetShown(true)
            else
                row:SetShown(false)
            end
        end

        local lineY = topY - math.max(visible, 1) * (ROW_HEIGHT + ROW_GAP) + ROW_GAP - 6
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, lineY)
        local descriptor = profile and (profile.specLabel or profile.profileLabel or profile.profileKey) or profileKey or "未知专精"
        local suffix = reason and (" · " .. tostring(reason)) or ""
        status:SetText("当前专精：" .. tostring(descriptor) .. " · 列表项目：" .. tostring(visible) .. suffix)

        local nextY = lineY - 30
        if customCaption then
            customCaption:ClearAllPoints(); customCaption:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, nextY - 4)
            customBox:ClearAllPoints(); customBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 148, nextY + 1)
            addButton:ClearAllPoints(); addButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 280, nextY)
            nextY = nextY - 38
        end
        if resetButton then
            resetButton:ClearAllPoints(); resetButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, nextY)
        end
    end

    registerControl(refresh)
    refresh()

    -- Reserve the complete pool height. Subsequent static controls never share
    -- an anchor with a list row, even after the user adds a custom burst spell.
    local trailing = (options.add and 42 or 0) + (showRestore and 38 or 0) + 42
    return topY - (maxRows * (ROW_HEIGHT + ROW_GAP) + trailing)
end

local function refreshTacticalBoard()
    if TE.TacticalBoard and type(TE.TacticalBoard.Render) == "function" then
        local snapshot = TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil
        TE.TacticalBoard:Render(snapshot)
    end
end

local function getSnapshot()
    if TE.TacticalAdvisors and type(TE.TacticalAdvisors.GetSnapshot) == "function" then
        return TE.TacticalAdvisors:GetSnapshot()
    end
    return {}
end

local function profileSummary()
    local manager = TE.ProfileManager
    if not manager or type(manager.GetSummary) ~= "function" then return "配置管理器：未加载" end
    local summary = manager:GetSummary()
    return "当前配置：" .. tostring(summary.activeName)
        .. "\n自动匹配：" .. tostring(summary.selectedByScope) .. "（" .. tostring(summary.selectedScope) .. "）"
        .. "\n当前角色：" .. tostring(summary.context and summary.context.character or "-")
        .. "  ·  专精：" .. tostring(summary.context and summary.context.specName or "未知")
        .. "\n已保存：" .. table.concat(summary.profiles or {}, "、")
end

local function formatHotkey(value)
    if type(value) ~= "string" or value == "" then return "未设置" end
    return value:gsub("%-", "+")
end

local function isBareModifier(key)
    return key == "LALT" or key == "RALT" or key == "LCTRL" or key == "RCTRL"
        or key == "LSHIFT" or key == "RSHIFT"
end

local function normalizeCapturedHotkey(key)
    if type(key) ~= "string" or key == "" then return nil end
    key = key:upper()
    if key == "ESCAPE" then return "__cancel" end
    if isBareModifier(key) then return nil end
    local modifiers = {}
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then modifiers[#modifiers + 1] = "CTRL" end
    if type(IsAltKeyDown) == "function" and IsAltKeyDown() then modifiers[#modifiers + 1] = "ALT" end
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then modifiers[#modifiers + 1] = "SHIFT" end
    modifiers[#modifiers + 1] = key
    return table.concat(modifiers, "-")
end

local function ensureHotkeyOwner()
    if hotkeyOwner then return hotkeyOwner end
    hotkeyOwner = CreateFrame("Button", "TacticEchoToggleHotkeyButton", UIParent)
    hotkeyOwner:SetSize(1, 1)
    hotkeyOwner:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    hotkeyOwner:SetAlpha(0)
    hotkeyOwner:RegisterForClicks("AnyUp")
    hotkeyOwner:SetScript("OnClick", function()
        if TE.ControlPanel then TE.ControlPanel:ToggleRun("hotkey") end
    end)
    hotkeyOwner:Show()
    return hotkeyOwner
end

local function setHotkeyHint(message)
    setLabel("generalHotkey", message)
    setLabel("footerStatus", message)
end

local function setAutoBurstHotkeyHint(message)
    setLabel("generalAutoBurstHotkey", message)
    setLabel("footerStatus", message)
end

function ControlPanel:ApplyToggleHotkey(binding, fromStored)
    binding = type(binding) == "string" and binding or ""
    local settings = ensureSettings()
    if binding ~= "" and binding == settings.autoBurstToggleHotkey then
        setHotkeyHint("启动/暂停快捷键不能与自动爆发快捷键相同。")
        return false, "auto_burst_hotkey_conflict"
    end
    if not fromStored then settings.toggleHotkey = binding end
    pendingToggleHotkey = binding
    if InCombatLockdown and InCombatLockdown() then
        pendingApplyAfterCombat = true
        setHotkeyHint("快捷键已保存，将在脱战后应用：" .. formatHotkey(binding))
        self:UpdateInputStatus()
        return false, "deferred_in_combat"
    end
    local owner = ensureHotkeyOwner()
    local clearOk, clearError = pcall(function()
        if type(ClearOverrideBindings) == "function" then ClearOverrideBindings(owner) end
    end)
    if not clearOk then
        setHotkeyHint("清除旧快捷键失败：" .. tostring(clearError))
        return false, "clear_override_failed"
    end
    if binding ~= "" then
        if type(SetOverrideBindingClick) ~= "function" then
            setHotkeyHint("当前客户端不支持临时覆盖快捷键")
            return false, "override_binding_unavailable"
        end
        local ok, err = pcall(SetOverrideBindingClick, owner, true, binding, "TacticEchoToggleHotkeyButton", "LeftButton")
        if not ok then
            setHotkeyHint("应用快捷键失败：" .. tostring(err))
            return false, "override_binding_failed"
        end
    end
    pendingApplyAfterCombat = false
    settings.toggleHotkey = binding
    setHotkeyHint(binding == "" and "启动/暂停快捷键已清除。" or ("启动/暂停快捷键已应用：" .. formatHotkey(binding)))
    self:UpdateInputStatus()
    return true
end

function ControlPanel:ApplyStoredToggleHotkey()
    return self:ApplyToggleHotkey(ensureSettings().toggleHotkey or "", true)
end

local function ensureAutoBurstHotkeyOwner()
    if autoBurstHotkeyOwner then return autoBurstHotkeyOwner end
    autoBurstHotkeyOwner = CreateFrame("Button", "TacticEchoAutoBurstToggleHotkeyButton", UIParent)
    autoBurstHotkeyOwner:SetSize(1, 1)
    autoBurstHotkeyOwner:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -12, 12)
    autoBurstHotkeyOwner:SetAlpha(0)
    autoBurstHotkeyOwner:RegisterForClicks("AnyUp")
    autoBurstHotkeyOwner:SetScript("OnClick", function()
        if TE.ControlPanel then TE.ControlPanel:ToggleAutoBurst("hotkey") end
    end)
    autoBurstHotkeyOwner:Show()
    return autoBurstHotkeyOwner
end

function ControlPanel:ApplyAutoBurstHotkey(binding, fromStored)
    binding = type(binding) == "string" and binding or ""
    local settings = ensureSettings()
    if binding ~= "" and binding == settings.toggleHotkey then
        setAutoBurstHotkeyHint("自动爆发快捷键不能与启动/暂停快捷键相同。")
        return false, "toggle_hotkey_conflict"
    end
    if not fromStored then settings.autoBurstToggleHotkey = binding end
    pendingAutoBurstHotkey = binding
    if InCombatLockdown and InCombatLockdown() then
        pendingAutoBurstApplyAfterCombat = true
        setAutoBurstHotkeyHint("自动爆发快捷键已保存，将在脱战后应用：" .. formatHotkey(binding))
        self:UpdateInputStatus()
        return false, "deferred_in_combat"
    end
    local owner = ensureAutoBurstHotkeyOwner()
    local clearOk, clearError = pcall(function()
        if type(ClearOverrideBindings) == "function" then ClearOverrideBindings(owner) end
    end)
    if not clearOk then
        setAutoBurstHotkeyHint("清除旧自动爆发快捷键失败：" .. tostring(clearError))
        return false, "clear_override_failed"
    end
    if binding ~= "" then
        if type(SetOverrideBindingClick) ~= "function" then
            setAutoBurstHotkeyHint("当前客户端不支持临时覆盖快捷键")
            return false, "override_binding_unavailable"
        end
        local ok, err = pcall(SetOverrideBindingClick, owner, true, binding,
            "TacticEchoAutoBurstToggleHotkeyButton", "LeftButton")
        if not ok then
            setAutoBurstHotkeyHint("应用自动爆发快捷键失败：" .. tostring(err))
            return false, "override_binding_failed"
        end
    end
    pendingAutoBurstApplyAfterCombat = false
    settings.autoBurstToggleHotkey = binding
    setAutoBurstHotkeyHint(binding == "" and "自动爆发快捷键已清除。"
        or ("自动爆发快捷键已应用：" .. formatHotkey(binding)))
    self:UpdateInputStatus()
    return true
end

function ControlPanel:ApplyStoredAutoBurstHotkey()
    return self:ApplyAutoBurstHotkey(ensureSettings().autoBurstToggleHotkey or "", true)
end

local function ensureHotkeyCapture()
    if hotkeyCapture then return hotkeyCapture end
    hotkeyCapture = CreateFrame("EditBox", "TacticEchoToggleHotkeyCapture", UIParent, "InputBoxTemplate")
    hotkeyCapture:SetSize(1, 1)
    hotkeyCapture:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    hotkeyCapture:SetAlpha(0)
    hotkeyCapture:SetFrameStrata("TOOLTIP")
    hotkeyCapture:SetAutoFocus(false)
    hotkeyCapture:EnableKeyboard(true)
    if type(hotkeyCapture.SetPropagateKeyboardInput) == "function" then hotkeyCapture:SetPropagateKeyboardInput(false) end
    hotkeyCapture:SetScript("OnEscapePressed", function(box)
        box:ClearFocus(); box:Hide()
        setHotkeyHint("快捷键录入已取消。")
    end)
    hotkeyCapture:SetScript("OnKeyDown", function(box, key)
        local captured = normalizeCapturedHotkey(key)
        if not captured then return end
        box:ClearFocus(); box:Hide()
        if captured == "__cancel" then
            setHotkeyHint("快捷键录入已取消。")
            return
        end
        pendingToggleHotkey = captured
        setHotkeyHint("待应用的启动/暂停快捷键：" .. formatHotkey(captured) .. "。点击“应用快捷键”提交。")
        ControlPanel:UpdateInputStatus()
    end)
    hotkeyCapture:Hide()
    return hotkeyCapture
end

local function ensureAutoBurstHotkeyCapture()
    if autoBurstHotkeyCapture then return autoBurstHotkeyCapture end
    autoBurstHotkeyCapture = CreateFrame("EditBox", "TacticEchoAutoBurstHotkeyCapture", UIParent, "InputBoxTemplate")
    autoBurstHotkeyCapture:SetSize(1, 1)
    autoBurstHotkeyCapture:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    autoBurstHotkeyCapture:SetAlpha(0)
    autoBurstHotkeyCapture:SetFrameStrata("TOOLTIP")
    autoBurstHotkeyCapture:SetAutoFocus(false)
    autoBurstHotkeyCapture:EnableKeyboard(true)
    if type(autoBurstHotkeyCapture.SetPropagateKeyboardInput) == "function" then
        autoBurstHotkeyCapture:SetPropagateKeyboardInput(false)
    end
    autoBurstHotkeyCapture:SetScript("OnEscapePressed", function(box)
        box:ClearFocus(); box:Hide()
        setAutoBurstHotkeyHint("自动爆发快捷键录入已取消。")
    end)
    autoBurstHotkeyCapture:SetScript("OnKeyDown", function(box, key)
        local captured = normalizeCapturedHotkey(key)
        if not captured then return end
        box:ClearFocus(); box:Hide()
        if captured == "__cancel" then
            setAutoBurstHotkeyHint("自动爆发快捷键录入已取消。")
            return
        end
        pendingAutoBurstHotkey = captured
        setAutoBurstHotkeyHint("待应用的自动爆发快捷键：" .. formatHotkey(captured) .. "。点击“应用”提交。")
        ControlPanel:UpdateInputStatus()
    end)
    autoBurstHotkeyCapture:Hide()
    return autoBurstHotkeyCapture
end

function ControlPanel:BeginToggleHotkeyCapture()
    local capture = ensureHotkeyCapture()
    capture:SetText("")
    capture:Show(); capture:SetFocus()
    setHotkeyHint("请按下启动/暂停快捷键组合；按 Esc 取消。该键只以临时覆盖方式服务于 TE，不会写入游戏动作条绑定。")
end

function ControlPanel:BeginAutoBurstHotkeyCapture()
    local capture = ensureAutoBurstHotkeyCapture()
    capture:SetText("")
    capture:Show(); capture:SetFocus()
    setAutoBurstHotkeyHint("请按下自动爆发开关快捷键组合；按 Esc 取消。该键只切换自动爆发设置。")
end

function ControlPanel:ApplyVisuals(saveProfile)
    ensureSettings()
    ensureTactics()
    refreshTacticalBoard()
    if saveProfile ~= false and TE.ProfileManager and type(TE.ProfileManager.SaveActive) == "function" then
        TE.ProfileManager:SaveActive()
    end
    self:UpdateInputStatus()
end

function ControlPanel:RefreshActionBar(reason)
    if TE.ActionBarBindingResolver then
        if type(TE.ActionBarBindingResolver.Invalidate) == "function" then TE.ActionBarBindingResolver:Invalidate(reason or "teui") end
        if type(TE.ActionBarBindingResolver.Rebuild) == "function" then TE.ActionBarBindingResolver:Rebuild(reason or "teui") end
    end
    if TE.SignalFrame and type(TE.SignalFrame.Refresh) == "function"
        and type(TE.SignalFrame.GetLastEncoded) == "function" and TE.SignalFrame:GetLastEncoded() then
        TE.SignalFrame:Refresh("settings_center")
    end
    self:ApplyVisuals(true)
end

function ControlPanel:StartDynamic()
    if TE.SignalFrame and type(TE.SignalFrame.SetState) == "function" then TE.SignalFrame:SetState("armed") end
    self:UpdateInputStatus()
end

function ControlPanel:PauseDynamic()
    if TE.SignalFrame and type(TE.SignalFrame.SetState) == "function" then TE.SignalFrame:SetState("paused") end
    self:UpdateInputStatus()
end

function ControlPanel:ToggleRun()
    local state = TE.SignalFrame and TE.SignalFrame:GetState() or "waiting"
    if state == "armed" then self:PauseDynamic() else self:StartDynamic() end
end

function ControlPanel:ToggleAutoBurst(source)
    local tactics = select(1, ensureTactics())
    tactics.autoBurstEnabled = tactics.autoBurstEnabled ~= true
    panelStatus(tactics.autoBurstEnabled == true
        and "自动爆发已开启；可派发状态显示 HAD。"
        or "自动爆发已关闭；可派发状态显示 LCC。")
    self:ApplyVisuals(false)
    return tactics.autoBurstEnabled == true, source
end

function ControlPanel:SetToggleHotkey(binding)
    return self:ApplyToggleHotkey(binding, false)
end

function ControlPanel:SetAutoBurstHotkey(binding)
    return self:ApplyAutoBurstHotkey(binding, false)
end

local function savePanelPosition(presentation)
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local store = root()
    if presentation == "compact" then
        store.compact.point, store.compact.relativePoint, store.compact.x, store.compact.y = point, relativePoint, x, y
        store.compact.hasPosition = true
    else
        store.point, store.relativePoint, store.x, store.y = point, relativePoint, x, y
    end
end

local function restorePanelPosition(presentation)
    if not frame then return end
    local store = root()
    local source = presentation == "compact" and store.compact or store
    frame:ClearAllPoints()
    if presentation == "compact" and source.hasPosition ~= true then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    frame:SetPoint(source.point or "CENTER", UIParent, source.relativePoint or "CENTER", tonumber(source.x) or 0, tonumber(source.y) or 0)
end

local function applyPanelPresentation(minimized)
    if not frame then return end
    local store = root()
    store.minimized = minimized == true
    if minimized then
        frame:SetSize(COMPACT_WIDTH, COMPACT_HEIGHT)
        normalHeader:Hide(); normalNavigation:Hide(); normalMain:Hide(); normalFooter:Hide()
        compactView:Show()
    else
        frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        compactView:Hide()
        normalHeader:Show(); normalNavigation:Show(); normalMain:Show(); normalFooter:Show()
    end
end

function ControlPanel:SetMinimized(minimized)
    local wasMinimized = root().minimized == true
    if minimized and not wasMinimized then
        savePanelPosition("normal")
        applyPanelPresentation(true)
        restorePanelPosition("compact")
    elseif not minimized and wasMinimized then
        savePanelPosition("compact")
        applyPanelPresentation(false)
        restorePanelPosition("normal")
    else
        applyPanelPresentation(minimized)
        restorePanelPosition(minimized and "compact" or "normal")
    end
end

function ControlPanel:Minimize()
    root().visible = true
    self:SetMinimized(true)
end

function ControlPanel:Restore()
    root().visible = true
    self:SetMinimized(false)
end

function ControlPanel:Show(page, subpage)
    page = LEGACY_PAGE_ALIAS[page] or page
    if not PAGE_META[page] then page = "general" end
    self:Create()
    root().visible = true
    if root().minimized then self:Restore() end
    activePage = page
    for key, button in pairs(navButtons) do
        button.selected = key == activePage
        setButtonVisual(button, button.selected)
    end
    for key, pane in pairs(panes) do
        pane:SetShown(key == activePage)
        if key == activePage and type(pane.SetVerticalScroll) == "function" then pane:SetVerticalScroll(0) end
    end
    if labels.pageTitle then labels.pageTitle:SetText(PAGE_META[activePage].label) end
    if labels.pageDescription then labels.pageDescription:SetText(PAGE_META[activePage].description) end
    root().page = activePage
    frame:Show()
    self:UpdateInputStatus()
end

function ControlPanel:Hide()
    if not frame then return end
    root().visible = false
    if TE.ProfileManager and type(TE.ProfileManager.SaveActive) == "function" then TE.ProfileManager:SaveActive() end
    frame:Hide()
end

function ControlPanel:Toggle()
    if frame and frame:IsShown() then self:Hide() else self:Show(activePage) end
end

-- Compatibility command: tactical HUD compact mode; /teui min is the compact
-- settings-window presentation.
function ControlPanel:SetCompact(compact)
    local _, hud = ensureTactics()
    hud.compact = compact == true
    if TE.TacticalBoard and type(TE.TacticalBoard.SetCompact) == "function" then
        TE.TacticalBoard:SetCompact(hud.compact)
        if hud.compact then TE.TacticalBoard:Show() end
    end
    if hud.compact then self:Hide() else self:Show("hud") end
end

function ControlPanel:ShowTacticalQueue()
    return self:Show("hud")
end

function ControlPanel:ResetPosition()
    local store = root()
    store.point, store.relativePoint, store.x, store.y = "CENTER", "CENTER", 0, 0
    if store.minimized ~= true then restorePanelPosition("normal") end
end

function ControlPanel:ResetCompactPosition()
    local store = root()
    store.compact.point, store.compact.relativePoint, store.compact.x, store.compact.y = "CENTER", "CENTER", 0, 0
    store.compact.hasPosition = false
    if store.minimized == true then restorePanelPosition("compact") end
end

function ControlPanel:ResetTacticalLayout()
    local _, hud = ensureTactics()
    if TE.TacticalHudLayout and type(TE.TacticalHudLayout.Reset) == "function" then
        TE.TacticalHudLayout:Reset(hud)
    else
        hud.layoutPreset, hud.primaryGrowth, hud.tacticalGrowth = "queue_horizontal", "RIGHT", "RIGHT"
    end
    self:ApplyVisuals(true)
end

function ControlPanel:ResetDisplaySettings()
    -- Reset presentation only. Tactical policy and priority lists are not
    -- altered by a display reset.
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.ResetVisuals) == "function" then
        TE.Config.Normalize:ResetVisuals()
    else
        local _, hud = ensureTactics()
        hud.enabled, hud.queueMode, hud.maxCandidates = true, "tactical", 3
        hud.hideWhenIdle, hud.outOfCombatMode = false, "show"
        hud.scale, hud.alpha, hud.backdropAlpha = 1, 1, 0.08
        hud.outOfCombatAlpha, hud.outOfCombatScale = 0.62, 1
        hud.showHistory, hud.showKeyLabels, hud.showStatusText, hud.showSourceTags = true, true, true, true
        for _, key in ipairs({ "main", "burst" }) do
            local style = ensureModuleStyle(hud, key)
            style.show = true
        end
    end
    self:ApplyVisuals(true)
end

local INPUT_PROTECTION_REASONS = {
    chat_input_active = true, keyboard_focus_active = true, chat_editbox_active = true,
    macro_editor_active = true, keybinding_editor_active = true,
    static_popup_active = true, static_popup_edit_active = true,
}

-- Human-facing labels are intentionally owned by the display layer. The raw
-- TEAP states remain unchanged and are retained on the monitor page.
local USER_STATE_LABELS = {
    waiting = "未运行",
    armed = "运行中",
    paused = "暂停中",
    standby = "待命中",
    channeling = "引导中",
    empowering = "蓄力中",
    blocked = "已阻断",
    error = "异常",
    display_only = "仅显示",
}

local function userVisibleReason(rawReason, reasonText)
    if INPUT_PROTECTION_REASONS[rawReason] then return "界面输入中" end
    if type(reasonText) == "string" and reasonText ~= "" and reasonText ~= rawReason then return reasonText end
    if rawReason and TE.TacticalState and type(TE.TacticalState.DescribeReason) == "function" then
        local mapped = TE.TacticalState:DescribeReason(rawReason)
        if type(mapped) == "string" and mapped ~= "" and mapped ~= rawReason then return mapped end
    end
    if rawReason and rawReason ~= "" then return "原因未提供" end
    return nil
end

local function compactToggleGlyph(status)
    -- Channeling / empowering retain the user's armed intent. Showing II keeps
    -- the button truthful: clicking it records a manual pause after the cast
    -- lock ends, rather than pretending the cast itself can be resumed.
    return status and status.intentState == "armed" and "Ⅱ" or "▶"
end

function ControlPanel:GetCompactStatus()
    local snapshot = getSnapshot()
    local primary = type(snapshot.primary) == "table" and snapshot.primary or {}
    local display = type(snapshot.primaryDisplay) == "table" and snapshot.primaryDisplay or {}
    local rawState = primary.state or display.state or (TE.SignalFrame and TE.SignalFrame:GetEffectiveState()) or "waiting"
    local rawReason = primary.reason or display.reason
    local reasonText = primary.reasonText or display.reasonText
    local rawIntent = primary.intentState or (TE.SignalFrame and TE.SignalFrame:GetState()) or "waiting"
    local intent = rawIntent == "armed" and "运行中" or (rawIntent == "paused" and "暂停中" or "未运行")
    local displayState = (rawState == "paused" and rawReason == "out_of_combat_auto_standby") and "standby" or rawState
    local label = USER_STATE_LABELS[displayState] or "状态未知"
    local status = {
        label = label,
        rawState = displayState,
        transportState = rawState,
        rawReason = nil,
        intent = intent,
        intentState = rawIntent,
        reasonText = userVisibleReason(rawReason, reasonText),
    }
    if rawState == "blocked" then
        status.showIntent = true
        status.rawReason = rawReason
    elseif displayState == "standby" then
        status.rawReason = rawReason
    elseif rawState == "paused" then
        if not INPUT_PROTECTION_REASONS[rawReason] then status.rawReason = rawReason end
    elseif rawState == "channeling" or rawState == "empowering" then
        status.rawReason = rawReason
    elseif rawState == "error" or label == "状态未知" then
        status.rawReason = rawReason or rawState
    end
    return status
end

function ControlPanel:UpdateInputStatus()
    local settings = ensureSettings()
    local tactics, hud = ensureTactics()
    local snapshot = getSnapshot()
    local context = snapshot.context or (TE.Context and TE.Context:GetPlayer()) or {}
    local primary = snapshot.primaryDisplay or snapshot.primary or {}
    local page = activePage

    local compactStatus = self:GetCompactStatus()
    setLabel("headerState", "状态：" .. compactStatus.label .. "  ·  " .. tostring(context.class or "-") .. " / " .. tostring(context.specName or "未知专精"))
    setLabel("compactRunState", compactStatus.label)
    if compactToggleButton and compactToggleButton.text then
        compactToggleButton.text:SetText(compactToggleGlyph(compactStatus))
    end
    setLabel("footerState", "当前配置：" .. (TE.ProfileManager and TE.ProfileManager:GetActiveName() or "Default"))

    if page == "general" then
        setLabel("generalRuntime", "当前状态：" .. compactStatus.label
            .. "\n官方主推荐：" .. tostring(primary.spellName or "等待") .. "  ·  键位：" .. tostring(primary.binding or "无")
            .. "\n自动爆发：" .. (tactics.autoBurstEnabled == true and "已开启（HAD）" or "已关闭（LCC）"))
        local policyLabel = TE.SignalFrame and type(TE.SignalFrame.GetSessionPolicyLabel) == "function"
            and TE.SignalFrame:GetSessionPolicyLabel() or tostring(settings.sessionPolicy)
        setLabel("generalPolicy", "当前：" .. policyLabel)
        setLabel("generalHotkey", settings.toggleHotkey ~= "" and ("TE 快捷键：" .. settings.toggleHotkey) or "TE 快捷键：未设置")
        local autoBurstToggleHotkey = type(settings.autoBurstToggleHotkey) == "string"
            and settings.autoBurstToggleHotkey or ""
        setLabel("generalAutoBurstHotkey", autoBurstToggleHotkey ~= ""
            and ("自动爆发快捷键：" .. autoBurstToggleHotkey)
            or "自动爆发快捷键：未设置")
    end

    if page == "profiles" then
        setLabel("profileState", profileSummary())
        setLabel("profileScopes", (function()
            local manager = TE.ProfileManager
            if not manager then return "配置范围：配置管理器未加载" end
            local summary = manager:GetSummary()
            local keys = summary.keys or {}
            local assignments = summary.assignments or {}
            return "全局：" .. tostring(assignments[keys.global] or "未指定")
                .. "\n角色：" .. tostring(assignments[keys.character] or "未指定")
                .. "\n职业：" .. tostring(assignments[keys.class] or "未指定")
                .. "\n专精：" .. tostring(assignments[keys.spec] or "未指定")
        end)())
    end

    -- Only active-page controls need periodic synchronization. Hidden pages
    -- refresh on first show and after their own user actions, avoiding needless
    -- list/row rebuild work and focus flicker across the entire settings center.
    refreshControls(activePage)
end

local function buildGeneral(pane)
    local y = createSection(pane, "运行", -12)
    createReadout(pane, "generalRuntime", "当前状态", 14, y, 720, "GameFontHighlightSmall")
    createActionButton(pane, "启动 / 暂停", 14, y - 72, 126, function() ControlPanel:ToggleRun() end)
    createActionButton(pane, "重扫动作条", 150, y - 72, 118, function() ControlPanel:RefreshActionBar("teui_general") end)
    y = y - 118
    y = createSection(pane, "运行方式", y)
    createChoice(pane, "脱战策略", 14, y, 300, {
        { value = "pause_out_of_combat", label = "自动启停（推荐）" },
        { value = "manual_keep", label = "手动启停" },
        { value = "close_out_of_combat", label = "脱战后保持停止" },
    }, function() return ensureSettings().sessionPolicy end, function(value)
        ensureSettings().sessionPolicy = value
        if TE.SignalFrame and type(TE.SignalFrame.SetSessionPolicy) == "function" then TE.SignalFrame:SetSessionPolicy(value) end
    end)
    createReadout(pane, "generalPolicy", "当前策略", RIGHT_X, y, 330, "GameFontDisableSmall")
    y = y - 96
    y = createSection(pane, "整体启停快捷键", y)
    createReadout(pane, "generalHotkey", "当前快捷键", 14, y, 720, "GameFontHighlightSmall")
    local hotkeyBox = createEditBox(pane, "快捷键", LEFT_X, y - 58, 150, ensureSettings().toggleHotkey)
    createActionButton(pane, "录入", 326, y - 58, 72, function() ControlPanel:BeginToggleHotkeyCapture() end)
    createActionButton(pane, "应用", 408, y - 58, 90, function()
        ControlPanel:SetToggleHotkey(pendingToggleHotkey or hotkeyBox:GetText())
    end)
    createActionButton(pane, "清除", 508, y - 58, 90, function() ControlPanel:SetToggleHotkey("") end)
    y = y - 118
    y = createSection(pane, "自动爆发快捷键", y)
    createReadout(pane, "generalAutoBurstHotkey", "当前快捷键", 14, y, 720, "GameFontHighlightSmall")
    local autoBurstHotkeyBox = createEditBox(pane, "快捷键", LEFT_X, y - 58, 150,
        ensureSettings().autoBurstToggleHotkey)
    createActionButton(pane, "录入", 326, y - 58, 72, function() ControlPanel:BeginAutoBurstHotkeyCapture() end)
    createActionButton(pane, "应用", 408, y - 58, 90, function()
        ControlPanel:SetAutoBurstHotkey(pendingAutoBurstHotkey or autoBurstHotkeyBox:GetText())
    end)
    createActionButton(pane, "清除", 508, y - 58, 90, function() ControlPanel:SetAutoBurstHotkey("") end)
end

-- Text styles are presentation-only.  Keep the editor on the HUD page so the
-- current product scope does not need separate module or style pages.
local function buildTextStyleSection(pane, style, label, y)
    y = createSection(pane, label, y)
    createCheckbox(pane, "显示", LEFT_X, y, function() return style.enabled end, function(value) style.enabled = value end)
    createChoice(pane, "字体", RIGHT_X, y, 160, {
        { value = "normal", label = "标准" }, { value = "highlight", label = "高亮" }, { value = "disable", label = "弱化" },
    }, function() return style.fontPreset end, function(value) style.fontPreset = value end)
    y = y - 38
    createNumberStepper(pane, "字号", LEFT_X, y, 64, function() return style.fontSize end, function(value) style.fontSize = value end, 1, 8, 30, "")
    createNumberStepper(pane, "缩放", RIGHT_X, y, 64, function() return math.floor(style.scale * 100 + 0.5) end, function(value) style.scale = value / 100 end, 10, 60, 200, "%")
    y = y - 38
    createChoice(pane, "位置", LEFT_X, y, 160, {
        { value = "TOPLEFT", label = "左上" }, { value = "TOPRIGHT", label = "右上" }, { value = "CENTER", label = "中间" },
        { value = "BOTTOMLEFT", label = "左下" }, { value = "BOTTOMRIGHT", label = "右下" },
    }, function() return style.point end, function(value) style.point = value end)
    createColorChoice(pane, "颜色", RIGHT_X, y, function() return style.colorKey end, function(value)
        style.colorKey = value
        style.color = copyColor(COLOR_PRESETS[value].color)
    end)
    y = y - 38
    createNumberStepper(pane, "横向偏移", LEFT_X, y, 64, function() return style.offsetX end, function(value) style.offsetX = value end, 1, -30, 30, "")
    createNumberStepper(pane, "纵向偏移", RIGHT_X, y, 64, function() return style.offsetY end, function(value) style.offsetY = value end, 1, -30, 30, "")
    return y - 62
end

local function buildHudLabelStyles(pane, mainStyle, burstStyle, y)
    y = createSection(pane, "标签样式", y)
    createText(pane, "GameFontDisableSmall", LEFT_X, y, 720,
        "以下设置只改变 HUD 文字显示，不改变推荐、AutoBurst、动作条绑定或派发资格。")
    y = y - 48
    y = createSection(pane, "主键", y)
    y = buildTextStyleSection(pane, mainStyle.keyLabel, "快捷键", y)
    y = buildTextStyleSection(pane, mainStyle.chargeLabel, "充能 / 可用次数", y)
    y = buildTextStyleSection(pane, mainStyle.cooldownText, "CD 时间（HUD 统一秒数）", y)
    y = buildTextStyleSection(pane, mainStyle.stateText, "状态文字", y)
    y = createSection(pane, "自动爆发", y)
    y = buildTextStyleSection(pane, burstStyle.keyLabel, "快捷键", y)
    y = buildTextStyleSection(pane, burstStyle.chargeLabel, "充能 / 可用次数", y)
    y = buildTextStyleSection(pane, burstStyle.cooldownText, "CD 时间（HUD 统一秒数）", y)
    return buildTextStyleSection(pane, burstStyle.stateText, "状态文字", y)
end

local function buildHUD(pane)
    local _, hud = ensureTactics()
    do
        local y = createSection(pane, "HUD 显示", -12)
        createCheckbox(pane, "启用 HUD", LEFT_X, y, function() return hud.enabled end, function(value) hud.enabled = value end)
        createCheckbox(pane, "无推荐时隐藏", RIGHT_X, y, function() return hud.hideWhenIdle end, function(value) hud.hideWhenIdle = value end)
        y = y - 38
        createChoice(pane, "脱战显示", LEFT_X, y, 240, {
            { value = "show", label = "保持显示" }, { value = "dim", label = "淡化显示" }, { value = "hide", label = "隐藏 HUD" },
        }, function() return hud.outOfCombatMode end, function(value) hud.outOfCombatMode = value end)
        createCheckbox(pane, "显示拖动把手", RIGHT_X, y, function() return hud.showDragHandle end, function(value) hud.showDragHandle = value end)

        y = y - 76
        y = createSection(pane, "显示内容", y)
        local mainStyle = getModuleStyle("main")
        local burstStyle = getModuleStyle("burst")
        createChoice(pane, "内容", LEFT_X, y, 260, {
            { value = "tactical", label = "主键 + 自动爆发" },
            { value = "primary", label = "仅主键" },
        }, function()
            return hud.queueMode == "primary" and "primary" or "tactical"
        end, function(value)
            hud.queueMode = value == "primary" and "primary" or "tactical"
            hud.compact = false
            mainStyle.show = true
            burstStyle.show = hud.queueMode ~= "primary"
        end)
        y = y - 38
        createNumberStepper(pane, "主键大小", LEFT_X, y, 56, function() return mainStyle.iconSize end, function(value) setModuleIconSize("main", value) end, 2, 44, 120, "")
        createNumberStepper(pane, "爆发大小", RIGHT_X, y, 56, function() return burstStyle.iconSize end, function(value) setModuleIconSize("burst", value) end, 2, 28, 88, "")

        y = y - 76
        y = createSection(pane, "排列", y)
        createChoice(pane, "爆发方向", RIGHT_X, y, 170, {
            { value = "RIGHT", label = "向右" }, { value = "LEFT", label = "向左" }, { value = "UP", label = "向上" }, { value = "DOWN", label = "向下" },
        }, function() return hud.burstGrowth end, function(value) hud.burstGrowth = value end)
        y = y - 38
        createNumberStepper(pane, "图标间距", LEFT_X, y, 56, function() return hud.gap end, function(value) hud.gap = value end, 1, 2, 24, "")

        y = y - 76
        y = createSection(pane, "外观", y)
        createNumberStepper(pane, "HUD 缩放", LEFT_X, y, 64, function() return math.floor(hud.scale * 100 + 0.5) end,
            function(value) hud.scale = value / 100 end, 5, 60, 200, "%")
        createNumberStepper(pane, "HUD 透明度", RIGHT_X, y, 64, function() return math.floor(hud.alpha * 100 + 0.5) end,
            function(value) hud.alpha = value / 100 end, 5, 20, 100, "%")
        y = y - 38
        createNumberStepper(pane, "底纹透明度", LEFT_X, y, 64, function() return math.floor(hud.backdropAlpha * 100 + 0.5) end,
            function(value) hud.backdropAlpha = value / 100 end, 2, 0, 100, "%")
        createCheckbox(pane, "显示按键", RIGHT_X, y, function() return hud.showKeyLabels end, function(value) hud.showKeyLabels = value end)
        y = y - 38
        createCheckbox(pane, "显示状态文字", LEFT_X, y, function() return hud.showStatusText end, function(value) hud.showStatusText = value end)
        createCheckbox(pane, "显示冷却秒数", RIGHT_X, y, function()
            return mainStyle.cooldownText.enabled ~= false and burstStyle.cooldownText.enabled ~= false
        end, function(value)
            mainStyle.cooldownText.enabled = value
            burstStyle.cooldownText.enabled = value
        end)
        y = y - 38
        createNumberStepper(pane, "冷却字号", LEFT_X, y, 56, function() return mainStyle.cooldownText.fontSize end, function(value)
            mainStyle.cooldownText.fontSize = value
            burstStyle.cooldownText.fontSize = value
        end, 1, 8, 30, "")

        y = y - 76
        y = buildHudLabelStyles(pane, mainStyle, burstStyle, y)

        y = y - 76
        createActionButton(pane, "锁定 / 解锁", LEFT_X, y, 118, function() hud.locked = not hud.locked; ControlPanel:ApplyVisuals(true) end)
        createActionButton(pane, "重置布局", 142, y, 104, function() ControlPanel:ResetTacticalLayout() end)
        createActionButton(pane, "恢复默认", 256, y, 104, function() ControlPanel:ResetDisplaySettings() end)
        createActionButton(pane, "隐藏 HUD", 370, y, 96, function() hud.enabled = false; ControlPanel:ApplyVisuals(true) end)
        return
    end
end

local function buildBurstSettings(pane)
    local y = -12
    local tactics = select(1, ensureTactics())
    y = createSection(pane, "自动爆发", y)
    createCheckbox(pane, "启用自动爆发", 14, y, function() return tactics.autoBurstEnabled == true end, function(value)
        tactics.autoBurstEnabled = value == true
    end, "命中窗口技能后，按下方顺序执行已启用并通过检查的步骤。")
    y = y - 38
    createChoice(pane, "执行模式", 14, y, 300, {
        { value = "simple", label = "简易：跳过本轮不可用步骤" },
        { value = "focused", label = "严格：任一步骤不可用则不启动" },
    }, function() return tactics.autoBurstMode end, function(value)
        tactics.autoBurstMode = value == "focused" and "focused" or "simple"
    end, "简易模式尽量完成可用步骤；严格模式要求所有启用步骤都可用。")
    y = y - 48

    y = createSection(pane, "爆发顺序（当前专精）", y)
    createText(pane, "GameFontDisableSmall", 14, y, 720,
        "HUD 与自动爆发都使用此顺序。窗口技能固定保留；注入和饰品可调整位置或停用。")
    y = y - 38

    local function sequenceBurstContext()
        return (TE.Context and TE.Context:GetPlayer()) or {}
    end
    local function sequenceSpellLabel(spellID)
        spellID = tonumber(spellID)
        local name
        if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
            local ok, value = pcall(C_Spell.GetSpellName, spellID)
            if ok and type(value) == "string" and value ~= "" then name = value end
        end
        if not name and spellID and type(GetSpellInfo) == "function" then
            local ok, value = pcall(GetSpellInfo, spellID)
            if ok and type(value) == "string" and value ~= "" then name = value end
        end
        return (name or "SpellID") .. " " .. tostring(spellID or "-")
    end
    local function sequenceEntryLabel(entry)
        if not entry then return "" end
        if entry.category == "window" then
            return "窗口技能：" .. sequenceSpellLabel(entry.spellID) .. "（固定）"
        end
        if entry.category == "trinket" then
            return "饰品 " .. tostring(entry.inventorySlot or "?") .. "：实时装备栏步骤"
        end
        return "注入技能 " .. tostring(entry.slotIndex or "?") .. "：" .. sequenceSpellLabel(entry.spellID)
    end
    local sequenceRows = {}
    local refreshSequenceRows
    for rowIndex = 1, 6 do
        local row = { index = rowIndex }
        row.label = createText(pane, "GameFontHighlightSmall", 14, y - 4, 332, "")
        row.up = createActionButton(pane, "上", 354, y, 38, function()
            if not row.key or not (TE.BurstProfiles and TE.BurstProfiles.MoveAutoBurstStep) then return end
            local ok, reason = TE.BurstProfiles:MoveAutoBurstStep(sequenceBurstContext(), row.key, -1)
            if not ok then panelStatus("爆发顺序未调整：" .. tostring(reason)) end
            if refreshSequenceRows then refreshSequenceRows() end
            ControlPanel:ApplyVisuals(false)
        end)
        row.down = createActionButton(pane, "下", 398, y, 38, function()
            if not row.key or not (TE.BurstProfiles and TE.BurstProfiles.MoveAutoBurstStep) then return end
            local ok, reason = TE.BurstProfiles:MoveAutoBurstStep(sequenceBurstContext(), row.key, 1)
            if not ok then panelStatus("爆发顺序未调整：" .. tostring(reason)) end
            if refreshSequenceRows then refreshSequenceRows() end
            ControlPanel:ApplyVisuals(false)
        end)
        row.toggle = createActionButton(pane, "启用", 444, y, 62, function()
            if not row.key or row.fixed or not (TE.BurstProfiles and TE.BurstProfiles.SetAutoBurstStepEnabled) then return end
            local ok, reason = TE.BurstProfiles:SetAutoBurstStepEnabled(sequenceBurstContext(), row.key, not row.enabled)
            if not ok then panelStatus("步骤状态未调整：" .. tostring(reason)) end
            if refreshSequenceRows then refreshSequenceRows() end
            ControlPanel:ApplyVisuals(false)
        end)
        row.fixedLabel = createText(pane, "GameFontDisableSmall", 516, y - 4, 88, "固定")
        sequenceRows[#sequenceRows + 1] = row
        y = y - 34
    end
    refreshSequenceRows = function()
        local sequence
        if TE.BurstProfiles and type(TE.BurstProfiles.GetAutoBurstSequence) == "function" then
            sequence = select(1, TE.BurstProfiles:GetAutoBurstSequence(sequenceBurstContext()))
        end
        local entries = sequence and sequence.entries or {}
        for index, row in ipairs(sequenceRows) do
            local entry = entries[index]
            row.key = entry and entry.key or nil
            row.enabled = entry and entry.enabled == true or false
            row.fixed = entry and entry.fixed == true or false
            row.label:SetShown(entry ~= nil)
            row.up:SetShown(entry ~= nil and index > 1)
            row.down:SetShown(entry ~= nil and index < #entries)
            row.toggle:SetShown(entry ~= nil and row.fixed ~= true)
            row.fixedLabel:SetShown(entry ~= nil and row.fixed == true)
            if entry then
                row.label:SetText(sequenceEntryLabel(entry) .. (entry.enabled == true and "" or "（已停用）"))
                row.toggle.text:SetText(row.enabled and "停用" or "启用")
            end
        end
    end
    registerControl(refreshSequenceRows)
    refreshSequenceRows()
    y = y - 8
    createText(pane, "GameFontDisableSmall", 14, y, 720,
        "要更换窗口或注入技能，请使用下方技能列表。饰品 13 / 14 始终代表对应装备栏。")
    y = y - 34

    local function getSequenceEntry(key)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.GetAutoBurstSequence) == "function") then return nil end
        local sequence = select(1, TE.BurstProfiles:GetAutoBurstSequence(sequenceBurstContext()))
        for _, entry in ipairs(sequence and sequence.entries or {}) do
            if entry.key == key then return entry end
        end
        return nil
    end
    local function setTrinketOffGCD(key, value)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.SetAutoBurstTrinketOffGCD) == "function") then return end
        local ok, reason = TE.BurstProfiles:SetAutoBurstTrinketOffGCD(sequenceBurstContext(), key, value == true)
        if not ok then panelStatus("饰品 GCD 设置未调整：" .. tostring(reason)) end
    end
    createCheckbox(pane, "饰品 13 已确认脱 GCD", 14, y, function()
        local entry = getSequenceEntry("trinket:13")
        return entry and entry.offGCDExplicit == true
    end, function(value) setTrinketOffGCD("trinket:13", value) end,
        "只在实测确认该饰品不触发公共冷却时勾选。")
    createCheckbox(pane, "饰品 14 已确认脱 GCD", RIGHT_X, y, function()
        local entry = getSequenceEntry("trinket:14")
        return entry and entry.offGCDExplicit == true
    end, function(value) setTrinketOffGCD("trinket:14", value) end,
        "只在实测确认该饰品不触发公共冷却时勾选。")
    y = y - 54

    local function currentBurstContext()
        return (TE.Context and TE.Context:GetPlayer()) or {}
    end
    local function editableBurstEntries(kind)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.GetEditableList) == "function") then
            return {}, nil, "BurstProfiles 未加载", nil
        end
        return TE.BurstProfiles:GetEditableList(currentBurstContext(), kind)
    end
    local function burstMove(kind, spellID, delta)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.Move) == "function") then return false, "BurstProfiles 未加载" end
        return TE.BurstProfiles:Move(currentBurstContext(), kind, spellID, delta)
    end
    local function burstEnable(kind, spellID, enabled)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.SetEnabled) == "function") then return false, "BurstProfiles 未加载" end
        return TE.BurstProfiles:SetEnabled(currentBurstContext(), kind, spellID, enabled)
    end
    local function burstRemove(kind, spellID)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.RemoveCustom) == "function") then return false, "BurstProfiles 未加载" end
        return TE.BurstProfiles:RemoveCustom(currentBurstContext(), kind, spellID)
    end
    local function burstAdd(kind, spellID)
        if not (TE.BurstProfiles and type(TE.BurstProfiles.AddCustom) == "function") then return false, "BurstProfiles 未加载" end
        return TE.BurstProfiles:AddCustom(currentBurstContext(), kind, spellID)
    end
    local function burstRestore()
        if not (TE.BurstProfiles and type(TE.BurstProfiles.RestoreDefaults) == "function") then return false, "BurstProfiles 未加载" end
        return TE.BurstProfiles:RestoreDefaults(currentBurstContext())
    end

    y = createSpellPriorityEditor(pane, "官方窗口候选库", "首个已启用、已知且有真实键位的技能是自动爆发窗口锚点。上方窗口步骤固定存在，可调整位置。", y, {
        maxRows = 5,
        enabledLabel = "窗口优先级",
        removeLabel = "停用",
        getEntries = function() return editableBurstEntries("trigger") end,
        move = function(spellID, delta) return burstMove("trigger", spellID, delta) end,
        setEnabled = function(spellID, enabled) return burstEnable("trigger", spellID, enabled) end,
        remove = function(spellID) return burstRemove("trigger", spellID) end,
        add = function(spellID) return burstAdd("trigger", spellID) end,
        addLabel = "添加触发技能",
        showRestore = false,
    })

    y = createSpellPriorityEditor(pane, "注入技能", "当前专精已启用的前 6 项可加入上方爆发顺序。此处维护 SpellID 和优先级；上方只调参与和位置。", y, {
        maxRows = 6,
        enabledLabel = "注入优先级",
        removeLabel = "停用",
        getEntries = function() return editableBurstEntries("injection") end,
        move = function(spellID, delta) return burstMove("injection", spellID, delta) end,
        setEnabled = function(spellID, enabled) return burstEnable("injection", spellID, enabled) end,
        remove = function(spellID) return burstRemove("injection", spellID) end,
        add = function(spellID) return burstAdd("injection", spellID) end,
        addLabel = "添加注入技能",
        restore = burstRestore,
        resetLabel = "恢复当前专精全部爆发默认",
    })

end

local function buildBurst(pane)
    buildBurstSettings(pane)
end

local function buildProfiles(pane)
    local y = createSection(pane, "当前配置", -12)
    createReadout(pane, "profileState", "状态", 14, y, 720, "GameFontHighlightSmall")
    y = y - 126
    y = createSection(pane, "配置文件管理", y)
    profileNameBox = createEditBox(pane, "配置名称", 14, y, 250, TE.ProfileManager and TE.ProfileManager:GetActiveName() or "Default")
    createActionButton(pane, "载入", 456, y, 78, function()
        local manager = TE.ProfileManager
        if not manager then return end
        profileAction("已载入", function() return manager:Activate(profileNameBox:GetText(), "teui_load") end)
    end)
    createActionButton(pane, "新建并载入", 544, y, 112, function()
        local manager = TE.ProfileManager
        if not manager then return end
        profileAction("已新建", function()
            local ok, value = manager:Duplicate(profileNameBox:GetText())
            if not ok then return ok, value end
            return manager:Activate(value, "teui_create")
        end)
    end)
    y = y - 38
    createActionButton(pane, "重命名当前", 14, y, 112, function()
        local manager = TE.ProfileManager
        if not manager then return end
        profileAction("已重命名", function() return manager:Rename(manager:GetActiveName(), profileNameBox:GetText()) end)
    end)
    createActionButton(pane, "删除指定配置", 136, y, 112, function()
        local manager = TE.ProfileManager
        if not manager then return end
        profileAction("删除", function() return manager:Delete(profileNameBox:GetText()) end)
    end)
    createActionButton(pane, "保存当前", 258, y, 96, function()
        local manager = TE.ProfileManager
        if not manager then return end
        profileAction("已保存", function() return manager:SaveActive() end)
    end)
    createText(pane, "GameFontDisableSmall", 14, y - 42, 720,
        "新建会复制当前配置。Default 不可删除。配置只保存设置与战术 HUD 偏好，不复制动作条绑定，也不保存或生成 TEAP / Token。")
    y = y - 96
    y = createSection(pane, "重置", y)
    createActionButton(pane, "重置 HUD 布局", 14, y, 128, function() ControlPanel:ResetTacticalLayout() end)
    createActionButton(pane, "恢复显示默认", 152, y, 128, function() ControlPanel:ResetDisplaySettings() end)
    createActionButton(pane, "重置设置窗口位置", 290, y, 146, function() ControlPanel:ResetPosition() end)
    y = y - 76

    y = createSection(pane, "高级设置", y)
    local advancedFrame = CreateFrame("Frame", nil, pane)
    advancedFrame:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y - 44)
    advancedFrame:SetSize(CONTENT_PANE_WIDTH, 260)
    local advancedButton
    local function refreshAdvanced()
        advancedFrame:SetShown(profilesAdvancedExpanded == true)
        if advancedButton and advancedButton.text then
            advancedButton.text:SetText(profilesAdvancedExpanded and "收起自动切换" or "展开自动切换")
        end
    end
    advancedButton = createActionButton(pane, "展开自动切换", 14, y, 136, function()
        profilesAdvancedExpanded = not profilesAdvancedExpanded
        refreshAdvanced()
    end)

    local advancedY = createSection(advancedFrame, "按范围自动切换", -12)
    createReadout(advancedFrame, "profileScopes", "当前映射", 14, advancedY, 720, "GameFontHighlightSmall")
    advancedY = advancedY - 116
    local manager = TE.ProfileManager
    local keys = manager and manager:GetScopeKeys() or {}
    createActionButton(advancedFrame, "全局 ← 当前", 14, advancedY, 112, function()
        profileAction("全局映射", function() return TE.ProfileManager:SetScopeProfile(keys.global, TE.ProfileManager:GetActiveName()) end)
    end)
    createActionButton(advancedFrame, "角色 ← 当前", 136, advancedY, 112, function()
        profileAction("角色映射", function() return TE.ProfileManager:SetScopeProfile(keys.character, TE.ProfileManager:GetActiveName()) end)
    end)
    createActionButton(advancedFrame, "职业 ← 当前", 258, advancedY, 112, function()
        profileAction("职业映射", function() return TE.ProfileManager:SetScopeProfile(keys.class, TE.ProfileManager:GetActiveName()) end)
    end)
    createActionButton(advancedFrame, "专精 ← 当前", 380, advancedY, 112, function()
        profileAction("专精映射", function() return TE.ProfileManager:SetScopeProfile(keys.spec, TE.ProfileManager:GetActiveName()) end)
    end)
    advancedY = advancedY - 42
    createActionButton(advancedFrame, "清除全局", 14, advancedY, 112, function() profileAction("清除全局", function() return TE.ProfileManager:ClearScopeProfile(keys.global) end) end)
    createActionButton(advancedFrame, "清除角色", 136, advancedY, 112, function() profileAction("清除角色", function() return TE.ProfileManager:ClearScopeProfile(keys.character) end) end)
    createActionButton(advancedFrame, "清除职业", 258, advancedY, 112, function() profileAction("清除职业", function() return TE.ProfileManager:ClearScopeProfile(keys.class) end) end)
    createActionButton(advancedFrame, "清除专精", 380, advancedY, 112, function() profileAction("清除专精", function() return TE.ProfileManager:ClearScopeProfile(keys.spec) end) end)
    refreshAdvanced()
end

local BUILDERS = {
    general = buildGeneral,
    hud = buildHUD,
    burst = buildBurst,
    profiles = buildProfiles,
}

local function showCompactTooltip(owner, status)
    if not GameTooltip or not owner or not status then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:SetText(status.label, 0.80, 0.92, 1)
    if status.intent and status.showIntent then GameTooltip:AddLine("运行意图：" .. status.intent, 1, 1, 1, true) end
    if status.reasonText then GameTooltip:AddLine("原因：" .. status.reasonText, 1, 1, 1, true) end
    if status.rawReason then GameTooltip:AddLine("原始原因：" .. status.rawReason, 0.70, 0.75, 0.84, true) end
    if status.label == "未运行" then GameTooltip:AddLine("点击 ▶ 启动", 1, 1, 1, true) end
    GameTooltip:Show()
end

local function createCompactView(parent)
    compactView = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    compactView:SetPoint("TOPLEFT", parent, "TOPLEFT", 3, -3)
    compactView:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 3)
    panelBackdrop(compactView, 0.008, 0.012, 0.022, 0.98, 0.48, 0.56, 0.68, 1)

    local dragArea = CreateFrame("Frame", nil, compactView)
    dragArea:SetPoint("TOPLEFT", compactView, "TOPLEFT", 5, -3)
    dragArea:SetPoint("BOTTOMRIGHT", compactView, "BOTTOMRIGHT", -61, 3)
    dragArea:EnableMouse(true)
    dragArea:RegisterForDrag("LeftButton")
    dragArea:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragArea:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if InCombatLockdown and InCombatLockdown() then pendingCompactPositionSave = true else savePanelPosition("compact") end
    end)
    dragArea:SetScript("OnEnter", function(self) showCompactTooltip(self, ControlPanel:GetCompactStatus()) end)
    dragArea:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    labels.compactRunState = dragArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labels.compactRunState:SetPoint("LEFT", dragArea, "LEFT", 3, 0)
    labels.compactRunState:SetPoint("RIGHT", dragArea, "RIGHT", -2, 0)
    labels.compactRunState:SetJustifyH("LEFT")
    labels.compactRunState:SetJustifyV("MIDDLE")
    labels.compactRunState:SetWordWrap(false)
    labels.compactRunState:SetText("未运行")

    compactToggleButton = createActionButton(compactView, "▶", 220, -5, 24, function() ControlPanel:ToggleRun() end)
    createActionButton(compactView, "□", 248, -5, 24, function() ControlPanel:Restore() end)
    compactView:Hide()
end

function ControlPanel:Create()
    if frame then return frame end
    ensureSettings(); ensureTactics()
    frame = CreateFrame("Frame", "TacticEchoSettingsCenter", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    panelBackdrop(frame, 0.008, 0.012, 0.022, 0.98, 0.48, 0.56, 0.68, 1)

    normalHeader = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    normalHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
    normalHeader:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -7)
    normalHeader:SetHeight(48)
    normalHeader:EnableMouse(true)
    panelBackdrop(normalHeader, 0.05, 0.07, 0.12, 0.97, 0.38, 0.48, 0.64, 1)
    normalHeader:RegisterForDrag("LeftButton")
    normalHeader:SetScript("OnDragStart", function() frame:StartMoving() end)
    normalHeader:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePanelPosition("normal") end)
    local title = createText(normalHeader, "GameFontNormalLarge", 18, -12, 500, "Tactic Echo · 战术回响")
    title:SetTextColor(1.00, 0.83, 0.10)
    local subtitle = createText(normalHeader, "GameFontDisableSmall", 20, -31, 580, "设置中心 · HUD 与策略分离 · 只读战术建议")
    subtitle:SetTextColor(0.68, 0.78, 0.94)
    -- Anchor the changing state text to the fixed action-button block rather
    -- than a raw X coordinate. This keeps it centered vertically and prevents
    -- a long state label from drifting into the minimize / close controls.
    labels.headerState = normalHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labels.headerState:SetPoint("RIGHT", normalHeader, "RIGHT", -116, 0)
    labels.headerState:SetSize(320, 20)
    labels.headerState:SetJustifyH("RIGHT")
    labels.headerState:SetJustifyV("MIDDLE")
    labels.headerState:SetText("等待状态")
    labels.headerState:SetTextColor(0.72, 0.92, 0.82)
    createActionButton(normalHeader, "-", 962, -10, 40, function() ControlPanel:Minimize() end)
    createActionButton(normalHeader, "×", 1008, -10, 40, function() ControlPanel:Hide() end)

    normalNavigation = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    normalNavigation:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -62)
    normalNavigation:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 50)
    normalNavigation:SetWidth(NAV_WIDTH)
    panelBackdrop(normalNavigation, 0.035, 0.05, 0.09, 0.96, 0.22, 0.30, 0.45, 1)
    local navTitle = createText(normalNavigation, "GameFontNormalLarge", 16, -18, 190, "设置导航")
    navTitle:SetTextColor(0.90, 0.94, 1.00)
    createLine(normalNavigation, 16, -48, 190)
    local navY = -62
    for _, page in ipairs(NAV_ORDER) do
        local meta = PAGE_META[page]
        local button = createActionButton(normalNavigation, meta.label, 16, navY, 194, function() ControlPanel:Show(page) end)
        button.text:SetJustifyH("LEFT")
        button.text:ClearAllPoints()
        button.text:SetPoint("LEFT", button, "LEFT", 14, 0)
        navButtons[page] = button
        navY = navY - 38
    end

    normalMain = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    normalMain:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_WIDTH + 24, -62)
    normalMain:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 50)
    panelBackdrop(normalMain, 0.022, 0.03, 0.055, 0.97, 0.22, 0.32, 0.48, 1)
    labels.pageTitle = createText(normalMain, "GameFontNormalLarge", 18, -16, 400, "常规")
    labels.pageTitle:SetTextColor(1.00, 0.83, 0.10)
    labels.pageDescription = createText(normalMain, "GameFontDisableSmall", 20, -39, 720, PAGE_META.general.description)
    labels.pageDescription:SetTextColor(0.68, 0.78, 0.94)
    createLine(normalMain, 18, -64, 760)

    local content = CreateFrame("Frame", nil, normalMain)
    content:SetPoint("TOPLEFT", normalMain, "TOPLEFT", 16, -78)
    content:SetPoint("BOTTOMRIGHT", normalMain, "BOTTOMRIGHT", -34, 14)
    for page, builder in pairs(BUILDERS) do
        local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
        scroll:SetAllPoints(content)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            self:SetVerticalScroll(math.max(0, (self:GetVerticalScroll() or 0) - (delta or 0) * 42))
        end)
        local pane = CreateFrame("Frame", nil, scroll)
        pane:SetSize(CONTENT_PANE_WIDTH, CONTENT_PANE_HEIGHT) -- replaces legacy pane:SetSize(672, 1320) with a bounded two-column layout.
        scroll:SetScrollChild(pane)
        panes[page] = scroll
        scroll:Hide()
        controlBuildScope = page
        builder(pane)
        controlBuildScope = nil
    end

    normalFooter = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    normalFooter:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    normalFooter:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    normalFooter:SetHeight(30)
    panelBackdrop(normalFooter, 0.035, 0.05, 0.09, 0.98, 0.22, 0.30, 0.45, 1)
    labels.footerState = createText(normalFooter, "GameFontHighlightSmall", 12, -8, 300, "当前配置：Default")
    labels.footerStatus = createText(normalFooter, "GameFontDisableSmall", 310, -8, 430, "设置自动保存到当前配置。")
    createActionButton(normalFooter, "应用并保存", 752, -2, 108, function()
        ControlPanel:ApplyVisuals(true)
        setLabel("footerStatus", "设置已应用并保存到当前配置。")
    end)
    createActionButton(normalFooter, "关闭", 870, -2, 78, function() ControlPanel:Hide() end)

    createCompactView(frame)
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + elapsed
        if elapsedSinceRefresh < REFRESH_INTERVAL then return end
        elapsedSinceRefresh = 0
        if frame:IsShown() then
            -- TacticalAdvisors owns recommendation polling. The settings center
            -- only updates its own diagnostic labels on this timer.
            ControlPanel:UpdateInputStatus()
        end
    end)

    restorePanelPosition("normal")
    local store = root()
    activePage = PAGE_META[store.page] and store.page or "general"
    local meta = PAGE_META[activePage]
    for page, button in pairs(navButtons) do
        button.selected = page == activePage
        setButtonVisual(button, button.selected)
    end
    for page, pane in pairs(panes) do pane:SetShown(page == activePage) end
    setLabel("pageTitle", meta.label)
    setLabel("pageDescription", meta.description)
    applyPanelPresentation(store.minimized == true)
    restorePanelPosition(store.minimized == true and "compact" or "normal")
    frame:Hide()
    return frame
end

local eventFrame = CreateFrame("Frame")
TE:RegisterEventsSafe(eventFrame, { "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED" })
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingApplyAfterCombat then ControlPanel:ApplyStoredToggleHotkey() end
        if pendingAutoBurstApplyAfterCombat then ControlPanel:ApplyStoredAutoBurstHotkey() end
        if pendingCompactPositionSave then
            pendingCompactPositionSave = false
            if root().minimized == true then savePanelPosition("compact") end
        end
        return
    end
    local store = root()
    ControlPanel:Create()
    ControlPanel:ApplyStoredToggleHotkey()
    ControlPanel:ApplyStoredAutoBurstHotkey()
    if store.visible and store.minimized == true then
        frame:Show()
        ControlPanel:UpdateInputStatus()
    elseif store.visible then
        ControlPanel:Show(store.page)
    else
        ControlPanel:Hide()
    end
end)

SLASH_TACTICECHOUI1 = "/teui"
SlashCmdList.TACTICECHOUI = function(message)
    local command = string.lower(message or "")
    if command == "reset" then
        ControlPanel:Create(); ControlPanel:ResetPosition()
    elseif command == "start" or command == "general" or command == "settings" then
        ControlPanel:Show("general")
    elseif command == "hud" or command == "tactics" then
        ControlPanel:Show("hud")
    elseif command == "main" or command == "primary" then
        ControlPanel:Show("main")
    elseif command == "burst" then
        ControlPanel:Show("burst")
    elseif command == "interrupt" then
        ControlPanel:Show("interrupt", "interrupt")
    elseif command == "control" then
        ControlPanel:Show("interrupt", "control")
    elseif command == "interruptstyle" or command == "reactionstyle" then
        ControlPanel:Show("interrupt", "style")
    elseif command == "defense" or command == "defensive" then
        ControlPanel:Show("defense")
    elseif command == "debug" or command == "monitor" or command == "actionbar" or command == "safety" then
        ControlPanel:Show("monitor")
    elseif command == "profile" or command == "profiles" then
        ControlPanel:Show("profiles")
    elseif command == "compact" then
        ControlPanel:SetCompact(true)
    elseif command == "min" or command == "minimize" then
        ControlPanel:Minimize()
    elseif command == "restore" or command == "expand" then
        ControlPanel:Restore()
    elseif command == "refresh" then
        ControlPanel:RefreshActionBar("slash_settings")
    elseif command == "close" or command == "hide" then
        ControlPanel:Hide()
    else
        ControlPanel:Toggle()
    end
end
