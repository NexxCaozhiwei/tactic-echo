local _,T,F=...
local P,C=T.APL.PublicConditions,T.APL.Custom
local n=0
local saved={}; for _,k in ipairs({"UnitPower","UnitPowerMax","UnitDistanceSquared","C_CooldownViewer","EssentialCooldownViewer","UtilityCooldownViewer","BuffIconCooldownViewer","BuffBarCooldownViewer"}) do saved[k]={_G[k]} end
local function eq(a,b) assert(a==b,"conditions expected " .. tostring(b) .. " got " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function row(id) return C.CleanRows({{spellID=id,enabled=true,moving="any",activity="any"}})[1] end
local function state(rows)
 local s={combat={in_combat=true},actions={},scene="single",moving=false,manaPercent=15,distance=19}
 for i,r in ipairs(rows) do s.actions["custom_" .. i]={spellID=r.spellID,name="技能",known=true,usable=true,power_ok=true,in_range=true,ready=true,cdmActive=false} end
 return s
end
local function fixtures(active)
 C_CooldownViewer={GetCooldownViewerCategorySet=function(category) return category==2 and {10} or {} end,
 GetCooldownViewerCooldownInfo=function() return {spellID=133} end}
 local frame={cooldownID=10,isActive=active}
 local function pool(frames) return {EnumerateActive=function() local i=0; return function() i=i+1; return frames[i] end end} end
 BuffIconCooldownViewer={itemFramePool=pool({frame})}; BuffBarCooldownViewer={itemFramePool=pool({})}
 return frame,pool
end
test("numeric_operators_boundaries_unknown",function()
 for _,op in ipairs({"lt","le","eq","ne","ge","gt"}) do eq(P.Compare(nil,op,20),nil) end
 eq(P.Compare(20,"lt",20),false); eq(P.Compare(20,"le",20),true); eq(P.Compare(20,"eq",20),true)
 eq(P.Compare(20,"ne",20),false); eq(P.Compare(20,"ge",20),true); eq(P.Compare(20,"gt",20),false)
 eq(P.Compare(19.99,"lt",20),true); eq(P.Compare(20.01,"gt",20),true)
end)
test("mana_percent_public_only_and_no_max_zero",function()
 UnitPower=function(unit,kind) eq(unit,"player"); eq(kind,0); return 150 end
 UnitPowerMax=function() return 1000 end; eq(P.Mana(),15)
 UnitPowerMax=function() return 0 end; eq(P.Mana(),nil)
 UnitPowerMax=function() return F.secret end; eq(P.Mana(),nil)
 UnitPower=function() return F.secret end; eq(P.Mana(),nil)
 UnitPower=function() error("PRIVATE_ERROR") end; local _,why=P.Mana(); eq(why,"CALL_FAILED")
end)
test("distance_requires_checked_and_public_squared",function()
 UnitDistanceSquared=function(unit) eq(unit,"target"); return 400,true end; eq(P.Distance(),20)
 UnitDistanceSquared=function() return 400,false end; eq(P.Distance(),nil)
 UnitDistanceSquared=function() return F.secret,true end; eq(P.Distance(),nil)
 UnitDistanceSquared=function() return 400,F.secret end; eq(P.Distance(),nil)
 UnitDistanceSquared=nil; local _,why=P.Distance(); eq(why,"UNAVAILABLE")
end)
test("cdm_exact_directory_false_and_true",function()
 local r=row(143); r.cdmKind="buff"; r.cdmSpellID=133
 fixtures(false); eq(P.CDM({r})["buff:133"].value,false)
 C_CooldownViewer.GetCooldownViewerCategorySet=function(category) return category==2 and {10,12} or {} end
 C_CooldownViewer.GetCooldownViewerCooldownInfo=function(id) return id==10 and {spellID=133} or {equipSlot=13} end
 eq(P.CDM({r})["buff:133"].value,false)
 fixtures(true); eq(P.CDM({r})["buff:133"].value,true)
end)
test("cdm_missing_secret_linked_never_inactive",function()
 local r=row(143); r.cdmKind="buff"; r.cdmSpellID=133
 fixtures(F.secret); eq(P.CDM({r})["buff:133"].value,nil)
 fixtures(false); C_CooldownViewer.GetCooldownViewerCooldownInfo=function() return {spellID=999,linkedSpellIDs={133}} end
 eq(P.CDM({r})["buff:133"].value,nil)
 BuffIconCooldownViewer=nil; eq(P.CDM({r})["buff:133"].value,nil)
end)
test("cdm_capacity_failure_conflict_block",function()
 local r=row(143); r.cdmKind="buff"; r.cdmSpellID=133
 local _,pool=fixtures(false)
 BuffIconCooldownViewer.itemFramePool=pool({{cooldownID=10,isActive=false},{cooldownID=10,isActive=true}})
 eq(P.CDM({r})["buff:133"].value,nil)
 fixtures(false); BuffBarCooldownViewer.itemFramePool.EnumerateActive=function() error("RAW_FAILURE") end
 eq(P.CDM({r})["buff:133"].value,nil)
 fixtures(false); C_CooldownViewer.GetCooldownViewerCategorySet=function() local ids={}; for i=1,129 do ids[i]=i end; return ids end
 eq(P.CDM({r})["buff:133"].reason,"CDM_CAPACITY")
end)
test("cdm_unidentified_frames_before_after_preserve_public_false",function()
 local r=row(143); r.cdmKind="buff"; r.cdmSpellID=133
 local frame,pool=fixtures(false)
 BuffIconCooldownViewer.itemFramePool=pool({{},frame,{cooldownID=99,isActive=true},{}})
 local v=P.CDM({r})["buff:133"]
 eq(v.value,false); eq(v.reason,"PUBLIC"); eq(v.scanReason,"CDM_FRAME_ID_UNKNOWN"); eq(v.skippedFrames,2)
 frame.isActive=true; eq(P.CDM({r})["buff:133"].value,true)
end)
test("cdm_secret_id_failed_getter_and_public_getter_continue",function()
 local r=row(143); r.cdmKind="buff"; r.cdmSpellID=133
 local _,pool=fixtures(false)
 local unknown={cooldownID=F.secret,GetCooldownID=function() error("PRIVATE_ERROR") end}
 local secret={GetCooldownID=function() return F.secret end}
 local good={GetCooldownID=function() return 10 end,isActive=true}
 BuffIconCooldownViewer.itemFramePool=pool({unknown,secret,good})
 local v=P.CDM({r})["buff:133"]; eq(v.value,true); eq(v.skippedFrames,2)
end)
test("cdm_missing_request_stays_unknown_while_other_exact_match_survives",function()
 local r,row2=row(143),row(205); r.cdmKind="buff"; r.cdmSpellID=133; row2.cdmKind="buff"; row2.cdmSpellID=116
 local frame,pool=fixtures(false)
 C_CooldownViewer.GetCooldownViewerCategorySet=function(category) return category==2 and {10,11} or {} end
 C_CooldownViewer.GetCooldownViewerCooldownInfo=function(id) return {spellID=id==10 and 133 or 116} end
 BuffIconCooldownViewer.itemFramePool=pool({{},frame})
 local values=P.CDM({r,row2}); eq(values["buff:133"].value,false); eq(values["buff:116"].value,nil)
 eq(values["buff:116"].reason,"CDM_FRAME_ID_UNKNOWN")
 local s=state({r,row2}); P:Sample(s,{r,row2}); eq(s.actions.custom_1.cdmActive,false); eq(s.actions.custom_2.cdmActive,nil)
 eq(s.actions.custom_1.cdmSkippedFrames,1)
end)
test("cdm_unknown_frames_do_not_hide_exact_conflict_or_secret_state",function()
 local r=row(143); r.cdmKind="buff"; r.cdmSpellID=133
 local _,pool=fixtures(false)
 BuffIconCooldownViewer.itemFramePool=pool({{},{cooldownID=10,isActive=false},{},{cooldownID=10,isActive=true}})
 local v=P.CDM({r})["buff:133"]; eq(v.value,nil); eq(v.reason,"CDM_CONFLICT")
 BuffIconCooldownViewer.itemFramePool=pool({{},{cooldownID=10,isActive=F.secret},{cooldownID=10,isActive=false}})
 eq(P.CDM({r})["buff:133"].value,nil)
 local frames={{cooldownID=10,isActive=false}}; for i=2,81 do frames[i]={} end
 BuffIconCooldownViewer.itemFramePool=pool(frames); eq(P.CDM({r})["buff:133"].reason,"CDM_CAPACITY")
end)
test("cdm_scan_diagnostics_clean_and_ledger",function()
 local raw={reason="APL_NO_PUBLIC_ELIGIBLE_RULE",actions={custom_1={cdmActive=false,cdmScanReason="CDM_FRAME_ID_UNKNOWN",cdmSkippedFrames=2}}}
 local clean=T.APL.Trace.Clean(raw); eq(clean.actions.custom_1.cdmSkippedFrames,2); eq(clean.actions.custom_1.cdmActive,false)
 raw.actions.custom_1.cdmSkippedFrames=F.secret; raw.actions.custom_1.cdmScanReason="PRIVATE_ERROR"
 clean=T.APL.Trace.Clean(raw); eq(clean.actions.custom_1.cdmSkippedFrames,nil); eq(clean.actions.custom_1.cdmScanReason,nil)
 local e=F.runtime(); e.db.apl.custom.MAGE={single={row(143)}}
 e.aplSnapshot=state({row(143)}); e.aplSnapshot.actions.custom_1.cdmScanReason="CDM_FRAME_ID_UNKNOWN"; e.aplSnapshot.actions.custom_1.cdmSkippedFrames=2
 assert(C:Ledger(e):find("跳过身份未知帧 2",1,true))
end)
test("user_examples_numeric_cdm_and_moving",function()
 local rows={row(2136),row(5019),row(205),row(143)}
 rows[1].distanceOp,rows[1].distanceValue,rows[1].moving="lt",20,"yes"
 rows[1].cdmKind="cooldown"
 rows[2].manaOp,rows[2].manaValue,rows[2].moving="lt",20,"no"
 rows[3].distanceOp,rows[3].distanceValue,rows[3].cdmKind,rows[3].cdmSpellID="lt",30,"buff",116
 rows[4].distanceOp,rows[4].distanceValue,rows[4].cdmKind,rows[4].cdmSpellID="lt",35,"buff",133
 local s=state(rows); s.moving=true
 local config={custom={MAGE={single=rows}}}
 eq(C:Evaluate(s,config,"MAGE").spellID,2136)
 s.moving=false; eq(C:Evaluate(s,config,"MAGE").spellID,5019)
 s.manaPercent=60; eq(C:Evaluate(s,config,"MAGE").spellID,205)
 s.actions.custom_3.cdmActive=true; eq(C:Evaluate(s,config,"MAGE").spellID,143)
 s.distance=36; eq(C:Evaluate(s,config,"MAGE"),nil)
 s.distance=nil; eq(C:Evaluate(s,config,"MAGE"),nil)
end)
test("config_numeric_invalid_and_secret_preserved_blocked",function()
 local r=row(143); r.manaOp="lt"; r.manaValue=101; assert(C.CleanRows({r})[1].invalid)
 r.manaValue=20; r.distanceOp="lt"; r.distanceValue=F.secret; assert(C.CleanRows({r})[1].invalid)
 r.distanceValue=20; r.cdmKind="buff"; r.cdmSpellID=133; eq(C.CleanRows({r})[1].invalid,nil)
 r.distanceOp="execute"; assert(C.CleanRows({r})[1].invalid)
end)
test("shoot_exact_known_metadata_and_range_fallback",function()
 local e=F.runtime(); local old=C_Spell.GetSpellInfo; C_Spell.GetSpellInfo=function(id) if id==5019 then return {name="射击"} end; return old(id) end
 local a=C:Read(5019); eq(a.spellID,5019); eq(a.name,"射击"); eq(a.target,"enemy"); eq(a.reason,"CUSTOM_EXACT_ID")
 C_Spell.GetSpellInfo=old
end)
test("live_distance_and_mana_changes_revoke_packet",function()
 local e=F.runtime(); local r=row(143); r.distanceOp,r.distanceValue="lt",20
 UnitDistanceSquared=function() return 100,true end
 C:Save(e,{r},"single","MAGE"); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 UnitDistanceSquared=function() return 900,true end; eq(T.Dispatch:Packet(),nil)
 local r2=row(143); r2.manaOp,r2.manaValue="lt",20
 UnitPower=function() return 10 end; UnitPowerMax=function() return 100 end
 C:Save(e,{r2},"single","MAGE"); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 UnitPower=function() return F.secret end; eq(T.Dispatch:Packet(),nil)
 local r3=row(143); r3.cdmKind="buff"; r3.cdmSpellID=133
 local frame,pool=fixtures(false)
 BuffIconCooldownViewer.itemFramePool=pool({{},frame,{}})
 C:Save(e,{r3},"single","MAGE"); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 frame.isActive=true; eq(T.Dispatch:Packet(),nil)
end)
test("diagnostics_clean_public_new_conditions",function()
 local clean=T.APL.Trace.Clean({reason="APL_NO_PUBLIC_ELIGIBLE_RULE",manaPercent=15,distance=19,manaReason="PUBLIC",distanceReason="PUBLIC",actions={custom_1={cdmActive=false,cdmReason="PUBLIC"}}})
 eq(clean.manaPercent,15); eq(clean.distance,19); eq(clean.actions.custom_1.cdmActive,false)
 local hidden=T.APL.Trace.Clean({reason="APL_NO_PUBLIC_ELIGIBLE_RULE",manaPercent=F.secret,distance=F.secret,actions={custom_1={cdmActive=F.secret}}})
 eq(hidden.manaPercent,nil); eq(hidden.distance,nil); eq(hidden.actions.custom_1.cdmActive,nil)
end)
test("click_pickup_and_drag_both_add_no_duplicates_after_clear",function()
 local e=F.runtime(); T.UI:ShowPage("customapl"); T.UI.customDraft={}; T.UI.customSelected=1; T.UI.customFormIndex=nil; T.UI:RefreshCustomAPL()
 local cursor,clear=GetCursorInfo,ClearCursor; local held=true
 GetCursorInfo=function() if held then return "spell",1,"spell",143 end end
 ClearCursor=function() held=false end
 T.UI.customDrop.scripts.OnClick(); eq(#T.UI.customDraft,1)
 T.UI.customDrop.scripts.OnReceiveDrag(); eq(#T.UI.customDraft,1)
 held=true; T.UI.customDrop.scripts.OnReceiveDrag(); eq(#T.UI.customDraft,2)
 local r=T.UI:CustomRow(); r.manaOp="lt"; r.distanceOp="lt"; r.cdmKind="buff"
 T.UI.customNumbers.manaValue.text="20"; T.UI.customNumbers.distanceValue.text="30"; T.UI.customNumbers.cdmSpellID.text="116"
 T.UI.customSave.scripts.OnClick()
 local savedRow=C:Rows(e)[2]; eq(savedRow.manaOp,"lt"); eq(savedRow.manaValue,20); eq(savedRow.distanceValue,30); eq(savedRow.cdmSpellID,116)
 local action=GetActionInfo
 GetCursorInfo=function() return "action",7 end; GetActionInfo=function(slot) eq(slot,7); return "spell",205 end
 T.UI.customDrop.scripts.OnClick(); eq(#T.UI.customDraft,3); eq(T.UI.customDraft[3].spellID,205)
 GetActionInfo=function() return "macro",205 end; T.UI.customDrop.scripts.OnClick(); eq(#T.UI.customDraft,3)
 GetActionInfo=action
 GetCursorInfo,ClearCursor=cursor,clear
end)
for key,value in pairs(saved) do _G[key]=value[1] end
TEF_PUBLIC_CONDITION_TEST_COUNT=n
return n
