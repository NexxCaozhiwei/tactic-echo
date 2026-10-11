local _,TEF=...
local A,S=TEF.APL,TEF.Safety
A.Packs={}; A.CatalogByID={}
-- Preserve every supplied candidate, including Infinite additions. Unknown
-- semantics are visible in the database, never enabled as a DPS rule.
for _,row in ipairs(A.Catalog) do
 local key=A.AbilityNames[row.name] or A.TalentNames[row.name]
 if not key then key="catalog_" .. row.id end
 if not A.Abilities[key] then
  A.Abilities[key]={key=key,name=row.name,type="unclassified",unsupported="CATALOG_SEMANTICS_UNVERIFIED"}
 end
 A.AbilityNames[row.name]=key; A.CatalogByID[row.id]={key=key,rank=row.rank,learnLevel=row.learnLevel}
 local a=A.Abilities[key]; a.candidates=a.candidates or {}; a.candidates[#a.candidates+1]=row.id
end
function A.Clean(raw)
 local filler=S.Field(raw,"filler","string")
 local fillers={auto=true,fireball=true,frostbolt=true,scorch=true,arcane_missiles=true,arcane_blast=true}
 local template=S.Field(raw,"template","string")
 if template~="arcane" and template~="fire" and template~="frost" and template~="custom" then
  template=filler=="frostbolt" and "frost" or filler=="arcane_blast" and "arcane" or "fire"
 end
 local threshold=S.Field(raw,"aoeThreshold","number")
 local ids={}; local saved=S.Field(raw,"exactIDs","table")
 for key in pairs(A.Abilities) do
  local id=saved and S.ID(S.Field(saved,key,"number")); if id then ids[key]=id end
 end
 return {schema=3,custom=A.Custom.CleanProfiles(S.Field(raw,"custom","table")),template=template,filler=fillers[filler] and filler or "auto",exactIDs=ids,
  aoeThreshold=threshold and threshold>=2 and threshold<=40 and threshold%1==0 and threshold or 3,
  arcane_power=S.Field(raw,"arcane_power","boolean")==true,
  presence_of_mind=S.Field(raw,"presence_of_mind","boolean")==true,
  pyroblast=S.Field(raw,"pyroblast","boolean")==true,
  fire_blast=S.Field(raw,"fire_blast","boolean")==true,
  arcane_explosion=S.Field(raw,"arcane_explosion","boolean")==true}
end
function A:Register(pack)
 assert(pack.class and not pack.spec and pack.id=="MAGE_FOREVER_60")
 self.Packs[pack.class]=pack
end
