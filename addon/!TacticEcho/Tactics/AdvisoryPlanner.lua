-- Read-only tactical advisory planner.
-- The planner can only display already-bound actions. It never creates TEAP
-- tokens, modifies the official recommendation, or asks TEK to input.
-- Compatibility marker: official_burst_anchor is now handled by BurstPlanner as a UI-only opener source.
local TE = _G.TacticEcho
local Planner = {}
TE.AdvisoryPlanner = Planner

local movement = { active = false, observedAt = 0 }

local function spellInfo(spellID)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then return info.name, info.iconID or info.icon end
    end
    if type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
    return nil, nil
end

local function bound(spellID)
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveSpell) ~= "function" then return nil end
    local resolved = resolver:ResolveSpell(spellID)
    if not resolved then return nil end
    if resolved.status == "Ready" and resolved.binding then return resolved end
    if resolved.rawBinding then
        return {
            binding = resolved.rawBinding,
            bindingToken = 0,
            source = resolved.source,
            bindingSourceIndex = resolved.bindingSourceIndex,
            actionSlot = resolved.actionSlot or resolved.slot,
            directActionSlot = resolved.directActionSlot == true,
            requestedSpellID = resolved.requestedSpellID,
            matchedSpellID = resolved.matchedSpellID,
            equivalentSpellIDs = resolved.equivalentSpellIDs,
            advisoryOnlyBinding = true,
            reason = resolved.reason,
        }
    end
    return nil
end

local function knownState(spellID)
    -- Known-state is a boolean capability check only. It never reads resource,
    -- cooldown, duration or other secret numeric values. When the client API
    -- is unavailable or cannot be interpreted, return nil and let the current
    -- profile plus action-bar resolver decide safely.
    local function callKnown(probe)
        if type(probe) ~= "function" then return nil end
        local ok, result = pcall(probe, spellID)
        if ok and type(result) == "boolean" then return result end
        return nil
    end
    -- Keep these calls explicit rather than storing potentially-nil functions
    -- in an ipairs table; Lua would stop at the first nil and skip later APIs.
    local result = callKnown(C_Spell and C_Spell.IsSpellKnown)
    if result ~= nil then return result, "C_Spell.IsSpellKnown" end
    result = callKnown(IsPlayerSpell)
    if result ~= nil then return result, "IsPlayerSpell" end
    result = callKnown(IsSpellKnown)
    if result ~= nil then return result, "IsSpellKnown" end
    return nil, "spell_known_unavailable"
end

local function advisoryItem(spellID, category, binding, known, knownSource, defenseEntry)
    local name, icon = spellInfo(spellID)
    -- Every advisory role must carry the resolver's canonical action-bar
    -- identity.  Without these fields interrupt/control/defense cards fall
    -- back to spell-ID cooldown tracking while burst cards use slot identity,
    -- causing aliases/overrides of the same visible button to disagree.
    local actionSlot = binding and (binding.actionSlot or binding.slot) or nil
    local directActionSlot = binding and binding.directActionSlot == true or false
    local item = {
        spellID = spellID,
        spellName = name or tostring(spellID),
        spellIcon = icon,
        binding = binding and binding.binding or nil,
        bindingToken = binding and binding.bindingToken or 0,
        bindingSource = binding and binding.source or nil,
        bindingSourceIndex = binding and binding.bindingSourceIndex or nil,
        actionSlot = actionSlot,
        slot = actionSlot,
        directActionSlot = directActionSlot,
        actionBarStateTrusted = directActionSlot,
        requestedSpellID = binding and (binding.requestedSpellID or spellID) or spellID,
        matchedSpellID = binding and binding.matchedSpellID or nil,
        equivalentSpellIDs = binding and binding.equivalentSpellIDs or nil,
        bindingInfo = binding,
        known = known,
        knownSource = knownSource,
        unbound = binding == nil,
        unusableReason = binding and nil or "动作条未找到现实绑定",
        category = category,
        advisoryOnly = true,
        usableState = "unknown",
    }
    if type(defenseEntry) == "table" then
        item.defensiveType = defenseEntry.type or category
        item.defensivePriority = tonumber(defenseEntry.priority)
        item.defensiveConditionMode = type(defenseEntry.conditions) == "table" and defenseEntry.conditions.mode or nil
        item.defensiveConditionText = defenseEntry.conditionText
    end
    return item
