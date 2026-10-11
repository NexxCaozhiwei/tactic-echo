local _,TEF=...
local A,S=TEF.APL,TEF.Safety
local P={}; A.State=P
function P.Boolean(path,...)
 local ok,raw,reason=S.Call(path,...)
 if not ok then return nil,reason end
 return S.Public(raw,"boolean")
end
function P.Time()
 local ok,value=S.Call("GetTime"); local n=ok and S.Public(value,"number")
 if n and n>=0 then return n end
end
local function int(value,max)
 local v=S.Public(value,"number"); if v and v>=0 and v<=max and v%1==0 then return v end
end
function P:Invalidate(static)
 self.revision=(self.revision or 0)+1; self.last=nil
 if static then self.learned=nil; self.talents=nil; self.build=nil end
end
function P:Learned(config)
 local sets,complete={},false
 local bank=S.Field(S.Field(Enum,"SpellBookSpellBank","table"),"Player","number")
 local spellType=S.Field(S.Field(Enum,"SpellBookItemType","table"),"Spell","number")
 local ok,total=S.Call("C_SpellBook.GetNumSpellBookSkillLines"); total=ok and int(total,16)
 if total and bank~=nil and spellType~=nil then
  complete=true; local slots=0
  for line=1,total do
   local got,info=S.Call("C_SpellBook.GetSpellBookSkillLineInfo",line)
   local offset=got and int(S.Field(info,"itemIndexOffset","number"),512)
   local count=got and int(S.Field(info,"numSpellBookItems","number"),256)
   if not offset or not count or slots+count>256 then complete=false; break end
   for index=offset+1,offset+count do
    slots=slots+1
    local read,item=S.Call("C_SpellBook.GetSpellBookItemInfo",index,bank)
    local kind=read and S.Field(item,"itemType","number")
    if kind==nil then complete=false
    elseif kind==spellType then
     local id=S.ID(S.Field(item,"spellID","number"))
     local name=S.Field(item,"name","string")
     local passive=S.Field(item,"isPassive","boolean")
     local key=id and name and A.AbilityNames[name]
     if not id or not name or passive==nil then complete=false
     elseif key and passive==false and id~=7268 then
      sets[key]=sets[key] or {}; sets[key][id]=true
     end
    end
   end
  end
 end
 local learned={}
 for key,ability in pairs(A.Abilities) do
  local ids=sets[key] or {}; local explicit=config.exactIDs[key]
  -- Observed/candidate IDs only add positive known results. A false result
  -- for a catalogue rank does not prove all other ranks unlearned.
  if explicit then
   local known=P.Boolean("C_SpellBook.IsSpellKnown",explicit)
   local got,info=S.Call("C_Spell.GetSpellInfo",explicit)
   local name=got and S.Field(info,"name","string")
   if known==true and name and A.AbilityNames[name]==key then ids={[explicit]=true}
   else
    local value; if known==false then value=false end
    learned[key]={known=value,reason="EXACT_ID_NOT_CERTIFIED"}; ids={}
   end
  elseif not next(ids) and ability.observedID then
   local id=ability.observedID
   local known=P.Boolean("C_SpellBook.IsSpellKnown",id)
   local got,info=S.Call("C_Spell.GetSpellInfo",id)
   local name=got and S.Field(info,"name","string")
   if known==true and name and A.AbilityNames[name]==key then ids[id]=true end
  end
  if not learned[key] then
   local count,only,bound,boundCount=0,nil,nil,0
   for id in pairs(ids) do
    -- Being in a public book is still independently confirmed as learned.
    local known=P.Boolean("C_SpellBook.IsSpellKnown",id)
    if known==true then
     count=count+1; only=id
     local binding=TEF.Dispatch and TEF.Dispatch:ResolveCached(id)
     if binding then bound=id; boundCount=boundCount+1 end
    elseif known==nil then complete=false end
   end
   local chosen=boundCount==1 and bound or (count==1 and only or nil)
   local value
   if count>0 then value=true elseif complete then value=false end
   learned[key]={known=value,spellID=chosen,reason=chosen and "PUBLIC_EXACT_LEARNED" or count>1 and "RANK_ID_AMBIGUOUS" or "LEARNED_UNKNOWN_OR_ABSENT"}
  end
 end
 return learned
