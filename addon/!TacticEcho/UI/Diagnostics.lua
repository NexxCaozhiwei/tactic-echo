local TE = _G.TacticEcho
TE.Diagnostics = TE.Diagnostics or {}

local function safePrint(message)
    if TE and type(TE.Print) == "function" then
        TE:Print(message)
    elseif print then
        print("|cff66ccffTactic Echo|r " .. tostring(message))
    end
end

local function ensureDiagnostics()
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.diagnostics = TacticEchoDB.diagnostics or {}
    TacticEchoDB.diagnostics.current = TacticEchoDB.diagnostics.current or {}
    return TacticEchoDB.diagnostics.current
end

local function printAction(action)
    if not action then
        safePrint("动作为空")
        return
    end

    safePrint("动作=" .. action.actionId
        .. " 技能=" .. tostring((action.spellIDs or {})[1])
        .. " 名称=" .. tostring(action.displayName))
end

SLASH_TACTICECHOCONTEXT1 = "/tecontext"
SlashCmdList.TACTICECHOCONTEXT = function()
    local context = TE.Context:GetPlayer()
    local active = 0
    for _ in pairs(TE.ActionRegistry:ListActiveActions(context)) do
        active = active + 1
    end

    safePrint("当前环境：职业=" .. tostring(context.class)
        .. " 专精=" .. tostring(context.specIndex)
        .. " 专精ID=" .. tostring(context.specID)
        .. " 名称=" .. tostring(context.specName)
        .. " 语言=" .. tostring(context.locale)
        .. " 当前动作数=" .. active
        .. " 战斗中=" .. tostring(context.inCombat))
end

local function printSignal(encoded)
    if not encoded then
        safePrint("信号帧：无")
        return
    end

    local fields = {}
    for index, value in ipairs(encoded.fields or {}) do
        fields[index] = tostring(value)
    end

        safePrint("信号帧：状态=" .. tostring(encoded.state)
        .. " 协议=" .. tostring(encoded.protocolVersion)
        .. " 会话=" .. tostring(encoded.sessionEpoch)
        .. " 序号=" .. tostring(encoded.sequence)
        .. " 新鲜度=" .. tostring(encoded.frameFreshnessCounter)
        .. " 动作码=" .. tostring(encoded.actionCode)
        .. " 动作=" .. tostring(encoded.actionId)
        .. " 技能=" .. tostring(encoded.spellID)
        .. " 目录=" .. tostring(encoded.catalogFingerprint)
        .. " Token=" .. tostring(encoded.bindingToken)
        .. " 键=" .. tostring(encoded.binding or "-")
        .. " 意图=" .. tostring(encoded.intentState or "-")
        .. " 脱战策略=" .. tostring(encoded.sessionPolicy or "-")
        .. " 校验=" .. tostring(encoded.checksum)
        .. " 字段=" .. table.concat(fields, ","))
end

SLASH_TACTICECHOSIGNAL1 = "/tesignal"
SlashCmdList.TACTICECHOSIGNAL = function(message)
    local command = string.lower(message or "")
    local encoded

    if command == "armed" or command == "arm" or command == "on" then
        TE.SignalFrame:SetState("armed")
        encoded = TE.SignalFrame:Refresh("manual")
        safePrint("信号框：已武装")
    elseif command == "pause" or command == "paused" then
        TE.SignalFrame:SetState("paused")
        encoded = TE.SignalFrame:Refresh("manual")
        safePrint("信号框：已暂停")
    elseif command == "off" or command == "waiting" then
        TE.SignalFrame:SetState("waiting")
        safePrint("信号框：已关闭")
    elseif command == "once" or command == "" then
        encoded = TE.SignalFrame:ShowOnce()
        safePrint("信号框：已输出一帧")
    elseif command == "status" then
        encoded = TE.SignalFrame:Refresh("manual")
        safePrint("信号框状态：" .. tostring(TE.SignalFrame:GetState()))
    else
        safePrint("命令：/tesignal armed 启用；/tesignal pause 暂停；/tesignal off 关闭；/tesignal status 查看。")
        return
    end

    printSignal(encoded)
end

