local _,TEF=...
local C={}; TEF.APL.Conditions=C
-- nil is UNKNOWN. Conditions consume only provider-normalized Lua values.
function C:One(state,term,config)
 local op=term.op; local value
 if op=="combat" then value=state.combat.in_combat
 elseif op=="moving" then value=state.moving
 elseif op=="scene" then value=state.scene
 elseif op=="gcd" then value=state.gcd.ready
 elseif op=="action" then local a=state.actions[term.key]; value=a and a[term.field]
 elseif op=="talent_known" then local t=state.talents[term.key]; if t then value=t.known end
 elseif op=="talent_rank" then
  local t=state.talents[term.key]; if not t or t.rank==nil then return nil end
  return t.rank>=term.min
 elseif op=="enemy_count" then
  if state.enemy_count==nil then return nil end
  return state.enemy_count>=(term.min or config.aoeThreshold)
 elseif op=="config" then value=config[term.key]
 elseif op=="filler" then return config.filler==term.key
 else return nil end
 if value==nil then return nil end
 if term.equals~=nil then return value==term.equals end
 return value==true
end
function C:All(state,terms,config)
 local unknown
 for _,term in ipairs(terms) do
  local result=self:One(state,term,config)
  if result==false then return false,term.op .. ":" .. (term.key or term.field or "") .. (term.op=="action" and ":" .. term.field or "") end
  if result==nil and not unknown then unknown="UNKNOWN:" .. term.op .. ":" .. (term.key or "") .. ":" .. (term.field or "") end
 end
 if unknown then return nil,unknown end
 return true,"CONDITIONS_TRUE"
end
