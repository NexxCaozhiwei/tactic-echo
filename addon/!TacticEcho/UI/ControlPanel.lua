-- Tactic Echo settings center (TEUI v2).
--
-- The settings center intentionally separates three concerns:
--   1. visual presentation (HUD / icon labels / layout),
--   2. display-only tactical advisory policy (burst, interrupt, defense), and
--   3. configuration profiles.
--
-- No setting in this file creates a recommendation, writes a binding,
-- changes a BindingToken, mutates TEAP, or asks TEK to send input. Tactical
-- modules remain display-only even when their policy pages are enabled.
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
local navButtons = {}
local labels = {}
local controls = {}
local profileNameBox
local elapsedSinceRefresh = 0
local hotkeyOwner
local hotkeyCapture
local pendingToggleHotkey
local pendingApplyAfterCombat = false
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
local CONTENT_PANE_HEIGHT = 2500
local CONTENT_MARGIN = 14
local LEFT_X = 14
local RIGHT_X = 376
local COLUMN_GUTTER = 18
local CONTROL_LABEL_WIDTH = 126
local CONTROL_GAP = 8

local PAGE_META = {
    general = { label = "常规", description = "运行状态、手动启停 / 脱战策略与 Tactic Echo 自身快捷键。" },
    hud = { label = "HUD", description = "四模块显示、图标大小、队列模式、全局标签和布局。" },
    main = { label = "主键", description = "主推荐队列的按键、充能、冷却时间和转盘遮罩样式。" },
    burst = { label = "爆发", description = "爆发窗口辅助的图标样式与只读策略。" },
    interrupt = { label = "打断与控制", description = "打断、控制提示的图标样式与目标读条策略。" },
    defense = { label = "防御与生存", description = "专精防御提示、治疗石与血瓶提示的显示策略。" },
    monitor = { label = "监控与调试", description = "动作条、专精、推荐链路、协议与安全诊断。" },
    profiles = { label = "配置文件", description = "Default、角色、职业、专精的配置保存与自动切换。" },
}

local NAV_ORDER = { "general", "hud", "main", "burst", "interrupt", "defense", "monitor", "profiles" }
local LEGACY_PAGE_ALIAS = {
    tactics = "hud", actionbar = "monitor", safety = "monitor", defensive = "defense",
}
-- Legacy labels are retained for external slash/menu integrations only. They
-- map into the eight pages above and never create duplicate navigation entries.
local LEGACY_PAGE_LABELS = {
    actionbar = { label = "动态动作条" },
    tactics = { label = "战术显示" },
    safety = { label = "派发与安全" },
}

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

local function safePrint(message)
    if TE and type(TE.Print) == "function" then
        TE:Print(message)
    elseif print then
        print("|cff67c8ffTactic Echo|r " .. tostring(message))
    end
end

local function root()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.ui = type(TacticEchoDB.ui) == "table" and TacticEchoDB.ui or {}
    TacticEchoDB.ui.settingsCenter = type(TacticEchoDB.ui.settingsCenter) == "table" and TacticEchoDB.ui.settingsCenter or {}
    local store = TacticEchoDB.ui.settingsCenter
    if TacticEchoDB.ui.settingsCenter.minimized == nil then TacticEchoDB.ui.settingsCenter.minimized = false end
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
        style.mode = ({ auto = true, custom = true, duration = true })[style.mode] and style.mode or (defaults.mode or "auto")
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
        enabled = true, mode = "auto", fontPreset = "highlight", fontSize = 14, scale = 1,
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

local function getCurrentBurstOverride()
    local tactics = select(1, ensureTactics())
    local context = TE.Context and TE.Context:GetPlayer() or {}
    local key = tostring(context.class or "UNKNOWN") .. "_" .. tostring(tonumber(context.specIndex) or 0)
    tactics.burstProfiles[key] = type(tactics.burstProfiles[key]) == "table" and tactics.burstProfiles[key] or {}
    return tactics.burstProfiles[key], key, context
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
        button:SetBackdropColor(0.10, 0.18, 0.32, 0.98)
        button:SetBackdropBorderColor(0.55, 0.74, 1.00, 1)
        if button.text then button.text:SetTextColor(1.00, 0.85, 0.18) end
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
    button:SetScript("OnLeave", function(self) setButtonVisual(self, false) end)
    button:SetScript("OnClick", function() if callback then callback() end end)
    setButtonVisual(button, false)
    return button
end

