local addonName, TEF = ...
local VERSION = "0.10.1"
local S = TEF.Safety
local engine, frame

local function printSafe(message)
    if type(print)=="function" then pcall(print,"|cff66ccffTEF|r " .. message) end
end
local function refresh() if engine then TEF.UI:Refresh() end end

local function initialize()
    engine=TEF.Engine.New(TEF.Config,TEF_DB)
    TEF_DB=engine.db
    -- Runtime namespace is the addon's private loader table, no TE dependency.
    TEF.engine=engine
    TEF.Profiles:Select(engine,engine.scene)
    TEF.Transport:Initialize(engine)
    engine.clientValidated=false
    local ok, version, build, _, interface=pcall(function() return GetBuildInfo() end)
    if ok then
        local safeVersion=S.Public(version,"string")
        local safeBuild=S.Public(build,"string")
        local safeInterface=S.ID(interface)
        if safeVersion and safeBuild and safeInterface then
            engine.db.client={version=safeVersion,build=safeBuild,interface=safeInterface}
            engine.clientValidated=safeVersion=="1.60.1" and safeBuild=="70338" and safeInterface==16001
            if safeVersion ~= "1.60.1" or safeBuild ~= "70338" or safeInterface ~= 16001 then
                engine:Log("error","CLIENT_CONTEXT_CHANGED")
                printSafe("客户端与70338基线不同，请核对接口及事件；当前默认暂停。")
            end
        else engine:Log("unknown","CLIENT_UNKNOWN") end
    else engine:Log("unknown","CLIENT_CALL_FAILED") end
    TEF.UI:Create(engine)
    TEF.HUD:Create(engine)
    TEF.UI:Paint(TEF.UI.frame,"Hide")
    TEF.Runtime:Initialize(engine)
    TEF.Transport:SetEnabled(engine.db.dispatch.signal)
    TEF.Hotkeys:Apply()
    printSafe("v" .. VERSION .. " 已加载；统一派发启停，默认自动启停。/tefui")
end

local function onEvent(_,event,...)
    if event == "ADDON_LOADED" then
        local name=S.Public((...),"string")
        if name==addonName and not engine then initialize() end
        return
    end
    if not engine then return end
    if event == "PLAYER_LOGOUT" then TEF.Runtime:Stop("RUNTIME_LOGOUT"); TEF.Transport:SetEnabled(false); return end
    if event == "PLAYER_LOGIN" then TEF.Hotkeys:Apply(); refresh(); return end
    if event == "PLAYER_ENTERING_WORLD" then TEF.Hotkeys:Apply(); TEF.Profiles:RefreshIdentity(engine); TEF.Runtime:World(); refresh(); return end
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event=="CHARACTER_POINTS_CHANGED" then
        TEF.Profiles:RefreshIdentity(engine); refresh(); return
    end
    if event == "SPELLS_CHANGED" then TEF.Presentation.bindings={}; TEF.Presentation.cooldowns={}; TEF.HUD.metadata={}; TEF.Dispatch:ClearBindingCache(); refresh(); return end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then TEF.HUD:Refresh(event=="SPELL_UPDATE_COOLDOWN"); return end
    if event == "PLAYER_REGEN_ENABLED" then
        if engine.db.loopMode=="combat" then TEF.Runtime:ResetCycle("LOOP_COMBAT_RESET") end
        TEF.Hotkeys:Apply(); TEF.Runtime:Tick(); TEF.UI:Layout(); refresh(); return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_BINDINGS" then
        if event=="UPDATE_BINDINGS" then TEF.Hotkeys:Apply() end
        TEF.Dispatch:BindingsChanged(); TEF.Presentation.bindings={}; TEF.Research:Invalidate(); refresh(); return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat flags are sampled live by Packet; entering combat is not a
        -- generation or target change and must not kill a first-cast request.
        TEF.Research:Invalidate(); TEF.Runtime:Tick(); refresh(); return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        if engine.db.loopMode=="target" then TEF.Runtime:ResetCycle("LOOP_TARGET_RESET")
        else TEF.Runtime:Suspend("RUNTIME_TARGET_CHANGED") end
        TEF.Presentation.bindings={}; TEF.Research:Invalidate(); refresh(); return
    end
    if event == "UI_SCALE_CHANGED" then
        TEF.Runtime:Suspend("RUNTIME_LAYOUT_REFRESH")
        if engine.db.dispatch.signal then TEF.Transport:SetEnabled(true) end
        TEF.UI:Layout(); refresh(); return
    end
    if TEF.Events[event] then
        local unit,guid,id,ignoredTarget
        if event == "UNIT_SPELLCAST_SENT" then
            -- Deliberately ignore target (argument 2), including its Secret value.
            unit,ignoredTarget,guid,id=...
        else unit,guid,id=... end
        local consumed=TEF.Dispatch:Event(event,unit,id,guid)
        if not consumed then engine:Handle(engine.generation,event,unit,guid,id) end
        -- Events invalidate research evidence, never manufacture cast=false.
        local publicUnit=S.Public(unit,"string")
        if publicUnit=="player" then TEF.Research:Invalidate() end
        refresh()
    end
end