local function printMacroDiagnostics(bindingInfo)
    local diagnostics = bindingInfo and bindingInfo.macroDiagnostics
    if type(diagnostics) ~= "table" or #diagnostics == 0 then return end
    local diag = diagnostics[1]
    safePrint("宏候选诊断：槽位=" .. tostring(diag.slot)
        .. " 绑定=" .. tostring(diag.rawBinding or "无")
        .. " 命令=" .. tostring(diag.bindingCommand or "无")
        .. " actionInfoId=" .. tostring(diag.actionInfoId or "无")
        .. " macroIndex=" .. tostring(diag.actionInfoMacroIndex or "无")
        .. " 身份=" .. tostring(diag.macroIdentitySource or "无")
        .. " 已核验=" .. tostring(diag.macroIdentityVerified == true)
        .. " actionText=" .. tostring(diag.actionText or "无")
        .. " macroSpellID=" .. tostring(diag.actionMacroSpellID or "无")
        .. " 查找=" .. tostring(diag.lookupSource or diag.failureReason or "无"))
    if diag.macroName or diag.resolvedMacroIndex or diag.resolvedBodyLength
        or diag.actionInfoIdReadAttempts then
        safePrint("宏候选详情：宏=" .. tostring(diag.macroName or diag.getMacroInfoByActionInfoIdName or "未知")
            .. " index=" .. tostring(diag.resolvedMacroIndex or diag.actionInfoMacroIndex or "无")
            .. " 读取=" .. tostring(diag.actionInfoIdReadAttempts or 0)
            .. " bodyLength=" .. tostring(diag.resolvedBodyLength or diag.getMacroInfoByActionInfoIdBodyLength or 0)
            .. " 原因=" .. tostring(diag.failureReason or "待匹配"))
    end
end
local function printButtonCache()
    if not TE.ActionBarBindingResolver then
        safePrint("ButtonCache：Resolver 未加载")
        return
    end
    local summary = TE.ActionBarBindingResolver:GetCacheSummary()
    safePrint("ButtonCache：代=" .. tostring(summary.generation)
        .. " 扫描=" .. tostring(summary.scannedButtons)
        .. " 可见=" .. tostring(summary.visibleButtons)
        .. " 条目=" .. tostring(summary.entries)
        .. " 宏=" .. tostring(summary.macroEntries)
        .. " 诊断=" .. tostring(summary.diagnostics)
        .. " 原因=" .. tostring(summary.scanReason))
    local special = summary.specialActionBar or {}
    if summary.blockedBySpecialActionBar then
        safePrint("动作条派发已显式阻断：" .. tostring(special.reason or "special_actionbar"))
    elseif special.extraActionVisible then
        safePrint("额外动作按钮显示：主动作条继续解析（非阻断）")
    end
end

SLASH_TACTICECHOCACHE1 = "/tecache"
SlashCmdList.TACTICECHOCACHE = function(message)
    local command = string.lower(message or "")
    if command == "refresh" or command == "rebuild" then
        TE.ActionBarBindingResolver:Invalidate("slash_cache")
        TE.ActionBarBindingResolver:Rebuild("slash_cache")
    end
    printButtonCache()
end

