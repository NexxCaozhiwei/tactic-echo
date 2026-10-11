local _,TEF=...
local T={}; TEF.APL.Trace=T
function T:Record(e,trace,reason,candidate,state)
 local old=e.aplTrace
 local parts={reason}
 if state then parts[#parts+1]=tostring(state.gcd.ready); for _,key in ipairs({"fireball","frostbolt","scorch","arcane_missiles"}) do local a=state.actions[key]; if a then for _,field in ipairs({"known","usable","power_ok","in_range","ready"}) do parts[#parts+1]=tostring(a[field]) end end end end
 for _,r in ipairs(trace) do parts[#parts+1]=r.rule .. ":" .. r.result .. ":" .. r.reason end
 for _,tree in ipairs({"ARCANE","FIRE","FROST"}) do parts[#parts+1]=state and state.buildSignature[tree] or "UNKNOWN" end
 if state then
  parts[#parts+1]="moving=" .. tostring(state.moving)
  parts[#parts+1]="visible=" .. tostring(state.enemy_count)
  parts[#parts+1]="mana=" .. tostring(state.manaPercent) .. ":" .. (state.manaReason or "UNKNOWN")
  parts[#parts+1]="distance=" .. tostring(state.distance) .. ":" .. (state.distanceReason or "UNKNOWN")
  for i=1,16 do
   local a=state.actions["custom_" .. i]
   if a then
    parts[#parts+1]="custom_" .. i .. "=" .. tostring(a.spellID)
    for _,field in ipairs({"known","usable","power_ok","in_range","ready","active"}) do parts[#parts+1]=tostring(a[field]) end
    parts[#parts+1]=tostring(a.cdmActive) .. ":" .. (a.cdmReason or "UNKNOWN")
    parts[#parts+1]=(a.cdmScanReason or "NONE") .. ":" .. tostring(a.cdmSkippedFrames)
   end
  end
  for _,key in ipairs({"arcane_power","presence_of_mind","pyroblast","improved_scorch"}) do
   local t=state.talents[key]; parts[#parts+1]=t and t.status or "UNKNOWN"; parts[#parts+1]=t and t.rank or "UNKNOWN"
  end
 end
 local fingerprint=table.concat(parts,"|")
 e.aplTrace={reason=reason,rule=candidate and candidate.rule,action=candidate and candidate.action,
  spellID=candidate and candidate.spellID,rules=trace,build=state and state.buildSignature or {},fingerprint=fingerprint}
 local changed=not old or old.fingerprint~=fingerprint or old.rule~=e.aplTrace.rule or old.spellID~=e.aplTrace.spellID
 if changed then
  e:Log("observed",candidate and "APL_SELECTED" or "APL_NO_CANDIDATE",candidate and candidate.spellID)
  local row=e.db.diagnostics[#e.db.diagnostics]
  row.apl={reason=reason,rule=e.aplTrace.rule,action=e.aplTrace.action,build=e.aplTrace.build,rules=trace}
  if state then
   row.apl.gcd=state.gcd and state.gcd.ready
   row.apl.inCombat=state.combat.in_combat
   row.apl.moving=state.moving
   row.apl.visibleCount=state.enemy_count
   row.apl.manaPercent,row.apl.distance=state.manaPercent,state.distance
   row.apl.manaReason,row.apl.distanceReason=state.manaReason,state.distanceReason
   row.apl.actions={}; row.apl.talents={}
   for key,action in pairs(state.actions) do
    row.apl.actions[key]={spellID=action.spellID,known=action.known,usable=action.usable,power_ok=action.power_ok,in_range=action.in_range,ready=action.ready,active=action.active,cdmActive=action.cdmActive,cdmReason=action.cdmReason,cooldownReason=action.cooldownReason,cdmScanReason=action.cdmScanReason,cdmSkippedFrames=action.cdmSkippedFrames}
   end
   for _,key in ipairs({"arcane_power","presence_of_mind","pyroblast","improved_scorch"}) do
    local t=state.talents[key]; if t then row.apl.talents[key]={status=t.status,known=t.known,rank=t.rank,maxRank=t.maxRank} end
   end
  end
 end
end
function T.Clean(raw)
 local S=TEF.Safety
 local reason=S.Field(raw,"reason","string")
 if not reason or #reason>80 or not reason:match("^[A-Z_]+$") then return nil end
 local out={reason=reason,build={},rules={},actions={},talents={},inCombat=S.Field(raw,"inCombat","boolean"),gcd=S.Field(raw,"gcd","boolean")}
 out.moving=S.Field(raw,"moving","boolean")
 local count=S.Field(raw,"visibleCount","number")
 if count and count>=0 and count<=40 and count%1==0 then out.visibleCount=count end
 for _,spec in ipairs({{"manaPercent",100},{"distance",1000000}}) do
  local value=S.Field(raw,spec[1],"number"); if value and value>=0 and value<=spec[2] then out[spec[1]]=value end
 end
 for _,field in ipairs({"manaReason","distanceReason"}) do
  local value=S.Field(raw,field,"string"); if value and #value<=80 and value:match("^[A-Z_]+$") then out[field]=value end
 end
 local rule=S.Field(raw,"rule","string"); local action=S.Field(raw,"action","string")
 if rule and #rule<=80 and rule:match("^[A-Za-z_:%d]+$") then out.rule=rule end
 if action and (TEF.APL.Abilities[action] or action:match("^custom_%d+$")) then out.action=action end
 local build=S.Field(raw,"build","table")
 for _,key in ipairs({"ARCANE","FIRE","FROST"}) do
  local n=build and S.Field(build,key,"number"); if n and n>=0 and n<=100 and n%1==0 then out.build[key]=n end
 end
 local rows=S.Field(raw,"rules","table")
 if rows then for i=1,48 do
  local r=S.Field(rows,i,"table"); if not r then break end
  local id=S.Field(r,"rule","string"); local value=S.Field(r,"result","string"); local why=S.Field(r,"reason","string")
  if id and #id<=80 and id:match("^[A-Za-z_:%d]+$") and (value=="TRUE" or value=="FALSE" or value=="UNKNOWN" or value=="BLOCKED" or value=="DISABLED")
   and why and #why<=100 and why:match("^[A-Za-z_:]+$") then out.rules[#out.rules+1]={rule=id,result=value,reason=why} end
 end end
 local actions=S.Field(raw,"actions","table")
 local keys={}; for _,key in ipairs(TEF.APL.RuleActions) do keys[#keys+1]=key end; for i=1,16 do keys[#keys+1]="custom_" .. i end
 for _,key in ipairs(keys) do
  local r=actions and S.Field(actions,key,"table")
  if r then
   local a={spellID=S.ID(S.Field(r,"spellID","number"))}
   for _,field in ipairs({"known","usable","power_ok","in_range","ready","active","cdmActive"}) do a[field]=S.Field(r,field,"boolean") end
   local cooldown=S.Field(r,"cooldownReason","string"); if cooldown and #cooldown<=80 and cooldown:match("^[A-Z_]+$") then a.cooldownReason=cooldown end
   local why=S.Field(r,"cdmReason","string"); if why and #why<=80 and why:match("^[A-Z_]+$") then a.cdmReason=why end
   local scan=S.Field(r,"cdmScanReason","string"); if scan=="CDM_FRAME_ID_UNKNOWN" then a.cdmScanReason=scan end
   local skipped=S.Field(r,"cdmSkippedFrames","number"); if skipped and skipped>=1 and skipped<=160 and skipped%1==0 then a.cdmSkippedFrames=skipped end
   out.actions[key]=a
  end
 end
 local talents=S.Field(raw,"talents","table")
 for _,key in ipairs({"arcane_power","presence_of_mind","pyroblast","improved_scorch"}) do
  local r=talents and S.Field(talents,key,"table")
  local status=r and S.Field(r,"status","string")
  if status=="KNOWN" or status=="NOT_KNOWN" or status=="UNKNOWN" then
   local t={status=status,known=S.Field(r,"known","boolean")}
   for _,field in ipairs({"rank","maxRank"}) do
    local v=S.Field(r,field,"number"); if v and v>=0 and v<=10 and v%1==0 then t[field]=v end
   end
   out.talents[key]=t
  end
 end
 return out
end
function T:View(e)
 local t=e.aplTrace; if not t then return "法师 APL · 等待启动采样" end
 if e.db.apl.template=="custom" then return "自定义 APL | " .. (t.rule or t.reason) .. "\n从上往下选择首条满足规则；详见自定义APL页。" end
 local b=t.build or {}
 return "法师 APL（" .. e.db.apl.template .. "） | " .. (t.rule or t.reason) .. "\n天赋：" .. (b.ARCANE or "?") .. "/" .. (b.FIRE or "?") .. "/" .. (b.FROST or "?") .. "（仅诊断）"
end
function T:Waiting(e)
 local runtime=TEF.Runtime
 if runtime and runtime.e==e and runtime.state=="standby" then return "APL待命：暂无满足条件的规则" end
 local t=e.aplTrace
 if t then for _,r in ipairs(t.rules or {}) do
  if r.reason=="combat:" or r.reason=="custom:combat" then return "APL待命：等待重新评估" end
 end end
 return "APL暂无满足条件的规则"
end
