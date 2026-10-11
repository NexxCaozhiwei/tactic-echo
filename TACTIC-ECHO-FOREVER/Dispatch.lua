local _, TEF = ...
local D,S={},TEF.Safety
TEF.Dispatch=D
D.enabled=false
-- Runtime-only opt-in; no timer estimates, persisted arm state or second transport.
D.continuous=false
function D:StopContinuous(reason)
    local active=self.continuous
    self.continuous=false; self.continuousGeneration=nil; self.waitReceipt=nil; self.continuousBinding=nil; self.initiation=nil
    self.continuousReason=reason or "CONTINUOUS_OFF"
    if active then
        TEF.engine:Log("transport",self.continuousReason)
    end
end
function D:ContinuousStatus(reason)
    if self.continuousReason~=reason then
        self.continuousReason=reason; TEF.engine:Log("transport",reason)
    end
end
function D:Block(reason)
    self:StopContinuous(reason); self:Cancel(reason)
    if TEF.Runtime and TEF.Runtime.e==TEF.engine and TEF.Runtime.intent then TEF.Runtime:Suspend(reason) end
end
function D:SetContinuous(value)
    self:Cancel("TEK_CONTINUOUS_CHANGED")
    if value~=true then self:StopContinuous(); return true end
    local e=TEF.engine
    if not self.enabled or not e.running or e.completed or TEF.UI.settingsOpen then
        self:StopContinuous("CONTINUOUS_START_BLOCKED"); return false
    end
    self.continuous=true; self.continuousGeneration=e.generation
    self.waitReceipt=nil; self.continuousReason=nil; self.continuousBinding=nil
    self:ContinuousStatus("CONTINUOUS_ON")
    return true
end
local function publicBoolean(path,...)
    local ok,value=S.Call(path,...)
    if not ok then return nil end
    return S.Public(value,"boolean")
end
function D:InputIdle()
    local path=S.Resolve("GetCurrentKeyBoardFocus") and "GetCurrentKeyBoardFocus" or "GetCurrentKeyboardFocus"
    local ok,raw=S.Call(path)
    if not ok then return false end
    local _,classification=S.Public(raw,"table")
    -- Any focused object, restricted result or unknown detector blocks input.
    return classification=="NO_DATA"
end
function D:ContinuousEvidence(id)
    if TEF.APL and TEF.APL:IsActive(TEF.engine) then
        local allowed,reason=TEF.APL:Allowed(TEF.engine,id)
        if not allowed then return false,reason end
    end
    if not self:InputIdle() then return false,"CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN" end
    if publicBoolean("UnitExists","target")~=true
        or publicBoolean("UnitCanAttack","player","target")~=true
        or publicBoolean("UnitIsDeadOrGhost","target")~=false then return false,"CONTINUOUS_TARGET_UNKNOWN_OR_BLOCKED" end
    local rangeOK,rangeRaw=S.Call("C_Spell.IsSpellInRange",id,"target")
    local range,rangeReason
    if rangeOK then range,rangeReason=S.Public(rangeRaw,"boolean") end
    -- Shoot may not expose spell-range data. Only an exact verified action
    -- slot can supply this narrow nil-data fallback; false/Secret never do.
    if id==5019 and rangeOK and rangeReason=="NO_DATA" then
        local b=self:ResolveCached(id)
        if b and self:VerifyCurrent(b) then range=publicBoolean("C_ActionBar.IsActionInRange",b.slot,"target") end
    end
    local c=TEF.engine.aplCandidate
    local selfAction=TEF.APL and TEF.APL:IsActive(TEF.engine) and c and c.spellID==id and (c.target=="self" or (TEF.APL.Abilities[c.action] and TEF.APL.Abilities[c.action].target=="self"))
    if not selfAction and range~=true then return false,"CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED" end
    local fn=S.Resolve("C_Spell.IsSpellUsable")
    if not fn then return false,"CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED" end
    local ok,usable,power=pcall(fn,id)
    if not ok or S.Public(usable,"boolean")~=true or S.Public(power,"boolean")~=false then
        return false,"CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED"
    end
    -- Ordinary fixed practice is an explicitly authorized input attempt, like
    -- TE's ordinary recommendation transport, not AutoBurst admission or a
    -- dynamic ready selector. Never interpret UNKNOWN cooldown/GCD as ready.
    return true