local function registerControl(refresh)
    controls[#controls + 1] = refresh
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

local function createColorChoice(parent, label, x, y, getter, setter)
    local choices = {}
    for key, preset in pairs(COLOR_PRESETS) do choices[#choices + 1] = { value = key, label = preset.label } end
    table.sort(choices, function(left, right) return left.label < right.label end)
    return createChoice(parent, label, x, y, 150, choices, getter, setter)
end

local function createReadout(parent, key, title, x, y, width, template)
    local caption = createText(parent, "GameFontHighlight", x, y, width or (CONTENT_PANE_WIDTH - CONTENT_MARGIN * 2), title)
    local value = createText(parent, template or "GameFontHighlightSmall", x, y - 24, width or (CONTENT_PANE_WIDTH - CONTENT_MARGIN * 2), "等待刷新")
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

local function specialActionObservation(snapshot)
    local state = snapshot and snapshot.specialActionBar or nil
    if type(state) ~= "table" then return nil end
    if state.active == true then
        return "替换型特殊动作条已阻断：" .. tostring(state.reason or "unknown")
    end
    if state.extraActionVisible == true then
        local sources = type(state.extraActionSources) == "table" and table.concat(state.extraActionSources, ", ") or ""
        return "额外动作条：已显示（仅观察，不阻断）" .. (sources ~= "" and " · " .. sources or "")
    end
    return nil
end

local function getBindingSummary()
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.GetCacheSummary) ~= "function" then return "动作条解析器：未加载" end
    local ok, summary = pcall(resolver.GetCacheSummary, resolver)
    if not ok or type(summary) ~= "table" then return "动作条解析器：读取失败" end
    return "扫描代次：" .. tostring(summary.scanGeneration or "-")
        .. "  ·  映射技能：" .. tostring(summary.spellCount or summary.mappedSpells or "-")
        .. "  ·  ButtonCache：" .. tostring(summary.buttonCount or summary.buttons or "-")
        .. "\n当前动作条页：" .. tostring(summary.mainPage or "-")
        .. "  ·  最近原因：" .. tostring(summary.lastReason or "-")
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

function ControlPanel:ApplyToggleHotkey(binding, fromStored)
    binding = type(binding) == "string" and binding or ""
    local settings = ensureSettings()
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

function ControlPanel:BeginToggleHotkeyCapture()
    local capture = ensureHotkeyCapture()
    capture:SetText("")
    capture:Show(); capture:SetFocus()
    setHotkeyHint("请按下启动/暂停快捷键组合；按 Esc 取消。该键只以临时覆盖方式服务于 TE，不会写入游戏动作条绑定。")
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

function ControlPanel:SetToggleHotkey(binding)
    return self:ApplyToggleHotkey(binding, false)
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

function ControlPanel:Show(page)
    page = LEGACY_PAGE_ALIAS[page] or page
    if not PAGE_META[page] then page = "general" end
    self:Create()
    root().visible = true
    if root().minimized then self:Restore() end
    activePage = page
    for key, button in pairs(navButtons) do setButtonVisual(button, key == activePage) end
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
        for _, key in ipairs({ "main", "burst", "interrupt", "defense" }) do
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

local function castGuidMatchDiagnostic()
    local signal = type(TacticEchoDB) == "table" and type(TacticEchoDB.signal) == "table" and TacticEchoDB.signal or nil
    local transition = signal and signal.lastCastLockTransition or nil
    local outcome = transition and transition.outcome or nil
    if outcome == "channel_cleared" or outcome == "empower_cleared" then
        return "匹配（" .. outcome .. ")"
    end
    if outcome == "channel_terminal_guid_mismatch" or outcome == "empower_terminal_guid_mismatch" then
        return "不匹配，锁保持（" .. outcome .. ")"
    end
    if outcome == "channel_api_fallback_cleared" or outcome == "empower_api_fallback_cleared" then
        return "API 回退，无 GUID（" .. outcome .. ")"
    end
    if outcome and outcome ~= "" then return "未校验（" .. outcome .. ")" end
    return "未记录"
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
    local label = USER_STATE_LABELS[rawState] or "状态未知"
    local status = {
        label = label,
        rawState = rawState,
        rawReason = nil,
        intent = intent,
        intentState = rawIntent,
        reasonText = userVisibleReason(rawReason, reasonText),
    }
    if rawState == "blocked" then
        status.showIntent = true
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
    local encoded = TE.SignalFrame and TE.SignalFrame:GetLastEncoded() or {}
    local primary = snapshot.primaryDisplay or snapshot.primary or {}
    local advisory = snapshot.advisory or {}
    local interrupt = snapshot.interrupt or {}
    local defense = snapshot.defensives or {}

    local compactStatus = self:GetCompactStatus()
    setLabel("headerState", "状态：" .. compactStatus.label .. "  ·  " .. tostring(context.class or "-") .. " / " .. tostring(context.specName or "未知专精"))
    setLabel("compactRunState", compactStatus.label)
    if compactToggleButton and compactToggleButton.text then
        compactToggleButton.text:SetText(compactToggleGlyph(compactStatus))
    end
    setLabel("footerState", "当前配置：" .. (TE.ProfileManager and TE.ProfileManager:GetActiveName() or "Default"))
    local specialObservation = specialActionObservation(snapshot)
    local runtimeReasonLine = compactStatus.reasonText and ("\n原因：" .. compactStatus.reasonText) or ""
    setLabel("generalRuntime", "当前状态：" .. compactStatus.label
        .. runtimeReasonLine
        .. "\n当前职业/专精：" .. tostring(context.class or "-") .. " / " .. tostring(context.specName or "未知")
        .. "\n官方主推荐：" .. tostring(primary.spellName or "等待") .. "  ·  键位：" .. tostring(primary.binding or "无")
        .. "\n动作条映射：" .. (primary.binding and "已确认" or "等待或无绑定")
        .. (specialObservation and ("\n" .. specialObservation) or ""))
    local policyLabel = TE.SignalFrame and type(TE.SignalFrame.GetSessionPolicyLabel) == "function"
        and TE.SignalFrame:GetSessionPolicyLabel() or tostring(settings.sessionPolicy)
    setLabel("generalPolicy", "当前策略：" .. policyLabel
        .. "\n手动启停：脱战仍保持运行，直到手动暂停。"
        .. "\n脱战暂停：脱战显示暂停，进战自动恢复运行。"
        .. "\n脱战停止：脱战显示暂停，进战后仍暂停，需手动启动。"
        .. "\n“运行中”仅代表用户已启动动态链路；实际派发仍受 TEAP、前台与安全门禁约束。")
    setLabel("generalHotkey", settings.toggleHotkey ~= "" and ("TE 快捷键：" .. settings.toggleHotkey) or "TE 快捷键：未设置")

    setLabel("hudState", "HUD：" .. (hud.enabled and "显示" or "隐藏")
        .. "  ·  队列：" .. tostring(hud.queueMode)
        .. "  ·  候选上限：" .. tostring(hud.maxCandidates)
        .. "\n布局：" .. tostring(hud.layoutPreset) .. "  ·  主队列：" .. tostring(hud.primaryGrowth)
        .. "  ·  战术栏：" .. tostring(hud.tacticalGrowth))
    setLabel("mainState", "主推荐按键：" .. tostring(primary.binding or "无绑定")
        .. "\n标签、充能、CD 时间和转盘均可独立设置；所有样式仅影响显示层。")
    setLabel("burstState", "状态：" .. tostring((advisory.burst or {}).state or "等待")
        .. "  ·  配置：" .. tostring((advisory.burst or {}).profileKey or "当前专精暂无")
        .. "\n说明：" .. tostring((advisory.burst or {}).notice or "爆发模块只读"))
    setLabel("interruptState", "打断：" .. tostring(interrupt.state or "monitoring")
        .. "  ·  建议：" .. tostring(interrupt.suggestion and interrupt.suggestion.spellName or "无")
        .. "\n控制：" .. tostring((advisory.control or {}).state or "monitoring")
        .. "  ·  " .. tostring((advisory.control or {}).notice or "等待目标读条"))
    setLabel("defenseState", "防御：" .. tostring(defense.state or "monitoring")
        .. "  ·  配置：" .. tostring(defense.profileKey or "-")
        .. "\n来源：" .. tostring(defense.profileSource or "-")
        .. "  ·  当前建议：" .. tostring(defense.items and defense.items[1] and defense.items[1].spellName or "无")
        .. "\n说明：" .. tostring(defense.notice or "等待低血或高压兼容信号"))
    setLabel("monitorMapping", getBindingSummary())
    setLabel("monitorSpec", "当前职业：" .. tostring(context.class or "-")
        .. "\n当前专精：" .. tostring(context.specName or "未知") .. "（Index=" .. tostring(context.specIndex or "-") .. "，ID=" .. tostring(context.specID or "-") .. "）"
        .. "\n防御资料：" .. tostring(defense.profileKey or "-") .. " / " .. tostring(defense.profileSource or "-"))
    setLabel("monitorRecommendation", "官方：" .. tostring(primary.spellName or "等待") .. " / " .. tostring(primary.binding or "无")
        .. "\n爆发：" .. tostring((advisory.burst or {}).state or "-")
        .. "  ·  打断：" .. tostring(interrupt.state or "-")
        .. "  ·  防御：" .. tostring(defense.state or "-")
        .. "\n队列：" .. tostring(snapshot.queue and snapshot.queue.source or "等待"))
    local encodedFields = type(encoded and encoded.fields) == "table" and encoded.fields or {}
    local rawProtocolState = encoded and encoded.state or (snapshot.primary and snapshot.primary.state) or "-"
    local rawProtocolReason = snapshot.primary and snapshot.primary.reason or "-"
    local castLock = TE.SignalFrame and type(TE.SignalFrame.GetCastLockInfo) == "function" and TE.SignalFrame:GetCastLockInfo() or {}
    setLabel("monitorProtocol", "TEAP：v3 固定布局，仅官方主推荐可进入现有安全链。"
        .. "\n第4格：" .. tostring(encodedFields[4] or "-")
        .. "  ·  协议状态：" .. tostring(rawProtocolState)
        .. "  ·  原因码：" .. tostring(rawProtocolReason)
        .. "\n锁类型：" .. tostring(castLock.kind or "-")
        .. "  ·  施法 SpellID：" .. tostring(castLock.spellID or "-")
        .. "  ·  castGUID：" .. castGuidMatchDiagnostic()
        .. "\n最近帧：序号=" .. tostring(encoded and encoded.sequence or "-")
        .. "  ·  Token=" .. tostring(encoded and encoded.bindingToken or 0))
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

    for _, refresh in ipairs(controls) do pcall(refresh) end
end

local function buildTextStyleSection(pane, style, label, y, options)
    options = type(options) == "table" and options or {}
    y = createSection(pane, label, y)
    createCheckbox(pane, "显示", 14, y, function() return style.enabled end, function(value) style.enabled = value end)
    createChoice(pane, "字体", RIGHT_X, y, 160, {
        { value = "normal", label = "标准" }, { value = "highlight", label = "高亮" }, { value = "disable", label = "弱化" },
    }, function() return style.fontPreset end, function(value) style.fontPreset = value end)
    if options.cooldownMode == true then
        y = y - 38
        createChoice(pane, "CD 数字", 14, y, 160, {
            { value = "auto", label = "自动" }, { value = "duration", label = "原生" }, { value = "custom", label = "HUD" },
        }, function() return style.mode or "auto" end, function(value) style.mode = value end)
    end
    y = y - 38
    createNumberStepper(pane, "字号", 14, y, 64, function() return style.fontSize end, function(value) style.fontSize = value end, 1, 8, 30, "")
    createNumberStepper(pane, "缩放", RIGHT_X, y, 64, function() return math.floor(style.scale * 100 + 0.5) end, function(value) style.scale = value / 100 end, 10, 60, 200, "%")
    y = y - 38
    createChoice(pane, "位置", 14, y, 160, {
        { value = "TOPLEFT", label = "左上" }, { value = "TOPRIGHT", label = "右上" }, { value = "CENTER", label = "中间" },
        { value = "BOTTOMLEFT", label = "左下" }, { value = "BOTTOMRIGHT", label = "右下" },
    }, function() return style.point end, function(value) style.point = value end)
    createColorChoice(pane, "颜色", RIGHT_X, y, function() return style.colorKey end, function(value)
        style.colorKey = value; style.color = copyColor(COLOR_PRESETS[value].color)
    end)
    y = y - 38
    createNumberStepper(pane, "横向偏移", 14, y, 64, function() return style.offsetX end, function(value) style.offsetX = value end, 1, -30, 30, "")
    createNumberStepper(pane, "纵向偏移", RIGHT_X, y, 64, function() return style.offsetY end, function(value) style.offsetY = value end, 1, -30, 30, "")
    return y - 62
end

local function buildIconStyleEditor(pane, moduleKey, title, y)
    local style = getModuleStyle(moduleKey)
    y = createSection(pane, title .. "图标样式", y)
    createText(pane, "GameFontDisableSmall", 14, y, 720,
        "以下设置只改变 " .. title .. " 图标的文字与冷却表现，不改变推荐顺序、动作条绑定或派发资格。\nCD 时间与施法、暂停、引导、蓄力、阻止、未绑定等状态标签可独立定位。")
    y = y - 48
    y = buildTextStyleSection(pane, style.keyLabel, "按键标签", y)
    y = buildTextStyleSection(pane, style.chargeLabel, "充能次数", y)
    y = buildTextStyleSection(pane, style.cooldownText, "CD 时间", y, { cooldownMode = true })
    y = buildTextStyleSection(pane, style.stateText, "状态标签（施法 / 暂停等）", y)

    y = createSection(pane, "图标外观", y)
    style.appearance = type(style.appearance) == "table" and style.appearance or {}
    createChoice(pane, "风格", 14, y, 230, {
        { value = "native", label = "WoW 原生动作条" }, { value = "minimal", label = "极简" },
    }, function() return style.appearance.theme or "native" end, function(value) style.appearance.theme = value end,
        "原生风格使用 Blizzard 动作条圆角遮罩、背景与边框图集；极简风格保留图标与现有状态提示。")
    createCheckbox(pane, "圆角技能图标", RIGHT_X, y, function() return style.appearance.roundedIcons ~= false end, function(value) style.appearance.roundedIcons = value end)
    y = y - 34
    createCheckbox(pane, "显示动作条边框", 14, y, function() return style.appearance.showBorder ~= false end, function(value) style.appearance.showBorder = value end)
    createCheckbox(pane, "悬停高亮", RIGHT_X, y, function() return style.appearance.hoverHighlight ~= false end, function(value) style.appearance.hoverHighlight = value end)
    y = y - 34
    createCheckbox(pane, "按下反馈", 14, y, function() return style.appearance.pressedHighlight ~= false end, function(value) style.appearance.pressedHighlight = value end)
    createCheckbox(pane, "当前施法高亮", RIGHT_X, y, function() return style.appearance.castHighlight ~= false end, function(value) style.appearance.castHighlight = value end)
    y = y - 34
    createCheckbox(pane, "0.1 秒淡入淡出", 14, y, function() return style.appearance.fadeTransitions ~= false end, function(value) style.appearance.fadeTransitions = value end)
    createCheckbox(pane, "启用 Masque 兼容", RIGHT_X, y, function() return style.appearance.masque == true end, function(value) style.appearance.masque = value end,
        "仅在已安装 Masque 时生效；未安装时自动保持原生外观。")

    y = y - 54
    y = createSection(pane, "技能 CD 转盘", y)
    createCheckbox(pane, "显示技能 CD 转盘", 14, y, function() return style.cooldownSwipe.enabled end, function(value) style.cooldownSwipe.enabled = value end,
        "仅绘制技能自身冷却。动态光效使用独立暴雪图集层，不会给技能图标本身染色。")
    createChoice(pane, "方向", RIGHT_X, y, 160, {
        { value = false, label = "正向" }, { value = true, label = "反向" },
    }, function() return style.cooldownSwipe.reverse end, function(value) style.cooldownSwipe.reverse = value end)
    y = y - 38
    createNumberStepper(pane, "CD 遮罩透明度", 14, y, 64, function() return math.floor(style.cooldownSwipe.alpha * 100 + 0.5) end,
        function(value) style.cooldownSwipe.alpha = value / 100 end, 5, 0, 95, "%")

    y = y - 54
    y = createSection(pane, "公共冷却（GCD）转盘", y)
    createCheckbox(pane, "显示共 CD 转盘", 14, y, function() return style.gcdSwipe.enabled end, function(value) style.gcdSwipe.enabled = value end,
        "读取暴雪全局冷却 SpellID 61304，仅用于图标显示，不改变推荐或派发。")
    createChoice(pane, "方向", RIGHT_X, y, 160, {
        { value = false, label = "正向" }, { value = true, label = "反向" },
    }, function() return style.gcdSwipe.reverse end, function(value) style.gcdSwipe.reverse = value end)
    y = y - 38
    createNumberStepper(pane, "共 CD 透明度", 14, y, 64, function() return math.floor(style.gcdSwipe.alpha * 100 + 0.5) end,
        function(value) style.gcdSwipe.alpha = value / 100 end, 5, 0, 95, "%")
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 4, 390, "技能 CD 与公共冷却重合时只渲染一次，避免两个转盘叠加导致图标变暗。")

    y = y - 54
    y = createSection(pane, "静态边框高亮", y)
    createCheckbox(pane, "启用静态边框高亮", 14, y, function() return style.highlight.enabled end, function(value) style.highlight.enabled = value end,
        "用于可读性：触发 / 爆发为金色边框，紧急防御为红色边框；不改变技能图标本身。")
    createCheckbox(pane, "触发 / 爆发状态边框", RIGHT_X, y, function() return style.highlight.proc end, function(value) style.highlight.proc = value end)
    y = y - 34
    createCheckbox(pane, "紧急防御状态边框", 14, y, function() return style.highlight.emergency end, function(value) style.highlight.emergency = value end)

    y = y - 54
    y = createSection(pane, "光效与动画", y)
    style.effects = type(style.effects) == "table" and style.effects or {}
    createCheckbox(pane, "启用动态光效", 14, y, function() return style.effects.enabled ~= false end, function(value) style.effects.enabled = value end,
        "使用暴雪图集做显示层效果。所有效果只反映当前卡片状态，不改推荐、按键绑定、TEAP 或 TEK。")

    local effectRows = {
        main = { { "主推荐跑马边框", "marching" }, { "Proc 光效", "proc" }, { "按键就绪闪烁", "hotkeyFlash" }, { "引导条填充", "channelFill" } },
        burst = { { "爆发光效", "burst" }, { "Proc 光效", "proc" }, { "按键就绪闪烁", "hotkeyFlash" }, { "引导条填充", "channelFill" } },
        interrupt = { { "打断光效", "interrupt" }, { "突进光效", "mobility" }, { "Proc 光效", "proc" }, { "按键就绪闪烁", "hotkeyFlash" }, { "引导条填充", "channelFill" } },
        defense = { { "Proc 光效", "proc" }, { "按键就绪闪烁", "hotkeyFlash" }, { "引导条填充", "channelFill" } },
    }
    local row = effectRows[moduleKey] or effectRows.main
    local column = 0
    for _, entry in ipairs(row) do
        local x = column == 0 and 14 or RIGHT_X
        createCheckbox(pane, entry[1], x, y, function() return style.effects[entry[2]] ~= false end, function(value) style.effects[entry[2]] = value end)
        if column == 1 then y = y - 34 end
        column = 1 - column
    end
    if column == 1 then y = y - 34 end
    createText(pane, "GameFontDisableSmall", 14, y - 12, 720,
        "跑马边框按模块状态显示：打断为红橙、爆发为紫、突进为金；Proc 使用暴雪动作条触发光效。持续刷新会缓存同一状态，不会每 0.2 秒重启动画。")
    return y - 60
