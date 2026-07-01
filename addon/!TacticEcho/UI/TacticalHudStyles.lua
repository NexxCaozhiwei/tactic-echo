-- Tactic Echo tactical HUD visual-state resolver.
--
-- This module maps sanitized card state to display colors, labels and effect
-- intents. It is presentation-only: it never writes tactical state, binding
-- tokens, TEAP data or input requests.
local TE = _G.TacticEcho

local TacticalHudStyles = {}
TE.TacticalHudStyles = TacticalHudStyles

TacticalHudStyles.COLORS = {
    primary = { 0.96, 0.78, 0.18, 1.00 },
    candidate = { 0.42, 0.62, 0.94, 1.00 },
    interrupt = { 1.00, 0.40, 0.16, 1.00 },
    defense = { 0.20, 0.86, 0.47, 1.00 },
    burst = { 0.72, 0.38, 1.00, 1.00 },
    control = { 0.92, 0.64, 0.18, 1.00 },
    mobility = { 0.28, 0.84, 0.94, 1.00 },
    ready = { 0.22, 0.96, 0.56, 1.00 },
    blocked = { 0.96, 0.22, 0.24, 1.00 },
    error = { 0.76, 0.36, 0.82, 1.00 },
    unknown = { 0.60, 0.52, 0.78, 1.00 },
    unbound = { 0.48, 0.52, 0.60, 1.00 },
    paused = { 0.96, 0.72, 0.18, 1.00 },
    cooldown = { 0.58, 0.68, 0.80, 1.00 },
    resource = { 0.28, 0.62, 1.00, 1.00 },
    range = { 1.00, 0.30, 0.18, 1.00 },
    target = { 0.92, 0.20, 0.24, 1.00 },
    casting = { 0.95, 0.78, 0.34, 1.00 },
    channeling = { 0.44, 0.94, 1.00, 1.00 },
    channeling_lock = { 0.32, 0.76, 1.00, 1.00 },
    empowering = { 0.94, 0.70, 0.30, 1.00 },
    empowering_lock = { 0.88, 0.56, 0.18, 1.00 },
    neutral = { 0.20, 0.28, 0.40, 0.95 },
}

local KIND_COLORS = {
    primary = "primary",
    candidate = "candidate",
    interrupt = "interrupt",
    defense = "defense",
    burst = "burst",
    control = "control",
    mobility = "mobility",
}

local function copyColor(name)
    local color = TacticalHudStyles.COLORS[name] or TacticalHudStyles.COLORS.neutral
    return { color[1], color[2], color[3], color[4] }
end

local function primaryVisual(item)
    if not item or (not item.spellID and not item.itemID) then
        return "unknown", "等待官方推荐"
    end
    -- Keep the actual runtime state first so a real error/block cannot be
    -- hidden behind a channel or Empower label.
    local runtimeState = item.runtimeState or item.state
    local runtimeReason = item.runtimeReasonText or item.reasonText
    if runtimeState == "error" then
        return "error", runtimeReason or "TEAP 状态异常"
    end
    if runtimeState == "blocked" or item.blocked == true then
        return "blocked", runtimeReason or "现实键位链路已阻止"
    end
    if item.displayState == "channeling_lock" or runtimeState == "channeling" then
        if item.channelingMatchesRecommendation == true then
            return "channeling", "正在引导该技能"
        end
        return "channeling_lock", "玩家正在引导；当前推荐将在引导结束后恢复"
    end
    if item.displayState == "empowering_lock" or runtimeState == "empowering" then
        if item.empoweringMatchesRecommendation == true then
            return "empowering", "正在蓄力该技能"
        end
        return "empowering_lock", "玩家正在蓄力；当前推荐将在蓄力结束后恢复"
    end
    if runtimeState == "paused" or item.paused == true then
        return "paused", runtimeReason or "TE 已暂停"
    end
    if item.displayOnly == true then
        if not item.binding or item.binding == "" then
            return "unbound", "脱战主推荐已读取，但当前动作条未找到现实绑定"
        end
        return "primary", "脱战只读主推荐；不进入 TEAP 或派发链"
    end
    if not item.binding or item.binding == "" then
        return "unbound", "未找到现实动作条绑定"
    end
    if item.usableState == "cooldown" or item.cooldownActive == true then
        return "cooldown", "技能冷却中；图标转盘由客户端渲染，CD 标签由 HUD 统一绘制"
    end
    if item.dispatchAllowed == true then
        return "dispatchable", "官方主推荐已通过原有安全校验"
    end
    if item.usableState == "unknown" or item.unknown == true then
        return "unknown", item.unusableReason or "状态未确认"
    end
    return "primary", item.reasonText or "官方主推荐仅显示"