end
function D:ShootActive(binding)
    if binding.spellID~=5019 then return false end
    if not self:VerifyCurrent(binding) then return nil end
    local path=S.Resolve("C_ActionBar.IsCurrentAction") and "C_ActionBar.IsCurrentAction" or "IsCurrentAction"
    return publicBoolean(path,binding.slot)
end
function D:HasCurrentInitiation()
    local e=TEF.engine; local i=self.initiation
    if not i or i.generation~=e.generation or i.index~=e.index then return false end
    local a=e.associations[i.guid]
    return a~=nil and not a.failed and a.generation==e.generation and a.index==e.index and a.spellID==i.spellID
        and a.receiptSerial==(e.receiptSerial or 0)
end
function D:YieldCast(reason)
    self:Cancel(reason)
    -- Only an actual current initiation owns a success wait. An uninitiated
    -- candidate withdrawn for somebody else's cast must become publishable
    -- again when the authoritative presence query becomes idle.
    if not self:HasCurrentInitiation() then
        if self.waitReceipt~=nil then TEF.engine:Log("transport","CONTINUOUS_UNINITIATED_WAIT_RELEASED") end
        self.waitReceipt=nil; self.initiation=nil
    end
end
function D:TickContinuous()
    if not self.continuous then return end
    local e=TEF.engine
    if TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent and TEF.Runtime.state~="running" then return end
    if e.generation~=self.continuousGeneration or not e.running or e.completed
        or not self.enabled or TEF.UI.settingsOpen then
        self:StopContinuous("CONTINUOUS_LIFECYCLE_STOP"); self:Cancel(); return
    end
    local current=e.steps and e.steps[e.index]
    if current and current.spellID==5019 then
        local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
        local binding=self:ResolveCached(5019)
        local active
        if binding then active=self:ShootActive(binding) end
        if generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) or not self.continuous then return end
        if active~=false then
            self:Cancel("SHOOT_ACTIVE_OR_UNKNOWN")
            self:ContinuousStatus(active==true and "SHOOT_ACTIVE_WAIT_SUCCESS" or "SHOOT_ACTIVE_UNKNOWN")
            return
        end
        -- A withdrawn toggle without actual initiation owns no success wait.
        if not self.pending and not self:HasCurrentInitiation() then self.waitReceipt=nil end
    end
    if self.pending or self.waitReceipt==(e.receiptSerial or 0) then return end
    if not self:CastIdle() then self:ContinuousStatus("CONTINUOUS_CAST_PRESENT_OR_UNKNOWN"); return end
    local recommendation=TEF.Recommendation:Current(e)
    local step=recommendation and e.steps[e.index]
    if not step or step.unverified then self:StopContinuous("CONTINUOUS_STEP_UNRESOLVED"); return end
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local allowed,reason=self:ContinuousEvidence(step.spellID)
    if not self.continuous or generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) then return end
    if not allowed then self:ContinuousStatus(reason); return end
    local requested,blocked=self:Request(true)
    if requested then self.waitReceipt=serial; self.continuousBinding=self.pending.binding; self:ContinuousStatus("CONTINUOUS_WAIT_RECEIPT")
    else self:Block(blocked) end
end
function D:SetEnabled(value)
    self:StopContinuous("CONTINUOUS_PERMISSION_CHANGED")
    self:Cancel("TEK_PERMISSION_CHANGED")
    self.enabled=value==true
    TEF.engine:Log("transport",self.enabled and "TEK_PERMISSION_ON" or "TEK_PERMISSION_OFF")
