local _,T,F=...
local A=T.APL
local n=0
local function eq(a,b) assert(a==b,"APL expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function state()
 local s={combat={in_combat=true},gcd={ready=true},actions={},talents={},enemy_count=4,scene="single",buildSignature={}}
 for _,key in ipairs(A.RuleActions) do
  s.actions[key]={known=false,spellID=key=="fireball" and 143 or key=="frostbolt" and 205 or key=="pyroblast" and 11366 or key=="arcane_power" and 12042 or key=="presence_of_mind" and 12043 or 5143,usable=true,in_range=true,power_ok=true,ready=true}
 end
 for key in pairs(A.Talents) do s.talents[key]={status="UNKNOWN"} end
 return s
end
local function config() local c=A.Clean(nil); c.filler="fireball"; return c end
local function talent(s,key,rank) s.talents[key]={known=rank>0,rank=rank,status=rank>0 and "KNOWN" or "NOT_KNOWN"} end
local function evaluate(s,c) return A:Evaluate(s,c or config(),"MAGE") end
test("apl_pack_registry_loads_mage_60",function() eq(A.Packs.MAGE.id,"MAGE_FOREVER_60"); eq(#A.Catalog,272); local count=0; for _ in pairs(A.Talents) do count=count+1 end; eq(count,54) end)
test("mage_pack_has_no_modern_spec_dependency",function() eq(A.Packs.MAGE.spec,nil); eq(A.Packs.MAGE.levelCap,60); eq(A.Packs.MAGE_FROST,nil); eq(A.Packs.MAGE_FIRE,nil); eq(A.Packs.MAGE_ARCANE,nil) end)
test("mage_rule_skips_unknown_spell",function() local s=state(); s.actions.fireball.known=nil; eq(evaluate(s),nil) end)
test("mage_rule_skips_unlearned_spell",function() eq(evaluate(state()),nil) end)
test("mage_rule_enables_learned_spell",function() local s=state(); s.actions.fireball.known=true; eq(evaluate(s).spellID,143) end)
test("mage_talent_rank_condition_true",function() local s=state(); talent(s,"improved_scorch",3); eq(A.Conditions:One(s,{op="talent_rank",key="improved_scorch",min=3},config()),true) end)
test("mage_talent_rank_condition_false",function() local s=state(); talent(s,"improved_scorch",2); eq(A.Conditions:One(s,{op="talent_rank",key="improved_scorch",min=3},config()),false) end)
test("mage_talent_unknown_fail_closed",function() local s=state(); eq(A.Conditions:One(s,{op="talent_rank",key="improved_scorch",min=1},config()),nil) end)
test("mage_pyroblast_rule_requires_actual_availability",function()
 local s,c=state(),config(); c.pyroblast=true; s.actions.pyroblast.known=true; talent(s,"pyroblast",1)
 for _,field in ipairs({"usable","ready","in_range","power_ok"}) do s.actions.pyroblast[field]=nil; eq(evaluate(s,c),nil); s.actions.pyroblast[field]=true end
 eq(evaluate(s,c),nil)
end)
for _,key in ipairs({"presence_of_mind","arcane_power"}) do
 test("mage_" .. key .. "_rule_requires_talent",function()
  local s,c=state(),config(); c.template="arcane"; s.scene=key=="presence_of_mind" and "multi" or "single"; c[key]=true; s.actions[key].known=true; eq(evaluate(s,c),nil)
  talent(s,key,0); eq(evaluate(s,c),nil); talent(s,key,1); eq(evaluate(s,c).action,key)
 end)
end
test("mage_mixed_talent_does_not_erase_proc_condition",function() local s,c=state(),config(); c.presence_of_mind=true; c.pyroblast=true; talent(s,"presence_of_mind",1); talent(s,"pyroblast",1); s.actions.presence_of_mind.known=true; s.actions.pyroblast.known=true; eq(evaluate(s,c),nil) end)
test("mage_no_single_spec_required",function() local s=state(); s.spec=nil; s.actions.fireball.known=true; eq(evaluate(s).action,"fireball") end)
test("mage_build_signature_is_diagnostic_only",function() local s=state(); s.actions.fireball.known=true; s.buildSignature={ARCANE=0,FIRE=0,FROST=51}; eq(evaluate(s).action,"fireball"); s.buildSignature={ARCANE=21,FIRE=30,FROST=0}; eq(evaluate(s).action,"fireball") end)
test("mage_pack_does_not_branch_on_build_label",function() local s=state(); s.actions.fireball.known=true; s.buildLabel="frost_heavy"; eq(evaluate(s).action,"fireball"); s.buildLabel="arcane_fire"; eq(evaluate(s).action,"fireball") end)
test("mage_preferred_filler_manual_override",function() local s,c=state(),config(); s.actions.fireball.known=true; s.actions.frostbolt.known=true; c.filler="frostbolt"; eq(evaluate(s,c).spellID,205) end)
test("mage_preferred_filler_unlearned_fails_safe",function() local s,c=state(),config(); s.actions.fireball.known=true; c.filler="frostbolt"; eq(evaluate(s,c),nil) end)
test("mage_template_filler_is_explicit_source_default",function() local s,c=state(),config(); s.actions.fireball.known=true; c.filler="auto"; eq(evaluate(s,c).action,"fireball") end)
test("preview_has_no_combat_or_gcd_condition_own_cd_remains",function() local s=state(); s.actions.fireball.known=true; s.gcd.ready=nil; eq(evaluate(s).action,"fireball"); s.gcd.ready=false; eq(evaluate(s).action,"fireball"); s.actions.fireball.ready=nil; eq(evaluate(s),nil); s.actions.fireball.ready=true; s.combat.in_combat=nil; eq(evaluate(s).action,"fireball"); s.combat.in_combat=false; eq(evaluate(s).action,"fireball") end)
test("aoe_source_radius_condition_not_removed",function() local s,c=state(),config(); c.template="arcane"; s.scene="multi"; c.arcane_explosion=true; s.actions.arcane_explosion.known=true; eq(evaluate(s,c),nil) end)
test("tri_value_false_dominates_unknown",function() local s=state(); s.actions.fireball.known=nil; s.actions.fireball.usable=false; eq(A.Conditions:All(s,{{op="action",key="fireball",field="known"},{op="action",key="fireball",field="usable"}},config()),false) end)
test("unsupported_class_never_uses_mage",function() local chosen,why=A:Evaluate(state(),config(),"WARRIOR"); eq(chosen,nil); eq(why,"APL_CLASS_UNSUPPORTED") end)

-- Independent provider fixtures: every fake value is explicitly synthetic.
local saved={C_Spell=C_Spell,C_SpellBook=C_SpellBook,Enum=Enum,GetTime=GetTime,UnitClass=UnitClass,
 InCombatLockdown=InCombatLockdown,GetNumTalentTabs=GetNumTalentTabs,GetNumTalents=GetNumTalents,GetTalentInfo=GetTalentInfo,
 C_ClassTalents=C_ClassTalents,C_Traits=C_Traits,issecretvalue=issecretvalue}
local originalDetector=issecretvalue
local secret=setmetatable({}, {__index=function() error("TOUCHED_SECRET") end,__tostring=function() error("TOUCHED_SECRET") end})
issecretvalue=function(v) return rawequal(v,secret) end
Enum={SpellBookSpellBank={Player=0},SpellBookItemType={Spell=1}}
local function book(rows)
 C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,
  GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=#rows} end,
  GetSpellBookItemInfo=function(i) local r=rows[i]; return {spellID=r[1],name=r[2],itemType=1,isPassive=false} end,
  IsSpellKnown=function(id) for _,r in ipairs(rows) do if r[1]==id then return true end end; return false end}
 C_Spell={GetSpellInfo=function(id) for _,r in ipairs(rows) do if r[1]==id then return {name=r[2]} end end end,
  GetSpellCooldown=function() return {startTime=0,duration=0,isEnabled=true,isActive=false} end,
  IsSpellUsable=function() return true,false end,IsSpellInRange=function() return true end}
 A:Invalidate(true)
end
test("book_actual_rank_exact_id_no_alias_or_catalog_guess",function() book({{205,"寒冰箭"},{143,"火球术"}}); local learned=A.State:Learned(config()); eq(learned.frostbolt.spellID,205); eq(learned.fireball.spellID,143); eq(learned.pyroblast.known,false); eq(learned.frostbolt.spellID==116,false) end)
test("missing_book_remains_unknown",function() book({}); C_SpellBook=nil; eq(A.State:Learned(config()).pyroblast.known,nil) end)
test("secret_book_and_detector_failed_unknown",function() book({}); C_SpellBook.GetNumSpellBookSkillLines=function() return secret end; eq(A.State:Learned(config()).fireball.known,nil); issecretvalue=function() error("NOT_SAVED") end; eq(A.State:Learned(config()).fireball.known,nil); issecretvalue=function(v) return rawequal(v,secret) end end)
test("exact_unlearned_and_wrong_family_fail_closed",function() book({{143,"火球术"}}); local c=config(); c.exactIDs.fireball=205; eq(A.State:Learned(c).fireball.known,false); c.exactIDs.fireball=143; eq(A.State:Learned(c).fireball.spellID,143); c.exactIDs.frostbolt=143; eq(A.State:Learned(c).frostbolt.spellID,nil) end)
test("cooldown_isActive_false_alone_not_ready",function() book({}); C_Spell.GetSpellCooldown=function() return {isActive=false,isEnabled=true,startTime=secret,duration=secret} end; eq(A.State.Ready(143),nil) end)
test("cooldown_public_zero_and_active_no_expiration_guess",function() book({}); eq(A.State.Ready(143),true); C_Spell.GetSpellCooldown=function() return {isEnabled=true,startTime=1,duration=1} end; GetTime=function() return 99999 end; eq(A.State.Ready(143),false) end)
test("nil_failed_api_and_secret_usable_are_unknown",function() book({{143,"火球术"}}); C_Spell.GetSpellCooldown=function() error("NO_PERSIST") end; eq(A.State.Ready(143),nil); C_Spell.IsSpellUsable=function() return secret,secret end; local a=A.State:ReadAction("fireball",{known=true,spellID=143}); eq(a.usable,nil); eq(a.power_ok,nil) end)
test("legacy_talent_ranks_actual_not_catalog_max",function() GetNumTalentTabs=function() return 1 end; GetNumTalents=function() return 1 end; GetTalentInfo=function() return "强化灼烧",nil,4,1,2,3 end; local t=A.TalentState:Read(); eq(t.improved_scorch.rank,2); eq(t.improved_scorch.known,true); eq(t.arcane_power.status,"UNKNOWN"); GetTalentInfo=function() return "强化灼烧",nil,4,1,0,3 end; t=A.TalentState:Read(); eq(t.improved_scorch.known,false) end)
test("legacy_secret_rank_never_zero",function() GetNumTalentTabs=function() return 1 end; GetNumTalents=function() return 1 end; GetTalentInfo=function() return "强化灼烧",nil,4,1,secret,3 end; local t=A.TalentState:Read(); eq(t.improved_scorch.status,"UNKNOWN"); eq(t.improved_scorch.rank,nil) end)
test("traits_live_identity_rank_and_config_change",function()
 GetNumTalentTabs=nil; C_ClassTalents={GetActiveConfigID=function() return 9 end}
 C_Traits={GetConfigInfo=function() return {treeIDs={1112}} end,GetTreeNodes=function() return {105798} end,
  GetNodeInfo=function() return {ID=105798,activeRank=1,maxRanks=1,entryIDs={7}} end,
  GetEntryInfo=function() return {definitionID=8} end,GetDefinitionInfo=function() return {spellID=12042} end}
 C_Spell.GetSpellInfo=function() return {name="奥术强化"} end
 local t=A.TalentState:Read(); eq(t.arcane_power.known,true); eq(t.arcane_power.rank,1)
 C_Traits.GetNodeInfo=function() return {ID=105799,activeRank=1,maxRanks=1,entryIDs={7}} end
 t=A.TalentState:Read(); eq(t.arcane_power.status,"UNKNOWN")
 C_Traits.GetNodeInfo=function() C_ClassTalents.GetActiveConfigID=function() return 10 end; return {ID=105798,activeRank=1,maxRanks=1,entryIDs={7}} end
 t=A.TalentState:Read(); eq(t.arcane_power.status,"UNKNOWN")
end)
test("traits_choice_node_aggregate_rank_not_used",function() C_ClassTalents.GetActiveConfigID=function() return 9 end; C_Traits.GetNodeInfo=function() return {ID=105798,activeRank=1,maxRanks=1,entryIDs={7,8}} end; local t=A.TalentState:Read(); eq(t.arcane_power.status,"UNKNOWN") end)
test("trace_bounded_and_scalar_reload_clean",function() UnitClass=function() return "法师","MAGE" end; GetSpecialization=nil; local e=T.Engine.New(T.Config); for i=1,140 do A.Trace:Record(e,{{rule="single:fireball",result="UNKNOWN",reason="UNKNOWN:action:fireball:known"}},i%2==0 and "APL_CANDIDATE" or "APL_NO_PUBLIC_ELIGIBLE_RULE",nil,state()) end; eq(#e.db.diagnostics,128); assert(e.db.evicted>0); local clean=A.Trace.Clean(e.db.diagnostics[128].apl); eq(#clean.rules,1) end)

-- Integration with the existing receipt owner and transport guards.
test("apl_source_preserves_sequence_and_no_fixed_completion",function()
 UnitClass=function() return "法师","MAGE" end; GetSpecialization=nil
 local e=T.Engine.New(T.Config); local old=e.db.profiles.single[1].spellID
 eq(T.Recommendation:SetSource(e,"apl"),true); eq(e.steps,nil); eq(e.db.profiles.single[1].spellID,old)
 local s=state(); s.actions.fireball.known=true; e.db.apl=config(); local candidate=evaluate(s)
 e.aplCandidate=candidate; e.steps=T.Engine.Validate({{name="火球术",spellID=143,matchIDs={143}}}); e:Start()
 e:Handle(e.generation,"UNIT_SPELLCAST_SENT","player","apl-one",143)
 e:Handle(e.generation,"UNIT_SPELLCAST_SUCCEEDED","player","apl-one",143)
 eq(e.receiptSerial,1); eq(e.index,1); eq(e.completed,false); eq(e.running,true)
 e:Handle(e.generation,"UNIT_SPELLCAST_SUCCEEDED","player","apl-one",143); eq(e.receiptSerial,1)
 eq(T.Recommendation:SetSource(e,"manual"),true); eq(e.db.profiles.single[1].spellID,old)
end)
test("apl_class_mode_persists_reload_no_candidate_restored",function()
 local e=T.Engine.New(T.Config); T.Recommendation:SetSource(e,"apl"); e.db.apl=config(); local copy=T.Engine.New(T.Config,e.db)
 eq(T.Recommendation:Source(copy),"apl"); eq(copy.running,false); eq(copy.aplCandidate,nil); eq(copy.aplSnapshot,nil); eq(copy.db.apl.filler,"fireball")
end)
test("apl_class_mode_without_specialization_identity",function()
 local e=T.Engine.New(T.Config); e.profileKey=nil; e.classToken="MAGE"
 eq(T.Recommendation:SetSource(e,"apl"),true); eq(T.Recommendation:Configured(e),true)
end)
test("apl_guard_stale_revision_generation_receipt_and_live_unknown",function()
 book({{143,"火球术"}}); InCombatLockdown=function() return true end; GetTime=function() return 10 end
 local e=T.Engine.New(T.Config); T.Recommendation:SetSource(e,"apl"); e.db.apl=config()
 local s=state(); s.actions.fireball.known=true; e.aplCandidate=evaluate(s)
 e.aplSnapshot={generation=e.generation,receiptSerial=0,revision=A.State.revision,sampledAt=10,talents=s.talents,scene="single"}
 eq(A:Allowed(e,143),true); e.aplSnapshot.generation=e.generation-1; eq(A:Allowed(e,143),false); e.aplSnapshot.generation=e.generation
 e.receiptSerial=1; eq(A:Allowed(e,143),false); e.receiptSerial=0
 C_Spell.GetSpellCooldown=function() return nil end; eq(A:Allowed(e,143),false)
end)
test("pause_reset_retires_apl_initiations",function()
 local e=T.Engine.New(T.Config); T.Recommendation:SetSource(e,"apl"); e.steps=T.Engine.Validate({{name="火球术",spellID=143,matchIDs={143}}}); e:Start()
 e:Handle(e.generation,"UNIT_SPELLCAST_SENT","player","old-apl",143); e:Reset(); e:Resume()
 e:Handle(e.generation,"UNIT_SPELLCAST_SENT","player","old-apl",143); e:Handle(e.generation,"UNIT_SPELLCAST_SUCCEEDED","player","old-apl",143); eq(e.receiptSerial,nil)
end)
test("apl_child_channel_event_never_consumed",function() local e=T.Engine.New(T.Config); T.Recommendation:SetSource(e,"apl"); e.steps=T.Engine.Validate({{name="奥术飞弹",spellID=5143,matchIDs={5143}}}); e:Start(); e:Handle(e.generation,"UNIT_SPELLCAST_SENT","player","missile",5143); e:Handle(e.generation,"UNIT_SPELLCAST_SUCCEEDED","player","child",7268); eq(e.receiptSerial,nil); e:Handle(e.generation,"UNIT_SPELLCAST_SUCCEEDED","player","missile",5143); eq(e.receiptSerial,1) end)

local function runtime()
 F.runtimeFixture("manual")
 book({{143,"火球术"},{205,"寒冰箭"}})
 GetNumTalentTabs=nil; C_ClassTalents=nil; C_Traits=nil
 GetActionInfo=function() return "spell",143 end
 InCombatLockdown=function() return true end; GetTime=function() return 10 end
 local e=T.engine; T.Recommendation:SetSource(e,"apl"); e.db.apl=config()
 return e
end
test("apl_runtime_same_transport_requests_and_success_re_evaluates",function()
 local e=runtime(); eq(T.Runtime:SetIntent(true),true); eq(T.Runtime.state,"running")
 eq(T.Recommendation:Current(e).spellID,143)
 T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); assert(T.Dispatch:Packet())
 F.receipt("UNIT_SPELLCAST_SENT",143,"runtime-apl"); eq(T.Dispatch.pending,nil)
 UnitCastingInfo=function() return "cast" end
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"runtime-apl"); eq(e.receiptSerial,1); eq(e.completed,false)
 T.Runtime:Reconcile(); eq(T.Runtime.state,"blocked"); T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
 UnitCastingInfo=function() return nil end
 T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); eq(T.Dispatch.pending.receiptSerial,1)
end)
test("apl_runtime_and_packet_never_query_gcd",function()
 local e=runtime(); local calls=0
 C_Spell.GetSpellCooldown=function(id) if id==61304 then calls=calls+1; error("GCD_MUST_NOT_BE_QUERIED") end; return {startTime=0,duration=0,isEnabled=true} end
 eq(T.Runtime:SetIntent(true),true); eq(T.Runtime.state,"running"); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); assert(T.Dispatch:Packet()); eq(calls,0)
end)
test("apl_initiated_action_locked_against_new_priority",function()
 local e=runtime(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); F.receipt("UNIT_SPELLCAST_SENT",143,"lock")
 local generation=e.generation; e.db.apl.fire_blast=true; IsPlayerMoving=function() return true end
 A.State.learned.fire_blast={known=true,spellID=2136}
 A:Invalidate(); T.Runtime:Reconcile(); eq(e.steps[1].spellID,143); eq(e.generation,generation)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"lock"); T.Runtime:Reconcile(); eq(e.steps[1].spellID,2136); assert(e.generation~=generation)
