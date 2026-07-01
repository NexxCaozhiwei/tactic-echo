-- Independent trigger recommendation: the burst planner evaluates the current specialization independently, even when the official primary queue does not itself recommend that spell.
--
-- Burst cards are display-only. The first slot is the configured burst-window
-- trigger; subsequent slots are injection spells, trinkets, potion and racial
-- candidates. No branch in this file mutates the official primary queue,
-- creates a BindingToken, writes TEAP or requests TEK input.
local TE = _G.TacticEcho

local BurstPlanner = {}
TE.BurstPlanner = BurstPlanner

local function number(value)
    local ok, result = pcall(function()
        local resolved = tonumber(value)
        if type(resolved) ~= "number" then return nil end
        local probe = resolved + 0
        if probe < -math.huge or probe > math.huge then return nil end
        return probe
    end)
    return ok and result or nil
end

local function boolean(value)
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function uniqueAppend(out, seen, key, item)
    if key == nil or seen[key] then return end
    seen[key] = true
    out[#out + 1] = item
end

local function spellInfo(spellID)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name, info.iconID or info.icon end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok then return name, icon end
    end
    return nil, nil
end

local function itemInfo(itemID)
    local icon
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, value = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = value end
    end
    if type(GetItemInfo) == "function" then
        local ok, name, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, itemID)
        if ok then return name, icon or texture end
    end
    return nil, icon
end

local function knownState(spellID)
    spellID = number(spellID)
    if not spellID then return false, "spell_id_invalid" end
    local function probe(fn)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, spellID)
        if ok and type(value) == "boolean" then return value end
        return nil
    end
    local known = probe(C_Spell and C_Spell.IsSpellKnown)
    if known ~= nil then return known, "C_Spell.IsSpellKnown" end
    known = probe(IsPlayerSpell)
    if known ~= nil then return known, "IsPlayerSpell" end
    known = probe(IsSpellKnown)
    if known ~= nil then return known, "IsSpellKnown" end
    return nil, "spell_known_unavailable"
end

local function resolveSpell(spellID)
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveSpell) ~= "function" then return nil, "binding_resolver_unavailable" end
    local ok, result = pcall(resolver.ResolveSpell, resolver, spellID)
    if not ok then return nil, "binding_resolver_failed" end
    if not result then return nil, "未找到动作条映射" end
    if result.status == "Ready" and result.binding then return result end
    if result.rawBinding then
        return {
            binding = result.rawBinding,
            bindingToken = 0,
            source = result.source,
            bindingSourceIndex = result.bindingSourceIndex,
            actionSlot = result.actionSlot or result.slot,
            advisoryOnlyBinding = true,
            reason = result.reason,
        }
    end
    return nil, result.reason or result.status or "技能未绑定或当前不可解析"
end

local function resolveItem(itemID)
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.ResolveItem) ~= "function" then return nil, "binding_resolver_unavailable" end
    local ok, result = pcall(resolver.ResolveItem, resolver, itemID)
    if not ok then return nil, "binding_resolver_failed" end
    if not result then return nil, "未找到动作条映射" end
    if result.status == "Ready" and result.binding then return result end
    if result.rawBinding then
        return {
            binding = result.rawBinding,
            bindingToken = 0,
            source = result.source,
            bindingSourceIndex = result.bindingSourceIndex,
            actionSlot = result.actionSlot or result.slot,
            advisoryOnlyBinding = true,
            reason = result.reason,
        }
    end
    return nil, result.reason or result.status or "物品未绑定或当前不可解析"
end

local function hostileTargetState()
    if type(UnitExists) == "function" and not UnitExists("target") then return false, "没有敌对目标" end
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("target") then return false, "目标已死亡" end
    if type(UnitCanAttack) == "function" and type(UnitExists) == "function" and UnitExists("target") then
        if not UnitCanAttack("player", "target") then return false, "目标不可攻击" end
    end
    return true, nil
end

local function collectSpellState(item, options)
    options = type(options) == "table" and options or {}
    if not (TE.IconState and type(TE.IconState.Decorate) == "function") then
        item.usableState = "unknown"
        item.unusableReason = "图标状态模块不可用"
        return item
    end
    local ok, decorated = pcall(TE.IconState.Decorate, TE.IconState, item, {
        requiresHostileTarget = options.requiresHostileTarget == true,
        gcdSnapshot = options.gcdSnapshot,
        actionSlot = item.actionSlot or item.slot,
        directActionSlot = item.directActionSlot == true,
        actionBarStateTrusted = item.actionBarStateTrusted == true,
        matchedSpellID = item.matchedSpellID,
        requestedSpellID = item.requestedSpellID or item.spellID,
        equivalentSpellIDs = item.equivalentSpellIDs,
    })
    if ok and type(decorated) == "table" then return decorated end
    item.usableState = "unknown"
    item.unusableReason = "图标状态读取失败"
    return item