end
-- Exact direct spell slots only. Macros/overrides/rank aliases are not guessed.
local keys={Q=1,E=2,R=3,F=4,["1"]=5,["2"]=6,["3"]=7,["4"]=8,["5"]=9,Z=10,X=11,C=12,V=13,T=14,G=15,F1=16,F2=17,F3=18,F4=19,["`"]=20,["6"]=24,["7"]=25,["8"]=26,["9"]=27,["0"]=28,["-"]=29,["="]=30}
function D.Token(key)
    local k=S.Public(key,"string"); if not k then return nil end
    local prefix,base=k:match("^(%u+)%-(.+)$")
    local modifier=0
    if prefix then modifier=({ALT=1,CTRL=2,SHIFT=3})[prefix]; if not modifier then return nil end; k=base end
    local code=keys[k]; return code and code+modifier*64 or nil
end
function D.SkillToken(raw)
    local key=S.Public(raw,"string"); if not key then return nil end
    -- A control override must never be sent as a spell key. During a deferred
    -- combat edit both the saved key and the still-installed old key are reserved.
    local dispatch=TEF.engine and TEF.engine.db.dispatch
    if dispatch and key==dispatch.hotkey then return nil end
    if TEF.Hotkeys and key==TEF.Hotkeys.appliedKey then return nil end
    return D.Token(key)
end
function D:Cancel(reason)
    local hadPending=self.pending~=nil
    if hadPending then TEF.engine:Log("transport",reason or "TEK_REQUEST_CANCELLED") end
    self.pending=nil
    -- Publish the zero-token barrier immediately, rather than leaving an old
    -- armed strip until the next heartbeat after a pause/settings/game event.
    if hadPending and TEF.Transport and TEF.Transport.enabled then
        local ok=pcall(TEF.Transport.Paint,TEF.Transport)
        if not ok then TEF.Transport:Fail("TRANSPORT_REVOKE_FAILED") end
    end
end
function D:Resolve(id)
    local info=S.Resolve("C_ActionBar.GetActionInfo") or S.Resolve("GetActionInfo")
    if not info then return nil,"TEK_ACTION_API_MISSING" end
    local names={"ActionButton","MultiBarBottomLeftButton","MultiBarBottomRightButton","MultiBarRightButton","MultiBarLeftButton","MultiBar5Button","MultiBar6Button","MultiBar7Button"}
    local commands={"ACTIONBUTTON","MULTIACTIONBAR1BUTTON","MULTIACTIONBAR2BUTTON","MULTIACTIONBAR3BUTTON","MULTIACTIONBAR4BUTTON","MULTIACTIONBAR5BUTTON","MULTIACTIONBAR6BUTTON","MULTIACTIONBAR7BUTTON"}
    for bar,name in ipairs(names) do for n=1,12 do
        local got,b=pcall(function() return _G[name .. n] end)
        if got and b then
            local ok,raw=TEF.UI:Invoke(b,"GetAttribute","action")
            local slot=ok and S.ID(raw)
            if not slot then local read,v=pcall(function() return b.action end); slot=read and S.ID(v) end
            if slot and slot<=180 then
                local called,kind,rawID=pcall(info,slot)
                local spell=called and S.ID(rawID)
                if called and S.Public(kind,"string")=="spell" and spell==id then
                    local fn=S.Resolve("GetBindingKey")
                    if fn then
                        local bound,k1,k2=pcall(fn,commands[bar] .. n)
                        local token=bound and (D.SkillToken(k1) or D.SkillToken(k2))
                        if token then
                            local key=D.SkillToken(k1) and S.Public(k1,"string") or S.Public(k2,"string")
                            return {slot=slot,token=token,key=key,spellID=id,command=commands[bar] .. n,button=b,buttonName=name .. n},"TEK_BINDING_VERIFIED"
                        end
                    end
                end
            end
        end
    end end
    return nil,"TEK_EXACT_DIRECT_BINDING_UNAVAILABLE"