end)
test("apl_packet_live_unknown_immediately_zeroes_old_candidate",function()
 runtime(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 C_Spell.GetSpellCooldown=function() return {isEnabled=true,isActive=false,startTime=secret,duration=secret} end
 eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil)
end)
test("apl_sampling_reentry_rejects_stale_generation",function()
 local e=runtime(); C_Spell.IsSpellUsable=function() e:Reset(); return true,false end
 T.Runtime:SetIntent(true); eq(T.Dispatch.pending,nil); eq(e.aplCandidate,nil); eq(T.Runtime.intent,false)
end)
test("apl_ui_and_hud_hide_sequence_preview_and_keep_edit_draft",function()
 F.deliveryFixture("manual"); book({{143,"火球术"}}); GetActionInfo=function() return "spell",143 end
 InCombatLockdown=function() return false end; GetTime=function() return 10 end
 local e=T.engine; T.Recommendation:SetSource(e,"apl"); e.db.apl=config()
 T.UI:ShowPage("apl"); T.UI.aplExactID.scripts.OnEditFocusGained(); T.UI.aplExactID.text="143"; T.UI:RefreshPage(); eq(T.UI.aplExactID.text,"143")
 local s=state(); s.actions.fireball.known=true; e.aplCandidate=evaluate(s); e.steps=T.Engine.Validate({{name="火球术",spellID=143,matchIDs={143}}}); e.db.loop=true
 T.HUD:Refresh(); eq(T.HUD.cards[2].displayStep,nil); eq(T.HUD.cards[3].displayStep,nil)
end)
test("apl_auto_mode_out_of_combat_is_standby",function()
 local e=runtime(); e.db.dispatch.mode="auto"; InCombatLockdown=function() return false end
 eq(T.Runtime:SetIntent(true),true); eq(T.Runtime.state,"standby"); eq(T.Dispatch.pending,nil)
 eq(e.aplCandidate.spellID,143); eq(e.running,false); T.HUD.engine=e; T.HUD:Refresh(); eq(T.HUD.cards[1].displayStep.spellID,143)
 T.Dispatch:TickContinuous(); eq(T.Dispatch:Packet(),nil); eq(A:Allowed(e,143),false)
 T.Transport:Paint(); eq(T.Transport.fields[4],2); eq(T.Transport.fields[15],0); eq(T.Transport.fields[16],0)
end)
test("apl_missing_clock_does_not_sample_or_dispatch",function()
 local e=runtime(); GetTime=nil; local calls=0; C_Spell.IsSpellUsable=function() calls=calls+1; return true,false end
 T.Runtime:SetIntent(true); eq(T.Dispatch.pending,nil); eq(calls,0); eq(e.aplTrace.reason,"APL_TIME_UNKNOWN")
end)
test("apl_static_cache_reentry_is_not_published",function()
 local e=runtime(); C_SpellBook.GetSpellBookItemInfo=function() A:Invalidate(true); return {spellID=143,name="火球术",itemType=1,isPassive=false} end
 T.Runtime:SetIntent(true); eq(A.State.learned,nil); eq(e.aplCandidate,nil); eq(T.Dispatch.pending,nil)
end)
test("apl_dynamic_static_invalidation_returns_unknown_without_exception",function()
 local e=runtime(); C_Spell.IsSpellUsable=function() A:Invalidate(true); return true,false end
 eq(T.Runtime:SetIntent(true),true); eq(T.Runtime.state,"blocked"); eq(T.Dispatch.pending,nil); eq(e.aplCandidate,nil)
end)
test("apl_failed_current_cast_retries_without_receipt_or_old_success",function()
 local e=runtime(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 F.receipt("UNIT_SPELLCAST_SENT",143,"cancel-apl"); F.receipt("UNIT_SPELLCAST_INTERRUPTED",143,"cancel-apl")
 eq(T.Runtime.intent,true); eq(e.receiptSerial,nil); eq(T.Dispatch.pending,nil)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"cancel-apl"); eq(e.receiptSerial,nil)
 A:Invalidate(); T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 F.receipt("UNIT_SPELLCAST_SENT",143,"retry-apl"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"retry-apl"); eq(e.receiptSerial,1)
end)
test("multiple_learned_bound_ranks_require_explicit_exact_id",function()
 book({{116,"寒冰箭"},{205,"寒冰箭"}})
 local previous=T.Dispatch.ResolveCached; T.Dispatch.ResolveCached=function() return {} end
 local c=config(); local learned=A.State:Learned(c); eq(learned.frostbolt.known,true); eq(learned.frostbolt.spellID,nil)
 c.exactIDs.frostbolt=205; learned=A.State:Learned(c); eq(learned.frostbolt.spellID,205)
 T.Dispatch.ResolveCached=previous
end)

