local _, TEF = ...
local D,S={},TEF.Safety
TEF.Dispatch=D
D.enabled=false
function D:SetEnabled(value)
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
                        local token=bound and (D.Token(k1) or D.Token(k2))
                        if token then
                            local key=D.Token(k1) and S.Public(k1,"string") or S.Public(k2,"string")
                            return {slot=slot,token=token,key=key,spellID=id,command=commands[bar] .. n,button=b,buttonName=name .. n},"TEK_BINDING_VERIFIED"
                        end
                    end
                end
            end
        end
    end end
    return nil,"TEK_EXACT_DIRECT_BINDING_UNAVAILABLE"
end
function D:CastIdle()
    for _,path in ipairs({"UnitCastingInfo","UnitChannelInfo"}) do
        local ok,value=S.Call(path,"player")
        local _,reason=S.Public(value,"string")
        if not ok or reason~="NO_DATA" then return false end
    end
    return true
end
function D:Request()
    self:Cancel()
    local e=TEF.engine; local step=e.steps and e.steps[e.index]
    local blocked
    if not self.enabled then blocked="TEK_PERMISSION_DISABLED"
    elseif TEF.UI.settingsOpen then blocked="TEK_SETTINGS_OPEN"
    elseif not e.running then blocked="TEK_PRACTICE_PAUSED"
    elseif e.completed then blocked="TEK_PRACTICE_COMPLETED"
    elseif not step or step.unverified then blocked="TEK_STEP_UNRESOLVED"
    elseif not self:CastIdle() then blocked="TEK_CAST_PRESENT_OR_UNKNOWN" end
    if blocked then e:Log("transport",blocked); return false,blocked end
    local binding,reason=self:Resolve(step.spellID)
    if not binding then e:Log("transport",reason); return false,reason end
    if not TEF.Transport.enabled and not TEF.Transport:SetEnabled(true) then return false,"TEK_SIGNAL_UNAVAILABLE" end
    self.pending={generation=e.generation,index=e.index,binding=binding}
    e:Log("transport","TEK_MANUAL_REQUEST",step.spellID)
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
    local token=bound and (D.Token(k1) or D.Token(k2))
    return slot==b.slot and read and S.Public(kind,"string")=="spell" and S.ID(rawID)==b.spellID and token==b.token
end
function D:BindingsChanged()
    if not self.pending then return end
    if not self:VerifyCurrent(self.pending.binding) then self:Cancel("TEK_BINDING_CHANGED") end
end
function D:Packet()
    local p,e=self.pending,TEF.engine
    if not p then return nil end
    if not self.enabled or not e.running or e.completed or e.generation~=p.generation or e.index~=p.index or TEF.UI.settingsOpen then self:Cancel("TEK_REQUEST_STALE"); return nil end
    -- Revalidate the locked source; never silently switch to another slot/key.
    if not self:VerifyCurrent(p.binding) then self:Cancel("TEK_BINDING_CHANGED"); return nil end
    if not self:CastIdle() then self:Cancel("TEK_CAST_PRESENT_OR_UNKNOWN"); return nil end
    local ok,rawCombat=S.Call("InCombatLockdown")
    local combat
    if ok then combat=S.Public(rawCombat,"boolean") end
    if combat==nil then self:Cancel("TEK_COMBAT_UNKNOWN"); return nil end
    return p.binding.token,combat
end
function D:Event(event,unit,id)
    if not self.pending then return end
    local u=S.Public(unit,"string"); local spell=S.ID(id)
    if not u or (u=="player" and not spell) then self:Cancel("TEK_EVENT_UNKNOWN"); return end
    if u=="player" and spell==self.pending.binding.spellID then self:Cancel("TEK_GAME_EVENT_RECEIVED") end
end
