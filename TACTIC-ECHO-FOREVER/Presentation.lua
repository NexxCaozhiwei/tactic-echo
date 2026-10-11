local _,TEF=...
local P,S={},TEF.Safety
TEF.Presentation=P
-- Display-only. No state is read by Engine, Research or Dispatch.
P.cooldowns={}
P.bindings={}
local function number(record,key) return S.Field(record,key,"number") end
function P:Read(id,cooldownEvent)
    local result={cd="CD 未知",charges="充能 未知"}
    local ok,info=S.Call("C_Spell.GetSpellCooldown",id)
    if ok then
        local start,duration=number(info,"startTime"),number(info,"duration")
        local enabled=S.Field(info,"isEnabled","boolean")
        local rate=number(info,"modRate")
        if start and duration and start>=0 and duration>=0 and enabled==true and rate and rate>0 then
            if duration==0 then self.cooldowns[id]=nil; result.cd="CD 0"
            elseif cooldownEvent then
                local gcd=S.Field(info,"isOnGCD","boolean")
                if gcd==false then self.cooldowns[id]={start=start,duration=duration,rate=rate}
                elseif gcd==true then self.cooldowns[id]=nil; result.cd="GCD"
                else self.cooldowns[id]=nil end
            end
        elseif cooldownEvent then self.cooldowns[id]=nil end
    elseif cooldownEvent then self.cooldowns[id]=nil end
    local cached=self.cooldowns[id]
    if cached then
        local start,duration=number(info,"startTime"),number(info,"duration")
        local rate=number(info,"modRate")
        if start~=cached.start or duration~=cached.duration or rate~=cached.rate then cached=nil end
    end
    if cached then
        local got,raw=S.Call("GetTime"); local now=got and S.Public(raw,"number")
        if now then result.cd="CD " .. math.ceil(math.max(0,cached.start+cached.duration/cached.rate-now)) .. "s" end
    end
    local got,charge=S.Call("C_Spell.GetSpellCharges",id)
    if got then
        local _,reason=S.Public(charge,"table")
        if reason=="NO_DATA" then result.charges="充能 —"
        else
            local current,max=number(charge,"currentCharges"),number(charge,"maxCharges")
            if current and max and current>=0 and max>0 and current<=max and current%1==0 and max%1==0 then
                result.charges="充能 " .. current .. "/" .. max; result.recharging=current<max
            end
        end
    end
    return result
end
function P:Paint(card,step,cooldownEvent)
    local U=TEF.UI
    card.visualID=step and not step.unverified and step.spellID or nil
    U:Call(card.cooldown,"Clear")
    if not step or step.unverified then
        U:Paint(card.key,"SetText","—"); U:Paint(card.meta,"SetText","")
        U:Paint(card.cooldownText,"SetText",""); U:Paint(card.chargeText,"SetText",""); return
    end
    local binding=self.bindings[step.spellID]
    if binding==nil then binding=TEF.Dispatch:Resolve(step.spellID); self.bindings[step.spellID]=binding or false end
    U:Paint(card.key,"SetText",binding and binding.key or "未解析")
    local view=self:Read(step.spellID,cooldownEvent)
    U:Paint(card.meta,"SetText","")
    U:Paint(card.cooldownText,"SetText",view.cd:match("^CD (%d+)s$") or (view.cd=="CD 未知" and "?" or ""))
    U:Paint(card.chargeText,"SetText",view.charges:match("(%d+/%d+)") or "")
    -- A client duration object is passed directly to ONE renderer, never
    -- inspected, compared, persisted or used for input eligibility.
    local path=view.recharging and "C_Spell.GetSpellChargeDuration" or "C_Spell.GetSpellCooldownDuration"
    local ok,duration
    if view.recharging then ok,duration=S.Call(path,step.spellID)
    else ok,duration=S.Call(path,step.spellID,true) end
    if ok then U:Call(card.cooldown,"SetCooldownFromDurationObject",duration) end
end
function P:Tick(card)
    local cached=card.visualID and self.cooldowns[card.visualID]
    if not cached then return end
    local ok,raw=S.Call("GetTime"); local now=ok and S.Public(raw,"number")
    if not now then TEF.UI:Paint(card.cooldownText,"SetText","?"); return end
    local remain=math.ceil(math.max(0,cached.start+cached.duration/cached.rate-now))
    TEF.UI:Paint(card.cooldownText,"SetText",remain>0 and tostring(remain) or "")
end