end

local function buildGeneral(pane)
    local y = createSection(pane, "运行状态", -12)
    createReadout(pane, "generalRuntime", "当前状态", 14, y, 720, "GameFontHighlightSmall")
    createActionButton(pane, "启动", 14, y - 92, 94, function() ControlPanel:StartDynamic() end)
    createActionButton(pane, "暂停", 118, y - 92, 94, function() ControlPanel:PauseDynamic() end)
    createActionButton(pane, "重扫动作条", 222, y - 92, 130, function() ControlPanel:RefreshActionBar("teui_general") end)
    createActionButton(pane, "重置紧凑条位置", 362, y - 92, 132, function() ControlPanel:ResetCompactPosition() end)
    y = y - 138
    y = createSection(pane, "脱战策略", y)
    createChoice(pane, "策略", 14, y, 280, {
        { value = "manual_keep", label = "手动启停（脱战保持运行）" },
        { value = "pause_out_of_combat", label = "脱战暂停（进战自动运行，默认）" },
        { value = "close_out_of_combat", label = "脱战停止（进战需手动运行）" },
    }, function() return ensureSettings().sessionPolicy end, function(value)
        ensureSettings().sessionPolicy = value
        if TE.SignalFrame and type(TE.SignalFrame.SetSessionPolicy) == "function" then TE.SignalFrame:SetSessionPolicy(value) end
    end)
    createReadout(pane, "generalPolicy", "说明", 14, y - 70, 720, "GameFontDisableSmall")
    y = y - 160
    y = createSection(pane, "快捷键设置", y)
    createReadout(pane, "generalHotkey", "TE 自身快捷键", 14, y, 720, "GameFontHighlightSmall")
    local hotkeyBox = createEditBox(pane, "快捷键", LEFT_X, y - 58, 150, ensureSettings().toggleHotkey)
    createActionButton(pane, "录入", 326, y - 58, 72, function() ControlPanel:BeginToggleHotkeyCapture() end)
    createActionButton(pane, "应用", 408, y - 58, 90, function()
        ControlPanel:SetToggleHotkey(pendingToggleHotkey or hotkeyBox:GetText())
    end)
    createActionButton(pane, "清除", 508, y - 58, 90, function() ControlPanel:SetToggleHotkey("") end)
    createText(pane, "GameFontDisableSmall", 14, y - 100, 720,
        "TE 快捷键通过脱战时的临时覆盖绑定实现；不会保存或改写游戏动作条键位。动作条技能键位始终由 Blizzard 绑定解析器读取。")