test("legacy_total_includes_live_nodes_outside_catalog",function()
 GetNumTalentTabs=function() return 1 end; GetNumTalents=function() return 2 end
 GetTalentInfo=function(tab,index) if index==1 then return "强化灼烧",nil,4,1,2,3 end; return "目录外节点",nil,1,1,4,5 end
 local talents,build=A.TalentState:Read(); eq(build.FIRE,6); eq(talents.improved_scorch.rank,2)
 GetTalentInfo=function(tab,index) if index==1 then return "强化灼烧",nil,4,1,2,3 end; return "目录外节点",nil,1,1,secret,5 end
 talents,build=A.TalentState:Read(); eq(build.FIRE,nil)
end)
test("waiting_text_identifies_configuration_and_combat",function()
 local e={db={apl={filler="auto"}}}; eq(A.Trace:Waiting(e),"APL暂无满足条件的规则")
 e.db.apl.filler="fireball"; e.aplTrace={rules={{reason="combat:"}}}; eq(A.Trace:Waiting(e),"APL待命：等待重新评估")
 e.aplTrace={rules={{reason="custom:combat"}}}; eq(A.Trace:Waiting(e),"APL待命：等待重新评估")
end)
test("wotlk_template_source_defaults_and_exact_ids",function()
 local s,c=state(),config(); c.filler="auto"
 for template,key in pairs({arcane="arcane_blast",fire="fireball",frost="frostbolt"}) do
  c.template=template; s.actions[key].known=true; eq(evaluate(s,c).action,key); s.actions[key].known=false
 end
end)
test("wotlk_moving_fire_blast_only_public_true",function()
 local s,c=state(),config(); c.fire_blast=true; s.actions.fire_blast.known=true; s.actions.fireball.known=true
 s.moving=nil; eq(evaluate(s,c).action,"fireball")
 s.moving=false; eq(evaluate(s,c).action,"fireball")
 s.moving=true; eq(evaluate(s,c).action,"fire_blast")
end)
test("wotlk_child_list_keeps_parent_scene_and_count",function()
 local s,c=state(),config(); c.template="arcane"; c.presence_of_mind=true
 s.actions.presence_of_mind.known=true; talent(s,"presence_of_mind",1)
 s.scene="single"; eq(evaluate(s,c),nil)
 s.scene="multi"; s.enemy_count=nil; eq(evaluate(s,c),nil)
 s.enemy_count=2; eq(evaluate(s,c),nil)
 s.enemy_count=3; eq(evaluate(s,c).rule,"arcane:aoe:2")
end)
test("wotlk_blocked_receipt_trace_survives_reload",function()
 local s,c=state(),config(); local _,_,trace=evaluate(s,c)
 local clean=A.Trace.Clean({reason="APL_NO_PUBLIC_ELIGIBLE_RULE",rules=trace})
 local seen=false; for _,r in ipairs(clean.rules) do if r.rule=="fire:default:15" then eq(r.result,"BLOCKED"); seen=true end end; eq(seen,true)
end)
test("wotlk_ledger_includes_disabled_and_original_conditions",function()
 local text=A:Ledger({db={apl=config()}})
 assert(text:find("buff.hot_streak.up",1,true)); assert(text:find("SOURCE_DISABLED",1,true)); assert(text:find("fire:default:18",1,true))
end)
test("wotlk_manual_template_persist_and_invalid_rejected",function()
 local c=A.Clean({template="frost",filler="auto"}); eq(c.template,"frost"); eq(c.schema,3)
 local e=T.Engine.New(T.Config); local ok=A:Configure(e,"template","modern_frost"); eq(ok,false)
end)
n=n+assert(loadfile((arg and arg[1] or ".") .. "/tests/custom_apl.lua"))("TEF",T,{runtime=runtime,secret=secret,receipt=F.receipt})
for key,value in pairs(saved) do _G[key]=value end
issecretvalue=originalDetector
print("TEF APL simulated tests: " .. n .. " passed")
TEF_APL_TEST_COUNT=n
