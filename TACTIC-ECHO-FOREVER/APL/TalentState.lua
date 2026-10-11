local _,TEF=...
local A,S=TEF.APL,TEF.Safety
local P={}; A.TalentState=P
local function integer(value,max)
 local n=S.Public(value,"number"); if n and n>=0 and n<=max and n%1==0 then return n end
end
local function put(out,key,rank,max,id)
 if not key or rank==nil or not max or max<1 or rank>max then return end
 if out[key].observed then out[key]={status="UNKNOWN",reason="AMBIGUOUS_TALENT",observed=true}; return end
 out[key]={status=rank>0 and "KNOWN" or "NOT_KNOWN",known=rank>0,rank=rank,maxRank=max,spellID=id,observed=true}
end
local function signature(out)
 local build={}
 for _,tree in ipairs({"ARCANE","FIRE","FROST"}) do
  local sum,complete=0,true
  for key,t in pairs(A.Talents) do if t.tree==tree then
   if out[key].rank==nil then complete=false else sum=sum+out[key].rank end
  end end
  if complete then build[tree]=sum end
 end
 return build
end
function P:Read()
 local out,build={},{}
 for key in pairs(A.Talents) do out[key]={status="UNKNOWN",reason="TALENT_UNRESOLVED"} end
 -- Legacy provider accepts only the rank-bearing signature. Modern row /
 -- column GetTalentInfo is never substituted for these tree APIs.
 local tabsOK,tabs=S.Call("GetNumTalentTabs"); tabs=tabsOK and integer(tabs,3)
 local infoFn=S.Resolve("GetTalentInfo")
 if tabs and tabs>0 and infoFn then
  local totals={}
  for tab=1,tabs do
   local total,complete,tree=0,true,nil
   local nOK,n=S.Call("GetNumTalents",tab); n=nOK and integer(n,32)
   if n then for index=1,n do
    local ok,name,_,_,_,rank,max=pcall(infoFn,tab,index)
    name=ok and S.Public(name,"string")
    local key=name and A.TalentNames[name]
    local actual,maximum=ok and integer(rank,10),ok and integer(max,10)
    if actual==nil or maximum==nil or actual>maximum then complete=false else total=total+actual end
    if key then
     local observedTree=A.Talents[key].tree
     if tree and tree~=observedTree then complete=false else tree=observedTree end
    end
    put(out,key,actual,maximum)
   end end
   if n and n>0 and complete and tree then
    if totals[tree]~=nil then totals[tree]=false else totals[tree]=total end
   end
  end
  -- Sum only completely observed registered trees. Unknown entries never count
  -- as zero, and these numbers are diagnostic, not an APL selector.
  local measured={}
  for tree,total in pairs(totals) do if type(total)=="number" then measured[tree]=total end end
  return out,measured,"LEGACY_RANK_SIGNATURE"
 end
 -- Generated 70338 trait API, bounded by three trees and 128 nodes total.
 local ok,config=S.Call("C_ClassTalents.GetActiveConfigID"); config=ok and S.ID(config)
 if not config then return out,build,"TALENT_API_UNAVAILABLE" end
 local got,record=S.Call("C_Traits.GetConfigInfo",config)
 local trees=got and S.Field(record,"treeIDs","table")
 if not trees then return out,build,"TALENT_TREES_UNKNOWN" end
 local measured,size=pcall(function() return #trees end)
 if not measured or size>3 then return out,build,"TALENT_CAPACITY_UNKNOWN" end
 local budget,seen=0,{}
 for i=1,size do
  local read,raw=pcall(function() return trees[i] end); local tree=read and S.ID(raw)
  local called,nodes=S.Call("C_Traits.GetTreeNodes",tree)
  nodes=called and S.Public(nodes,"table")
  local valid,count=pcall(function() return #nodes end)
  if tree and nodes and valid and count<=128 then for j=1,count do
   budget=budget+1; if budget>128 then break end
   local r,v=pcall(function() return nodes[j] end); local node=r and S.ID(v)
   if node and not seen[node] then
    seen[node]=true
    local nodeOK,ni=S.Call("C_Traits.GetNodeInfo",config,node)
    if not nodeOK or S.ID(S.Field(ni,"ID","number"))~=node then ni=nil; nodeOK=false end
    local rank=nodeOK and integer(S.Field(ni,"activeRank","number"),10)
    local max=nodeOK and integer(S.Field(ni,"maxRanks","number"),10)
    local entries=nodeOK and S.Field(ni,"entryIDs","table")
    local m,length=pcall(function() return #entries end)
    -- Choice nodes cannot certify the unselected ability from aggregate rank.
    if entries and m and length==1 then
     local er,ev=pcall(function() return entries[1] end); local entry=er and S.ID(ev)
     local eOK,ei=S.Call("C_Traits.GetEntryInfo",config,entry)
     local def=eOK and S.ID(S.Field(ei,"definitionID","number"))
     local dOK,di=S.Call("C_Traits.GetDefinitionInfo",def)
     local spell=dOK and S.ID(S.Field(di,"spellID","number"))
     local sOK,si=S.Call("C_Spell.GetSpellInfo",spell)
     local name=sOK and S.Field(si,"name","string")
     local key=name and A.TalentNames[name]
     -- Imported node/SpellID data is only corroboration. The current config's
     -- tree membership, public node ID, actual rank and definition all agree.
     if key and A.Talents[key].nodeID==node and A.Talents[key].spellID==spell then put(out,key,rank,max,spell) end
    end
   end
  end end
 end
 local again,value=S.Call("C_ClassTalents.GetActiveConfigID")
 if not again or S.ID(value)~=config then
  for key in pairs(out) do out[key]={status="UNKNOWN",reason="TALENT_CONFIG_CHANGED"} end
 end
 return out,signature(out),"TRAITS_BOUNDED_SIGNATURE"
end