end

local function buildHUD(pane)
    local tactics, hud = ensureTactics()
    local y = createSection(pane, "HUD 显示 / 隐藏", -12)
    createCheckbox(pane, "启用战术 HUD", LEFT_X, y, function() return hud.enabled end, function(value) hud.enabled = value end)
    createCheckbox(pane, "无官方推荐时隐藏", RIGHT_X, y, function() return hud.hideWhenIdle end, function(value) hud.hideWhenIdle = value end)
    y = y - 38
    createChoice(pane, "脱战显示", LEFT_X, y, 240, {
        { value = "show", label = "保持显示" }, { value = "dim", label = "淡化显示" }, { value = "hide", label = "隐藏 HUD" },
    }, function() return hud.outOfCombatMode end, function(value) hud.outOfCombatMode = value end)
    createCheckbox(pane, "简洁 HUD 模式", RIGHT_X, y, function() return hud.compact end, function(value) hud.compact = value end,
        "仅保留主推荐与状态文字；不会停止官方推荐、动作条扫描或战术策略。")
    y = y - 38
    createCheckbox(pane, "显示拖动抓手", LEFT_X, y, function() return hud.showDragHandle end, function(value) hud.showDragHandle = value end)
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 4, 315,
        "目标框打断提示与位移脱险提示在“打断与控制”页面设置。")

    y = y - 76
    y = createSection(pane, "全局外观", y)
    createNumberStepper(pane, "HUD 全局缩放", LEFT_X, y, 64, function() return math.floor(hud.scale * 100 + 0.5) end,
        function(value) hud.scale = value / 100 end, 5, 60, 200, "%")
    createNumberStepper(pane, "HUD 全局透明度", RIGHT_X, y, 64, function() return math.floor(hud.alpha * 100 + 0.5) end,
        function(value) hud.alpha = value / 100 end, 5, 20, 100, "%")
    y = y - 38
    createNumberStepper(pane, "HUD 底纹透明度", LEFT_X, y, 64, function() return math.floor(hud.backdropAlpha * 100 + 0.5) end,
        function(value) hud.backdropAlpha = value / 100 end, 2, 0, 100, "%")
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 4, 315,
        "全局缩放与透明度影响主 HUD；模块图标大小仍可单独调整。")

    y = y - 76
    y = createSection(pane, "脱战外观", y)
    createNumberStepper(pane, "脱战透明度", LEFT_X, y, 64, function() return math.floor(hud.outOfCombatAlpha * 100 + 0.5) end,
        function(value) hud.outOfCombatAlpha = value / 100 end, 5, 20, 100, "%")
    createNumberStepper(pane, "脱战缩放", RIGHT_X, y, 64, function() return math.floor(hud.outOfCombatScale * 100 + 0.5) end,
        function(value) hud.outOfCombatScale = value / 100 end, 5, 60, 200, "%")
    createText(pane, "GameFontDisableSmall", LEFT_X, y - 38, 700,
        "仅当“脱战显示”设为“淡化显示”时生效。保持显示模式使用 HUD 全局透明度与缩放；隐藏模式不渲染 HUD。")

    y = y - 102
    y = createSection(pane, "模块显示与图标大小", y)
    local mainStyle = getModuleStyle("main")
    local burstStyle = getModuleStyle("burst")
    local interruptStyle = getModuleStyle("interrupt")
    local defenseStyle = getModuleStyle("defense")
    createCheckbox(pane, "显示主键", LEFT_X, y, function() return mainStyle.show ~= false end, function(value) mainStyle.show = value end,
        "只隐藏主推荐及候选队列的 HUD 图标；不会停止官方推荐或动作条扫描。")
    createCheckbox(pane, "显示爆发", RIGHT_X, y, function() return burstStyle.show ~= false end, function(value) burstStyle.show = value end,
        "只隐藏爆发提示图标；不会关闭爆发逻辑或改变主键推荐。")
    y = y - 34
    createCheckbox(pane, "显示打断与控制", LEFT_X, y, function() return interruptStyle.show ~= false end, function(value) interruptStyle.show = value end,
        "打断与控制共用一个显示开关；策略仍在后台只读监测。")
    createCheckbox(pane, "显示防御与生存", RIGHT_X, y, function() return defenseStyle.show ~= false end, function(value) defenseStyle.show = value end,
        "只隐藏防御技能、治疗石和治疗药水的 HUD 提示。")
    y = y - 42
    createNumberStepper(pane, "主键图标", LEFT_X, y, 56, function() return mainStyle.iconSize end, function(value) setModuleIconSize("main", value) end, 2, 44, 120, "")
    createNumberStepper(pane, "爆发图标", RIGHT_X, y, 56, function() return burstStyle.iconSize end, function(value) setModuleIconSize("burst", value) end, 2, 28, 88, "")
    y = y - 38
    createNumberStepper(pane, "打断控制图标", LEFT_X, y, 56, function() return interruptStyle.iconSize end, function(value) setModuleIconSize("interrupt", value) end, 2, 28, 88, "")
    createNumberStepper(pane, "防御生存图标", RIGHT_X, y, 56, function() return defenseStyle.iconSize end, function(value) setModuleIconSize("defense", value) end, 2, 28, 88, "")

    y = y - 76
    y = createSection(pane, "队列模式", y)
    createChoice(pane, "模式", LEFT_X, y, 280, {
        { value = "primary", label = "仅主推荐" }, { value = "queue", label = "主推荐 + 候选队列" }, { value = "tactical", label = "完整战术 HUD（默认）" },
    }, function() return hud.queueMode end, function(value) hud.queueMode = value end)
    createNumberStepper(pane, "候选数量", RIGHT_X, y, 64, function() return hud.maxCandidates end, function(value) hud.maxCandidates = value end, 1, 1, 3, "")
    y = y - 38
    createCheckbox(pane, "启用候选预测", LEFT_X, y, function() return tactics.candidatePredictionEnabled end, function(value) tactics.candidatePredictionEnabled = value end,
        "关闭后不再生成只读候选预测；不会影响官方主推荐。")
    createChoice(pane, "候选来源", RIGHT_X, y, 180, {
        { value = "prediction", label = "预测" }, { value = "history", label = "最近推荐" },
    }, function() return tactics.previewMode end, function(value) tactics.previewMode = value end)
    y = y - 38
    createChoice(pane, "战术队列优先级", LEFT_X, y, 230, {
        { value = "output_first", label = "输出优先" }, { value = "safety_first", label = "安全优先" },
    }, function() return tactics.queuePriorityPreset end, function(value)
        tactics.queuePriorityPreset = value
        tactics.queueOrder = nil -- switching presets intentionally clears any future custom order.
    end)
    createCheckbox(pane, "显示候选预览", RIGHT_X, y, function() return hud.showHistory end, function(value) hud.showHistory = value end)
    createReadout(pane, "hudState", "当前布局", LEFT_X, y - 48, 720, "GameFontHighlightSmall")

    y = y - 148
    y = createSection(pane, "图标标签", y)
    createCheckbox(pane, "全局显示按键标签", LEFT_X, y, function() return hud.showKeyLabels end, function(value) hud.showKeyLabels = value end)
    createCheckbox(pane, "显示图标状态文字", RIGHT_X, y, function() return hud.showStatusText end, function(value) hud.showStatusText = value end)
    createCheckbox(pane, "显示来源标签", LEFT_X, y - 34, function() return hud.showSourceTags end, function(value) hud.showSourceTags = value end)
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 38, 315, "按键、充能与 CD 的字体细节在各模块页面单独设置。")

    y = y - 92
    y = createSection(pane, "布局设置", y)
    createChoice(pane, "HUD 布局", LEFT_X, y, 250, {
        { value = "queue_horizontal", label = "横向主队列" }, { value = "queue_vertical", label = "纵向主队列" }, { value = "surround", label = "主推荐环绕" },
    }, function() return hud.layoutPreset end, function(value)
        hud.layoutPreset = value; hud.orientation = value == "queue_vertical" and "vertical" or "horizontal"
    end)
    createChoice(pane, "候选增长", RIGHT_X, y, 170, {
        { value = "RIGHT", label = "向右" }, { value = "LEFT", label = "向左" }, { value = "UP", label = "向上" }, { value = "DOWN", label = "向下" },
    }, function() return hud.primaryGrowth end, function(value) hud.primaryGrowth = value end)
    y = y - 38
    createChoice(pane, "打断控制方向", LEFT_X, y, 250, {
        { value = "RIGHT", label = "向右" }, { value = "LEFT", label = "向左" }, { value = "UP", label = "向上" }, { value = "DOWN", label = "向下" },
    }, function() return hud.tacticalGrowth end, function(value) hud.tacticalGrowth = value end,
        "仅控制打断、控制和位移提示在其独立区域中的排列；不会影响爆发队列。")
    createCheckbox(pane, "独立拆分防御队列", RIGHT_X, y, function() return hud.defenseDetached end, function(value) hud.defenseDetached = value end)
    y = y - 38
    createChoice(pane, "爆发队列方向", LEFT_X, y, 250, {
        { value = "RIGHT", label = "向右" }, { value = "LEFT", label = "向左" }, { value = "UP", label = "向上" }, { value = "DOWN", label = "向下" },
    }, function() return hud.burstGrowth end, function(value) hud.burstGrowth = value end,
        "爆发窗口技能固定为队列第一个图标，后续爆发技能、饰品、药水和种族技能沿此方向排布。")
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 4, 315, "爆发与打断控制始终属于独立区域；方向可以分别调整。")
    y = y - 38
    createNumberStepper(pane, "主键候选图标", LEFT_X, y, 56, function() return hud.candidateSize end, function(value) hud.candidateSize = value end, 2, 26, 88, "")
    createNumberStepper(pane, "图标间距", RIGHT_X, y, 56, function() return hud.gap end, function(value) hud.gap = value end, 1, 2, 24, "")
    y = y - 38
    createCheckbox(pane, "锁定独立防御队列", LEFT_X, y, function() return hud.defenseLocked end, function(value) hud.defenseLocked = value end,
        "仅在“独立拆分防御队列”启用时生效。")
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 4, 315, "独立防御队列的缩放、透明度仅影响拆分后的防御栏。")
    y = y - 38
    createNumberStepper(pane, "独立防御缩放", LEFT_X, y, 56, function() return math.floor(hud.defenseScale * 100 + 0.5) end,
        function(value) hud.defenseScale = value / 100 end, 5, 60, 200, "%")
    createNumberStepper(pane, "独立防御透明度", RIGHT_X, y, 56, function() return math.floor(hud.defenseAlpha * 100 + 0.5) end,
        function(value) hud.defenseAlpha = value / 100 end, 5, 20, 100, "%")
    y = y - 50
    createActionButton(pane, "锁定 / 解锁 HUD", LEFT_X, y, 138, function() hud.locked = not hud.locked; ControlPanel:ApplyVisuals(true) end)
    createActionButton(pane, "重置 HUD 布局", 162, y, 138, function() ControlPanel:ResetTacticalLayout() end)
    createActionButton(pane, "恢复显示默认", 310, y, 118, function() ControlPanel:ResetDisplaySettings() end)
    createActionButton(pane, "隐藏 HUD", 438, y, 98, function() hud.enabled = false; ControlPanel:ApplyVisuals(true) end)