end

local function readCandidate(candidate, fallbackCategory)
    if type(candidate) == "table" then
        local spellID = tonumber(candidate.spellID)
        if not spellID then return nil, nil end
        return spellID, candidate
    end
    local spellID = tonumber(candidate)
    if not spellID then return nil, nil end
    return spellID, nil
end

local function firstBound(candidates, category)
    -- Prefer the first spell that is both usable for the current specialization
    -- and actually found on a current visible Blizzard action bar.  Retain one
    -- current-spec unbound candidate only as a diagnostic fallback. Structured
    -- defense entries carry their type, priority and applicability text through
    -- this path; generic control/burst lists remain supported as numeric IDs.
    local firstUnbound = nil
    for _, candidate in ipairs(candidates or {}) do
        local spellID, defenseEntry = readCandidate(candidate, category)
        if spellID then
            local known, knownSource = knownState(spellID)
            if known ~= false then
                local binding = bound(spellID)
                local item = advisoryItem(spellID, category, binding, known, knownSource, defenseEntry)
                if binding then return item end
                if not firstUnbound then firstUnbound = item end
            end
        end
    end
    return firstUnbound
end

local function hasRequiredBinding(item, requireActualBinding)
    return requireActualBinding ~= true or (item.binding and item.unbound ~= true)
end

local function contains(values, value)
    for _, candidate in ipairs(values or {}) do
        if tonumber(candidate) == tonumber(value) then return true end
    end
    return false
end

local function monitor()
    return TE.ProtocolMonitor and TE.ProtocolMonitor:Sample() or {}
end

local function environment()
    return TE.EnvironmentCompatibility and TE.EnvironmentCompatibility:Sample() or {
        available = false,
        state = "unavailable",
        source = "environment_compatibility",
        reason = "环境兼容模块不可用",
    }
end

local function envNotice(sample)
    if sample.available then return "环境兼容信号正常" end
    return sample.reason or "环境数据未知；不会推断地板技能"
end


