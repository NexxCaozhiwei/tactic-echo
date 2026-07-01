-- Burst window state machine. Advisory-only: does not create TEAP tokens.
local TE = _G.TacticEcho

local Machine = {
    state = "IDLE",
    lastReason = "init",
    lastTransitionAt = 0,
    armedAt = nil,
    activeAt = nil,
    fallbackUntil = nil,
    openerSpellID = nil,
    activeBuffID = nil,
    profileKey = nil,
    observedCastAt = nil,
}
TE.BurstStateMachine = Machine

local function now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function transition(self, state, reason)
    if self.state ~= state or self.lastReason ~= reason then
        self.state = state
        self.lastReason = reason or state
        self.lastTransitionAt = now()
    end
end

local function hasAura(spellID)
    spellID = tonumber(spellID)
    if not spellID then return false, "invalid_buff" end
    if C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok then return aura ~= nil, nil end
        return false, "buff_api_unreliable"
    end
    if AuraUtil and type(AuraUtil.FindAuraBySpellID) == "function" then
        local ok, name = pcall(AuraUtil.FindAuraBySpellID, spellID, "player", "HELPFUL")
        if ok then return name ~= nil, nil end
        return false, "buff_api_unreliable"
    end
    return false, "buff_api_unavailable"
end

local function activeBuff(profile)
    for _, spellID in ipairs(profile.confirmBuffIDs or {}) do
        local active, reason = hasAura(spellID)
        if reason then return nil, nil, reason end
        if active then return spellID, true, nil end
    end
    return nil, false, nil
end

local function inCombat(context)
    return context and context.inCombat == true
end

function Machine:Reset(reason)
    self.armedAt, self.activeAt, self.fallbackUntil = nil, nil, nil
    self.openerSpellID, self.activeBuffID, self.observedCastAt = nil, nil, nil
    transition(self, "IDLE", reason or "reset")
end

-- Records an actual player spellcast. This is deliberately separate from
-- detection of an official primary recommendation: only a successful cast may
-- start the bounded non-aura fallback window.
function Machine:RecordTriggerCast(profile, profileKey, spellID)
    spellID = tonumber(spellID)
    if not profile or not spellID then return false, "invalid_trigger_cast" end
    if not (TE.BurstProfiles and type(TE.BurstProfiles.Contains) == "function"
        and TE.BurstProfiles:Contains(profile.openerSpellIDs, spellID)) then
        return false, "not_current_spec_trigger"
    end
    local t = now()
    self.profileKey = profileKey or self.profileKey
    self.armedAt = t
    self.observedCastAt = t
    self.activeAt = nil
    self.openerSpellID = spellID
    self.activeBuffID = nil
    self.fallbackUntil = t + (tonumber(profile.windowDurationFallback) or 20)
    transition(self, "ARMED", "已施放独立爆发触发技能，等待 Buff 确认")
    return true, nil
end