end
-- Input sources are cached only between binding/spell lifecycle events.
-- A positive source is still verified live at Request and every Packet.
D.bindingCache={}
function D:ClearBindingCache() self.bindingCache={} end
function D:ResolveCached(id)
    local cached=self.bindingCache[id]
    if cached==nil then cached=self:Resolve(id); self.bindingCache[id]=cached or false end
    if cached==false then return nil,"TEK_EXACT_DIRECT_BINDING_UNAVAILABLE" end
    return cached,"TEK_BINDING_VERIFIED"
end
function D:CastIdle()
    local e=TEF.engine; local h=e and e.shootHandoff
    local generation,index,serial=e and e.generation,e and e.index,e and e.receiptSerial
    local handoff=h and h.generation==generation and h.index==index and h.receiptSerial==serial
        and e.running and not e.completed and e.steps[index].spellID~=5019
    for _,path in ipairs({"UnitCastingInfo","UnitChannelInfo"}) do
        local fn=S.Resolve(path)
        if not fn then return false end
        local ok,value,_,__,___,____,_____,______,_______,spell=pcall(fn,"player")
        local _,reason=S.Public(value,"string")
        if not ok then return false end
        if reason~="NO_DATA" then
            if not handoff or path~="UnitCastingInfo" or reason~="PUBLIC" or S.ID(spell)~=5019 then return false end
        end
    end
    if e and (generation~=e.generation or index~=e.index or serial~=e.receiptSerial) then return false end
    return true
end
function D:Request(fromContinuous)
    -- The test button cannot revoke or replace an automatic request (S37).
    if fromContinuous~=true and self.continuous then
        if self.pending then return true,"TEK_REQUEST_ALREADY_PENDING" end
        return false,"TEK_AUTOMATIC_OWNS_REQUEST"
    end
    self:Cancel()
    local e=TEF.engine; local step=e.steps and e.steps[e.index]
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local blocked
    if not self.enabled then blocked="TEK_PERMISSION_DISABLED"
    elseif TEF.UI.settingsOpen then blocked="TEK_SETTINGS_OPEN"
    elseif not e.running then blocked="TEK_PRACTICE_PAUSED"
    elseif e.completed then blocked="TEK_PRACTICE_COMPLETED"
    elseif not step or step.unverified then blocked="TEK_STEP_UNRESOLVED"
    elseif not self:CastIdle() then blocked="TEK_CAST_PRESENT_OR_UNKNOWN" end
    if blocked then e:Log("transport",blocked); return false,blocked end
    if TEF.APL and TEF.APL:IsActive(e) then
        local allowed,reason=TEF.APL:Allowed(e,step.spellID)
        if not allowed then return false,reason end
    end
    local binding,reason
    if fromContinuous then binding,reason=self:ResolveCached(step.spellID) else binding,reason=self:Resolve(step.spellID) end
    if not binding then e:Log("transport",reason); return false,reason end
    if not self:VerifyCurrent(binding) then self.bindingCache[step.spellID]=nil; return false,"TEK_BINDING_CHANGED" end
    if step.spellID==5019 and self:ShootActive(binding)~=false then return false,"SHOOT_ACTIVE_OR_UNKNOWN" end
    if not TEF.Transport.enabled and not TEF.Transport:SetEnabled(true) then return false,"TEK_SIGNAL_UNAVAILABLE" end
    if generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) or not e.running or not self.enabled
        or TEF.UI.settingsOpen or (fromContinuous==true and not self.continuous) then
        return false,"TEK_REQUEST_STALE"
    end
    self.pending={generation=e.generation,index=e.index,binding=binding,receiptSerial=serial}
    if TEF.Runtime and TEF.Runtime.e==e then TEF.Runtime.requestSerial=TEF.Runtime.requestSerial+1 end
    e:Log("transport",fromContinuous==true and "TEK_CONTINUOUS_REQUEST" or "TEK_MANUAL_REQUEST",step.spellID)
    return true,"TEK_MANUAL_REQUEST"