end
-- Public 0/0 is sufficient evidence of inactivity; isActive alone is not.
-- No clock-based CD/GCD expiration, DurationObject or isOnGCD inference.
function P.Ready(id)
 local ok,record=S.Call("C_Spell.GetSpellCooldown",id)
 if not ok then return nil,"COOLDOWN_API_UNAVAILABLE" end
 local start=S.Field(record,"startTime","number")
 local duration=S.Field(record,"duration","number")
 local enabled=S.Field(record,"isEnabled","boolean")
 if enabled==false then return false,"COOLDOWN_DISABLED" end
 if enabled~=true or start==nil or duration==nil or start<0 or duration<0 then return nil,"COOLDOWN_UNKNOWN" end
 if start==0 and duration==0 then return true,"PUBLIC_ZERO_COOLDOWN" end
 return false,"PUBLIC_COOLDOWN_ACTIVE"
end
function P:ReadAction(key,learned,readReady)
 local result={known=learned.known,spellID=learned.spellID,reason=learned.reason}
 local ability=A.Abilities[key]; local id=result.spellID
 if result.known~=true or not id then return result end
 local fn=S.Resolve("C_Spell.IsSpellUsable")
 if fn then
  local ok,usable,power=pcall(fn,id)
  if ok then
   result.usable=S.Public(usable,"boolean")
   local insufficient=S.Public(power,"boolean")
   if insufficient~=nil then result.power_ok=not insufficient end
  end
 end
 if ability.target=="self" then result.in_range=true
 else result.in_range=P.Boolean("C_Spell.IsSpellInRange",id,"target") end
 if readReady~=false then result.ready,result.cooldownReason=P.Ready(id)
 else result.cooldownReason="NOT_REQUESTED" end
 return result
end
function P:Sample(e)
 local generation,serial,revision=e.generation,e.receiptSerial or 0,self.revision or 0
 local now=P.Time(); if not now then return nil,"APL_TIME_UNKNOWN" end
 local function fresh() return generation==e.generation and serial==(e.receiptSerial or 0) and revision==(self.revision or 0) end
 if not fresh() then return nil,"APL_STALE_SAMPLE" end
 if e.db.apl.template=="custom" then
  local state={generation=generation,receiptSerial=serial,revision=revision,sampledAt=now,
   combat={in_combat=P.Boolean("InCombatLockdown")},gcd={},actions={},talents={},buildSignature={},scene=e.scene,moving=P.Boolean("IsPlayerMoving")}
  A.Custom:Sample(e,state)
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  return state
 end
 local config=e.db.apl
 local learned,talents,build,provider=self.learned,self.talents,self.build,self.talentProvider
 if not learned then
  learned=self:Learned(config)
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  self.learned=learned
 end
 if not talents then
  talents,build,provider=A.TalentState:Read()
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  self.talents,self.build,self.talentProvider=talents,build,provider
 end
 local state={generation=generation,receiptSerial=serial,revision=revision,sampledAt=now,
  combat={in_combat=P.Boolean("InCombatLockdown")},gcd={},actions={},talents=talents,
  buildSignature=build,mana_band="UNKNOWN",scene=e.scene,moving=P.Boolean("IsPlayerMoving")}
 -- GCD is intentionally not queried or required by this APL policy.
 if not fresh() then return nil,"APL_STALE_SAMPLE" end
 local visible=TEF.Research:CountVisible()
 if visible.state=="PUBLIC_VALUE" then state.enemy_count=visible.value end
 -- Bounded live reads for the active v0 rules/fillers only. Registry coverage
 -- does not create a per-frame full spell or talent scan.
 for _,key in ipairs(A.RuleActions) do
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  state.actions[key]=self:ReadAction(key,learned[key])
 end
 if generation~=e.generation or serial~=(e.receiptSerial or 0) or revision~=(self.revision or 0) then return nil,"APL_STALE_SAMPLE" end
 return state
end
