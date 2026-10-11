local addonName, TEF = ...
local VERSION = "0.5.1"
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
    local ok, version, build, _, interface=pcall(function() return GetBuildInfo() end)
    if ok then
        local safeVersion=S.Public(version,"string")
        local safeBuild=S.Public(build,"string")
        local safeInterface=S.ID(interface)
        if safeVersion and safeBuild and safeInterface then
            engine.db.client={version=safeVersion,build=safeBuild,interface=safeInterface}
            if safeVersion ~= "1.60.1" or safeBuild ~= "70338" or safeInterface ~= 16001 then
                engine:Log("error","CLIENT_CONTEXT_CHANGED")
                printSafe("客户端与70338基线不同，请核对接口及事件；当前默认暂停。")
            end
        else engine:Log("unknown","CLIENT_UNKNOWN") end
    else engine:Log("unknown","CLIENT_CALL_FAILED") end
    TEF.UI:Create(engine)
    TEF.HUD:Create(engine)
    TEF.UI:Paint(TEF.UI.frame,"Hide")
    TEF.Transport:SetEnabled(true)
    printSafe("v" .. VERSION .. " 已加载，默认暂停。/tef help；请主动开始。")
end

local function onEvent(_,event,...)
    if event == "ADDON_LOADED" then
        local name=S.Public((...),"string")
        if name==addonName and not engine then initialize() end
        return
    end
    if not engine then return end
    if event == "PLAYER_LOGOUT" then engine:Pause(); TEF.Transport:SetEnabled(false); return end
    if event == "PLAYER_ENTERING_WORLD" then engine:Pause(); refresh(); return end
    if event == "SPELLS_CHANGED" then TEF.Presentation.bindings={}; TEF.Presentation.cooldowns={}; refresh(); return end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then TEF.HUD:Refresh(event=="SPELL_UPDATE_COOLDOWN"); return end
    if event == "PLAYER_REGEN_ENABLED" then TEF.UI:Layout(); refresh(); return end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_BINDINGS" then
        TEF.Dispatch:BindingsChanged(); TEF.Presentation.bindings={}; TEF.Research:Invalidate(); refresh(); return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_DISABLED" then
        TEF.Dispatch:Cancel("TEK_" .. event); TEF.Presentation.bindings={}; TEF.Research:Invalidate(); refresh(); return
    end
    if event == "UI_SCALE_CHANGED" then
        TEF.Transport:SetEnabled(false); TEF.UI:Layout(); refresh(); return
    end
    if TEF.Events[event] then
        local unit,guid,id,ignoredTarget
        if event == "UNIT_SPELLCAST_SENT" then
            -- Deliberately ignore target (argument 2), including its Secret value.
            unit,ignoredTarget,guid,id=...
        else unit,guid,id=... end
        TEF.Dispatch:Event(event,unit,id)
        engine:Handle(engine.generation,event,unit,guid,id)
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
        if not handled and engine then engine.running=false; engine:Invalidate("EVENT_CALL_FAILED") end
    end)
    if ok then
        local events={"ADDON_LOADED","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","SPELLS_CHANGED",
            "PLAYER_TARGET_CHANGED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","UI_SCALE_CHANGED","ACTIONBAR_SLOT_CHANGED","UPDATE_BINDINGS","SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES"}
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
BINDING_NAME_TEF_TOGGLE_PRACTICE="TEF：练习启/停"
BINDING_NAME_TEF_TOGGLE_PERMISSION="TEF：TEK请求许可启/停"
BINDING_NAME_TEF_REQUEST_CURRENT="TEF：派发当前技能"
BINDING_NAME_TEF_STOP_ALL="TEF：停止练习及TEK请求"
TEF_RunToggle=function()
    if not engine then return end
    if engine.running then engine:Pause() elseif engine.completed then engine:Start() else engine:Resume() end
    refresh()
end
TEF_PermissionToggle=function()
    if not engine then return end
    TEF.Dispatch:SetEnabled(not TEF.Dispatch.enabled); refresh()
end
TEF_RequestCurrent=function()
    if not engine then return end
    local ok,reason=TEF.Dispatch:Request()
    printSafe(reason .. (ok and "：已发布当前请求，桌面TEK使用UI联动；游戏事件到达即撤回。" or "：检查练习、许可和设置状态。")); refresh()
end
TEF_StopAll=function()
    if not engine then return end
    TEF.Dispatch:SetEnabled(false); engine:Pause(); refresh()
end
SlashCmdList.TEF=function(raw)
    local input=S.Public(raw,"string")
    if not input or not engine then return end
    local command=input:lower():match("^%s*(%S*)")
    if command=="start" then engine:Start()
    elseif command=="toggle" then TEF_RunToggle()
    elseif command=="tekon" then TEF.Dispatch:SetEnabled(true)
    elseif command=="tekoff" then TEF.Dispatch:SetEnabled(false)
    elseif command=="pause" or command=="stop" then engine:Pause()
    elseif command=="resume" then engine:Resume()
    elseif command=="reset" then engine:Reset()
    elseif command=="loop" then engine:SetLoop(not engine.db.loop)
    elseif command=="settings" then TEF.UI:OpenSettings()
    elseif command=="single" then TEF.Profiles:Select(engine,"single")
    elseif command=="multi" then TEF.Profiles:Select(engine,"multi")
    elseif command=="sample" then TEF.Research:Sample(engine); printSafe(TEF.Research:View())
    elseif command=="confirm" then
        local ok,reason=TEF.Profiles:ConfirmObserved(engine)
        printSafe(ok and "已确认公开成功ID，重置并暂停；请重新开始。" or ("未确认：" .. reason))
    elseif command=="protocol" then TEF.Transport:SetEnabled(not TEF.Transport.enabled)
    elseif command=="dispatch" or command=="tektest" then
        TEF_RequestCurrent()
    elseif command=="tekstop" then TEF.Dispatch:Cancel("TEK_MANUAL_STOP"); TEF.Transport:Paint()
    elseif command=="test" then TEF.UI:Paint(TEF.UI.frame,"Show")
    elseif command=="show" or command=="hud" or command=="" then TEF.UI:Paint(TEF.HUD.frame,"Show")
    elseif command=="hide" then engine:Pause(); TEF.Transport:SetEnabled(false); TEF.UI:Paint(TEF.UI.frame,"Hide"); TEF.UI:Paint(TEF.HUD.frame,"Hide")
    elseif command=="diag" then
        printSafe("session=" .. engine.session .. " generation=" .. engine.generation
            .. " step=" .. engine.index .. " logs=" .. #engine.db.diagnostics .. " evicted=" .. engine.db.evicted)
        for i=math.max(1,#engine.db.diagnostics-11),#engine.db.diagnostics do
            local r=engine.db.diagnostics[i]
            printSafe((r.event or "-") .. " " .. r.kind .. " " .. r.reason .. " " .. r.current .. "→" .. r.next .. " ID=" .. (r.spellID or 0))
        end
    else printSafe("toggle 练习启停；tekon/tekoff 请求许可；tektest/tekstop 请求/撤回；游戏按键设置→TEF快捷键；start/pause/resume/reset/loop；single/multi；settings；protocol；test/hud/show/hide/diag。") end
    refresh()
end