end
function D:VerifyCurrent(b)
    local currentOK,current=pcall(function() return _G[b.buttonName] end)
    if not currentOK or current~=b.button then return false end
    local ok,raw=TEF.UI:Invoke(b.button,"GetAttribute","action")
    local slot=ok and S.ID(raw)
    if not slot then local read,value=pcall(function() return b.button.action end); slot=read and S.ID(value) end
    local fn=S.Resolve("C_ActionBar.GetActionInfo") or S.Resolve("GetActionInfo")
    local read,kind,rawID=false,nil,nil
    if fn and slot then read,kind,rawID=pcall(fn,slot) end
    local bindingFn=S.Resolve("GetBindingKey")
    local bound,k1,k2=false,nil,nil
    if bindingFn then bound,k1,k2=pcall(bindingFn,b.command) end
    local token=bound and (D.SkillToken(k1) or D.SkillToken(k2))
    return slot==b.slot and read and S.Public(kind,"string")=="spell" and S.ID(rawID)==b.spellID and token==b.token
end
function D:BindingsChanged()
    self:ClearBindingCache()
    if self.continuous then
        local binding=self.pending and self.pending.binding or self.continuousBinding
        if binding and not self:VerifyCurrent(binding) then
            self:Block("CONTINUOUS_BINDING_CHANGED")
        end
        return
    end
    if not self.pending then return end
    if not self:VerifyCurrent(self.pending.binding) then self:Cancel("TEK_BINDING_CHANGED") end
end
function D:Packet()
    local p,e=self.pending,TEF.engine
    if not p then return nil end
    if not self.enabled or not e.running or e.completed or e.generation~=p.generation or e.index~=p.index
        or p.receiptSerial~=(e.receiptSerial or 0) or TEF.UI.settingsOpen then self:Cancel("TEK_REQUEST_STALE"); return nil end
    -- Revalidate the locked source; never silently switch to another slot/key.
    if not self:VerifyCurrent(p.binding) then
        self.bindingCache[p.binding.spellID]=nil
        self:Block("CONTINUOUS_BINDING_CHANGED"); return nil
    end
    if not self:CastIdle() then self:Cancel("TEK_CAST_PRESENT_OR_UNKNOWN"); return nil end
    if TEF.APL and TEF.APL:IsActive(e) then
        local allowed,reason=TEF.APL:Allowed(e,p.binding.spellID)
        if not allowed then self:Cancel(reason); return nil end
    end
    if p.binding.spellID==5019 and self:ShootActive(p.binding)~=false then self:Cancel("SHOOT_ACTIVE_OR_UNKNOWN"); return nil end
    if self.continuous then
        local allowed,reason=self:ContinuousEvidence(p.binding.spellID)
        if not allowed then self:Block(reason); return nil end
        if self.pending~=p or not self.continuous or e.generation~=p.generation or e.index~=p.index then return nil end
    end
    local ok,rawCombat=S.Call("InCombatLockdown")
    local combat
    if ok then combat=S.Public(rawCombat,"boolean") end
    if combat==nil then self:Cancel("TEK_COMBAT_UNKNOWN"); return nil end
    if TEF.APL and TEF.APL:IsActive(e) and combat~=true then self:Cancel("APL_DISPATCH_COMBAT_REQUIRED"); return nil end
    if self.pending~=p or not self.enabled or not e.running or e.completed
        or e.generation~=p.generation or e.index~=p.index or p.receiptSerial~=(e.receiptSerial or 0) or TEF.UI.settingsOpen then return nil end
    return p.binding.token,combat
