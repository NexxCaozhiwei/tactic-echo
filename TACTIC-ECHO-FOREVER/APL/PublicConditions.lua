local _,T=...
local S,P=T.Safety,{}
T.APL.PublicConditions=P
P.ops={any=true,lt=true,le=true,eq=true,ne=true,ge=true,gt=true}
function P.Compare(value,op,threshold)
 if op=="any" then return true end
 if value==nil then return nil end
 if op=="lt" then return value<threshold elseif op=="le" then return value<=threshold
 elseif op=="eq" then return value==threshold elseif op=="ne" then return value~=threshold
 elseif op=="ge" then return value>=threshold elseif op=="gt" then return value>threshold end
 return nil
end
function P.Mana()
 local ok,raw,reason=S.Call("UnitPower","player",0)
 if not ok then return nil,reason end
 local current,why=S.Public(raw,"number"); if current==nil then return nil,why end
 local got,maximum,status=S.Call("UnitPowerMax","player",0)
 if not got then return nil,status end
 local max,classification=S.Public(maximum,"number"); if max==nil then return nil,classification end
 if current<0 or max<=0 or current>max then return nil,"UNKNOWN_NUMBER" end
 local calculated,value=pcall(function() return current/max*100 end)
 if calculated then return S.Public(value,"number") end
 return nil,"UNKNOWN_OPERATION_FAILED"
end
function P.Distance()
 local fn=S.Resolve("UnitDistanceSquared"); if not fn then return nil,"UNAVAILABLE" end
 local ok,raw,checked=pcall(fn,"target"); if not ok then return nil,"CALL_FAILED" end
 local valid,why=S.Public(checked,"boolean"); if valid~=true then return nil,valid==false and "DISTANCE_NOT_CHECKED" or why end
 local squared,status=S.Public(raw,"number"); if squared==nil then return nil,status end
 if squared<0 then return nil,"UNKNOWN_NUMBER" end
 local calculated,value=pcall(math.sqrt,squared)
 if calculated then return S.Public(value,"number") end
 return nil,"UNKNOWN_OPERATION_FAILED"
end
local categories={
 {kind="cooldown",value=0,viewer="EssentialCooldownViewer"},
 {kind="cooldown",value=1,viewer="UtilityCooldownViewer"},
 {kind="buff",value=2,viewer="BuffIconCooldownViewer"},
 {kind="buff",value=3,viewer="BuffBarCooldownViewer"}}
local function key(kind,id) return kind .. ":" .. id end
function P.CDM(rows)
 local requests,needed,out,skipped={},{},{},{}
 for _,row in ipairs(rows) do
  if row.enabled and not row.invalid and row.cdmKind and row.cdmKind~="none" then
   local id=row.cdmSpellID or row.spellID; local k=key(row.cdmKind,id)
   requests[k]=id; needed[row.cdmKind]=true; out[k]={reason="CDM_FRAME_MISSING"}
  end
 end
 for _,cat in ipairs(categories) do if needed[cat.kind] then
  local ok,list=S.Call("C_CooldownViewer.GetCooldownViewerCategorySet",cat.value,true)
  list=ok and S.Public(list,"table")
  local mappings,bad={},nil
  local measured,size=pcall(function() return list and #list end)
  if not measured or not size then bad="CDM_CATALOG_UNKNOWN"
  elseif size>128 then bad="CDM_CAPACITY"
  else
   for i=1,size do
    local id=S.ID(S.Field(list,i,"number"))
    if not id then bad="CDM_CATALOG_UNKNOWN"; break end
    local got,info=S.Call("C_CooldownViewer.GetCooldownViewerCooldownInfo",id)
    local record=got and S.Public(info,"table")
    if not record then bad="CDM_MAPPING_UNKNOWN"; break end
    local raw,why=S.Field(record,"spellID","number")
    local spell=raw and S.ID(raw)
    -- Official spellID is nilable (for example an equipment entry). A
    -- public missing spellID cannot be a direct spell identity. Secret or
    -- malformed identity remains unknown, never a proxy match.
    if not spell and why~="NO_DATA" then bad="CDM_MAPPING_UNKNOWN"; break end
    -- Exact directory spellID only; overrides/linked spells are not identity.
    if spell and requests[key(cat.kind,spell)] then mappings[id]=key(cat.kind,spell) end
   end
  end
  local viewer=S.Field(_G,cat.viewer,"table")
  local pool=viewer and S.Field(viewer,"itemFramePool","table")
  local enumerate=pool and S.Field(pool,"EnumerateActive","function")
  if not bad and enumerate then
   local got,iterator,state,var=pcall(enumerate,pool)
   iterator=got and S.Public(iterator,"function")
   if not iterator then bad="CDM_ENUMERATION_UNKNOWN"
   else
    for i=1,81 do
     local nextOK,raw=pcall(iterator,state,var)
     if not nextOK then bad="CDM_ENUMERATION_FAILED"; break end
     local frame,why=S.Public(raw,"table")
     if why=="NO_DATA" then break end
     if not frame then bad="CDM_FRAME_UNKNOWN"; break end
     if i>80 then bad="CDM_CAPACITY"; break end
     var=frame
     local id=S.ID(S.Field(frame,"cooldownID","number"))
     if not id then
      local get=S.Field(frame,"GetCooldownID","function")
      if get then local read,value=pcall(get,frame); if read then id=S.ID(value) end end
     end
     -- An unidentified frame has no proven relation to any requested spell.
     -- Keep scanning; it must neither supply INACTIVE nor erase exact matches.
     if not id then skipped[cat.kind]=(skipped[cat.kind] or 0)+1 end
     local k=id and mappings[id]
     if k then
      local active,classification=S.Field(frame,"isActive","boolean")
      local old=out[k]
      if active==nil then out[k]={reason=classification or "CDM_ACTIVE_UNKNOWN",uncertain=true}
      elseif old.uncertain or (old.value~=nil and old.value~=active) then out[k]={reason="CDM_CONFLICT",uncertain=true}
      else out[k]={value=active,reason="PUBLIC"} end
     end
    end
   end
  elseif not bad then bad="CDM_VIEWER_UNAVAILABLE" end
  if bad then for k in pairs(requests) do if k:match("^" .. cat.kind .. ":") then out[k]={reason=bad,uncertain=true} end end end
 end end
 for k in pairs(requests) do
  local kind=k:match("^([a-z]+):")
  local count=skipped[kind]
  if count then
   out[k].scanReason="CDM_FRAME_ID_UNKNOWN"; out[k].skippedFrames=count
   if out[k].reason=="CDM_FRAME_MISSING" then out[k].reason="CDM_FRAME_ID_UNKNOWN" end
  end
 end
 return out
end
function P:Sample(state,rows)
 local mana,distance=false,false
 for _,r in ipairs(rows) do if r.enabled and not r.invalid then
  mana=mana or (r.manaOp and r.manaOp~="any")
  distance=distance or (r.distanceOp and r.distanceOp~="any")
 end end
 if mana then state.manaPercent,state.manaReason=self.Mana() end
 if distance then state.distance,state.distanceReason=self.Distance() end
 local cdm=self.CDM(rows)
 for i,row in ipairs(rows) do
  if row.cdmKind and row.cdmKind~="none" then
   local v=cdm[key(row.cdmKind,row.cdmSpellID or row.spellID)]
   local a=state.actions["custom_" .. i]
   if a and v then
    a.cdmActive,a.cdmReason=v.value,v.reason
    a.cdmScanReason,a.cdmSkippedFrames=v.scanReason,v.skippedFrames
   end
  end
 end
end