end

local function itemCooldownSnapshot(item)
    local resolver = TE.CooldownResolver
    if not resolver then return nil end
    if item.inventorySlot and type(resolver.GetInventory) == "function" then
        return resolver:GetInventory(item.inventorySlot, item.itemID)
    end
    if item.category == "potion" and type(resolver.GetPotion) == "function" then
        return resolver:GetPotion(item.itemID)
    end
    if type(resolver.GetItem) == "function" then
        return resolver:GetItem(item.itemID, item.category == "trinket" and "item" or item.category)
    end
    return nil
end

local function applyItemCooldown(item, snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    item.cooldownRemaining = snapshot.remaining
    item.cooldownDuration = snapshot.duration
    item.cooldownStart = snapshot.start
    item.cooldownKnown = snapshot.known == true
    item.cooldownUnknownReason = snapshot.reason
    item.cooldownSource = snapshot.source
    item.cooldownIdentityKey = snapshot.identity
    item.cooldownActive = snapshot.active == true
    item.cooldownOnGCD = snapshot.onGCD
    -- P5.1 diagnostics: an equipped trinket may use its ItemID API only when
    -- the slot API temporarily reports an empty ready sample after activation.
    -- These fields are display-only and make that resolution visible in HUD
    -- tooltips without affecting any recommendation or TEK dispatch path.
    item.cooldownSlotSource = snapshot.slotSource
    item.cooldownSlotKnown = snapshot.slotKnown
    item.cooldownSlotActive = snapshot.slotActive
    item.cooldownItemFallbackKnown = snapshot.itemFallbackKnown
    item.cooldownItemFallbackActive = snapshot.itemFallbackActive
    item.inventorySlot = snapshot.inventorySlot or item.inventorySlot
    return item
end

local function collectItemState(item)
    local slot = number(item.actionSlot or item.slot)
    local count
    -- Equipped trinkets have a stable inventory-slot identity. Their item count
    -- is not relevant and must not make a currently equipped item disappear.
    if item.category ~= "trinket" and type(GetItemCount) == "function" then
        local ok, value = pcall(GetItemCount, item.itemID)
        if ok then count = number(value) end
    end
    item.itemCount = count
    item.targetChecked = false
    item.rangeBlocked = false
    item.targetInvalid = false
    item.resourceBlocked = false
    item.procHighlight = false
    item.casting = false
    item.channeling = false
    item.castingThisSpell = false
    item.globalCasting = false
    item.globalChanneling = false
    item.gcdKnown = false
    item.gcdActive = nil

    -- P5: cooldown truth does not come from an action-bar slot.  Trinkets use
    -- GetInventoryItemCooldown(player, 13/14); potions and other consumables
    -- use C_Item.GetItemCooldown/GetItemCooldown by ItemID.  The action bar is
    -- now only a display of a real hotkey / icon / optional usability hint.
    applyItemCooldown(item, itemCooldownSnapshot(item))
    local cooling = item.cooldownActive == true
        or (item.cooldownKnown == true and (number(item.cooldownRemaining) or 0) > 0)
    if cooling then
        item.usableState = "cooldown"
        item.unusableReason = "物品冷却中"
        return item
    end

    -- A potion can be consumed to zero while its category cooldown continues.
    -- Once it is ready, a zero stack correctly becomes unavailable; while it is
    -- cooling the card remains visible so its cooldown can still be read.
    if count ~= nil and count <= 0 then
        item.usableState = "unavailable"
        item.unusableReason = "背包中没有该物品"
        return item
    end

    -- If a binding exists, retain the optional native usability indication. It
    -- never replaces the source-specific cooldown snapshot above.
    if slot and C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" then
        local ok, usable, notEnough = pcall(C_ActionBar.IsUsableAction, slot)
        usable, notEnough = boolean(usable), boolean(notEnough)
        if ok and usable == false then
            item.resourceBlocked = notEnough == true
            item.usableState = item.resourceBlocked and "resource" or "unavailable"
            item.unusableReason = item.resourceBlocked and "资源不足" or "物品当前不可用"
            return item
        end
    end

    -- An unbound item can still have a perfectly valid cooldown snapshot. The
    -- HUD renders its source and CD, then uses the independent state label to
    -- state “未绑定” instead of suppressing the whole card.
    item.usableState = "ready"
    item.unusableReason = nil
    return item
end

local function spellCandidate(spellID, category, source, options)
    spellID = number(spellID)
    if not spellID then return nil, "invalid_spell" end
    local known, knownSource = knownState(spellID)
    if known == false then return nil, "not_known_current_spec" end
    local binding, bindingReason = resolveSpell(spellID)
    if not binding or not binding.binding then return nil, bindingReason or "动作条未找到现实绑定" end
    local name, icon = spellInfo(spellID)
    local item = {
        spellID = spellID,
        spellName = name or tostring(spellID),
        spellIcon = icon,
        category = category,
        source = source,
        burstSource = source,
        advisoryOnly = true,
        displayOnly = true,
        binding = binding.binding,
        bindingToken = 0,
        bindingSource = binding.source,
        bindingSourceIndex = binding.bindingSourceIndex,
        actionSlot = binding.actionSlot or binding.slot,
        directActionSlot = binding.directActionSlot == true,
        actionBarStateTrusted = binding.directActionSlot == true,
        bindingInfo = binding,
        requestedSpellID = binding.requestedSpellID or spellID,
        matchedSpellID = binding.matchedSpellID,
        equivalentSpellIDs = binding.equivalentSpellIDs,
        known = known,
        knownSource = knownSource,
        advisoryCondition = "当前专精爆发注册表；当前有效动作条真实绑定；仅 HUD 提示",
    }
    -- The current action-bar key is resolved before this read-only state snapshot.
    -- Legacy audit note: TE.IconState:Collect(spellID, { requiresHostileTarget = true })
    -- is now routed through Decorate so all card fields are populated consistently.
    item = collectSpellState(item, options)
    -- TacticalAdvisors reuses this complete snapshot instead of querying the
    -- same spell state a second time later in the same refresh.
    item.iconStateCollectedBy = "BurstPlanner"
    item.burstReady = item.usableState == "ready"
    return item
end

local function itemCandidate(itemID, category, source, options)
    itemID = number(itemID)
    if not itemID or itemID <= 0 then return nil, "invalid_item" end
    options = type(options) == "table" and options or {}
    local binding, bindingReason = resolveItem(itemID)
    local name, icon = itemInfo(itemID)
    local item = {
        itemID = itemID,
        spellName = name or source or ("物品 " .. tostring(itemID)),
        spellIcon = icon,
        category = category,
        source = source,
        burstSource = source,
        advisoryOnly = true,
        displayOnly = true,
        -- Binding is optional for display-only item cards.  It determines the
        -- hotkey / “未绑定” state, never the existence or truth of cooldown data.
        binding = binding and binding.binding or nil,
        bindingToken = 0,
        bindingSource = binding and binding.source or nil,
        bindingSourceIndex = binding and binding.bindingSourceIndex or nil,
        actionSlot = binding and (binding.actionSlot or binding.slot) or nil,
        directActionSlot = binding and binding.directActionSlot == true or false,
        actionBarStateTrusted = binding and binding.directActionSlot == true or false,
        bindingInfo = binding,
        bindingMissing = not (binding and binding.binding),
        bindingReason = bindingReason,
        inventorySlot = number(options.inventorySlot),
        advisoryCondition = binding and binding.binding
            and "爆发物品冷却由装备槽位或物品类别 API 读取；动作条仅提供现实按键；仅 HUD 提示"
            or "爆发物品冷却由装备槽位或物品类别 API 读取；当前未绑定现实按键；仅 HUD 提示",
    }
    item = collectItemState(item)
    item.burstReady = item.usableState == "ready"
    return item
end

local function collectSpells(spellIDs, profile, category, source, options)
    local all, ready, cooling, blocked, diagnostics, seen = {}, {}, {}, {}, {}, {}
    for _, spellID in ipairs(spellIDs or {}) do
        spellID = number(spellID)
        if spellID and not seen[spellID] and not (TE.BurstProfiles and TE.BurstProfiles:IsBlacklisted(profile, spellID)) then
            seen[spellID] = true
            local item, reason = spellCandidate(spellID, category, source, options)
            if item then
                all[#all + 1] = item
                if item.usableState == "ready" then ready[#ready + 1] = item
                elseif item.usableState == "cooldown" then cooling[#cooling + 1] = item
                else blocked[#blocked + 1] = item end
            elseif reason then
                diagnostics[#diagnostics + 1] = tostring(reason)
            end
        end
    end
    return all, ready, cooling, blocked, diagnostics
end

local function append(out, source, limit, seen)
    for _, item in ipairs(source or {}) do
        if limit and #out >= limit then break end
        local key = item.itemID and ("item:" .. tostring(item.itemID)) or ("spell:" .. tostring(item.spellID))
        uniqueAppend(out, seen, key, item)
    end
end

local function cooldownAllowed(settings)
    return settings and settings.burstCooldownDisplay ~= "hide"
end

local function followerLimit(settings)
    local maximum = tonumber(settings and settings.burstMaxCandidates) or 3
    maximum = math.max(0, math.min(4, math.floor(maximum)))
    if settings and settings.burstDisplayMode == "compact" then maximum = 0 end
    return maximum
end

local function makeOutput(profile, profileKey, state, profileReason)
    return {
        active = false,
        state = state.state,
        windowState = state.state,
        stateLabel = state.label,
        window = nil,
        followups = {},
        items = {},
        advisoryOnly = true,
        displayOnly = true,
        source = "independent_burst_queue",
        profileKey = profileKey,
        profileLabel = profile and profile.label,
        openerSpellID = state.openerSpellID,
        activeBuffID = state.activeBuffID,
        lastTransitionReason = state.lastTransitionReason,
        dispatchPolicy = "strict_safe",
        overlayPrimary = false,
        recommendationState = "idle",
        notice = state.lastTransitionReason or profileReason or "爆发提示待命",
        diagnostics = {},
    }
end

local function markRole(item, role, state, sourceOrder)
    if not item then return nil end
    item.burstRole = role
    item.burstWindow = role == "window"
    item.burstState = state and state.state or nil
    item.burstOrder = sourceOrder
    item.burstOverlay = role == "window" and (state and (state.state == "ACTIVE" or state.state == "ARMED") or false)
    return item
end

local function windowCandidates(profile, state, options)
    local ordered, seen = {}, {}
    local observed = number(state and state.openerSpellID)
    if observed then
        ordered[#ordered + 1] = observed
        seen[observed] = true
    end
    for _, spellID in ipairs(profile.openerSpellIDs or {}) do
        spellID = number(spellID)
        if spellID and not seen[spellID] then ordered[#ordered + 1] = spellID; seen[spellID] = true end
    end
    return collectSpells(ordered, profile, "offensiveCooldowns", "爆发窗口技能", options)
end

local function selectWindow(profile, state, settings, options, allowReady)
    local all, ready, cooling, blocked, diagnostics = windowCandidates(profile, state, options)
    local selected
    if allowReady and #ready > 0 then selected = ready[1]
    elseif #cooling > 0 and cooldownAllowed(settings) then selected = cooling[1]
    elseif settings.burstDisplayMode == "always" and #blocked > 0 then selected = blocked[1]
    elseif settings.burstDisplayMode == "always" and #all > 0 then selected = all[1]
    end
    return selected, diagnostics
end

local function collectTrinkets(profile)
    local all, diagnostics = {}, {}
    if type(GetInventoryItemID) ~= "function" then return all, diagnostics end
    for _, entry in ipairs((profile.displayCandidates or {}).trinkets or {}) do
        if entry.enabled ~= false then
            local slot = number(entry.slot)
            local ok, itemID = pcall(GetInventoryItemID, "player", slot)
            itemID = ok and number(itemID) or nil
            if itemID and itemID > 0 then
                local item, reason = itemCandidate(itemID, "trinket", entry.label or ("饰品" .. tostring(slot)), { inventorySlot = slot })
                if item then all[#all + 1] = item elseif reason then diagnostics[#diagnostics + 1] = tostring(reason) end
            end
        end
    end
    return all, diagnostics
end

local function collectPotion(settings)
    local itemID = number(settings and settings.burstPotionItemID)
    if not itemID or itemID <= 0 then return {}, {} end
    local item, reason = itemCandidate(itemID, "potion", "爆发药水", { potion = true })
    return item and { item } or {}, reason and { tostring(reason) } or {}
end

local function collectRacial(profile, settings, options)
    local ids, seen = {}, {}
    for _, spellID in ipairs((profile.displayCandidates or {}).racial or {}) do
        spellID = number(spellID)
        if spellID and not seen[spellID] then ids[#ids + 1] = spellID; seen[spellID] = true end
    end
    local custom = number(settings and settings.burstRacialSpellID)
    if custom and custom > 0 and not seen[custom] then ids[#ids + 1] = custom end
    return collectSpells(ids, profile, "racial", "种族技能", options)
end

local function bucket(items)
    local ready, cooling, blocked = {}, {}, {}
    for _, item in ipairs(items or {}) do
        if item.usableState == "ready" then ready[#ready + 1] = item
        elseif item.usableState == "cooldown" then cooling[#cooling + 1] = item
        else blocked[#blocked + 1] = item end
    end
    return ready, cooling, blocked
end

local function followups(profile, state, settings, options, showSequence)
    local out, seen, diagnostics = {}, {}, {}
    local maximum = followerLimit(settings)
    if maximum <= 0 then return out, diagnostics end
    local always = settings.burstDisplayMode == "always"
    local active = state.state == "ACTIVE"
    -- A burst queue is useful before the trigger is pressed as well: the first
    -- card is the window skill and the followers show the prepared sequence.
    -- In non-always mode, only reveal followers when a real, ready window card
    -- is visible or the burst is already active.
    if not always and not active and showSequence ~= true then return out, diagnostics end

    local orderedGroups = {}
    local injectionAll, _, _, _, injectionDiag = collectSpells(profile.injectionSpellIDs, profile, "rotationSpells", "爆发注入", options)
    orderedGroups[#orderedGroups + 1] = { role = "injection", items = injectionAll }
    for _, reason in ipairs(injectionDiag or {}) do diagnostics[#diagnostics + 1] = reason end

    if settings.burstShowTrinkets == true and profile.allowTrinketHint ~= false then
        local values, diag = collectTrinkets(profile)
        orderedGroups[#orderedGroups + 1] = { role = "trinket", items = values }
        for _, reason in ipairs(diag or {}) do diagnostics[#diagnostics + 1] = reason end
    end
    if settings.burstShowPotions == true and profile.allowPotionHint ~= false then
        local values, diag = collectPotion(settings)
        orderedGroups[#orderedGroups + 1] = { role = "potion", items = values }
        for _, reason in ipairs(diag or {}) do diagnostics[#diagnostics + 1] = reason end
    end
    if settings.burstShowRacial == true and profile.allowRacialHint ~= false then
        local values, _, _, _, diag = collectRacial(profile, settings, options)
        orderedGroups[#orderedGroups + 1] = { role = "racial", items = values }
        for _, reason in ipairs(diag or {}) do diagnostics[#diagnostics + 1] = reason end
    end

    local function addGroup(items, role, wanted)
        for _, item in ipairs(items or {}) do
            if #out >= maximum then return end
            if wanted == nil or item.usableState == wanted then
                markRole(item, role, state, #out + 2)
                append(out, { item }, maximum, seen)
            end
        end
    end

    -- Always mode keeps configured, bound queue entries in their declared
    -- category order. Window mode prioritizes ready use during an active burst,
    -- then retains real cooldown cards only when the user requested them.
    if always then
        for _, group in ipairs(orderedGroups) do addGroup(group.items, group.role) end
    else
        for _, group in ipairs(orderedGroups) do addGroup(group.items, group.role, "ready") end
        if cooldownAllowed(settings) and #out < maximum then
            for _, group in ipairs(orderedGroups) do addGroup(group.items, group.role, "cooldown") end
        end
    end
    return out, diagnostics
end

local function compose(out)
    out.items = {}
    if out.window then out.items[#out.items + 1] = out.window end
    for _, item in ipairs(out.followups or {}) do out.items[#out.items + 1] = item end
    out.active = #out.items > 0
end

function BurstPlanner:Build(primary, context, settings, runtime)
    settings, context, runtime = settings or {}, context or {}, runtime or {}
    local profile, profileKey, profileReason = TE.BurstProfiles and TE.BurstProfiles:Get(context) or nil, nil, "BurstProfiles 不可用"
    if TE.BurstProfiles and type(TE.BurstProfiles.Get) == "function" then
        profile, profileKey, profileReason = TE.BurstProfiles:Get(context)
    end
    local state = TE.BurstStateMachine and TE.BurstStateMachine:Update(profile, profileKey, primary, context, settings)
        or { state = "UNKNOWN", label = "状态未知", lastTransitionReason = "BurstStateMachine 不可用" }
    local out = makeOutput(profile, profileKey, state, profileReason)

    if not profile then
        out.state, out.stateLabel, out.notice = "SUPPRESSED", "已抑制", profileReason or "当前专精暂无爆发辅助配置"
        return out
    end
    if settings.burstEnabled == false or profile.enabled == false then
        out.state, out.stateLabel, out.notice = "SUPPRESSED", "已抑制", "爆发模块已关闭"
        return out
    end
    if state.state == "UNKNOWN" then
        out.notice = state.lastTransitionReason or "爆发状态未知"
        return out
    end

    local always = settings.burstDisplayMode == "always"
    local inCombat = context.inCombat == true
    local targetOK, targetReason = hostileTargetState()
    local activeWindow = state.state == "ACTIVE" or state.state == "ARMED"
    local primaryExists = primary and primary.spellID
    local policyAllowsReady = state.state == "ACTIVE"
        or (settings.burstPolicy ~= "hold" and inCombat and targetOK and (settings.burstPolicy ~= "align" or primaryExists))
    if always then policyAllowsReady = true end

    local options = {
        -- Constant display cards should not be greyed because no target exists.
        requiresHostileTarget = inCombat and targetOK and not always,
        -- Shared GCD observation for all burst cards in this advisor cycle.
        gcdSnapshot = runtime.iconContext and runtime.iconContext.gcdSnapshot or nil,
    }

    if settings.burstShowClassCooldowns ~= false then
        local window, diagnostics = selectWindow(profile, state, settings, options, policyAllowsReady)
        out.diagnostics = diagnostics or {}
        if window then out.window = markRole(window, "window", state, 1) end
    end

    local shouldFollow = always or activeWindow or (out.window and out.window.usableState == "ready" and policyAllowsReady)
    if shouldFollow and settings.burstShowCandidates ~= false then
        local values, diagnostics = followups(profile, state, settings, options, shouldFollow)
        out.followups = values
        for _, reason in ipairs(diagnostics or {}) do out.diagnostics[#out.diagnostics + 1] = reason end
    end
    compose(out)

    if out.active then
        if state.state == "ACTIVE" then
            out.recommendationState = "active_window_queue"
            out.notice = "爆发窗口：首图标为窗口技能，后续按注入技能、饰品、药水、种族技能顺序显示；仅 HUD 提示"
        elseif always and not inCombat then
            out.recommendationState = "always_out_of_combat_queue"
            out.notice = "常驻爆发队列：仅展示当前专精已知且有真实动作条绑定的窗口与后续技能"
        elseif always then
            out.recommendationState = "always_queue"
            out.notice = "常驻爆发队列：窗口技能固定首位；后续按已配置顺序保留，并显示真实冷却状态"
        elseif out.window and out.window.usableState == "cooldown" then
            out.recommendationState = "window_cooldown"
            out.notice = "爆发窗口技能冷却中：保留首图标并由游戏原生转盘显示倒计时"
        else
            out.recommendationState = "window_ready"
            out.notice = "当前专精爆发窗口技能已就绪：首图标显示真实动作条按键；仅 HUD 提示"
        end
        return out
    end

    if settings.burstPolicy == "hold" then
        out.state, out.stateLabel, out.recommendationState = "HOLD", "保留爆发", "held"
        out.notice = "爆发保留模式：不主动显示就绪窗口技能；开启常驻后仍会保留已绑定的队列卡片"
    elseif not inCombat then
        out.state, out.stateLabel, out.recommendationState = "OUT_OF_COMBAT", "脱战待命", "out_of_combat"
        out.notice = "进入战斗并选择敌对目标后，独立检测当前专精爆发窗口技能"
    elseif not targetOK then
        out.state, out.stateLabel, out.recommendationState = "WAITING_TARGET", "等待敌对目标", "waiting_target"
        out.notice = targetReason or "没有可攻击目标"
    elseif settings.burstPolicy == "align" and not primaryExists then
        out.state, out.stateLabel, out.recommendationState = "WAITING_PRIMARY", "等待主推荐", "waiting_primary"
        out.notice = "对齐爆发模式：等待官方主推荐可用后再显示独立爆发窗口技能"
    else
        out.state, out.stateLabel, out.recommendationState = "WAITING_READY", "等待爆发就绪", "no_bound_candidate"
        out.notice = "当前专精未找到已知、已绑定的爆发窗口技能或后续候选"
    end
    return out
end