end

local function buildMain(pane)
    local y = buildIconStyleEditor(pane, "main", "主键", -12)
    createReadout(pane, "mainState", "当前主推荐状态", 14, y, 720, "GameFontHighlightSmall")
end

local function buildBurst(pane)
    local y = buildIconStyleEditor(pane, "burst", "爆发", -12)
    local tactics = select(1, ensureTactics())
    y = createSection(pane, "爆发逻辑", y)
    createCheckbox(pane, "启用爆发窗口辅助", 14, y, function() return tactics.burstEnabled end, function(value) tactics.burstEnabled = value end,
        "显示层独立检查当前专精的已知、已绑定爆发窗口与注入技能；关闭后不显示爆发候选栏。")
    createCheckbox(pane, "显示爆发候选栏", RIGHT_X, y, function() return tactics.burstShowCandidates end, function(value) tactics.burstShowCandidates = value end)
    y = y - 38

    y = createSection(pane, "自动爆发测试（仅窗口技能 + 注入技能）", y)
    createCheckbox(pane, "启用自动爆发", 14, y, function() return tactics.autoBurstEnabled == true end, function(value) tactics.autoBurstEnabled = value end,
        "必须同时处于“运行中”并且当前官方推荐首次命中窗口技能。第一阶段只接管一条当前专精规则，不包含饰品、药水或组合宏。")
    createCheckbox(pane, "完整调试日志", RIGHT_X, y, function() return tactics.autoBurstDebug == true end, function(value) tactics.autoBurstDebug = value end)
    y = y - 38
    createChoice(pane, "注入顺序", 14, y, 230, {
        { value = "pre", label = "前置：注入 → 窗口" }, { value = "post", label = "后置：窗口 → 注入" },
    }, function() return tactics.autoBurstDirection end, function(value) tactics.autoBurstDirection = value end)
    createChoice(pane, "联动模式", RIGHT_X, y, 230, {
        { value = "simple", label = "简易：注入不可用可跳过" }, { value = "focused", label = "集中：两步均就绪才启动" },
    }, function() return tactics.autoBurstMode end, function(value) tactics.autoBurstMode = value end)
    createText(pane, "GameFontDisableSmall", 14, y - 32, 720,
        "每轮只派发一个动作；占 GCD 技能会在客户端预输入窗口内单次发送，随后等待技能专属 CD 或充能确认。自动爆发等待确认、软暂停或等待窗口推荐离开期间会发送非派发 TEAP 帧。")
    y = y - 68

    y = createSection(pane, "Phase 1 测试规则（推荐显式填写）", y)
    createText(pane, "GameFontDisableSmall", 14, y, 720,
        "“官方窗口技能”必须是暴雪官方推荐实际会给出的触发锚点；“注入技能”是 TE 要在其前或后插入的技能。两个 ID 必须同时填写；空白时才会使用当前爆发列表首项。")
    y = y - 34
    local windowBox = createEditBox(pane, "官方窗口 SpellID", LEFT_X, y, 196, tostring(tactics.autoBurstWindowSpellID or 0))
    local injectionBox = createEditBox(pane, "注入 SpellID", RIGHT_X, y, 196, tostring(tactics.autoBurstInjectionSpellID or 0))
    y = y - 36
    createActionButton(pane, "保存测试规则", LEFT_X, y, 146, function()
        local windowSpellID = math.max(0, math.floor(tonumber(windowBox:GetText()) or 0))
        local injectionSpellID = math.max(0, math.floor(tonumber(injectionBox:GetText()) or 0))
        if (windowSpellID == 0) ~= (injectionSpellID == 0) then
            panelStatus("窗口与注入 SpellID 必须同时填写，或同时清空。")
            return
        end
        tactics.autoBurstWindowSpellID = windowSpellID
        tactics.autoBurstInjectionSpellID = injectionSpellID
        windowBox:SetText(tostring(windowSpellID))
        injectionBox:SetText(tostring(injectionSpellID))
        panelStatus(windowSpellID > 0 and "自动爆发测试规则已保存。" or "已清空显式规则；将按下方设置决定是否使用爆发列表首项。")
        ControlPanel:ApplyVisuals(true)
    end)
    createCheckbox(pane, "未填写 ID 时使用爆发列表首项", 176, y, function() return tactics.autoBurstUseProfileFallback == true end, function(value) tactics.autoBurstUseProfileFallback = value end,
        "仅用于兼容旧列表。若官方推荐不会显示该首项，自动爆发不会触发；请优先填写上方两个 SpellID。")
    y = y - 38
    createReadout(pane, "autoBurstRuntime", "自动爆发诊断", LEFT_X, y, 720, "GameFontHighlightSmall")
    registerControl(function()
        local data = TE.AutoBurst and type(TE.AutoBurst.GetDiagnostics) == "function" and TE.AutoBurst:GetDiagnostics() or nil
        if type(data) ~= "table" then setLabel("autoBurstRuntime", "AutoBurst 未加载") return end
        local rule = data.resolvedRule or {}
        local decision = data.lastDecision or {}
        local source = rule.source or (data.ruleReason and "无有效规则") or "未解析"
        setLabel("autoBurstRuntime", "规则=" .. tostring(source)
            .. " 窗口=" .. tostring(rule.windowSpellID or "-")
            .. " 注入=" .. tostring(rule.injectionSpellID or "-")
            .. " · 最近=" .. tostring(decision.reason or data.ruleReason or "等待官方窗口")
            .. " · 计划=" .. tostring(data.plan and data.plan.state or "IDLE"))
    end)
    y = y - 70

    createChoice(pane, "爆发策略", 14, y, 230, {
        { value = "immediate", label = "立即提示" }, { value = "align", label = "对齐主推荐" }, { value = "hold", label = "保留爆发" },
    }, function() return tactics.burstPolicy end, function(value) tactics.burstPolicy = value end)
    createChoice(pane, "显示方式", RIGHT_X, y, 190, {
        { value = "always", label = "常驻" }, { value = "window", label = "窗口出现" }, { value = "highlight", label = "窗口高亮" }, { value = "compact", label = "简洁" },
    }, function() return tactics.burstDisplayMode end, function(value) tactics.burstDisplayMode = value end)
    y = y - 38
    createChoice(pane, "冷却中图标", 14, y, 230, {
        { value = "gray", label = "保留并显示倒计时" }, { value = "hide", label = "冷却时隐藏" },
    }, function() return tactics.burstCooldownDisplay end, function(value) tactics.burstCooldownDisplay = value end,
        "保留时，只会显示已在当前有效动作条绑定、且确实处于自身冷却的爆发技能。图标由游戏原生转盘与倒计时渲染，不会显示“CD”占位字。")
    createNumberStepper(pane, "后续候选数量", RIGHT_X, y, 64, function() return tactics.burstMaxCandidates end, function(value) tactics.burstMaxCandidates = value end, 1, 0, 4, "")
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 32, 360, "第 1 个图标始终保留爆发窗口技能；此项只控制其后的注入技能、饰品、药水和种族技能数量。")
    y = y - 38
    createCheckbox(pane, "主推荐爆发状态标记", 14, y, function() return tactics.burstHighlightPrimary end, function(value) tactics.burstHighlightPrimary = value end)
    y = y - 38

    y = createSection(pane, "爆发候选来源", y)
    createCheckbox(pane, "职业爆发技能", 14, y, function() return tactics.burstShowClassCooldowns end, function(value) tactics.burstShowClassCooldowns = value end)
    createCheckbox(pane, "饰品 13 / 14", RIGHT_X, y, function() return tactics.burstShowTrinkets end, function(value) tactics.burstShowTrinkets = value end)
    createCheckbox(pane, "爆发药水", 14, y - 34, function() return tactics.burstShowPotions end, function(value) tactics.burstShowPotions = value end)
    createCheckbox(pane, "种族技能", RIGHT_X, y - 34, function() return tactics.burstShowRacial end, function(value) tactics.burstShowRacial = value end)
    y = y - 72
    local potionBox = createEditBox(pane, "爆发药水物品 ID", 14, y, 160, tostring(tactics.burstPotionItemID or 0))
    createActionButton(pane, "保存药水 ID", 370, y - 2, 116, function()
        tactics.burstPotionItemID = math.max(0, math.floor(tonumber(potionBox:GetText()) or 0))
        potionBox:SetText(tostring(tactics.burstPotionItemID))
        refreshTacticalBoard()
    end)
    y = y - 38
    local racialBox = createEditBox(pane, "自定义种族技能 ID", 14, y, 160, tostring(tactics.burstRacialSpellID or 0))
    createActionButton(pane, "保存种族 ID", 370, y - 2, 116, function()
        tactics.burstRacialSpellID = math.max(0, math.floor(tonumber(racialBox:GetText()) or 0))
        racialBox:SetText(tostring(tactics.burstRacialSpellID))
        refreshTacticalBoard()
    end)
    createText(pane, "GameFontDisableSmall", 14, y - 38, 720,
        "饰品、药水和种族技能只有同时满足已配置、当前动作条可解析到真实键位、且可用性状态可读取时才进入爆发后续队列；它们始终为只读 HUD 卡片。")
    y = y - 96

    y = createSection(pane, "当前专精覆盖", y)
    local override, profileKey = getCurrentBurstOverride()
    createCheckbox(pane, "当前专精启用", 14, y, function() return override.enabled ~= false end, function(value) override.enabled = value end)
    createCheckbox(pane, "允许饰品提示", RIGHT_X, y, function() return override.allowTrinketHint ~= false end, function(value) override.allowTrinketHint = value end)
    createCheckbox(pane, "允许药水提示", 14, y - 34, function() return override.allowPotionHint ~= false end, function(value) override.allowPotionHint = value end)
    createCheckbox(pane, "允许种族提示", RIGHT_X, y - 34, function() return override.allowRacialHint ~= false end, function(value) override.allowRacialHint = value end)
    createCheckbox(pane, "允许主推荐状态标记", 14, y - 68, function() return override.allowBurstOverlay ~= false end, function(value) override.allowBurstOverlay = value end)
    createText(pane, "GameFontDisableSmall", 14, y - 110, 720,
        "当前专精键：" .. tostring(profileKey) .. "。立即提示：战斗中有敌对目标即可提示已就绪窗口技能；对齐主推荐：还需当前官方主推荐存在；保留爆发：不主动提示窗口技能。候选栏始终只读；仅上方“自动爆发测试”可在严格双开关、单规则和 TEAP/TEK 门禁下临时接管下一步。")
    y = y - 164

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

    y = createSpellPriorityEditor(pane, "爆发窗口技能", "该列表的首个当前专精已知、且在当前有效动作条有真实键位的技能固定占据爆发队列第 1 格。常驻模式会保留其冷却状态；该卡片始终只读，BindingToken=0。", y, {
        maxRows = 5,
        enabledLabel = "触发优先级",
        removeLabel = "停用",
        getEntries = function() return editableBurstEntries("trigger") end,
        move = function(spellID, delta) return burstMove("trigger", spellID, delta) end,
        setEnabled = function(spellID, enabled) return burstEnable("trigger", spellID, enabled) end,
        remove = function(spellID) return burstRemove("trigger", spellID) end,
        add = function(spellID) return burstAdd("trigger", spellID) end,
        addLabel = "添加触发技能",
        showRestore = false,
    })

    y = createSpellPriorityEditor(pane, "爆发后续技能", "这些技能位于爆发窗口技能之后。常驻模式会按注入技能、饰品、药水、种族技能顺序保留可解析的卡片；不会压入主键官方推荐，也不会进入 TEAP / TEK 输入链路。", y, {
        maxRows = 6,
        enabledLabel = "触发优先级",
        removeLabel = "停用",
        getEntries = function() return editableBurstEntries("injection") end,
        move = function(spellID, delta) return burstMove("injection", spellID, delta) end,
        setEnabled = function(spellID, enabled) return burstEnable("injection", spellID, enabled) end,
        remove = function(spellID) return burstRemove("injection", spellID) end,
        add = function(spellID) return burstAdd("injection", spellID) end,
        addLabel = "添加注入技能",
        restore = burstRestore,
        resetLabel = "恢复当前专精爆发默认（两列）",
    })

    createReadout(pane, "burstState", "爆发状态机", 14, y, 720, "GameFontHighlightSmall")