function Machine:Update(profile, profileKey, primary, context, settings)
    local t = now()
    settings = settings or {}
    if settings.burstEnabled == false then
        transition(self, "SUPPRESSED", "爆发模块已关闭")
        return self:Snapshot(profile, profileKey)
    end
    if not profile or profile.enabled == false then
        transition(self, "SUPPRESSED", "当前专精暂无爆发辅助配置")
        return self:Snapshot(profile, profileKey)
    end
    -- Every specialization has an explicit profile key, but reference seed data is
    -- intentionally sparse. Keep an unseeded profile visibly suppressed rather
    -- than pretending that an empty list is a usable burst configuration.
    if profile.noSeedNotice then
        transition(self, "SUPPRESSED", profile.noSeedNotice)
        return self:Snapshot(profile, profileKey)
    end
    if not context or not context.class or not context.specIndex then
        transition(self, "UNKNOWN", "玩家职业或专精无法确认")
        return self:Snapshot(profile, profileKey)
    end
    if self.profileKey and profileKey and self.profileKey ~= profileKey then
        self.armedAt, self.activeAt, self.fallbackUntil = nil, nil, nil
        self.openerSpellID, self.activeBuffID, self.observedCastAt = nil, nil, nil
        transition(self, "IDLE", "专精变化，重置爆发状态")
    end
    self.profileKey = profileKey

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        self:Reset("玩家死亡或灵魂状态，退出爆发窗口")
        return self:Snapshot(profile, profileKey)
    end
    if not inCombat(context) then
        self:Reset("脱战，退出爆发窗口")
        return self:Snapshot(profile, profileKey)
    end

    local buffID, buffActive, buffReason = activeBuff(profile)
    if buffReason then
        transition(self, "UNKNOWN", "Buff 状态无法可靠解释：" .. tostring(buffReason))
        return self:Snapshot(profile, profileKey)
    end
    if buffActive then
        self.activeBuffID = buffID
        if not self.activeAt then self.activeAt = t end
        self.fallbackUntil = t + (tonumber(profile.windowDurationFallback) or 20)
        transition(self, "ACTIVE", "确认爆发 Buff 生效")
        return self:Snapshot(profile, profileKey)
    end

    if self.state == "ACTIVE" then
        if self.fallbackUntil and t < self.fallbackUntil then
            transition(self, "ACTIVE", "爆发 Buff 未见但 fallback 窗口仍有效")
            return self:Snapshot(profile, profileKey)
        end
        self.activeAt, self.activeBuffID, self.fallbackUntil = nil, nil, nil
        self.observedCastAt = nil
        transition(self, "COOLDOWN", "爆发 Buff 消失或窗口超时")
        return self:Snapshot(profile, profileKey)
    end

    local primarySpellID = primary and primary.spellID
    local isOpener = TE.BurstProfiles and TE.BurstProfiles:Contains(profile.openerSpellIDs, primarySpellID)
    if settings.burstPolicy == "hold" then
        transition(self, "SUPPRESSED", "爆发保留模式")
        return self:Snapshot(profile, profileKey)
    end

    if self.state == "ARMED" and self.observedCastAt then
        -- A player cast has been observed. Give an aura a short grace period;
        -- non-aura triggers then use the profile's bounded fallback window.
        local grace = math.max(0, tonumber(profile.auraGraceMs) or 500) / 1000
        if (t - self.observedCastAt) >= grace and self.fallbackUntil and t < self.fallbackUntil then
            if not self.activeAt then self.activeAt = self.observedCastAt end
            transition(self, "ACTIVE", "触发技能已施放但未检测到 Buff：使用定时爆发窗口")
            return self:Snapshot(profile, profileKey)
        end
    end

    if isOpener then
        self.armedAt = self.armedAt or t
        self.openerSpellID = primarySpellID
        transition(self, "ARMED", "官方主推荐命中爆发启动技能")
        return self:Snapshot(profile, profileKey)
    end

    if self.state == "ARMED" then
        local timeout = tonumber(profile.armedTimeout) or 3
        if self.armedAt and (t - self.armedAt) <= timeout then
            transition(self, "ARMED", "等待爆发 Buff 确认")
            return self:Snapshot(profile, profileKey)
        end
        self.armedAt, self.openerSpellID, self.observedCastAt = nil, nil, nil
        transition(self, "IDLE", "爆发启动技能未确认 Buff，准备状态结束")
        return self:Snapshot(profile, profileKey)
    end

    if self.state == "COOLDOWN" then
        transition(self, "COOLDOWN", "上一轮爆发结束，等待下一次爆发技能就绪")
        return self:Snapshot(profile, profileKey)
    end

    transition(self, "IDLE", "等待当前专精爆发触发技能就绪")
    return self:Snapshot(profile, profileKey)
end

function Machine:Snapshot(profile, profileKey)
    local state = self.state or "UNKNOWN"
    local labels = {
        IDLE = "未准备", ARMED = "即将爆发", ACTIVE = "爆发中", COOLDOWN = "冷却中",
        SUPPRESSED = "已抑制", UNKNOWN = "状态未知",
    }
    return {
        schema = 2,
        state = state,
        label = labels[state] or "状态未知",
        profileKey = profileKey or self.profileKey,
        profileLabel = profile and profile.label,
        openerSpellID = self.openerSpellID,
        activeBuffID = self.activeBuffID,
        lastTransitionAt = self.lastTransitionAt,
        lastTransitionReason = self.lastReason,
        armedAt = self.armedAt,
        activeAt = self.activeAt,
        observedCastAt = self.observedCastAt,
        remaining = nil,
        advisoryOnly = true,
    }
end

local watcher = CreateFrame("Frame")
TE:RegisterEventsSafe(watcher, { "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_ENABLED" })
watcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local context = TE.Context and TE.Context:GetPlayer() or {}
        local profile, profileKey = TE.BurstProfiles and TE.BurstProfiles:Get(context) or nil, nil
        if TE.BurstProfiles and type(TE.BurstProfiles.Get) == "function" then
            profile, profileKey = TE.BurstProfiles:Get(context)
        end
        Machine:RecordTriggerCast(profile, profileKey, spellID)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" then
        Machine.profileKey = nil
        Machine:Reset("专精变化，清空爆发窗口")
    elseif event == "PLAYER_REGEN_ENABLED" then
        Machine:Reset("脱战，清空爆发窗口")
    end
end)
