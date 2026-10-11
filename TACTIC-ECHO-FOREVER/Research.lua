local _, TEF = ...
local S, R = TEF.Safety, {revision=0,fields={},versions={}}
TEF.Research = R
local keys={"targetExists","targetAttackable","targetAlive","inRange","usable","insufficientPower",
    "moving","castPresent","channelPresent","ready","gcdClear","visibleEnemies"}
local states={PUBLIC_TRUE=true,PUBLIC_FALSE=true,PUBLIC_VALUE=true,NO_DATA=true,SECRET=true,
    UNKNOWN=true,UNAVAILABLE=true,CALL_FAILED=true,FIELD_FAILED=true,UNKNOWN_UNIT=true,
    UNKNOWN_CAPACITY=true,UNKNOWN_IDENTITY=true,UNKNOWN_DETECTOR_MISSING=true,
    UNKNOWN_DETECTOR_FAILED=true,UNKNOWN_DETECTOR_RESULT=true,UNKNOWN_OPERATION_FAILED=true,
    UNKNOWN_TYPE=true,UNKNOWN_NUMBER=true}
function R.CleanSummary(raw)
    if not S.Public(raw,"table") then return nil end
    local clean={}
    for _,key in ipairs(keys) do
        local value=S.Field(raw,key,"string")
        if value and states[value] then clean[key]=value end
    end
    local count=S.Field(raw,"visibleCount","number")
    if count and count>=0 and count<=40 and count%1==0 then clean.visibleCount=count end
    local proposal=S.Field(raw,"proposal","string")
    if proposal=="single" or proposal=="multi" then clean.proposal=proposal end
    return clean
end

function R:Invalidate()
    self.revision=self.revision+1
    self.fields={}; self.auto={}; self.proposal=nil; self.dynamic=nil; self.sampledAt=nil
    for _,key in ipairs(keys) do self.versions[key]=(self.versions[key] or 0)+1 end
end
function R:Ticket(e)
    local versions={}
    for _,key in ipairs(keys) do versions[key]=self.versions[key] end
    return {generation=e.generation,revision=self.revision,versions=versions}
end
function R:Put(e,ticket,key,field)
    if ticket.generation~=e.generation or ticket.revision~=self.revision
        or ticket.versions[key]~=self.versions[key] then return false end
    self.fields[key]=field
    return true
end
function R:Current(e,ticket)
    if ticket.generation~=e.generation or ticket.revision~=self.revision then return false end
    for _,key in ipairs(keys) do if ticket.versions[key]~=self.versions[key] then return false end end
    return true
end
function R:Immediate(e,key,field)
    self.versions[key]=(self.versions[key] or 0)+1
    self.fields[key]=field
end
function R.Boolean(raw, reason)
    local value, classification=S.Public(raw,"boolean")
    if value==nil then return {state=classification or reason or "UNKNOWN"} end
    return {state=value and "PUBLIC_TRUE" or "PUBLIC_FALSE",value=value}
end
local function boolean(path,...)
    local ok,raw,reason=S.Call(path,...)
    if not ok then return {state=reason} end
    return R.Boolean(raw)
end
local function presence(path)
    local ok,raw,reason=S.Call(path,"player")
    if not ok then return {state=reason} end
    -- The first return is a name; only derive existence after official
    -- detection. Never save or inspect restricted name content.
    local value, classification=S.Public(raw,"string")
    if classification=="NO_DATA" then return {state="PUBLIC_FALSE",value=false} end
    if value then return {state="PUBLIC_TRUE",value=true} end
    return {state=classification}