end

local function buildInterrupt(pane)
    local y = buildIconStyleEditor(pane, "interrupt", "打断与控制", -12)
    local tactics = select(1, ensureTactics())
    y = createSection(pane, "打断逻辑", y)
    createCheckbox(pane, "启用打断提示", 14, y, function() return tactics.interruptEnabled end, function(value) tactics.interruptEnabled = value end,
        "仅展示已经在当前有效动作条中解析到的真实键位。打断提示不会覆盖官方主推荐或进入派发链。")
    createChoice(pane, "显示方式", RIGHT_X, y, 240, {
        { value = "always", label = "常驻" }, { value = "cast", label = "目标读条时出现" }, { value = "highlight", label = "可打断时标记" },
    }, function() return tactics.interruptDisplayMode end, function(value) tactics.interruptDisplayMode = value end)
    y = y - 38
    createCheckbox(pane, "目标框 / 姓名板打断提示", LEFT_X, y, function() return select(2, ensureTactics()).showTargetPrompt end, function(value) select(2, ensureTactics()).showTargetPrompt = value end,
        "默认关闭。仅当当前目标正在进行可打断读条、打断技能存在真实动作条键位且当前可用时显示；不继承“打断常驻”模式。")
    createCheckbox(pane, "启用位移脱险提示", RIGHT_X, y, function() return tactics.mobilityEnabled end, function(value) tactics.mobilityEnabled = value end,
        "控制位移脱险类只读建议，不影响主键、TEAP 或 TEK。")
    y = y - 76
    y = createSection(pane, "控制逻辑", y)
    createCheckbox(pane, "启用控制提示", LEFT_X, y, function() return tactics.controlEnabled end, function(value) tactics.controlEnabled = value end)
    createChoice(pane, "显示方式", RIGHT_X, y, 240, {
        { value = "always", label = "常驻" }, { value = "cast", label = "读条时出现" }, { value = "highlight", label = "需要控制时标记" },
    }, function() return tactics.controlDisplayMode end, function(value) tactics.controlDisplayMode = value end)
    createText(pane, "GameFontDisableSmall", 14, y - 48, 720,
        "控制候选只在明确的不可打断读条时作为后备显示；目标可被打断时，TE 始终优先显示打断而非控制。控制递减、免控和队友技能不会被猜测为可派发键位。")
    y = y - 102
    createReadout(pane, "interruptState", "当前读条监控", 14, y, 720, "GameFontHighlightSmall")
