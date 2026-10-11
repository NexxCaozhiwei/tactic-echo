local _,T=...
local A,S=T.APL,T.Safety
local C={}; A.Custom=C
local fields={spellID=true,enabled=true,moving=true,enemyMin=true,enemyMax=true,activity=true,experimentalEnemies=true,invalid=true,requireReady=true,
 manaOp=true,manaValue=true,distanceOp=true,distanceValue=true,cdmKind=true,cdmState=true,cdmSpellID=true}
local classes={"MAGE","WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","WARLOCK","DRUID","DEATHKNIGHT","MONK","DEMONHUNTER","EVOKER"}
function C.CleanRows(raw)
 local rows={}; raw=S.Public(raw,"table"); if not raw then return rows end
 local ok,size=pcall(function() return #raw end)
 if not ok or size>16 then return {{enabled=false,invalid="CUSTOM_CAPACITY"}} end
 for i=1,size do
  local r=S.Field(raw,i,"table"); local row={spellID=r and S.ID(S.Field(r,"spellID","number")),enabled=true,requireReady=false,moving="any",activity="any",manaOp="any",distanceOp="any",cdmKind="none",cdmState="inactive"}
  if not r or not row.spellID then row.invalid="CUSTOM_ID_INVALID" end
  if r then
   for field,kind in pairs({enabled="boolean",requireReady="boolean",moving="string",activity="string",enemyMin="number",enemyMax="number",experimentalEnemies="boolean",manaOp="string",manaValue="number",distanceOp="string",distanceValue="number",cdmKind="string",cdmState="string",cdmSpellID="number"}) do
    local _,why=S.Field(r,field,kind)
    if why~="PUBLIC" and why~="NO_DATA" then row.invalid="CUSTOM_CONDITION_INVALID" end
   end
   local count=0
   local valid=pcall(function() for k in pairs(r) do count=count+1; local key=S.Public(k,"string"); if count>24 or not key or not fields[key] then row.invalid="CUSTOM_CONDITION_UNSUPPORTED" end end end)
   if not valid then row.invalid="CUSTOM_CONDITION_UNSUPPORTED" end
   local enabled=S.Field(r,"enabled","boolean"); if enabled~=nil then row.enabled=enabled end
   row.requireReady=S.Field(r,"requireReady","boolean")==true
   local moving=S.Field(r,"moving","string"); local activity=S.Field(r,"activity","string")
   if moving=="yes" or moving=="no" or moving=="any" then row.moving=moving elseif moving then row.invalid="CUSTOM_CONDITION_INVALID" end
   if activity=="active" or activity=="inactive" or activity=="any" then row.activity=activity elseif activity then row.invalid="CUSTOM_CONDITION_INVALID" end
   row.experimentalEnemies=S.Field(r,"experimentalEnemies","boolean")==true
   for _,field in ipairs({"enemyMin","enemyMax"}) do
    local n=S.Field(r,field,"number")
    if n then if n>=0 and n<=40 and n%1==0 then row[field]=n else row.invalid="CUSTOM_CONDITION_INVALID" end end
   end
   if row.enemyMin and row.enemyMax and row.enemyMin>row.enemyMax then row.invalid="CUSTOM_CONDITION_INVALID" end
   for _,prefix in ipairs({"mana","distance"}) do
    local op=S.Field(r,prefix .. "Op","string") or "any"
    local value=S.Field(r,prefix .. "Value","number")
    if not A.PublicConditions.ops[op] or (value and (value<0 or value>(prefix=="mana" and 100 or 2000)))
     or (op~="any" and value==nil) then row.invalid="CUSTOM_CONDITION_INVALID" end
    row[prefix .. "Op"],row[prefix .. "Value"]=op,value
   end
   local kind=S.Field(r,"cdmKind","string") or "none"
   local state=S.Field(r,"cdmState","string") or "inactive"
   if kind~="none" and kind~="buff" and kind~="cooldown" then row.invalid="CUSTOM_CONDITION_INVALID" end
   if state~="active" and state~="inactive" then row.invalid="CUSTOM_CONDITION_INVALID" end
   row.cdmKind,row.cdmState=kind,state
   local id=S.Field(r,"cdmSpellID","number"); if id then row.cdmSpellID=S.ID(id); if not row.cdmSpellID then row.invalid="CUSTOM_CONDITION_INVALID" end end
   if S.Field(r,"invalid","string") then row.invalid=row.invalid or "CUSTOM_CONDITION_INVALID" end
  end
  rows[#rows+1]=row
 end
 return rows
end
function C.CleanProfiles(raw)
 local out={}
 for _,class in ipairs(classes) do
  local p=S.Field(raw,class,"table")
  if p then out[class]={single=C.CleanRows(S.Field(p,"single","table")),multi=C.CleanRows(S.Field(p,"multi","table"))} end
 end
 return out
end
function C:Rows(e,scene)
 local p=e.db.apl.custom[e.classToken or ""]
 return p and p[scene or e.scene] or {}
end
function C:Save(e,rows,scene,class)
 if class~=e.classToken or class~="MAGE" or (scene~="single" and scene~="multi") then return false,"CUSTOM_PROFILE_UNKNOWN" end
 local clean=C.CleanRows(rows)
 for _,r in ipairs(clean) do if r.invalid then return false,r.invalid end end
 e:Reset(); e.db.apl.custom[class]=e.db.apl.custom[class] or {}
 e.db.apl.custom[class][scene]=clean; e.db.apl.template="custom"
 A:Invalidate(true); if A:IsActive(e) then e.steps=nil end
 return true
end
function C:Read(id,requireReady)
 local known=A.State.Boolean("C_SpellBook.IsSpellKnown",id)
 local ok,info=S.Call("C_Spell.GetSpellInfo",id); local name=ok and S.Field(info,"name","string")
 local key=name and A.AbilityNames[name]; local allowed=false
 if id==5019 and name then
  key="shoot"; allowed=true; A.Abilities.shoot={name=name,target="enemy"}
 end
 for _,k in ipairs(A.RuleActions) do if k==key then allowed=true end end
 if not allowed then return {spellID=id,known=known,reason="CUSTOM_SPELL_UNSUPPORTED"} end
 local action=A.State:ReadAction(key,{known=known,spellID=id,reason="CUSTOM_EXACT_ID"},requireReady==true)
 if id==5019 and action.in_range==nil then
  local ok,raw=S.Call("C_Spell.IsSpellInRange",id,"target"); local _,why=S.Public(raw,"boolean")
  if ok and why=="NO_DATA" then
   local b=T.Dispatch:ResolveCached(id)
   if b and T.Dispatch:VerifyCurrent(b) then action.in_range=A.State.Boolean("C_ActionBar.IsActionInRange",b.slot,"target") end
  end
 end
 action.name=name; action.target=A.Abilities[key].target
 return action
end
function C:Sample(e,state)
 local rows=self:Rows(e); local countNeeded=false
 for i,row in ipairs(rows) do
  if row.enabled and row.experimentalEnemies and (row.enemyMin or row.enemyMax) then countNeeded=true end
  local action
  if row.enabled and not row.invalid then action=self:Read(row.spellID,row.requireReady) else action={spellID=row.spellID} end
  if row.enabled and not row.invalid and row.activity~="any" then
   local ok,record=S.Call("C_Spell.GetSpellCooldown",row.spellID)
   if ok then action.active=S.Field(record,"isActive","boolean") end
  end
  state.actions["custom_" .. i]=action
 end
 if countNeeded then local value=T.Research:CountVisible(); if value.state=="PUBLIC_VALUE" then state.enemy_count=value.value end end
 A.PublicConditions:Sample(state,rows)
end
function C:Check(state,row,index)
 if row.invalid then return false,row.invalid,"BLOCKED" end
 if not row.enabled then return false,"CUSTOM_DISABLED","DISABLED" end
 local action=state.actions["custom_" .. index] or {}; local unknown
 if action.reason=="CUSTOM_SPELL_UNSUPPORTED" then return false,action.reason,"BLOCKED" end
 local function require(value,wanted,why)
  if value==nil then unknown=unknown or "UNKNOWN:custom:" .. why; return true end
  return value==wanted
 end
 -- Preview eligibility is independent of the transport combat gate.
 for _,field in ipairs({"known","usable","power_ok","in_range"}) do
  if not require(action[field],true,field) then return false,"custom:" .. field end
 end
 if row.requireReady==true and not require(action.ready,true,"ready") then return false,"custom:ready" end
 if row.moving~="any" and not require(state.moving,row.moving=="yes","moving") then return false,"custom:moving" end
 if row.activity~="any" and not require(action.active,row.activity=="active","activity") then return false,"custom:activity" end
 for _,p in ipairs({{"mana","manaPercent","manaReason"},{"distance","distance","distanceReason"}}) do
  local op=row[p[1] .. "Op"] or "any"
  local result=A.PublicConditions.Compare(state[p[2]],op,row[p[1] .. "Value"])
  if result==nil then unknown=unknown or "UNKNOWN:custom:" .. p[1] .. ":" .. (state[p[3]] or "UNKNOWN")
  elseif result==false then return false,"custom:" .. p[1] end
 end
 if row.cdmKind and row.cdmKind~="none" then
  if not require(action.cdmActive,row.cdmState=="active","cdm:" .. (action.cdmReason or "UNKNOWN")) then return false,"custom:cdm" end
 end
 if row.enemyMin or row.enemyMax then
  if not row.experimentalEnemies then return false,"CUSTOM_ENEMIES_UNVERIFIED","BLOCKED" end
  local n=state.enemy_count
  if n==nil then unknown=unknown or "UNKNOWN:custom:enemies"
  elseif (row.enemyMin and n<row.enemyMin) or (row.enemyMax and n>row.enemyMax) then return false,"custom:enemies" end
 end
 if unknown then return nil,unknown end
 return true,"CUSTOM_CONDITIONS_TRUE"
end
function C:Evaluate(state,config,class)
 local trace,candidate={},nil
 local rows=config.custom[class] and config.custom[class][state.scene] or {}
 for i,row in ipairs(rows) do
  local allowed,reason,status=self:Check(state,row,i)
  trace[#trace+1]={rule="custom:" .. i,result=status or (allowed==nil and "UNKNOWN" or allowed and "TRUE" or "FALSE"),reason=reason}
  if allowed==true and not candidate then
   local a=state.actions["custom_" .. i]
   if a.spellID then candidate={spellID=a.spellID,action="custom_" .. i,rule="custom:" .. i,name=a.name,target=a.target,customIndex=i} end
  end
 end
 return candidate,candidate and "APL_CANDIDATE" or "APL_NO_PUBLIC_ELIGIBLE_RULE",trace
end
function C:Ledger(e)
 local lines={"自定义优先级：从上往下选第一条满足的规则；成功后重新求值。",
  "待命也评估；必需：已学、可用、资源足够、技能范围。冷却检查可选，派发另要求战斗。"}
 local state=e.aplSnapshot; local results={}
 lines[#lines+1]="最近观察：移动=" .. tostring(state and state.moving) .. "；可见敌人数=" .. tostring(state and state.enemy_count)
 lines[#lines+1]="蓝量%=" .. tostring(state and state.manaPercent) .. "；距离=" .. tostring(state and state.distance)
 for _,r in ipairs(e.aplTrace and e.aplTrace.rules or {}) do results[r.rule]=r end
 for i,row in ipairs(self:Rows(e)) do
  local a=state and state.actions["custom_" .. i]; local result=results["custom:" .. i]
  lines[#lines+1]=i .. ". ID " .. (row.spellID or "?") .. " · " .. (result and result.result .. " · " .. result.reason or "未评估")
  if a then
   local parts={}; for _,field in ipairs({"known","usable","power_ok","in_range","ready","active"}) do parts[#parts+1]=field .. "=" .. tostring(a[field]) end
   lines[#lines+1]=table.concat(parts,"；")
  end
  lines[#lines+1]="移动=" .. row.moving .. "；冷却活动=" .. row.activity .. "；可见敌人=" .. (row.enemyMin or "不限") .. "～" .. (row.enemyMax or "不限")
  lines[#lines+1]="冷却数值检查=" .. (row.requireReady and "开启" or "关闭") .. "；" .. (a and a.cooldownReason or "未采样")
  lines[#lines+1]="蓝量=" .. (row.manaOp or "any") .. " " .. (row.manaValue or "") .. "；距离=" .. (row.distanceOp or "any") .. " " .. (row.distanceValue or "") .. "；CDM=" .. (row.cdmKind or "none") .. "/" .. (row.cdmState or "inactive") .. " ID " .. (row.cdmSpellID or row.spellID or "?") .. " · " .. tostring(a and a.cdmActive) .. " / " .. (a and a.cdmReason or "未采样")
  if a and a.cdmScanReason then lines[#lines+1]="CDM扫描：跳过身份未知帧 " .. (a.cdmSkippedFrames or 0) .. "；仅精确匹配帧决定该技能状态。" end
 end
 return table.concat(lines,"\n")
end