-- Survival consumables are a display-only advisory source. A card is emitted
-- only after three independent observations agree: the item exists in bags,
-- it occupies a real current action-bar slot, and the resolver can name a
-- legal visible key. These item entries never enter the primary recommendation,
-- BindingToken, TEAP or TEK input chains.
local function plainItemCount(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return 0 end
    local probes = {
        function()
            if C_Item and type(C_Item.GetItemCount) == "function" then
                return C_Item.GetItemCount(itemID, false, false, false)
            end
        end,
        function()
            if type(GetItemCount) == "function" then return GetItemCount(itemID, false, false, false, false) end
        end,
    }
    for _, probe in ipairs(probes) do
        local ok, value = pcall(probe)
        local count = ok and tonumber(value) or nil
        if count and count >= 0 then return math.floor(count) end
    end
    return 0
end

local function itemInfo(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil, nil end
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, info = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(info) == "table" then
            return info.itemName or info.name, info.iconFileID or info.iconID or info.icon
        end
    end
    if type(GetItemInfo) == "function" then
        local ok, name, _, _, _, _, _, _, _, _, icon = pcall(GetItemInfo, itemID)
        if ok then return name, icon end
    end
    return nil, nil
end

local function itemBinding(itemID)
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveItem) ~= "function" then return nil, "item_resolver_unavailable" end
    local ok, resolved = pcall(resolver.ResolveItem, resolver, itemID)
    if not ok or type(resolved) ~= "table" then return nil, "item_resolver_failed" end
    if resolved.status == "Ready" and resolved.binding then return resolved, nil end
    return nil, resolved.reason or "actionbar_item_not_found"
end

local function survivalItem(itemID, category, displayName)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil, "item_not_configured" end
    local count = plainItemCount(itemID)
    if count <= 0 then return nil, "item_not_in_bags" end
    local binding, bindingReason = itemBinding(itemID)
    if not binding then return nil, bindingReason or "actionbar_item_not_found" end
    local name, icon = itemInfo(itemID)
    return {
        itemID = itemID,
        itemCount = count,
        spellName = name or displayName or ("物品 " .. tostring(itemID)),
        spellIcon = icon,
        binding = binding.binding,
        bindingToken = 0, -- advisory items never receive a dispatch token.
        bindingSource = binding.source,
        bindingSourceIndex = binding.bindingSourceIndex,
        bindingInfo = binding,
        category = category,
        source = "survival_consumable",
        advisoryCondition = "背包、当前动作条与真实键位均已确认；只读提示，不参与派发",
        advisoryOnly = true,
        usableState = "unknown",
        unbound = false,
    }, nil
end

local function survivalConfig(settings)
    settings.survival = type(settings.survival) == "table" and settings.survival or {}
    local survival = settings.survival
    if survival.healthstoneEnabled == nil then survival.healthstoneEnabled = true end
    if survival.potionEnabled == nil then survival.potionEnabled = true end
    survival.priority = survival.priority == "potion_first" and "potion_first" or "healthstone_first"
    survival.healthstoneItemID = tonumber(survival.healthstoneItemID) or 5512
    survival.potionItemID = tonumber(survival.potionItemID) or 0
    survival.displayHealthPercent = math.max(5, math.min(100, tonumber(survival.displayHealthPercent) or 35))
    survival.emergencyHealthPercent = math.max(5, math.min(100, tonumber(survival.emergencyHealthPercent) or 20))
    if survival.inCombatOnly == nil then survival.inCombatOnly = true end
    return survival
end

local function buildSurvivalItems(settings, inCombat, healthPercent, pressure, critical)
    local survival = survivalConfig(settings)
    local out = { active = false, items = {}, diagnostics = {}, threshold = survival.displayHealthPercent, emergencyThreshold = survival.emergencyHealthPercent }
    if survival.inCombatOnly == true and inCombat ~= true then
        out.state, out.notice = "out_of_combat", "消耗品仅设置为战斗中提示"
        return out
    end
    local displayByHealth = healthPercent ~= nil and healthPercent <= survival.displayHealthPercent
    local emergency = critical == true or (healthPercent ~= nil and healthPercent <= survival.emergencyHealthPercent)
    if not displayByHealth and not pressure and not emergency then
        out.state, out.notice = "monitoring", "等待消耗品血量阈值或高压信号"
        return out
    end

    local requested = survival.priority == "potion_first"
        and { { key = "potion", id = survival.potionItemID, enabled = survival.potionEnabled, label = "治疗药水" }, { key = "healthstone", id = survival.healthstoneItemID, enabled = survival.healthstoneEnabled, label = "治疗石" } }
        or { { key = "healthstone", id = survival.healthstoneItemID, enabled = survival.healthstoneEnabled, label = "治疗石" }, { key = "potion", id = survival.potionItemID, enabled = survival.potionEnabled, label = "治疗药水" } }

    for _, entry in ipairs(requested) do
        if entry.enabled ~= false then
            local item, reason = survivalItem(entry.id, entry.key, entry.label)
            if item then
                item.survivalPriority = #out.items + 1
                item.survivalEmergency = emergency == true
                out.items[#out.items + 1] = item
            elseif reason == "item_not_configured" and entry.key == "potion" then
                out.diagnostics[#out.diagnostics + 1] = "治疗药水尚未配置物品 ID"
            elseif reason == "item_not_in_bags" then
                out.diagnostics[#out.diagnostics + 1] = entry.label .. "不在背包中"
            elseif reason == "actionbar_item_not_found" then
                out.diagnostics[#out.diagnostics + 1] = entry.label .. "未在当前有效动作条中找到"
            else
                out.diagnostics[#out.diagnostics + 1] = entry.label .. "未通过绑定确认（" .. tostring(reason or "unknown") .. "）"
            end
        end
    end
    out.active = #out.items > 0
    out.state = out.active and (emergency and "emergency" or "threshold") or "no_bound_consumable"
    out.notice = out.active
        and (emergency and "紧急生存条件触发：已确认消耗品键位；只读提示" or "消耗品显示条件触发：已确认背包与键位")
        or (out.diagnostics[1] or "未找到可显示的消耗品")
    return out
end

function Planner:GetMovementState()
    return { active = movement.active == true, observedAt = movement.observedAt }
end

function Planner:BuildCandidates(primary, settings)
    local out = {
        active = false,
        mode = "prediction",
        label = "候选预测",
        items = {},
        source = "observed_transition",
        advisoryOnly = true,
        notice = "等待本会话官方推荐转移样本",
    }
    if settings.candidatePredictionEnabled == false then
        out.disabled, out.state, out.notice = true, "disabled", "候选预测已关闭"
        return out
    end
    if not primary or not primary.spellID then
        out.state = "waiting_primary"
        return out
    end
    local list, total = {}, 0
    if TE.TacticalState and type(TE.TacticalState.GetTransitionCandidates) == "function" then
        list, total = TE.TacticalState:GetTransitionCandidates(primary.spellID, 4)
    end
    for _, candidate in ipairs(list or {}) do
        local binding = bound(candidate.spellID)
        candidate.binding = binding and binding.binding or nil
        candidate.bindingToken = binding and binding.bindingToken or 0
        candidate.bindingSource = binding and binding.source or nil
        candidate.actionSlot = binding and (binding.actionSlot or binding.slot) or nil
        candidate.slot = candidate.actionSlot
        candidate.directActionSlot = binding and binding.directActionSlot == true or false
        candidate.actionBarStateTrusted = candidate.directActionSlot == true
        candidate.requestedSpellID = binding and (binding.requestedSpellID or candidate.spellID) or candidate.spellID
        candidate.matchedSpellID = binding and binding.matchedSpellID or nil
        candidate.equivalentSpellIDs = binding and binding.equivalentSpellIDs or nil
        candidate.bindingInfo = binding
        candidate.unbound = binding == nil
        candidate.unusableReason = binding and nil or "候选技能未在现实动作条中绑定"
        candidate.advisoryOnly = true
        candidate.usableState = "unknown"
        out.items[#out.items + 1] = candidate
    end
    out.totalObservations = total or 0
    out.active = #out.items > 0
    out.state = out.active and "observed" or "learning"
    if out.active then out.notice = "会话内官方推荐转移统计；只读，不参与派发" end
    return out
end

function Planner:BuildDefense(classFile, inCombat, settings, context, runtime)
    local out = { active = false, state = "monitoring", items = {}, advisoryOnly = true, source = "defense_explicit_spec_priority", survival = { active = false, items = {}, diagnostics = {} } }
    if settings.defensiveEnabled == false then
        out.disabled, out.state = true, "disabled"
        return out
    end

    runtime = type(runtime) == "table" and runtime or {}
    local monitorSample = runtime.monitor or monitor()
    local environmentSample = runtime.environment or environment()
    local healthPercent = tonumber(monitorSample.playerHealthPercent)
    local thresholdCritical = healthPercent ~= nil and healthPercent <= (tonumber(settings.defensiveHighlightHealthPercent) or 30)
    local thresholdDisplay = healthPercent ~= nil and healthPercent <= (tonumber(settings.defensiveDisplayHealthPercent) or 45)
    local pressure = monitorSample.playerRecentDamage == true and environmentSample.available == true and environmentSample.highPressure == true
    local critical = monitorSample.playerHealthCritical == true or thresholdCritical
    local survival = buildSurvivalItems(settings, inCombat, healthPercent, pressure, critical)
    out.survival = survival

    -- The current explicit specialization registry owns every eligible defense.
    -- User ordering is resolved as one unified list; it cannot import a class
    -- fallback or another specialization's spell.
    local priorityList, profile = {}, { profileKey = classFile or "unknown", source = "missing", calibrated = false }
    if TE.AbilityProfiles and type(TE.AbilityProfiles.GetDefensivePriorityList) == "function" then
        priorityList, profile = TE.AbilityProfiles:GetDefensivePriorityList(classFile, context and context.specIndex)
    elseif TE.AbilityProfiles and type(TE.AbilityProfiles.GetDefensiveGroups) == "function" then
        local groups
        groups, profile = TE.AbilityProfiles:GetDefensiveGroups(classFile, context and context.specIndex)
        -- Compatibility fallback for pre-unified registry implementations.
        -- The active implementation uses GetDefensivePriorityList above.
        for _, category in ipairs({ "minor", "major", "emergency", "selfheal" }) do
            for _, entry in ipairs((groups or {})[category] or {}) do priorityList[#priorityList + 1] = entry end
        end
    end
    out.profileKey = profile and profile.profileKey or classFile
    out.profileSource = profile and (profile.prioritySource or profile.source) or "missing"
    out.profileCalibrated = profile and profile.calibrated == true

    local seen = {}
    local function appendDefensive(entry, condition, requireActualBinding)
        if type(entry) ~= "table" or entry.enabled == false then return false end
        local spellID = tonumber(entry.spellID)
        if not spellID or seen[spellID] then return false end
        -- firstBound retains the current known-spell and real action-bar resolver
        -- checks. Passing one registry entry preserves the unified user order.
        local item = firstBound({ entry }, entry.type or "defense")
        if not item or not hasRequiredBinding(item, requireActualBinding) then return false end
        seen[spellID] = true
        item.defensiveProfileKey = out.profileKey
        item.defensiveProfileSource = out.profileSource
        item.defensivePriority = tonumber(entry.priority) or (#out.items + 1)
        item.advisoryOnly = true
        item.displayOnly = true
        -- Advisory cards must never carry an input-capable token, including when
        -- the action-bar resolver reports a Ready binding.
        item.bindingToken = 0
        item.advisoryCondition = condition or item.defensiveConditionText or "当前专精统一防御优先表"
        out.items[#out.items + 1] = item
        return true
    end

    if not inCombat then
        if settings.defensiveOutOfCombatStandby == false then
            out.state, out.notice = "out_of_combat_disabled", "脱战：防御待命显示已关闭"
            return out
        end
        local condition = "脱战待命：当前专精防御优先表、已知技能且已在有效动作条绑定；仅显示，不参与派发"
        for _, entry in ipairs(priorityList or {}) do appendDefensive(entry, condition, true) end
        out.active = #out.items > 0
        out.state = out.active and "out_of_combat_standby" or "out_of_combat_no_bound_defensive"
        out.severity = "idle"
        out.healthSource = monitorSample.healthSource
        out.healthPercent = healthPercent
        out.environmentState = environmentSample.state
        out.notice = out.active
            and "脱战：当前专精防御待命（只读显示，BindingToken=0）"
            or "脱战：当前专精未找到已知且在有效动作条绑定的防御技能"
        out.priorityNotice = "脱战防御按当前专精统一优先表排序"
        return out
    end

    local alwaysVisible = settings.defensiveDisplayMode == "always"
    local displayByThreshold = settings.defensiveDisplayMode ~= "condition" and thresholdDisplay
    local defenseTriggered = critical or pressure or alwaysVisible or displayByThreshold
    if not defenseTriggered then
        -- Consumables may still have a stricter independent threshold, but they
        -- remain display-only and do not cause spell defenses to appear early.
        for _, item in ipairs(survival.items or {}) do out.items[#out.items + 1] = item end
        out.active = #out.items > 0
        out.state = out.active and "survival_threshold" or "monitoring"
        out.severity = survival.state == "emergency" and "emergency" or "idle"
        out.healthSource = monitorSample.healthSource
        out.healthPercent = healthPercent
        out.environmentState = environmentSample.state
        out.notice = out.active and survival.notice or (monitorSample.healthAvailable == true
            and "等待低血兼容信号或高压伤害兼容信号"
            or "防御建议等待兼容的布尔低血监控来源")
        return out
    end

    -- Unified specialization sequence: the list order chosen for the active
    -- specialization is preserved. Survival consumables remain advisory-only
    -- and are inserted after the first eligible defense so they are not hidden
    -- behind a long list of low-priority cards.
    local survivalInserted = false
    for _, entry in ipairs(priorityList or {}) do
        appendDefensive(entry, "当前专精统一防御优先表触发")
        if not survivalInserted and #out.items > 0 then
            for _, item in ipairs(survival.items or {}) do
                item.advisoryOnly, item.displayOnly, item.bindingToken = true, true, 0
                out.items[#out.items + 1] = item
            end
            survivalInserted = true
        end
    end
    if not survivalInserted then
        for _, item in ipairs(survival.items or {}) do
            item.advisoryOnly, item.displayOnly, item.bindingToken = true, true, 0
            out.items[#out.items + 1] = item
        end
    end

    out.active = #out.items > 0
    out.state = out.active and (critical and "critical" or (pressure and "pressure" or "always_visible")) or "no_bound_defensive"
    out.severity = critical and "emergency" or (thresholdDisplay and "threshold" or (pressure and "pressure" or "idle"))
    out.healthSource = monitorSample.healthSource
    out.healthPercent = healthPercent
    out.environmentState = environmentSample.state
    if out.active then
        if critical then out.notice = "低血兼容监控触发：按当前专精统一优先表显示防御与生存建议"
        elseif pressure then out.notice = "近期受伤且高压环境兼容信号触发：按当前专精统一优先表显示防御建议"
        elseif thresholdDisplay then out.notice = "兼容血量低于显示阈值：按当前专精统一优先表显示防御建议"
        else out.notice = "防御提示常驻：等待低血或高压条件" end
    else
        out.notice = "防御条件已触发，但当前专精配置未找到现实动作条防御技能或可用消耗品"
    end
    return out
end

function Planner:BuildBurst(primary, classFile, settings, context, runtime)
    if TE.BurstPlanner and type(TE.BurstPlanner.Build) == "function" then
        local ok, result = pcall(function() return TE.BurstPlanner:Build(primary, context or {}, settings or {}, runtime or {}) end)
        if ok and type(result) == "table" then return result end
        return {
            active = false,
            state = "UNKNOWN",
            stateLabel = "状态未知",
            items = {},
            advisoryOnly = true,
            source = "burst_window_helper_fail_safe",
            notice = "爆发窗口辅助安全模式：" .. tostring(result),
        }
    end
    return { active = false, state = "SUPPRESSED", stateLabel = "已抑制", items = {}, advisoryOnly = true, source = "burst_window_helper_unavailable", notice = "爆发窗口辅助模块未加载" }
end

function Planner:BuildControl(classFile, settings, runtime)
    local out = { active = false, state = "monitoring", items = {}, advisoryOnly = true, source = "target_cast" }
    if settings.controlEnabled == false then
        out.disabled, out.state = true, "disabled"
        return out
    end
    runtime = type(runtime) == "table" and runtime or {}
    local sample = runtime.monitor or monitor()
    if sample.targetCasting ~= true then
        if settings.controlDisplayMode == "always" then
            local item = firstBound(TE.AbilityProfiles and TE.AbilityProfiles:GetControls(classFile) or {}, "control")
            if item then
                out.active, out.state, out.items = true, "always_visible", { item }
                out.notice = "控制提示常驻：等待不可打断读条"
            else
                out.state, out.notice = "no_bound_control", "控制提示常驻：动作条未找到控制技能"
            end
        else
            out.notice = "等待目标读条"
        end
        return out
    end
    if sample.targetInterruptSuppressed == true then
        out.state, out.notice = "suppressed", "目标读条刚被打断；短暂抑制重复控制提示"
        return out
    end
    if sample.targetInterruptibleKnown and sample.targetInterruptible == true then
        out.state, out.notice = "interrupt_preferred", "优先使用打断；控制仅作后备"
        return out
    end
    if sample.targetInterruptibleKnown and sample.targetInterruptible == false then
        local item = firstBound(TE.AbilityProfiles and TE.AbilityProfiles:GetControls(classFile) or {}, "control")
        if item then
            item.source = "target_noninterruptible_cast"
            out.active, out.state, out.items = true, "noninterruptible_cast", { item }
            out.dangerous = sample.targetCastDangerous == true
            out.notice = out.dangerous and "危险读条不可打断：控制候选" or "目标读条不可打断：控制候选"
        else
            out.state, out.notice = "no_bound_control", "动作条未找到控制技能"
        end
    else
        out.state, out.notice = "cast_unknown", "读条可打断状态未知"
    end
    return out
end

function Planner:BuildMobility(inCombat, classFile, settings, runtime)
    local out = { active = false, state = "monitoring", items = {}, advisoryOnly = true, source = "environment_compatibility" }
    if settings.mobilityEnabled == false then
        out.disabled, out.state = true, "disabled"
        return out
    end
    if not inCombat then
        out.state, out.notice = "out_of_combat", "脱战：位移待命"
        return out
    end
    runtime = type(runtime) == "table" and runtime or {}
    local monitorSample = runtime.monitor or monitor()
    local environmentSample = runtime.environment or environment()
    local need = monitorSample.playerHealthCritical == true
        or environmentSample.dangerZone == true
        or environmentSample.knockbackRisk == true
        or (movement.active and environmentSample.highPressure == true)
    if not need then
        out.state = environmentSample.available and "monitoring" or "environment_unknown"
        out.environmentState = environmentSample.state
        out.notice = envNotice(environmentSample)
        return out
    end
    local item = firstBound(TE.AbilityProfiles and TE.AbilityProfiles:GetMobility(classFile) or {}, "mobility")
    if item then
        item.source = monitorSample.playerHealthCritical and "low_health_compatibility" or environmentSample.source
        out.active, out.state, out.items = true, "escape", { item }
        out.environmentState = environmentSample.state
        out.notice = "低血或新鲜危险环境兼容信号触发位移建议"
    else
        out.state, out.notice = "no_bound_mobility", "条件已触发，但动作条未找到位移技能"
    end
    return out
end

function Planner:Build(primary, context, settings, runtime)
    context = type(context) == "table" and context or {}
    runtime = type(runtime) == "table" and runtime or {}
    runtime.monitor = runtime.monitor or monitor()
    runtime.environment = runtime.environment or environment()
    return {
        candidates = self:BuildCandidates(primary, settings),
        defense = self:BuildDefense(context.class, context.inCombat == true, settings, context, runtime),
        burst = self:BuildBurst(primary, context.class, settings, context, runtime),
        control = self:BuildControl(context.class, settings, runtime),
        mobility = self:BuildMobility(context.inCombat == true, context.class, settings, runtime),
    }
end

local watcher = CreateFrame("Frame")
local movementElapsed = 0
watcher:SetScript("OnUpdate", function(_, delta)
    movementElapsed = movementElapsed + (tonumber(delta) or 0)
    if movementElapsed < 0.25 then return end
    movementElapsed = 0
    if type(GetUnitSpeed) ~= "function" then return end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if not ok then
        movement.active = false
        movement.unknown = true
    else
        local compareOk, moving = pcall(function()
            return (speed or 0) > 0
        end)
        movement.active = compareOk and moving == true
        movement.unknown = not compareOk
    end
    movement.observedAt = type(GetTime) == "function" and GetTime() or 0
end)