end

local function buildDefense(pane)
    local y = buildIconStyleEditor(pane, "defense", "防御与生存", -12)
    local tactics = select(1, ensureTactics())
    local survival = tactics.survival
    y = createSection(pane, "防御逻辑", y)
    createCheckbox(pane, "启用防御提示", 14, y, function() return tactics.defensiveEnabled end, function(value) tactics.defensiveEnabled = value end,
        "候选按 当前职业 → 当前专精 → 已知技能 → 有效动作条 → 真实键位 的顺序筛选。跨专精技能不会作为正常候选。")
    createChoice(pane, "显示方式", RIGHT_X, y, 240, {
        { value = "always", label = "常驻" }, { value = "condition", label = "低血 / 高压时出现" }, { value = "highlight", label = "低血时重点标记" },
    }, function() return tactics.defensiveDisplayMode end, function(value) tactics.defensiveDisplayMode = value end)
    y = y - 38
    createCheckbox(pane, "脱战显示防御待命", 14, y, function() return tactics.defensiveOutOfCombatStandby end, function(value) tactics.defensiveOutOfCombatStandby = value end,
        "脱战时显示当前专精、已知且在有效动作条绑定的防御技能；仅只读显示，BindingToken 固定为 0。")
    createText(pane, "GameFontDisableSmall", RIGHT_X, y - 4, 390, "如 HUD 脱战显示设为“隐藏”或队列模式设为“仅主推荐”，防御栏仍按你的全局显示策略隐藏。")
    y = y - 48
    createNumberStepper(pane, "显示阈值", 14, y, 64, function() return tactics.defensiveDisplayHealthPercent end, function(value) tactics.defensiveDisplayHealthPercent = value end, 5, 5, 100, "%")
    createNumberStepper(pane, "紧急阈值", RIGHT_X, y, 64, function() return tactics.defensiveHighlightHealthPercent end, function(value) tactics.defensiveHighlightHealthPercent = value end, 5, 5, 100, "%")
    y = y - 76

    local function currentDefenseContext()
        return (TE.Context and TE.Context:GetPlayer()) or {}
    end
    local function defensiveEntries()
        if not (TE.AbilityProfiles and type(TE.AbilityProfiles.GetEditableDefensivePriority) == "function") then
            return {}, nil, "AbilityProfiles 未加载", nil
        end
        local entries, profile = TE.AbilityProfiles:GetEditableDefensivePriority(currentDefenseContext())
        return entries, profile and profile.profileKey, nil, profile
    end
    local function defensiveMove(spellID, delta)
        if not (TE.AbilityProfiles and type(TE.AbilityProfiles.MoveDefensivePriority) == "function") then return false, "AbilityProfiles 未加载" end
        return TE.AbilityProfiles:MoveDefensivePriority(currentDefenseContext(), spellID, delta)
    end
    local function defensiveEnable(spellID, enabled)
        if not (TE.AbilityProfiles and type(TE.AbilityProfiles.SetDefensivePriorityEnabled) == "function") then return false, "AbilityProfiles 未加载" end
        return TE.AbilityProfiles:SetDefensivePriorityEnabled(currentDefenseContext(), spellID, enabled)
    end
    local function defensiveRestore()
        if not (TE.AbilityProfiles and type(TE.AbilityProfiles.RestoreDefensivePriority) == "function") then return false, "AbilityProfiles 未加载" end
        return TE.AbilityProfiles:RestoreDefensivePriority(currentDefenseContext())
    end

    y = createSpellPriorityEditor(pane, "防御优先列表", "自我治疗、减伤和保命技能合并为当前专精的一条统一顺序。可上移、下移或停用；不能在 TEUI 手工加入其他专精技能。要补充缺失技能，应修改当前专精防御注册表。", y, {
        maxRows = 7,
        enabledLabel = "触发优先级",
        removeLabel = "停用",
        getEntries = defensiveEntries,
        move = defensiveMove,
        setEnabled = defensiveEnable,
        remove = function(spellID) return defensiveEnable(spellID, false) end,
        restore = defensiveRestore,
        resetLabel = "恢复当前专精防御默认",
    })

    y = createSection(pane, "治疗石与血瓶逻辑", y)
    createCheckbox(pane, "治疗石提示", 14, y, function() return survival.healthstoneEnabled end, function(value) survival.healthstoneEnabled = value end)
    createCheckbox(pane, "治疗药水提示", RIGHT_X, y, function() return survival.potionEnabled end, function(value) survival.potionEnabled = value end)
    y = y - 38
    createChoice(pane, "优先级", 14, y, 240, {
        { value = "healthstone_first", label = "治疗石优先" }, { value = "potion_first", label = "血瓶优先" },
    }, function() return survival.priority end, function(value) survival.priority = value end)
    createCheckbox(pane, "仅战斗中提示", RIGHT_X, y, function() return survival.inCombatOnly end, function(value) survival.inCombatOnly = value end)
    y = y - 38
    createNumberStepper(pane, "消耗品显示阈值", 14, y, 64, function() return survival.displayHealthPercent end, function(value) survival.displayHealthPercent = value end, 5, 5, 100, "%")
    createNumberStepper(pane, "消耗品紧急阈值", RIGHT_X, y, 64, function() return survival.emergencyHealthPercent end, function(value) survival.emergencyHealthPercent = value end, 5, 5, 100, "%")
    y = y - 42
    local potionBox = createEditBox(pane, "治疗药水物品 ID", 14, y, 160, tostring(survival.potionItemID or 0))
    createActionButton(pane, "保存药水 ID", 370, y - 2, 116, function()
        local itemID = math.floor(tonumber(potionBox:GetText()) or 0)
        survival.potionItemID = math.max(0, itemID)
        potionBox:SetText(tostring(survival.potionItemID))
        refreshTacticalBoard()
    end)
    createText(pane, "GameFontDisableSmall", 14, y - 42, 720,
        "治疗石默认物品 ID 为 5512。治疗药水请填入你实际使用的物品 ID，并将该物品拖入当前有效动作条；TE 仅在背包、动作条和真实键位都确认后显示，不猜测物品键位，也不参与任何按键派发。")
    y = y - 112
    createReadout(pane, "defenseState", "当前专精防御状态", 14, y, 720, "GameFontHighlightSmall")
