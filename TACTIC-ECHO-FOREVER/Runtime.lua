local _,TEF=...
local S,C=TEF.Safety,{intent=false,state="paused",requestSerial=0,cycle=0}
TEF.Runtime=C
local modes={auto=true,manual=true,stop=true}
local names={paused="暂停",standby="待命",running="运行",blocked="阻断",completed="完成",error="异常"}
function C.Clean(raw)
    local mode=S.Field(raw,"mode","string")
    local key=S.Field(raw,"hotkey","string")
    return {mode=modes[mode] and mode or "auto",autoStart=S.Field(raw,"autoStart","boolean")~=false,
        permission=S.Field(raw,"permission","boolean")~=false,signal=S.Field(raw,"signal","boolean")~=false,
        hotkey=key and #key<=40 and key:match("^[A-Z0-9%-=]+$") and key or "",
        hotkeyOverride=S.Field(raw,"hotkeyOverride","boolean")==true}
end
function C:SetLoopMode(mode)
    if mode~="none" and mode~="normal" and mode~="target" and mode~="combat" then return false end
    self:Stop("RUNTIME_LOOP_CONFIGURATION_CHANGED")
    self.e:SetLoopMode(mode); self:EngineCall("Reset"); return true
end
function C:ResetCycle(reason)
    -- Reset through the sole runtime owner: preserve intention, invalidate all
    -- old receipts/requests, and let live gates decide when execution resumes.
    if not self:EngineCall("Reset") then return false end
    self:Changed("paused",reason); return true
end
function C:Changed(state,reason)
    local changed=self.state~=state or self.reason~=reason
    self.state,self.reason=state,reason
    if not changed then return end
    self.e:Log("transport",reason)
    if self.notifying then return end
    self.notifying=true
    if TEF.HUD and TEF.HUD.engine==self.e then pcall(TEF.HUD.RefreshState,TEF.HUD) end
    if TEF.UI and TEF.UI.engine==self.e and TEF.UI.settingsOpen and TEF.UI.readouts then pcall(TEF.UI.RefreshPage,TEF.UI) end
    self.notifying=false
end
function C:EngineCall(method)
    self.internal=true
    local ok=pcall(self.e[method],self.e)
    self.internal=false
    if not ok then
        -- Last-resort containment belongs to Runtime, never to presentation.
        self.intent=false; self.e.running=false
        self.e.generation=self.e.generation+1; self.e.associations={}; self.e.associationCount=0
        TEF.Dispatch:StopContinuous("RUNTIME_ENGINE_FAILED"); TEF.Dispatch:Cancel("RUNTIME_ENGINE_FAILED")
        self:Changed("error","RUNTIME_ENGINE_FAILED")
    end
    return ok
end
function C:Initialize(e)
    self.e=e; self.intent=false; self.worldSeen=false; self.state="paused"
    self.reason=nil; self.cycle=0; self.requestSerial=0
    e.db.dispatch=self.Clean(e.db.dispatch)
    TEF.Dispatch:SetEnabled(e.db.dispatch.permission)
end
function C:Invalidated(e)
    -- Explicit edits/reset and the retained developer Engine API stop intent.
    if e==self.e and not self.internal then
        self.intent=false; self:Changed("paused","RUNTIME_CONFIGURATION_INVALIDATED")
    end
end
function C:Stop(reason,state)
    self.intent=false
    if not self:EngineCall("Pause") then return end
    TEF.Dispatch:StopContinuous(reason or "RUNTIME_MANUAL_PAUSE")
    TEF.Dispatch:Cancel(reason or "RUNTIME_MANUAL_PAUSE")
    self:Changed(state or "paused",reason or "RUNTIME_MANUAL_PAUSE")
end
function C:Fault(reason) self:Stop(reason or "RUNTIME_FATAL_ERROR","error") end
function C:OnDispatchFault(reason)
    -- A game failure yields the ordinary candidate; only fatal errors stop intent.
    if self.e~=TEF.engine then return end
    if reason=="CONTINUOUS_FAILURE_STOP" then self:Suspend("CONTINUOUS_FAILURE_RETRY")
    else self:Fault(reason) end
end
function C:Suspend(reason,state)
    if not self.e then return end
    if self.e.running and not self:EngineCall("Pause") then return end
    TEF.Dispatch:StopContinuous(reason); TEF.Dispatch:Cancel(reason)
    self:Changed(self.intent and (state or "blocked") or "paused",reason)
end
function C:SetIntent(enabled,reason)
    if enabled~=true then self:Stop(reason); return true end
    if self.intent then return true,"RUNTIME_ALREADY_ENABLED" end
    if self.e.identitySaturated then self:Fault("RUNTIME_IDENTITY_CAPACITY_RELOAD_REQUIRED"); return false end
    if self.e.clientValidated==false then self:Fault("RUNTIME_CLIENT_UNVERIFIED"); return false end
    if not TEF.Recommendation:Configured(self.e) then self:Stop("RUNTIME_PROFILE_UNCONFIGURED"); return false end
    if self.e.completed and not self:EngineCall("Reset") then return false end
    self.intent=true
    if self.e.db.dispatch.signal and not TEF.Transport.enabled then
        if not TEF.Transport:SetEnabled(true) then self:Fault("RUNTIME_SIGNAL_FAILED"); return false end
    end
    self:Changed("standby",reason or "RUNTIME_ENABLED")
    self:Reconcile(); return self.intent
