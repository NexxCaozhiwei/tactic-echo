local _,TEF=...
local A=TEF.APL
function A:RuleAllowed(state,rule,config)
 if rule.status=="DROP" or rule.status=="BLOCKED" then return false,rule.reason end
 if rule.id:match(":aoe:") then
  if state.scene~="multi" then return false,"MANUAL_MULTI_REQUIRED" end
  if state.enemy_count==nil then return nil,"UNKNOWN:enemy_count" end
  if state.enemy_count<3 then return false,"VISIBLE_COUNT_TOO_LOW" end
 end
 local allowed,reason=self.Conditions:All(state,rule.if_all,config)
 if allowed~=true or rule.call then return allowed,reason end
 local key=rule.fallback and config.filler~="auto" and config.filler or rule.action
 -- Selection is a read-only preview, including automatic standby. Combat
 -- belongs to Allowed/Runtime transport gates, not mandatory eligibility.
 local terms={}
 for _,field in ipairs({"known","usable","power_ok","in_range","ready"}) do terms[#terms+1]={op="action",key=key,field=field} end
 local good,why=self.Conditions:All(state,terms,config)
 return good,why,key
end
function A:Evaluate(state,config,class)
 local pack=self.Packs[class]; local trace={}
 if not pack then return nil,"APL_CLASS_UNSUPPORTED",trace end
 if config.template=="custom" then return self.Custom:Evaluate(state,config,class) end
 local template=pack.templates[config.template]
 if not template then return nil,"APL_TEMPLATE_UNKNOWN",trace end
 local visited,budget={},0
 local function walk(list,depth)
  if depth>4 or visited[list] then return nil end
  visited[list]=true
  for _,rule in ipairs(template.lists[list] or {}) do
   budget=budget+1; if budget>96 then break end
   local allowed,reason,key=self:RuleAllowed(state,rule,config)
   trace[#trace+1]={rule=rule.id,result=rule.status=="DROP" and "DISABLED" or rule.status=="BLOCKED" and "BLOCKED" or allowed==nil and "UNKNOWN" or allowed and "TRUE" or "FALSE",reason=reason}
   if allowed==true then
    if rule.call then
     local result=walk(rule.call,depth+1); if result then return result end
    else
     local action=state.actions[key]
     if action and action.spellID then return {spellID=action.spellID,action=key,rule=rule.id} end
    end
   end
  end
  visited[list]=nil
 end
 local candidate=walk("default",1)
 return candidate,candidate and "APL_CANDIDATE" or "APL_NO_PUBLIC_ELIGIBLE_RULE",trace
end
function A:Ledger(e)
 local config=e.db.apl; if config.template=="custom" then return self.Custom:Ledger(e) end; local template=self.Packs.MAGE.templates[config.template]
 if not template then return "模板未知" end
 local results={}; for _,r in ipairs(e.aplTrace and e.aplTrace.rules or {}) do results[r.rule]=r end
 local lines={"手选构筑模板：" .. config.template .. "；源条件未验证的规则不执行。",
  "KEEP保留；ADAPT适配；DROP停用；BLOCKED未支持。",
  "待命也评估推荐；技能须通过公开已学、可用、资源、范围、自身冷却。派发另要求战斗，不检测GCD。"}
 for _,list in ipairs({"default","aoe","combustion","2T10","precombat"}) do
  if template.lists[list] then
   lines[#lines+1]="【" .. list .. "】"
   for _,rule in ipairs(template.lists[list]) do
    local result=results[rule.id]; local key=rule.fallback and config.filler~="auto" and config.filler or rule.action
    local name=self.Abilities[key] and self.Abilities[key].name or key
    lines[#lines+1]=rule.id .. " · " .. name .. " · " .. rule.status .. " / " .. (result and result.result or "未评估")
    lines[#lines+1]="原条件：" .. (rule.criteria~="" and rule.criteria or "无") .. "；" .. (result and result.reason or rule.reason)
   end
  end
 end
 return table.concat(lines,"\n")
end
function A:IsActive(e) return TEF.Recommendation:Source(e)=="apl" end
function A:Invalidate(static) self.State:Invalidate(static) end
function A:Refresh(e)
 if not self:IsActive(e) then return end
 -- A current public initiation owns its exact identity until success/failure.
 if TEF.Dispatch:HasCurrentInitiation() or not TEF.Dispatch:CastIdle() then return end
 local now=self.State.Time(); local last=self.State.last
 if now and last and now>=last and now-last<.5 and e.aplSnapshot then return end
 local state,reason=self.State:Sample(e)
 if not self:IsActive(e) then return end
 if not state then
  self:Invalidate(); e.aplCandidate=nil; e.aplSnapshot=nil; e.steps=nil
  self.Trace:Record(e,{},reason,nil,nil); return
 end
 local candidate,why,trace=self:Evaluate(state,e.db.apl,e.classToken)
 local previous=e.steps and e.steps[e.index]
 if (previous and previous.spellID or nil)~=(candidate and candidate.spellID or nil) then
  -- Retire old initiations/requests via the existing lifecycle owner, never
  -- create a second execution state machine or overwrite saved sequences.
  local runtime=TEF.Runtime
  if runtime.e==e then runtime:EngineCall("Reset") else e:Reset() end
 end
 e.steps=candidate and TEF.Engine.Validate({{name=candidate.name or self.Abilities[candidate.action].name,
  spellID=candidate.spellID,matchIDs={candidate.spellID},repeatCount=1}}) or nil
 e.index=1; e.completed=false; e.aplCandidate=candidate
 state.generation=e.generation; state.receiptSerial=e.receiptSerial or 0
 e.aplSnapshot=state; self.State.last=state.sampledAt
 self.Trace:Record(e,trace,why,candidate,state)
 if TEF.HUD and TEF.HUD.engine==e then TEF.HUD:Refresh() end
end
function A:Allowed(e,id)
 if not self:IsActive(e) then return true end
 local s,c=e.aplSnapshot,e.aplCandidate; local now=self.State.Time()
 if not s or not c or c.spellID~=id or s.generation~=e.generation or s.receiptSerial~=(e.receiptSerial or 0)
  or s.revision~=(self.State.revision or 0) or not now or not s.sampledAt or now<s.sampledAt or now-s.sampledAt>1 then
  return false,"APL_STALE_OR_UNKNOWN"
 end
 -- A visible standby candidate never grants input authority, including
 -- explicit Request or manual runtime mode. Recheck public combat here.
 if self.State.Boolean("InCombatLockdown")~=true then return false,"APL_DISPATCH_COMBAT_REQUIRED" end
 -- Re-read the selected action immediately before transport. User-authorized:
 -- no GCD condition or 61304 query in APL selection/dispatch.
 if e.db.apl.template=="custom" then
  local row=self.Custom:Rows(e)[c.customIndex]
  if not row or row.spellID~=id then return false,"APL_RULE_UNKNOWN" end
  local action=self.Custom:Read(id,row.requireReady)
  if row.activity~="any" then local ok,record=TEF.Safety.Call("C_Spell.GetSpellCooldown",id); if ok then action.active=TEF.Safety.Field(record,"isActive","boolean") end end
  local live={combat={in_combat=self.State.Boolean("InCombatLockdown")},actions={[c.action]=action},moving=self.State.Boolean("IsPlayerMoving")}
  if live.combat.in_combat~=true then return false,"APL_DISPATCH_COMBAT_REQUIRED" end
  local isolated={}
  for i=1,c.customIndex do isolated[i]=i==c.customIndex and row or {enabled=false,cdmKind="none"} end
  self.PublicConditions:Sample(live,isolated)
  if row.enemyMin or row.enemyMax then local v=TEF.Research:CountVisible(); if v.state=="PUBLIC_VALUE" then live.enemy_count=v.value end end
  local allowed=self.Custom:Check(live,row,c.customIndex)
  if allowed~=true then return false,"APL_LIVE_DEPENDENCY_BLOCKED" end
  if s.revision~=(self.State.revision or 0) or s.generation~=e.generation or s.receiptSerial~=(e.receiptSerial or 0) then return false,"APL_STALE_OR_UNKNOWN" end
  return true
 end
 local action=self.State:ReadAction(c.action,{known=true,spellID=id,reason="CURRENT_CANDIDATE"})
 action.known=self.State.Boolean("C_SpellBook.IsSpellKnown",id)
 local live={combat={in_combat=self.State.Boolean("InCombatLockdown")},gcd={},
  actions={[c.action]=action},talents=s.talents,enemy_count=s.enemy_count,scene=s.scene,moving=self.State.Boolean("IsPlayerMoving")}
 if live.combat.in_combat~=true then return false,"APL_DISPATCH_COMBAT_REQUIRED" end
 local pack=self.Packs[e.classToken]
 local template=pack and pack.templates[e.db.apl.template]
 if not template then return false,"APL_TEMPLATE_UNKNOWN" end
 for _,rows in pairs(template.lists) do for _,rule in ipairs(rows) do if rule.id==c.rule then
  local allowed,_,key=self:RuleAllowed(live,rule,e.db.apl)
  if allowed~=true or key~=c.action then return false,"APL_LIVE_DEPENDENCY_BLOCKED" end
  if s.revision~=(self.State.revision or 0) or s.generation~=e.generation or s.receiptSerial~=(e.receiptSerial or 0) then return false,"APL_STALE_OR_UNKNOWN" end
  return true
 end end end
 return false,"APL_RULE_UNKNOWN"
end
function A:Configure(e,key,value)
 local raw=self.Clean(e.db.apl)
 if key=="template" then
  if value~="arcane" and value~="fire" and value~="frost" and value~="custom" then return false,"APL_TEMPLATE_INVALID" end
  raw.template=value
 elseif key=="filler" then
  if value~="auto" and value~="fireball" and value~="frostbolt" and value~="scorch" and value~="arcane_missiles" and value~="arcane_blast" then return false,"APL_FILLER_INVALID" end
  raw.filler=value
 elseif key=="aoeThreshold" then raw.aoeThreshold=value
 elseif key=="exactID" then
  if raw.filler=="auto" then return false,"APL_FILLER_SELECTION_REQUIRED" end
  if value~=nil and not TEF.Safety.ID(value) then return false,"APL_EXACT_ID_INVALID" end
  raw.exactIDs[raw.filler]=value
 else raw[key]=value end
 e:Reset(); e.db.apl=self.Clean(raw); self:Invalidate(true)
 if self:IsActive(e) then e.steps=nil end
 return true
end