end

local function buildMonitor(pane)
    local y = createSection(pane, "动作条与按键解析", -12)
    createReadout(pane, "monitorMapping", "映射状态", 14, y, 720, "GameFontHighlightSmall")
    createActionButton(pane, "重扫 ButtonCache", 14, y - 86, 150, function() ControlPanel:RefreshActionBar("teui_monitor") end)
    createActionButton(pane, "输出映射摘要", 174, y - 86, 150, function() safePrint(getBindingSummary():gsub("\n", "  ")) end)
    y = y - 134
    y = createSection(pane, "专精与技能池", y)
    createReadout(pane, "monitorSpec", "当前专精", 14, y, 720, "GameFontHighlightSmall")
    y = y - 126
    y = createSection(pane, "推荐链路", y)
    createReadout(pane, "monitorRecommendation", "同源快照", 14, y, 720, "GameFontHighlightSmall")
    y = y - 126
    y = createSection(pane, "协议与安全", y)
    createReadout(pane, "monitorProtocol", "TEAP / TEK", 14, y, 720, "GameFontHighlightSmall")
    createText(pane, "GameFontDisableSmall", 14, y - 66, 720,
        "调试页包含原 TEUI 的动作条、宏、状态、协议与排错入口。战术图标、爆发、打断、防御均为显示层，不能通过此页获得现实按键派发资格。")
end

local function profileAction(message, callback)
    local ok, result = callback()
    if ok then
        setLabel("footerStatus", message .. "：" .. tostring(result or "完成"))
    else
        setLabel("footerStatus", "配置操作失败：" .. tostring(result or "未知原因"))
    end
    ControlPanel:ApplyVisuals(true)
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
    y = createSection(pane, "自动按范围切换", y)
    createReadout(pane, "profileScopes", "当前映射", 14, y, 720, "GameFontHighlightSmall")
    y = y - 116
    local manager = TE.ProfileManager
    local keys = manager and manager:GetScopeKeys() or {}
    createActionButton(pane, "全局 ← 当前", 14, y, 112, function()
        profileAction("全局映射", function() return TE.ProfileManager:SetScopeProfile(keys.global, TE.ProfileManager:GetActiveName()) end)
    end)
    createActionButton(pane, "角色 ← 当前", 136, y, 112, function()
        profileAction("角色映射", function() return TE.ProfileManager:SetScopeProfile(keys.character, TE.ProfileManager:GetActiveName()) end)
    end)
    createActionButton(pane, "职业 ← 当前", 258, y, 112, function()
        profileAction("职业映射", function() return TE.ProfileManager:SetScopeProfile(keys.class, TE.ProfileManager:GetActiveName()) end)
    end)
    createActionButton(pane, "专精 ← 当前", 380, y, 112, function()
        profileAction("专精映射", function() return TE.ProfileManager:SetScopeProfile(keys.spec, TE.ProfileManager:GetActiveName()) end)
    end)
    y = y - 42
    createActionButton(pane, "清除全局映射", 14, y, 112, function() profileAction("清除全局", function() return TE.ProfileManager:ClearScopeProfile(keys.global) end) end)
    createActionButton(pane, "清除角色映射", 136, y, 112, function() profileAction("清除角色", function() return TE.ProfileManager:ClearScopeProfile(keys.character) end) end)
    createActionButton(pane, "清除职业映射", 258, y, 112, function() profileAction("清除职业", function() return TE.ProfileManager:ClearScopeProfile(keys.class) end) end)
    createActionButton(pane, "清除专精映射", 380, y, 112, function() profileAction("清除专精", function() return TE.ProfileManager:ClearScopeProfile(keys.spec) end) end)
    y = y - 90
    y = createSection(pane, "重置与恢复", y)
    createActionButton(pane, "重置 HUD 布局", 14, y, 128, function() ControlPanel:ResetTacticalLayout() end)
    createActionButton(pane, "重置显示设置", 152, y, 128, function() ControlPanel:ResetDisplaySettings() end)
    createActionButton(pane, "重置后台位置", 290, y, 128, function() ControlPanel:ResetPosition() end)
end

local BUILDERS = {
    general = buildGeneral,
    hud = buildHUD,
    main = buildMain,
    burst = buildBurst,
    interrupt = buildInterrupt,
    defense = buildDefense,
    monitor = buildMonitor,
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
        builder(pane)
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
    for page, button in pairs(navButtons) do setButtonVisual(button, page == activePage) end
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
        if pendingCompactPositionSave then
            pendingCompactPositionSave = false
            if root().minimized == true then savePanelPosition("compact") end
        end
        return
    end
    local store = root()
    ControlPanel:Create()
    ControlPanel:ApplyStoredToggleHotkey()
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
    elseif command == "interrupt" or command == "control" then
        ControlPanel:Show("interrupt")
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