end
function C:ToggleIntent(reason) return self:SetIntent(not self.intent,reason) end
function C:Start(reset)
    if reset then self:Stop("RUNTIME_RESTART"); if not self:EngineCall("Reset") then return false end end
    return self:SetIntent(true)
end
function C:Reset()
    self:Stop("RUNTIME_RESET")
    if self.state=="error" or not self:EngineCall("Reset") then return end
    self:Changed("paused","RUNTIME_RESET")
end
function C:SetMode(mode)
    if not modes[mode] then return false end
    self.e.db.dispatch.mode=mode; self:Reconcile(); return true
end
function C:SetPermission(value)
    self.e.db.dispatch.permission=value==true
    if value~=true then self:Stop("RUNTIME_PERMISSION_OFF") end
    TEF.Dispatch:SetEnabled(value); self:Reconcile(); return true
end
function C:SetSignal(value)
    self.e.db.dispatch.signal=value==true
    if value~=true then self:Stop("RUNTIME_SIGNAL_OFF") end
    local ok=TEF.Transport:SetEnabled(value)
    if not ok then self:Fault("RUNTIME_SIGNAL_FAILED") end
    self:Reconcile(); return ok
end
function C:World()
    local first=not self.worldSeen; self.worldSeen=true
    self:Stop("RUNTIME_WORLD_INVALIDATED")
    if first and self.e.db.dispatch.autoStart then self:SetIntent(true) end
end
function C:Reconcile()
    if not self.e or self.e~=TEF.engine then return end
    self.cycle=self.cycle+1
    if not self.intent then return end
    local e=self.e
    if e.identitySaturated then self:Fault("RUNTIME_IDENTITY_CAPACITY_RELOAD_REQUIRED"); return end
    if TEF.APL:IsActive(e) and not TEF.UI.settingsOpen then TEF.APL:Refresh(e) end
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local function current() return self.intent and self.e==e and TEF.engine==e and generation==e.generation and index==e.index and serial==(e.receiptSerial or 0) end
    if e.completed then self:Stop("RUNTIME_COMPLETED","completed"); return end
    if not e.db.dispatch.permission or not e.db.dispatch.signal then self:Stop("RUNTIME_GATE_OFF"); return end
    if not TEF.Recommendation:Configured(e) then self:Suspend("RUNTIME_PROFILE_UNCONFIGURED"); return end
    local ok,raw=S.Call("InCombatLockdown"); local combat
    if ok then combat=S.Public(raw,"boolean") end
    if not current() then return end
    if e.db.dispatch.mode=="stop" and combat==false then self:Stop("RUNTIME_OUT_OF_COMBAT_STOP"); return end
    if TEF.UI.settingsOpen then self:Suspend("RUNTIME_SETTINGS_STANDBY","standby"); return end
    if combat==nil then self:Suspend("RUNTIME_COMBAT_UNKNOWN"); return end
    if e.db.dispatch.mode=="auto" and combat==false then self:Suspend("RUNTIME_AUTO_STANDBY","standby"); return end
    -- Keep the already initiated receipt while showing a cast block. Pausing
    -- the Engine here would erase its initiation and lose SUCCEEDED (S61).
    local idle=TEF.Dispatch:CastIdle()
    if not current() then return end
    if not idle then
        TEF.Dispatch:YieldCast("CONTINUOUS_CAST_PRESENT_OR_UNKNOWN")
        self:Changed("blocked","CONTINUOUS_CAST_PRESENT_OR_UNKNOWN"); return
    end
    if TEF.APL:IsActive(e) and TEF.Dispatch:HasCurrentInitiation() then
        -- SENT may precede visible cast presence, and SUCCEEDED can precede
        -- cast disappearance. A dirty APL snapshot must not erase its receipt.
        TEF.Dispatch:YieldCast("APL_WAIT_CURRENT_RECEIPT")
        self:Changed("blocked","APL_WAIT_CURRENT_RECEIPT"); return
    end
    if not TEF.Recommendation:Current(e) then self:Suspend("APL_NO_CANDIDATE"); return end
    local allowed,reason=TEF.Dispatch:ContinuousEvidence(e.steps[e.index].spellID)
    if not current() then return end
    if not allowed then self:Suspend(reason); return end
    if TEF.Dispatch.bindingCache[e.steps[e.index].spellID]==false then self:Suspend("TEK_EXACT_DIRECT_BINDING_UNAVAILABLE"); return end
    if not e.running and not self:EngineCall("Resume") then return end
    if not TEF.Dispatch.enabled then TEF.Dispatch:SetEnabled(true) end
    if not TEF.Dispatch.continuous then
        if not TEF.Dispatch:SetContinuous(true) then self:Fault("RUNTIME_DISPATCH_START_FAILED"); return end
    end
    self:Changed("running","RUNTIME_RUNNING")
end
function C:GetViewState()
    local e=self.e
    local source=e and TEF.Recommendation:Source(e) or "manual"
    return {intent=self.intent,state=self.state,label=names[self.state] or "未知",reason=self.reason,
        profileKey=e and e.profileKey or "职业未解析",source=source,index=e and e.index or 1,
        count=e and e.steps and #e.steps or 0}
end
function C:IsDispatchIntentEnabled() return self.intent end
function C:View()
    local v=self:GetViewState()
    return v.label .. " | " .. (v.source=="apl" and "法师 APL" or v.profileKey) .. " | " .. (v.source=="apl" and "APL" or v.source=="code" and "代码序列" or "人工序列")
end
-- Internal compatibility, no additional public toggle or execution loop.
C.Tick=C.Reconcile
C.Toggle=C.ToggleIntent