end
function D:Event(event,unit,id,guidRaw)
    local failure=event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_FAILED_QUIET" or event=="UNIT_SPELLCAST_INTERRUPTED"
    local runtime=TEF.Runtime
    local e=TEF.engine
    local owned=runtime and runtime.e==e
    local eventGeneration,eventIndex=e.generation,e.index
    -- Public identities only; retain bounded failed-attempt tombstones across temporary
    -- generations so a delayed FAILED/START/SUCCEEDED cannot stop or advance retry.
    local unitValue=S.Public(unit,"string")
    local spellValue=S.ID(id)
    local guid=S.Identity(guidRaw)
    if owned and (runtime.e~=e or TEF.engine~=e or e.generation~=eventGeneration or e.index~=eventIndex) then return true end
    if owned and unitValue=="player" and guid and e.seen[guid]=="retired" then
        e:Log("ignored","CONTINUOUS_FAILED_RECEIPT_IGNORED",spellValue,nil,nil,event)
        return true
    end
    if owned and runtime.intent and self.continuous and unitValue=="player" and spellValue then
        local step=e.steps[e.index]
        if event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_START" then
            if step.matches[spellValue] and guid and not e.seen[guid] then
                self.initiation={generation=e.generation,index=e.index,spellID=spellValue,guid=guid}
            elseif not step.matches[spellValue] then
                self:YieldCast("CONTINUOUS_FOREIGN_CAST_YIELD")
            end
        end
    end
    if self.continuous or (owned and runtime.intent and runtime.reason=="CONTINUOUS_MOVING_OR_UNKNOWN" and failure) then
        local u=S.Public(unit,"string"); local spell=S.ID(id)
        local step=TEF.engine.steps and TEF.engine.steps[TEF.engine.index]
        if not u or (u=="player" and not spell) then self:Block("CONTINUOUS_EVENT_UNKNOWN")
        elseif u=="player" and step and step.matches[spell] and failure then
            if owned then
                local generation,index=e.generation,e.index
                local moving=publicBoolean("IsPlayerMoving")
                if runtime.e~=e or TEF.engine~=e or generation~=e.generation or index~=e.index or not runtime.intent then return true end
                local a=guid and e.associations[guid]
                if not guid then
                    self:Block("CONTINUOUS_FAILURE_IDENTITY_UNKNOWN"); return true
                elseif moving==true or (a and a.generation==generation and a.index==index and a.spellID==spell) then
                    -- Failed and invalidated initiations share Engine's existing
                    -- lifetime tombstones. Never evict: delayed events must stay
                    -- retired, but there is no redundant 128-attempt budget.
                    if not e.seen[guid] then
                        if e.seenCount>=4096 then e.identitySaturated=true; runtime:Fault("CONTINUOUS_FAILED_IDENTITY_CAPACITY"); return true end
                        e.seen[guid]="retired"; e.seenCount=e.seenCount+1
                    end
                    local reason=moving==true and "CONTINUOUS_MOVEMENT_FAILURE_RETRY" or (moving==false and "CONTINUOUS_FAILURE_RETRY" or "CONTINUOUS_FAILURE_MOVEMENT_UNKNOWN")
                    e:Log("observed",reason,spell,nil,nil,event)
                    runtime:Suspend(reason); return true
                elseif not a or a.generation~=generation or a.index~=index or a.spellID~=spell then
                    -- A same-ID failure without this attempt's initiation is not
                    -- proof of current failure, especially adjacent rank repeats.
                    e:Log("ignored","CONTINUOUS_FAILURE_NO_CURRENT_INITIATION",spell,nil,nil,event)
                    return true
                end
            end
            self:StopContinuous("CONTINUOUS_FAILURE_STOP")
            if TEF.Runtime and TEF.Runtime.e==TEF.engine then TEF.Runtime:OnDispatchFault("CONTINUOUS_FAILURE_STOP") end
        end
        if not self.continuous then self:Cancel() end
    end
    if not self.pending then return end
    local u=S.Public(unit,"string"); local spell=S.ID(id)
    if not u or (u=="player" and not spell) then self:Cancel("TEK_EVENT_UNKNOWN"); return end
    if u=="player" and spell==self.pending.binding.spellID then self:Cancel("TEK_GAME_EVENT_RECEIVED") end
end