local created
created,frame=pcall(CreateFrame,"Frame","TEF_EventFrame")
if created then
    local ok=TEF.UI:Call(frame,"SetScript","OnEvent",function(...)
        local handled=pcall(onEvent,...)
        if not handled and engine then TEF.Runtime:Fault("EVENT_CALL_FAILED") end
    end)
    if ok then
        local events={"ADDON_LOADED","PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","SPELLS_CHANGED",
            "PLAYER_TARGET_CHANGED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","UI_SCALE_CHANGED","ACTIONBAR_SLOT_CHANGED","UPDATE_BINDINGS","SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES","PLAYER_SPECIALIZATION_CHANGED","CHARACTER_POINTS_CHANGED"}
        for event in pairs(TEF.Events) do events[#events+1]=event end
        for _,event in ipairs(events) do
            local registered=TEF.UI:Call(frame,"RegisterEvent",event)
            if not registered then printSafe("事件注册失败：" .. event) end
        end
    end
end

SLASH_TEF1="/tef"
SLASH_TEFUI1="/tefui"
SlashCmdList.TEFUI=function() if engine then TEF.UI:OpenSettings() end end
BINDING_HEADER_TEF="TACTIC-ECHO-FOREVER"
BINDING_HEADER_TEF_LEGACY="TEF · 旧版兼容（迁移用途）"
BINDING_HEADER_TEF_TEST="TEF · 开发/测试工具"
BINDING_NAME_TEF_TOGGLE_PRACTICE="旧练习键：兼容统一派发启停"
BINDING_NAME_TEF_TOGGLE_CONTINUOUS="旧连续键：兼容统一派发启停"
BINDING_NAME_TEF_TOGGLE_DISPATCH="TEF：派发启/停"
BINDING_NAME_TEF_TOGGLE_PERMISSION="TEF：TEK请求许可启/停"
BINDING_NAME_TEF_REQUEST_CURRENT="TEF：派发当前技能"
BINDING_NAME_TEF_STOP_ALL="TEF：停止练习及TEK请求"
TEF_ToggleDispatchIntent=function()
    if not engine then return end
    TEF.Runtime:ToggleIntent("USER_TOGGLE_DISPATCH")
    refresh()
end
TEF_DispatchToggle=TEF_ToggleDispatchIntent
TEF_RunToggle=TEF_ToggleDispatchIntent
TEF_ContinuousToggle=TEF_ToggleDispatchIntent
TEF_PermissionToggle=function()
    if not engine then return end
    TEF.Runtime:SetPermission(not TEF.Dispatch.enabled); refresh()
end
TEF_RequestCurrent=function()
    if not engine then return end
    local ok,reason=TEF.Dispatch:Request()
    printSafe(reason .. (ok and "：已发布当前请求，桌面TEK使用UI联动；游戏事件到达即撤回。" or "：检查练习、许可和设置状态。")); refresh()
end
TEF_StopAll=function()
    if not engine then return end
    TEF.Runtime:Stop(); refresh()
end
SlashCmdList.TEF=function(raw)
    local input=S.Public(raw,"string")
    if not input or not engine then return end
    local command=input:lower():match("^%s*(%S*)")
    if command=="start" then TEF.Runtime:Start(true)
    elseif command=="toggle" then TEF_ToggleDispatchIntent()
    elseif command=="tekon" then TEF.Runtime:SetPermission(true)
    elseif command=="tekoff" then TEF.Runtime:SetPermission(false)
    elseif command=="continuous" then
        TEF_ContinuousToggle()
    elseif command=="continuousstatus" then printSafe(TEF.Dispatch.continuousReason or "CONTINUOUS_OFF")
    elseif command=="pause" or command=="stop" then TEF.Runtime:Stop()
    elseif command=="resume" then TEF.Runtime:Start(false)
    elseif command=="reset" then TEF.Runtime:Reset()
    elseif command=="loop" then engine:SetLoop(not engine.db.loop)
    elseif command=="settings" then TEF.UI:OpenSettings()
    elseif command=="single" then TEF.Profiles:Select(engine,"single")
    elseif command=="multi" then TEF.Profiles:Select(engine,"multi")
    elseif command=="sample" then TEF.Research:Sample(engine); printSafe(TEF.Research:View())
    elseif command=="confirm" then
        local ok,reason=TEF.Profiles:ConfirmObserved(engine)
        printSafe(ok and "已确认公开成功ID，重置并暂停；请重新开始。" or ("未确认：" .. reason))
    elseif command=="protocol" then TEF.Runtime:SetSignal(not TEF.Transport.enabled)
    elseif command=="dispatch" or command=="tektest" then
        TEF_RequestCurrent()
    elseif command=="tekstop" then TEF.Runtime:Stop(); TEF.Transport:Paint()
    elseif command=="manual" or command=="auto" or command=="combatstop" then TEF.Runtime:SetMode(command=="combatstop" and "stop" or command)
    elseif command=="test" then TEF.UI:Paint(TEF.UI.frame,"Show")
    elseif command=="show" or command=="hud" or command=="" then TEF.UI:Paint(TEF.HUD.frame,"Show")
    elseif command=="hide" or command=="hidehud" then TEF.UI:Paint(TEF.UI.frame,"Hide"); TEF.UI:Paint(TEF.HUD.frame,"Hide")
    elseif command=="diag" then
        printSafe("session=" .. engine.session .. " generation=" .. engine.generation
            .. " step=" .. engine.index .. " logs=" .. #engine.db.diagnostics .. " evicted=" .. engine.db.evicted)
        for i=math.max(1,#engine.db.diagnostics-11),#engine.db.diagnostics do
            local r=engine.db.diagnostics[i]
            printSafe((r.event or "-") .. " " .. r.kind .. " " .. r.reason .. " " .. r.current .. "→" .. r.next .. " ID=" .. (r.spellID or 0))
        end
    else printSafe("toggle 派发启停；auto/manual/combatstop 三模式；tekon/tekoff 许可；tektest 单步；tekstop 停止；start/pause/resume/reset/loop；single/multi；settings 自定义快捷键；protocol；test/hud/show/hide/diag。") end
    refresh()
end