end

local function advisoryVisual(item, kind)
    if not item or (not item.spellID and not item.itemID) then
        return "unknown", "暂无可显示建议"
    end
    if item.paused == true then
        return "paused", "仅提示队列已暂停"
    end
    if item.blocked == true then
        return "blocked", item.unusableReason or "建议当前不可用"
    end
    if not item.binding or item.binding == "" then
        return "unbound", "未在现实动作条白名单中找到绑定"
    end
    -- Mirror the reference renderer's state priority: an invalid target/range or
    -- resource shortfall should be visible before a generic advisory label.
    if item.targetInvalid == true then
        return "target", item.targetReason or "目标不可用"
    end
    if item.rangeBlocked == true then
        return "range", item.targetReason or "目标不在技能距离内"
    end
    if item.resourceBlocked == true or item.usableState == "resource" then
        return "resource", item.unusableReason or "资源不足"
    end
    if item.usableState == "cooldown" or item.cooldownActive == true then
        return "cooldown", "技能冷却中；图标转盘由客户端渲染，CD 标签由 HUD 统一绘制"
    end
    if item.castingThisSpell == true then
        return item.channeling == true and "channeling" or "casting", item.channeling == true and "正在引导该技能" or "正在施放该技能"
    end
    if item.usableState == "unknown" or item.unknown == true then
        return "unknown", item.unusableReason or "状态未确认"
    end
    return kind == "candidate" and "preview" or "advisory", item.advisoryCondition or "仅提示；不进入派发链路"
end

local function effectIntent(item, kind, meta, visual)
    item, meta = item or {}, meta or {}
    local burstWindow = kind == "burst" and (item.burstWindow == true or item.burstRole == "window")
    local burstActive = burstWindow and (item.burstState == "ACTIVE" or item.burstReady == true)
    return {
        -- Primary recommendation receives a restrained Blizzard-style crawling
        -- edge. Proc / interrupt / burst / mobility use their own intent;
        -- TacticalIconEffects resolves priority so the icon is never covered by
        -- several unrelated animated textures at once.
        marching = kind == "primary" and (visual == "primary" or visual == "dispatchable"),
        proc = item.procHighlight == true,
        interrupt = kind == "interrupt" and (meta.interruptible == true or item.interruptible == true),
        burst = burstActive,
        mobility = kind == "mobility" or item.gapCloser == true,
        hotkeyFlash = item.usableState == "ready",
        -- The primary `引导 / 引导锁 / 蓄力 / 蓄力锁` states are label + border
        -- only. Existing advisory cards may retain their independent optional
        -- channel-fill effect.
        channelFill = kind ~= "primary" and item.castingThisSpell == true and item.channeling == true,
    }
end

local function sourceLabelFor(kind, item)
    local labels = { primary = "官方", candidate = "候选", interrupt = "打断", defense = "防御", burst = "爆发", control = "控制", mobility = "位移" }
    local label = labels[kind] or "提示"
    if kind == "burst" and item then
        if item.burstRole == "window" then label = "窗口"
        elseif item.burstRole == "injection" then label = "注入"
        elseif item.burstRole == "trinket" then label = "饰品"
        elseif item.burstRole == "potion" then label = "药水"
        elseif item.burstRole == "racial" then label = "种族"
        end
    end
    return label
end