end
function R:CountVisible()
    local ok,raw,reason=S.Call("C_NamePlate.GetNamePlates")
    if not ok then return {state=reason} end
    local list,classification=S.Public(raw,"table")
    if not list then return {state=classification} end
    local measured,size=pcall(function() return #list end)
    if not measured or size>40 then return {state="UNKNOWN_CAPACITY"} end
    local count,seen=0,{}
    for i=1,size do
        local read,plate=pcall(function() return list[i] end)
        if not read then return {state="FIELD_FAILED"} end
        local token=S.Field(plate,"namePlateUnitToken","string")
        if not token or not token:match("^nameplate%d+$") or seen[token] then return {state="UNKNOWN_IDENTITY"} end
        seen[token]=true
        local exists=boolean("UnitExists",token)
        if exists.value==nil then return {state="UNKNOWN_UNIT"} end
        if exists.value then
            local enemy,dead=boolean("UnitCanAttack","player",token),boolean("UnitIsDeadOrGhost",token)
            if enemy.value==nil or dead.value==nil then return {state="UNKNOWN_UNIT"} end
            if enemy.value and not dead.value then count=count+1 end
        end
    end
    return {state="PUBLIC_VALUE",value=count}
end

-- Pure future scene policy: two distinct samples, hysteresis. It only
-- produces a proposal; runtime never consumes it as a scene change.
function R.Auto(policy,field,sample,current)
    if field.state~="PUBLIC_VALUE" then policy.last=nil; policy.pending=nil; policy.hits=0; return nil,"AUTO_UNKNOWN" end
    if policy.last==sample then return nil,"AUTO_SAME_SAMPLE" end
    policy.last=sample
    local desired=field.value>=3 and "multi" or (field.value<=1 and "single" or current)
    if desired==current then policy.pending=nil; policy.hits=0; return nil,"AUTO_HOLD" end
    if policy.pending~=desired then policy.pending=desired; policy.hits=1
    else policy.hits=policy.hits+1 end
    if policy.hits>=2 then return desired,"AUTO_PROPOSAL" end
    return nil,"AUTO_CONFIRMING"
end
local function isTrue(field) return field and field.state=="PUBLIC_TRUE" and field.value==true end
local function isFalse(field) return field and field.state=="PUBLIC_FALSE" and field.value==false end
-- Contract prototype, not a ready formula. Each exact spell must receive
-- independently certified own-ready evidence before any candidate exists.
function R.Priority(rows,byID,common)
    if not isTrue(common.targetExists) or not isTrue(common.targetAttackable) or not isTrue(common.targetAlive)
        or not isTrue(common.gcdClear) or not isFalse(common.castPresent) or not isFalse(common.channelPresent)
        or not isFalse(common.moving) then return nil,"PRIORITY_COMMON_UNKNOWN_OR_BLOCKED" end
    for _,row in ipairs(rows) do
        local f=byID[row.spellID]
        if not row.unverified and f and isTrue(f.learned) and isTrue(f.ready) and isTrue(f.usable)
            and isFalse(f.insufficientPower) and isTrue(f.inRange) then
            return row.spellID,"PRIORITY_CANDIDATE"
        end
    end
    return nil,"PRIORITY_NO_CERTIFIED_READY"
end
function R:Sample(e)
    if not e.running then self:Invalidate(); return false,"RESEARCH_PAUSED" end
    self.sampleSerial=(self.sampleSerial or 0)+1
    local ticket=self:Ticket(e)
    local step=e.steps[e.index]
    local id=step.spellID
    local alive=boolean("UnitIsDeadOrGhost","target")
    if alive.value~=nil then alive=R.Boolean(not alive.value) end
    local evidence={targetExists=boolean("UnitExists","target"),targetAttackable=boolean("UnitCanAttack","player","target"),
        targetAlive=alive,inRange=id>0 and boolean("C_Spell.IsSpellInRange",id,"target") or {state="UNAVAILABLE"},
        moving=boolean("IsPlayerMoving"),
        castPresent=presence("UnitCastingInfo"),channelPresent=presence("UnitChannelInfo"),
        ready={state="UNKNOWN"},gcdClear={state="UNKNOWN"},visibleEnemies=self:CountVisible()}
    local fn=S.Resolve("C_Spell.IsSpellUsable")
    if fn and id>0 then
        local ok,usable,power=pcall(fn,id)
        if ok then evidence.usable=R.Boolean(usable); evidence.insufficientPower=R.Boolean(power)
        else evidence.usable={state="CALL_FAILED"}; evidence.insufficientPower={state="CALL_FAILED"} end
    else evidence.usable={state="UNAVAILABLE"}; evidence.insufficientPower={state="UNAVAILABLE"} end
    local ok,raw=S.Call("GetTime")
    local sampledAt=ok and S.Public(raw,"number") or nil
    if not self:Current(e,ticket) then return false,"RESEARCH_STALE" end
    for _,key in ipairs(keys) do
        if not self:Put(e,ticket,key,evidence[key]) then return false,"RESEARCH_STALE" end
    end
    if not sampledAt or not self.sampledAt or sampledAt-self.sampledAt>1 or sampledAt<self.sampledAt then self.auto={} end
    self.sampledAt=sampledAt
    self.auto=self.auto or {}
    self.proposal,self.autoReason=nil,"AUTO_UNKNOWN"
    if sampledAt then self.proposal,self.autoReason=R.Auto(self.auto,self.fields.visibleEnemies,self.sampleSerial,e.scene) end
    -- Same public field evidence, but deliberately no certified ready source.
    self.dynamic,self.dynamicReason=R.Priority(e.db.profiles[e.scene],{},self.fields)
    e:Log("observed","RESEARCH_SAMPLED")
    local summary={proposal=self.proposal}
    for _,key in ipairs(keys) do summary[key]=self.fields[key].state end
    summary.visibleCount=self.fields.visibleEnemies.value
    e.db.diagnostics[#e.db.diagnostics].research=R.CleanSummary(summary)
    return true
end
function R:View()
    local ok,raw=S.Call("GetTime")
    local now=ok and S.Public(raw,"number") or nil
    if not now or not self.sampledAt or now-self.sampledAt>1 or now<self.sampledAt then return "状态未采样或已过期；ready未验证" end
    local lines={"最近手动采样时刻 " .. self.sampledAt .. "（非实时状态）"}
    for _,key in ipairs(keys) do
        local field=self.fields[key]
        lines[#lines+1]=key .. "=" .. (field and field.state or "UNKNOWN")
            .. (field and field.state=="PUBLIC_VALUE" and (":" .. field.value) or "")
    end
    lines[#lines+1]="场景建议：" .. (self.proposal or "无") .. "（只观察，不自动切换）"
    lines[#lines+1]="动态规则：" .. (self.dynamicReason or "PRIORITY_NO_CERTIFIED_READY")
    return table.concat(lines,"\n")
end
R:Invalidate()