local function printMappingExport(snapshot)
    snapshot = snapshot or {}
    local cache = snapshot.cache or {}
    safePrint("映射导出：时间=" .. tostring(snapshot.exportedAt or "无")
        .. " 原因=" .. tostring(snapshot.reason or "无")
        .. " 条目=" .. tostring(#(snapshot.entries or {}))
        .. " 诊断=" .. tostring(#(snapshot.diagnostics or {}))
        .. " 代=" .. tostring(cache.generation or "无"))
    local special = cache.specialActionBar or {}
    if cache.blockedBySpecialActionBar then
        safePrint("映射导出：特殊动作条阻断=" .. tostring(special.reason or "special_actionbar"))
    elseif special.extraActionVisible then
        safePrint("映射导出：额外动作按钮显示，主动作条继续解析")
    end
    safePrint("映射导出已写入 TacticEchoDB.diagnostics.mappingExport；TEK 诊断包可读取已选择的 TacticEcho.lua。")
end

SLASH_TACTICECHOMAPPING1 = "/temapping"
SlashCmdList.TACTICECHOMAPPING = function(message)
    local command = string.lower(message or "")
    if not TE.MappingExport then
        safePrint("映射导出：MappingExport 未加载")
        return
    end
    if command == "status" then
        printMappingExport(TE.MappingExport:GetLatest())
        return
    end
    printMappingExport(TE.MappingExport:Capture(command == "" and "slash_mapping" or command))
end

local function autoBurstTactics()
    if TE.Config and TE.Config.Normalize and type(TE.Config.Normalize.All) == "function" then
        local _, tactics = TE.Config.Normalize:All()
        return tactics
    end
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.tactics = type(TacticEchoDB.tactics) == "table" and TacticEchoDB.tactics or {}
    return TacticEchoDB.tactics
end

local function printAutoBurstStatus()
    if not (TE.AutoBurst and type(TE.AutoBurst.GetDiagnostics) == "function") then
        safePrint("自动爆发：模块未加载。请确认当前加载的插件目录为 !TacticEcho。")
        return
    end
    local data = TE.AutoBurst:GetDiagnostics() or {}
    local rule = data.resolvedRule or {}
    local decision = data.lastDecision or {}
    local plan = data.plan or {}
    local labels = {}
    for _, step in ipairs(rule.steps or {}) do
        if step.category == "window" then
            labels[#labels + 1] = "窗口"
        elseif step.actionKind == "inventory" then
            labels[#labels + 1] = "饰品" .. tostring(step.inventorySlot or "?")
        else
            labels[#labels + 1] = "注入" .. tostring(step.spellID or "?")
        end
    end
    safePrint("自动爆发：构建=" .. tostring(data.build or "未知")
        .. " 启用=" .. tostring(data.enabled == true)
        .. " 模式=" .. tostring(data.mode or "-")
        .. " 宏=" .. tostring(data.macroPolicy or "-"))
    safePrint("自动爆发规则：专精=" .. tostring(rule.profileKey or "无")
        .. " 窗口=" .. tostring(rule.windowSpellID or "-")
        .. " 顺序=" .. (#labels > 0 and table.concat(labels, "→") or "无")
        .. " 原因=" .. tostring(data.ruleReason or "无"))
    local pendingLabel = plan.pendingConfirmationActionKind == "inventory"
        and ("饰品槽=" .. tostring(plan.pendingConfirmationInventorySlot or "-")
            .. " 物品=" .. tostring(plan.pendingConfirmationItemID or "-"))
        or tostring(plan.pendingConfirmationSpellID or "-")
    safePrint("自动爆发最近：阶段=" .. tostring(decision.phase or "-")
        .. " 原因=" .. tostring(decision.reason or "-")
        .. " 官方=" .. tostring(decision.officialSpellID or "-")
        .. " 计划=" .. tostring(plan.state or "IDLE")
        .. " 等待确认=" .. pendingLabel
        .. " 候选帧=" .. tostring(plan.candidateOfferCount or 0))
    if data.lastFault and data.lastFault.reason then
        safePrint("自动爆发错误：" .. tostring(data.lastFault.reason))
    end
end

SLASH_TACTICECHOAUTOBURST1 = "/teab"
SlashCmdList.TACTICECHOAUTOBURST = function(message)
    local command = string.lower(message or "")
    local tactics = autoBurstTactics()
    if command == "" or command == "status" then
        printAutoBurstStatus()
    elseif command == "on" then
        tactics.autoBurstEnabled = true
        safePrint("自动爆发已开启；仍需 /tesignal armed，且仅当前专精的爆发顺序通过预检后才会建立计划。")
        printAutoBurstStatus()
    elseif command == "off" then
        tactics.autoBurstEnabled = false
        if TE.AutoBurst and type(TE.AutoBurst.Abort) == "function" then TE.AutoBurst:Abort("slash_disabled", false) end
        safePrint("自动爆发已关闭。")
    else
        safePrint("用法：/teab status|on|off。爆发窗口、注入技能、饰品和顺序请在 TE 设置 → 爆发设置中按当前专精配置。")
    end
end

SLASH_TACTICECHOPOLICY1 = "/tepolicy"
SlashCmdList.TACTICECHOPOLICY = function(message)
    local command = string.lower(message or "")
    local mapping = { keep="manual_keep", manual="manual_keep", pause="pause_out_of_combat", close="close_out_of_combat" }
    if command ~= "" then
        local policy = mapping[command]
        if not policy then
            safePrint("用法：/tepolicy keep|pause|close")
            return
        end
        local ok, reason = TE.SignalFrame:SetSessionPolicy(policy)
        if not ok then
            safePrint("脱战策略设置失败：" .. tostring(reason))
            return
        end
    end
    safePrint("当前脱战策略：" .. tostring(TE.SignalFrame:GetSessionPolicyLabel()))
end

SLASH_TACTICECHOCURRENT1 = "/tecurrent"
SlashCmdList.TACTICECHOCURRENT = function()
    local result = TE.RecommendationAdapter:ReadOfficial()
    local action, registryReason = TE.ActionRegistry:ResolveRecommendation(result)
    local inputFocusActive, inputFocusReason = false, nil
    local castLock = { active = false }
    if TE.SignalFrame and TE.SignalFrame.IsInputFocusActive then
        inputFocusActive, inputFocusReason = TE.SignalFrame:IsInputFocusActive()
    end
    if TE.SignalFrame and TE.SignalFrame.GetCastLockInfo then
        castLock = TE.SignalFrame:GetCastLockInfo() or castLock
    end
    local bindingInfo, bindingReason = TE.ActionBarBindingResolver:ResolveSpell(result and result.spellID)
    if inputFocusActive then bindingReason = inputFocusReason
    elseif castLock.active then bindingReason = castLock.kind == "empower" and "player_empowering" or "player_channeling" end
    local store = ensureDiagnostics()
    local record = {
        observedAt = date("%Y-%m-%d %H:%M:%S"),
        elapsed = GetTime and GetTime() or 0,
        recommendation = result,
        actionId = action and action.actionId or nil,
        actionRegistryReason = registryReason,
        bindingInfo = bindingInfo,
        unresolvedReason = bindingReason,
        inputFocusActive = inputFocusActive,
        inputFocusReason = inputFocusReason,
        channelingActive = castLock.active == true and castLock.kind == "channel",
        channelingName = castLock.kind == "channel" and castLock.name or nil,
        channelingSpellID = castLock.kind == "channel" and castLock.spellID or nil,
        empoweringActive = castLock.active == true and castLock.kind == "empower",
        empoweringName = castLock.kind == "empower" and castLock.name or nil,
        empoweringSpellID = castLock.kind == "empower" and castLock.spellID or nil,
    }

    store[#store + 1] = record
    if #store > 40 then
        table.remove(store, 1)
    end

    safePrint("官方推荐：SpellID=" .. tostring(result.spellID)
        .. " 来源=" .. tostring(result.source)
        .. " 状态=" .. tostring(result.apiStatus)
        .. " 职业=" .. tostring(result.class)
        .. " 专精=" .. tostring(result.specIndex)
        .. " 战斗中=" .. tostring(result.inCombat))

    if inputFocusActive then
        safePrint("动态联动已暂停：检测到输入/对话界面（" .. tostring(inputFocusReason) .. "）")
    elseif castLock.active and castLock.kind == "empower" then
        safePrint("动态联动已暂停：玩家正在蓄力（蓄力保护已启用）")
    elseif castLock.active then
        safePrint("动态联动已暂停：玩家正在引导（引导保护已启用）")
    elseif bindingInfo and bindingInfo.status == "Ready" and (tonumber(bindingInfo.bindingToken) or 0) > 0 and (bindingInfo.source == "spell" or bindingInfo.source == "macro") then
        safePrint("动态绑定就绪：键=" .. tostring(bindingInfo.binding)
            .. " token=" .. tostring(bindingInfo.bindingToken)
            .. " 槽位=" .. tostring(bindingInfo.slot)
            .. " 来源=" .. tostring(bindingInfo.source)
            .. (bindingInfo.source == "macro" and " 宏=" .. tostring(bindingInfo.macroName or "未知") or ""))
    else
        safePrint("动态绑定未就绪：" .. tostring(bindingReason or "actionbar_spell_not_found"))
        printMacroDiagnostics(bindingInfo)
        if bindingReason == "chat_input_active" or bindingReason == "keyboard_focus_active" or bindingReason == "macro_editor_active" or bindingReason == "keybinding_editor_active" or bindingReason == "static_popup_active" then
            safePrint("动态联动已暂停：关闭聊天/输入/对话界面后自动恢复。")
        end
    end
    if action then printAction(action) end
    if registryReason then
        if bindingInfo and bindingInfo.status == "Ready" and (tonumber(bindingInfo.bindingToken) or 0) > 0 and (bindingInfo.source == "spell" or bindingInfo.source == "macro") then
            safePrint("旧目录诊断：" .. tostring(registryReason) .. "（v3 已就绪，不影响动态按键）")
        else
            safePrint("旧目录诊断：" .. tostring(registryReason) .. "（仅兼容信息）")
        end
    end
end

local function printTacticalSnapshot()
    local data = TE.TacticalAdvisors and TE.TacticalAdvisors:GetSnapshot() or nil
    if not data then
        safePrint("战术状态：等待同源信号快照")
        return
    end
    local primary = data.primary or {}
    local interrupt = data.interrupt or {}
    local advisory = data.advisory or {}
    local candidates = advisory.candidates or {}
    local firstCandidate = candidates.items and candidates.items[1] or nil
    safePrint("战术主推荐：SpellID=" .. tostring(primary.spellID or "无")
        .. " 键=" .. tostring(primary.binding or "无")
        .. " 状态=" .. tostring(primary.state or "未知")
        .. " 原因=" .. tostring(primary.reasonText or primary.reason or "无"))
    safePrint("战术预测：状态=" .. tostring(candidates.state or "未知")
        .. " 样本=" .. tostring(candidates.totalObservations or 0)
        .. " 首候选=" .. tostring(firstCandidate and firstCandidate.spellID or "无")
        .. " 置信=" .. tostring(firstCandidate and math.floor((tonumber(firstCandidate.confidence) or 0) * 100 + 0.5) or 0) .. "%")
    safePrint("战术监控：目标读条=" .. tostring(interrupt.cast and interrupt.cast.active == true)
        .. " 可打断=" .. tostring(interrupt.interruptible == true)
        .. " 打断键=" .. tostring(interrupt.suggestion and interrupt.suggestion.binding or "无")
        .. " 防御=" .. tostring(data.defensives and data.defensives.state or "未知")
        .. " 爆发=" .. tostring(advisory.burst and advisory.burst.state or "未知")
        .. " 控制=" .. tostring(advisory.control and advisory.control.state or "未知")
        .. " 位移=" .. tostring(advisory.mobility and advisory.mobility.state or "未知"))
    safePrint("说明：候选预测、爆发、控制、位移、打断和防御均为只读提示，不生成额外 Token 或现实按键派发。")
end

SLASH_TACTICECHOTACTICS1 = "/tetactics"
SlashCmdList.TACTICECHOTACTICS = function(message)
    local command = string.lower(message or "")
    if command == "print" or command == "status" then
        printTacticalSnapshot()
        return
    end
    if TE.ControlPanel and type(TE.ControlPanel.Show) == "function" then
        TE.ControlPanel:Show("hud")
    else
        printTacticalSnapshot()
    end
end

TE.Diagnostics.PrintCurrent = function()
    if SlashCmdList and SlashCmdList.TACTICECHOCURRENT then
        SlashCmdList.TACTICECHOCURRENT("")
    end
end
TE.Diagnostics.PrintButtonCache = printButtonCache
TE.Diagnostics.ExportMapping = function(reason)
    if TE.MappingExport then return TE.MappingExport:Capture(reason or "diagnostics") end
    return nil
end

SLASH_TACTICECHO1 = "/te"
SlashCmdList.TACTICECHO = function(message)
    local command = string.lower(message or "")
    if command == "" or command == "help" then
        safePrint("命令：/te context；/te current；/te cache；/te mapping；/te policy；/te tactics；/teab status|on|off；/te once；/te armed；/te pause；/te off；/te status；/te ui。爆发顺序、窗口、注入与饰品请在 /teui burst 按当前专精配置。")
    elseif command == "context" then
        SlashCmdList.TACTICECHOCONTEXT("")
    elseif command == "current" then
        SlashCmdList.TACTICECHOCURRENT("")
    elseif command == "cache" then
        SlashCmdList.TACTICECHOCACHE("")
    elseif command == "cache refresh" then
        SlashCmdList.TACTICECHOCACHE("refresh")
    elseif command == "mapping" then
        SlashCmdList.TACTICECHOMAPPING("")
    elseif command == "mapping status" then
        SlashCmdList.TACTICECHOMAPPING("status")
    elseif command == "tactics" then
        SlashCmdList.TACTICECHOTACTICS("")
    elseif command == "policy" then
        SlashCmdList.TACTICECHOPOLICY("")
    elseif command == "policy keep" then
        SlashCmdList.TACTICECHOPOLICY("keep")
    elseif command == "policy pause" then
        SlashCmdList.TACTICECHOPOLICY("pause")
    elseif command == "policy close" then
        SlashCmdList.TACTICECHOPOLICY("close")
    elseif command == "once" then
        SlashCmdList.TACTICECHOSIGNAL("once")
    elseif command == "armed" or command == "arm" then
        SlashCmdList.TACTICECHOSIGNAL("armed")
    elseif command == "pause" then
        SlashCmdList.TACTICECHOSIGNAL("pause")
    elseif command == "off" then
        SlashCmdList.TACTICECHOSIGNAL("off")
    elseif command == "status" then
        SlashCmdList.TACTICECHOSIGNAL("status")
    elseif command == "ui" then
        SlashCmdList.TACTICECHOUI("")
    else
        safePrint("未知 /te 子命令：" .. tostring(command))
    end
end