function TacticalHudStyles:Resolve(item, kind, meta)
    kind = kind or "candidate"
    meta = meta or {}

    local visual, reason
    if kind == "primary" then
        visual, reason = primaryVisual(item)
    else
        visual, reason = advisoryVisual(item, kind)
    end

    local colorKey = KIND_COLORS[kind] or "neutral"
    local alpha = 1.00
    local overlay = "none"
    local sourceLabel = sourceLabelFor(kind, item)
    local stateLabel = ""
    local label = sourceLabel -- legacy aggregate label; stateText is independent.
    local desaturate = false

    if visual == "dispatchable" then
        colorKey, alpha = "ready", 1.00
    elseif visual == "primary" then
        colorKey, alpha = "primary", 1.00
    elseif visual == "preview" then
        colorKey, alpha = "candidate", 0.78
    elseif visual == "advisory" then
        colorKey, alpha = colorKey, 0.92
    elseif visual == "blocked" then
        colorKey, alpha, overlay, label, desaturate = "blocked", 0.58, "blocked", "阻止", true
        stateLabel = label
    elseif visual == "error" then
        colorKey, alpha, overlay, label, desaturate = "error", 0.56, "error", "异常", true
        stateLabel = label
    elseif visual == "unknown" then
        colorKey, alpha, overlay, label, desaturate = "unknown", 0.56, "unknown", "未知", true
        stateLabel = label
    elseif visual == "unbound" then
        colorKey, alpha, overlay, label, desaturate = "unbound", 0.48, "unbound", "无绑定", true
        stateLabel = label
    elseif visual == "paused" then
        colorKey, alpha, overlay, label, desaturate = "paused", 0.52, "paused", "暂停", true
        stateLabel = label
    elseif visual == "resource" then
        colorKey, alpha, overlay, label, desaturate = "resource", 0.70, "unknown", "资源", true
        stateLabel = label
    elseif visual == "range" then
        colorKey, alpha, overlay, label, desaturate = "range", 0.72, "blocked", "超距", true
        stateLabel = label
    elseif visual == "target" then
        colorKey, alpha, overlay, label, desaturate = "target", 0.62, "blocked", "目标", true
        stateLabel = label
    elseif visual == "casting" then
        colorKey, alpha, label = "casting", 1.00, "施法"
        stateLabel = label
    elseif visual == "channeling" then
        colorKey, alpha, label = "channeling", 1.00, "引导"
        stateLabel = label
    elseif visual == "channeling_lock" then
        -- Label + restrained border tint only. No timing fill or queued input
        -- behavior is attached to this presentation state.
        colorKey, alpha, label = "channeling_lock", 0.94, "引导锁"
        stateLabel = label
    elseif visual == "empowering" then
        colorKey, alpha, label = "empowering", 1.00, "蓄力"
        stateLabel = label
    elseif visual == "empowering_lock" then
        -- Empower remains a hard non-dispatchable TEAP state; this presentation
        -- metadata cannot schedule or release any external input.
        colorKey, alpha, label = "empowering_lock", 0.94, "蓄力锁"
        stateLabel = label
    elseif visual == "cooldown" then
        colorKey, alpha, overlay, label, desaturate = "cooldown", 0.72, "none", "", true
    end

    local effects = effectIntent(item, kind, meta, visual)
    local glow = effects.interrupt and "interrupt" or effects.burst and "burst" or effects.mobility and "mobility"
        or effects.proc and "proc" or effects.marching and "marching" or "none"

    return {
        visualState = visual,
        borderColor = copyColor(colorKey),
        alpha = alpha,
        overlay = overlay,
        glow = glow,
        effects = effects,
        -- P5 keeps this legacy field so existing board/status consumers remain
        -- compatible. Icon cards use sourceLabel and stateLabel independently.
        label = stateLabel ~= "" and stateLabel or label,
        sourceLabel = sourceLabel,
        stateLabel = stateLabel,
        desaturate = desaturate,
        reason = reason,
        previewOnly = kind ~= "primary",
        dispatchable = visual == "dispatchable",
    }
end

function TacticalHudStyles:GetColor(name)
    return copyColor(name)
end
