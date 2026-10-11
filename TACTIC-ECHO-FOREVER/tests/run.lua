-- Pure Lua simulated client. No WoW in-game validation is claimed.
local root = arg[1] or "."
local T = {}
local secret = setmetatable({}, {__tostring=function() error("SECRET_TOUCHED") end,
    __eq=function() error("SECRET_TOUCHED") end,__index=function() error("SECRET_TOUCHED") end})
local detectorMode
issecretvalue=function(v)
    if detectorMode=="error" then error("DO_NOT_SAVE_EXCEPTION") end
    if detectorMode=="nil" then return nil end
    return rawequal(v,secret)
end
local detector=issecretvalue
local function load(name) assert(loadfile(root .. "/" .. name))("TACTIC-ECHO-FOREVER",T) end
load("Config.lua"); load("Safety.lua"); load("Sequence.lua")
load("Profiles.lua"); load("Research.lua")
local standard=T.StandardConfig or T.Config
local count=0
local function test(name,fn)
    detectorMode=nil; issecretvalue=detector
    C_Spell={GetSpellInfo=function(id) return {name="spell" .. id} end,GetSpellTexture=function() return 123 end}
    GetSpellInfo=nil; GetSpellTexture=nil
    fn(); count=count+1; print("PASS " .. name)
end
local function eq(a,b) assert(a==b,"expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function engine(config,db) return T.Engine.New(config or standard,db) end
local function event(e,kind,id,guid,unit,generation)
    e:Handle(generation or e.generation,kind,unit or "player",guid,id)
end
local function cast(e,id,guid)
    event(e,"UNIT_SPELLCAST_SENT",id,guid)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",id,guid)
end
test("four_steps_complete",function()
    local e=engine(); eq(e.running,false); e:Start()
    for i,id in ipairs({205,143,2136,5143}) do cast(e,id,"cast" .. i) end
    eq(e.index,4); eq(e.completed,true); eq(e.running,false)
end)
test("start_stop_cancel_failure_never_advance",function()
    for _,kind in ipairs({"UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET"}) do
        local e=engine(); e:Start(); event(e,"UNIT_SPELLCAST_SENT",205,"cast")
        event(e,kind,205,"cast"); eq(e.index,1)
    end
end)
test("failed_initiation_late_success_rejected",function()
    local e=engine(); e:Start(); event(e,"UNIT_SPELLCAST_START",205,"cast")
    event(e,"UNIT_SPELLCAST_INTERRUPTED",205,"cast")
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"cast"); eq(e.index,1)
end)
test("deviation_only_current_step_matches",function()
    local e=engine(); e:Start(); cast(e,143,"later"); eq(e.index,1)
    eq(e.db.diagnostics[#e.db.diagnostics].reason,"OUT_OF_SEQUENCE")
    cast(e,205,"first"); eq(e.index,2)
end)
test("duplicate_same_success_and_adjacent_same_skill",function()
    local e=engine({standard[1],standard[1]}); e:Start(); cast(e,205,"first"); eq(e.index,2)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"first"); eq(e.completed,false)
    event(e,"UNIT_SPELLCAST_START",205,"first"); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"first")
    eq(e.completed,false); cast(e,205,"second"); eq(e.completed,true)
end)
test("channel_success_begin_and_child_excluded",function()
    local e=engine({standard[4],standard[4]}); e:Start(); cast(e,5143,"channel"); eq(e.index,2)
    for i=1,4 do cast(e,7268,"child" .. i) end
    eq(e.completed,false); event(e,"UNIT_SPELLCAST_CHANNEL_STOP",5143,"channel"); eq(e.completed,false)
    cast(e,5143,"nextChannel"); eq(e.completed,true)
end)
test("loop_one_event_one_step_duplicate_blocked",function()
    local e=engine({standard[1]}); e:SetLoop(true); e:Start(); cast(e,205,"first")
    eq(e.index,1); eq(e.running,true); eq(e.seenCount,1)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"first"); eq(e.seenCount,1)
    cast(e,205,"next"); eq(e.seenCount,2)
end)
test("unit_secret_spell_secret_guid_secret_independent",function()
    for _,field in ipairs({"unit","spell","guid"}) do
        local e=engine(); e:Start()
        event(e,"UNIT_SPELLCAST_SUCCEEDED",field=="spell" and secret or 205,
            field=="guid" and secret or "cast",field=="unit" and secret or "player")
        eq(e.index,1); eq(e.db.diagnostics[#e.db.diagnostics].kind,"unknown")
    end
end)
test("detector_missing_unknown_and_error",function()
    local e=engine(); e:Start()
    for _,mode in ipairs({"nil","error","missing"}) do
        detectorMode=mode; issecretvalue=mode=="missing" and nil or detector
        event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"cast"); eq(e.index,1)
    end
    issecretvalue=detector; detectorMode=nil
end)
test("nil_invalid_types_ids_and_guid",function()
    local e=engine(); e:Start()
    for _,id in ipairs({0,-1,1.5,"205",true,math.huge,0/0}) do
        event(e,"UNIT_SPELLCAST_SUCCEEDED",id,"cast"); eq(e.index,1)
    end
    event(e,"UNIT_SPELLCAST_SUCCEEDED",nil,"cast"); eq(e.index,1)
    for _,guid in ipairs({"",123,true,string.rep("a",129)}) do
        event(e,"UNIT_SPELLCAST_SUCCEEDED",205,guid); eq(e.index,1)
    end
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,nil); eq(e.index,1)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"cast","target"); eq(e.index,1)
end)
test("no_identity_or_current_initiation_no_advance",function()
    local e=engine(); e:Start(); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"notAssociated"); eq(e.index,1)
    event(e,"UNIT_SPELLCAST_SENT",205,secret); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,secret); eq(e.index,1)
end)
test("pause_resume_reset_and_late_generation",function()
    local e=engine(); e:Start(); event(e,"UNIT_SPELLCAST_START",205,"old"); local old=e.generation
    e:Pause(); cast(e,205,"paused"); eq(e.index,1); e:Resume()
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"old"); eq(e.index,1)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"old","player",old); eq(e.index,1)
    cast(e,205,"new"); eq(e.index,2); e:Pause(); e:Resume(); eq(e.index,2)
    e:Reset(); eq(e.index,1); eq(e.running,false)
    e:Start(); cast(e,205,"new"); eq(e.index,1); cast(e,205,"afterReset"); eq(e.index,2)
end)
test("reload_defaults_paused_history_sanitized",function()
    local e=engine(); e:SetLoop(true); e:Start(); cast(e,205,"old")
    e.db.running=true; e.db.secret=secret; e.db.foreign={}; e.db.diagnostics[#e.db.diagnostics+1]={kind=secret}
    local reloaded=engine(nil,e.db); eq(reloaded.running,false); eq(reloaded.index,1)
    eq(reloaded.session,e.session+1); eq(reloaded.db.loop,true); eq(reloaded.db.secret,nil); eq(reloaded.db.foreign,nil)
    reloaded:Start(); event(reloaded,"UNIT_SPELLCAST_SUCCEEDED",205,"old"); eq(reloaded.index,1)
end)
test("128_history_saturation_does_not_block_progress",function()
    local e=engine(); e:Start(); for i=1,200 do cast(e,143,"wrong" .. i) end
    eq(#e.db.diagnostics,128); assert(e.db.evicted>0); cast(e,205,"right"); eq(e.index,2); eq(#e.db.diagnostics,128)
end)
test("identity_capacity_fail_closed_no_eviction",function()
    local e=engine({standard[1]}); e:SetLoop(true); e:Start(); e.seenCount=4096
    cast(e,205,"overflow"); eq(e.running,false); eq(e.lastReason,"IDENTITY_CAPACITY_PAUSED")
end)
test("association_capacity_fail_closed",function()
    local e=engine(); e:Start(); for i=1,257 do event(e,"UNIT_SPELLCAST_START",205,"pending" .. i) end
    eq(e.running,false); eq(e.lastReason,"ASSOCIATION_CAPACITY_PAUSED")
end)
test("bad_config_no_guess_or_skip",function()
    for _,cfg in ipairs({{},{{name="bad",spellID=0,matchIDs={205}}},{{name="bad",spellID=5143,matchIDs={7268}}}}) do
        local e=engine(cfg); e:Start(); eq(e.running,false); eq(e.steps,nil)
    end
end)
test("spell_metadata_nil_missing_failed_secret_fields",function()
    for _,fn in ipairs({function() return nil end,function() error("DO_NOT_SAVE_EXCEPTION") end,
        function() return secret end,function() return {name=secret} end,
        function() return setmetatable({},{__index=function() error("FIELD_EXCEPTION") end}) end}) do
        C_Spell.GetSpellInfo=fn; local view=T.Safety.Spell(205,"寒冰箭"); assert(view.name:find("未解析"))
    end
    C_Spell=nil; local view=T.Safety.Spell(205,"寒冰箭"); eq(view.reason,"UNAVAILABLE")
end)
test("icon_missing_failed_secret_safe_placeholder",function()
    for _,fn in ipairs({function() return nil end,function() error("ICON_EXCEPTION") end,function() return secret end}) do
        C_Spell.GetSpellTexture=fn; eq(T.Safety.Spell(205,"寒冰箭").icon,T.Placeholder)
    end
    C_Spell.GetSpellTexture=nil; eq(T.Safety.Spell(205,"寒冰箭").icon,T.Placeholder)
end)
test("event_type_on_missing_channel_identity_and_success",function()
    local e=engine({standard[4]}); e:Start()
    event(e,"UNIT_SPELLCAST_CHANNEL_START",5143,nil)
    local row=e.db.diagnostics[#e.db.diagnostics]
    eq(row.reason,"IDENTITY_NO_DATA"); eq(row.event,"UNIT_SPELLCAST_CHANNEL_START"); eq(e.completed,false)
    cast(e,5143,"channel")
    row=e.db.diagnostics[#e.db.diagnostics]; eq(row.event,"UNIT_SPELLCAST_SUCCEEDED"); eq(row.reason,"COMPLETED")
    event(e,"UNIT_SPELLCAST_CHANNEL_STOP",5143,nil)
    eq(e.db.diagnostics[#e.db.diagnostics].event,"UNIT_SPELLCAST_CHANNEL_STOP")
end)
test("duplicate_success_distinct_from_followup_event",function()
    local e=engine({standard[1],standard[1]}); e:Start(); cast(e,205,"first")
    event(e,"UNIT_SPELLCAST_STOP",205,"first")
    local row=e.db.diagnostics[#e.db.diagnostics]
    eq(row.kind,"observed"); eq(row.reason,"CONSUMED_IDENTITY_EVENT"); eq(row.event,"UNIT_SPELLCAST_STOP")
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"first")
    row=e.db.diagnostics[#e.db.diagnostics]
    eq(row.kind,"duplicate"); eq(row.reason,"DUPLICATE_SUCCESS"); eq(row.event,"UNIT_SPELLCAST_SUCCEEDED")
    eq(e.index,2); eq(e.completed,false); eq(e.seenCount,1)
end)
test("event_metadata_safe_unknown_and_paused",function()
    local e=engine(); e:Start(); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,secret)
    local row=e.db.diagnostics[#e.db.diagnostics]
    eq(row.event,"UNIT_SPELLCAST_SUCCEEDED"); eq(row.reason,"IDENTITY_SECRET"); eq(row.castGUID,nil)
    e:Pause(); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"paused")
    row=e.db.diagnostics[#e.db.diagnostics]; eq(row.reason,"PAUSED_IGNORED"); eq(row.event,"UNIT_SPELLCAST_SUCCEEDED")
end)
test("reload_event_whitelist_and_legacy_unfilled",function()
    local e=engine(); e:Start(); cast(e,205,"first")
    local legacy={kind="duplicate",reason="DUPLICATE_IDENTITY",session=1,generation=2,current=2,next=2,spellID=205}
    e.db.diagnostics[#e.db.diagnostics+1]=legacy
    local invalid={kind="unknown",reason="IDENTITY_SECRET",session=1,generation=2,current=2,next=2,event=secret}
    e.db.diagnostics[#e.db.diagnostics+1]=invalid
    local unknown={kind="observed",reason="UNKNOWN_EVENT",session=1,generation=2,current=2,next=2,event="UNKNOWN_RAW_EVENT"}
    e.db.diagnostics[#e.db.diagnostics+1]=unknown
    local r=engine(nil,e.db); local foundMatch,foundLegacy=false,false
    for _,row in ipairs(r.db.diagnostics) do
        if row.reason=="CURRENT_MATCH" then eq(row.event,"UNIT_SPELLCAST_SUCCEEDED"); foundMatch=true end
        if row.reason=="DUPLICATE_IDENTITY" then eq(row.event,nil); foundLegacy=true end
        if row.reason=="IDENTITY_SECRET" or row.reason=="UNKNOWN_EVENT" then eq(row.event,nil) end
    end
    eq(foundMatch,true); eq(foundLegacy,true); eq(r.running,false)
end)
test("preserved_adjacent_preset_requires_two_independent_successes",function()
    eq(#T.AdjacentConfig,2); eq(#T.StandardConfig,4)
    local e=engine(T.AdjacentConfig,{loop=false}); eq(e.db.loop,false); eq(e.running,false); e:Start()
    cast(e,205,"first"); eq(e.index,2); eq(e.completed,false)
    event(e,"UNIT_SPELLCAST_STOP",205,"first"); eq(e.completed,false)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"first"); eq(e.completed,false)
    cast(e,205,"second"); eq(e.completed,true); eq(e.running,false)
end)
test("deployed_exact_rank_ids_adjacent_and_following_step",function()
    eq(#T.Config,4)
    for i,id in ipairs({116,205,205,143}) do eq(T.Config[i].spellID,id) end
    local e=engine(T.Config,{loop=false}); e:Start()
    cast(e,205,"wrongRank"); eq(e.index,1)
    cast(e,116,"rank116"); eq(e.index,2)
    cast(e,116,"wrongNextRank"); eq(e.index,2)
    cast(e,205,"rank205first"); eq(e.index,3)
    event(e,"UNIT_SPELLCAST_STOP",205,"rank205first"); eq(e.index,3)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"rank205first"); eq(e.index,3)
    cast(e,143,"earlyFireball"); eq(e.index,3)
    cast(e,205,"rank205second"); eq(e.index,4); eq(e.steps[e.index].spellID,143); eq(e.completed,false)
    cast(e,143,"finalFireball"); eq(e.completed,true); eq(e.running,false)
end)
test("scene_switch_resets_old_receipt_and_preserves_tombstones",function()
    local e=engine(T.Config); e:Start(); cast(e,116,"seen"); local old=e.generation
    event(e,"UNIT_SPELLCAST_SENT",205,"pending")
    assert(T.Profiles:Select(e,"multi")); eq(e.scene,"multi"); eq(e.index,1); eq(e.running,false)
    e:Start(); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"pending","player",old); eq(e.index,1)
    assert(T.Profiles:Select(e,"single")); e:Start(); cast(e,116,"seen"); eq(e.index,1)
    cast(e,116,"new"); eq(e.index,2)
end)
test("two_profiles_independent_and_save_resets",function()
    local e=engine(T.Config); e:Start(); cast(e,116,"first")
    assert(T.Profiles:Save(e,"multi",{{name="飞弹",spellID=5143,matchIDs={5143}}}))
    eq(e.index,1); eq(e.running,false); eq(e.db.profiles.single[1].spellID,116)
    T.Profiles:Select(e,"multi"); e:Start(); cast(e,5143,"multi"); eq(e.completed,true)
    T.Profiles:Select(e,"single"); eq(e.completed,false); eq(e.steps[1].spellID,116)
end)
test("profile_reload_whitelist_no_active_or_foreign_data",function()
    local e=engine(); T.Profiles:Select(e,"multi"); e:Start(); e.db.hud={scale=1.2,locked=true,preview=false}
    e.db.profiles.multi[1].foreign=secret; e.db.tekEnabled=true
    local reloaded=engine(T.Config,e.db)
    eq(reloaded.scene,"multi"); eq(reloaded.running,false); eq(reloaded.db.hud.scale,1.2)
    eq(reloaded.db.hud.preview,false); eq(reloaded.db.profiles.multi[1].foreign,nil); eq(reloaded.db.tekEnabled,nil)
    T.Profiles:Select(reloaded,reloaded.scene); eq(reloaded.steps[1].spellID,118)
end)
test("profile_parser_explicit_ids_pending_and_limits",function()
    local rows=T.Profiles:Parse("116\n205:205\n205\n143")
    eq(#rows,4); eq(rows[2].matchIDs[1],205)
    local pending=T.Profiles:Parse("?变形术\n5143")
    eq(pending[1].unverified,true); eq(pending[1].spellID,0)
    for _,raw in ipairs({"", "205:7268", "205:205//143", "205:205/", "205:205 143", "abc", "0", string.rep("205\n",33), "205:"}) do
        eq(T.Profiles:Parse(raw),nil)
    end
end)
test("profile_secret_and_field_failure_rejected",function()
    eq(T.Profiles:Clean(secret),nil)
    eq(T.Profiles:Clean({{name=secret,spellID=205,matchIDs={205}}}),nil)
    eq(T.Profiles:Clean({setmetatable({},{__index=function() error("FIELD") end})}),nil)
    eq(T.Profiles:Clean({{name="bad",spellID=205,matchIDs={secret}}}),nil)
end)
test("pending_polymorph_requires_explicit_confirmed_success",function()
    local e=engine(); e.db.profiles.multi={{name="变形术",spellID=0,matchIDs={},unverified=true},T.StandardConfig[4]}; T.Profiles:Select(e,"multi"); e:Start()
    C_Spell.GetSpellInfo=function(id) return {name=id==118 and "变形术" or "其他技能"} end
    event(e,"UNIT_SPELLCAST_START",118,"poly"); eq(T.Profiles:ConfirmObserved(e),false)
    cast(e,143,"other"); eq(T.Profiles:ConfirmObserved(e),false)
    cast(e,118,"polyNew"); eq(e.index,1); eq(e.steps[1].unverified,true)
    assert(T.Profiles:ConfirmObserved(e)); eq(e.running,false); eq(e.steps[1].spellID,118)
    eq(e.steps[1].matches[12824],nil) -- no inferred ranks.
    e:Start(); event(e,"UNIT_SPELLCAST_SUCCEEDED",118,"polyNew"); eq(e.index,1)
    cast(e,118,"polyConfirmed"); eq(e.index,2); cast(e,5143,"channel"); eq(e.completed,true)
end)
test("polymorph_confirmation_rejects_secret_name_or_old_session",function()
    local e=engine(); e.db.profiles.multi={{name="变形术",spellID=0,matchIDs={},unverified=true},T.StandardConfig[4]}; T.Profiles:Select(e,"multi"); e:Start(); cast(e,118,"poly")
    C_Spell.GetSpellInfo=function() return {name=secret} end
    eq(T.Profiles:ConfirmObserved(e),false)
    C_Spell.GetSpellInfo=function() return {name="变形术"} end
    e:Pause(); e:Resume(); eq(T.Profiles:ConfirmObserved(e),false)
    cast(e,118,"current"); local reload=engine(T.Config,e.db); T.Profiles:Select(reload,"multi"); reload:Start()
    eq(T.Profiles:ConfirmObserved(reload),false)
end)
test("auto_proposal_two_samples_hysteresis_unknown_resets",function()
    local p={}; local f={state="PUBLIC_VALUE",value=3}
    eq(T.Research.Auto(p,f,1,"single"),nil)
    eq(T.Research.Auto(p,f,1,"single"),nil)
    eq(T.Research.Auto(p,f,2,"single"),"multi")
    eq(T.Research.Auto(p,{state="UNKNOWN"},3,"single"),nil)
    eq(T.Research.Auto(p,f,4,"single"),nil)
    eq(T.Research.Auto(p,{state="PUBLIC_VALUE",value=2},5,"single"),nil)
    eq(T.Research.Auto(p,f,6,"single"),nil)
    eq(T.Research.Auto(p,f,7,"single"),"multi")
    p={}; eq(T.Research.Auto(p,{state="PUBLIC_VALUE",value=1},8,"multi"),nil)
    eq(T.Research.Auto(p,{state="PUBLIC_VALUE",value=1},9,"multi"),"single")
end)
test("field_revision_rejects_queued_cast_overwrite",function()
    local e=engine(); e:Start(); local r=T.Research; local old=r:Ticket(e)
    r:Immediate(e,"castPresent",{state="PUBLIC_TRUE",value=true})
    eq(r:Put(e,old,"castPresent",{state="PUBLIC_FALSE",value=false}),false)
    eq(r.fields.castPresent.value,true); eq(r:Current(e,old),false)
    local ticket=r:Ticket(e); e:Reset(); eq(r:Put(e,ticket,"moving",{state="PUBLIC_FALSE",value=false}),false)
end)
local function samplingAPIs()
    GetTime=function() return 10 end
    UnitExists=function() return true end; UnitCanAttack=function() return true end
    UnitIsDeadOrGhost=function() return false end; IsPlayerMoving=function() return false end
    UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
    C_NamePlate={GetNamePlates=function() return {} end}
    C_Spell.IsSpellUsable=function() return true,false end
    C_Spell.IsSpellInRange=function() return true end
end
test("sample_false_preserved_unknown_ready_no_dynamic_candidate",function()
    samplingAPIs(); local e=engine(); e:Start(); assert(T.Research:Sample(e))
    eq(T.Research.fields.insufficientPower.value,false); eq(T.Research.fields.channelPresent.value,false)
    eq(T.Research.fields.ready.state,"UNKNOWN"); eq(T.Research.dynamic,nil)
    local log=e.db.diagnostics[#e.db.diagnostics]; eq(log.research.ready,"UNKNOWN"); eq(log.research.visibleCount,0)
    eq(e.index,1); eq(e.running,true)
end)
test("succeeded_cast_can_still_present_and_channel_independent",function()
    samplingAPIs(); UnitCastingInfo=function() return "公开读条" end
    UnitChannelInfo=function() return secret end
    local e=engine(); e:Start(); cast(e,205,"done"); assert(T.Research:Sample(e))
    eq(T.Research.fields.castPresent.value,true); eq(T.Research.fields.channelPresent.state,"SECRET")
    eq(T.Research.dynamic,nil); eq(e.index,2)
end)
test("sample_api_missing_failed_and_unknown_detector",function()
    samplingAPIs(); local e=engine(); e:Start(); UnitExists=nil
    C_Spell.IsSpellUsable=function() error("API_OBJECT") end
    assert(T.Research:Sample(e)); eq(T.Research.fields.targetExists.state,"UNAVAILABLE")
    eq(T.Research.fields.usable.state,"CALL_FAILED")
    samplingAPIs(); detectorMode="nil"; eq(T.Research:Sample(e),true)
    eq(T.Research.fields.castPresent.value,nil); eq(T.Research.proposal,nil)
end)
test("sampling_invalidated_mid_api_discards_entire_packet",function()
    samplingAPIs(); local e=engine(); e:Start()
    C_Spell.IsSpellUsable=function() e:Reset(); return true,false end
    eq(T.Research:Sample(e),false); eq(T.Research.fields.targetExists,nil); eq(e.running,false)
end)
test("nameplates_public_enemy_count_duplicate_secret_and_limit",function()
    samplingAPIs()
    C_NamePlate.GetNamePlates=function() return {{namePlateUnitToken="nameplate1"},{namePlateUnitToken="nameplate2"}} end
    UnitIsDeadOrGhost=function(token) return token=="nameplate2" end
    eq(T.Research:CountVisible().value,1)
    UnitCanAttack=function() return secret end; eq(T.Research:CountVisible().value,nil)
    C_NamePlate.GetNamePlates=function() return {{namePlateUnitToken=secret}} end
    eq(T.Research:CountVisible().value,nil)
    UnitCanAttack=function() return true end
    C_NamePlate.GetNamePlates=function() return {{namePlateUnitToken="nameplate1"},{namePlateUnitToken="nameplate1"}} end
    eq(T.Research:CountVisible().state,"UNKNOWN_IDENTITY")
    C_NamePlate.GetNamePlates=function() local t={} for i=1,41 do t[i]={} end return t end
    eq(T.Research:CountVisible().state,"UNKNOWN_CAPACITY")
end)
test("research_proposal_never_switches_scene_and_expiry",function()
    samplingAPIs(); C_NamePlate.GetNamePlates=function() return {
        {namePlateUnitToken="nameplate1"},{namePlateUnitToken="nameplate2"},{namePlateUnitToken="nameplate3"}} end
    local e=engine(); e:Start(); T.Research:Sample(e); T.Research:Sample(e)
    eq(T.Research.proposal,"multi"); eq(e.scene,"single"); eq(e.index,1)
    GetTime=function() return 12 end; assert(T.Research:View():find("过期"))
    e:Pause(); eq(T.Research.fields.visibleEnemies,nil); eq(T.Research.proposal,nil)
end)
test("priority_exact_certified_ready_order_and_blockers",function()
    local yes={state="PUBLIC_TRUE",value=true}; local no={state="PUBLIC_FALSE",value=false}
    local common={targetExists=yes,targetAttackable=yes,targetAlive=yes,gcdClear=yes,castPresent=no,channelPresent=no,moving=no}
    local evidence={[205]={learned=yes,ready={state="UNKNOWN"},usable=yes,insufficientPower=no,inRange=yes},
        [143]={learned=yes,ready=yes,usable=yes,insufficientPower=no,inRange=yes}}
    eq(T.Research.Priority(standard,evidence,common),143)
    evidence[205].ready=yes; eq(T.Research.Priority(standard,evidence,common),205)
    common.castPresent=yes; eq(T.Research.Priority(standard,evidence,common),nil)
    common.castPresent=no; common.moving={state="UNKNOWN"}; eq(T.Research.Priority(standard,evidence,common),nil)
    common.moving=no; evidence[205].inRange=no; evidence[143].insufficientPower=yes
    eq(T.Research.Priority(standard,evidence,common),nil)
end)
test("research_summary_saturation_and_reload_sanitized",function()
    samplingAPIs(); local e=engine(); e:Start()
    for i=1,140 do T.Research:Sample(e) end
    eq(#e.db.diagnostics,128); assert(e.db.evicted>0)
    local summary=e.db.diagnostics[128].research; summary.raw=secret; summary.proposal=secret
    local reload=engine(T.Config,e.db)
    eq(reload.db.diagnostics[#reload.db.diagnostics-1].research.raw,nil)
    eq(reload.db.diagnostics[#reload.db.diagnostics-1].research.proposal,nil)
    eq(T.Research:Sample(reload),false)
end)
-- UI and actual TOC loader simulation.
test("priority_presence_not_target_validity_and_gcd_unknown_blocks",function()
    local yes={state="PUBLIC_TRUE",value=true}; local no={state="PUBLIC_FALSE",value=false}
    local common={targetExists=yes,targetAttackable={state="UNKNOWN"},targetAlive=yes,gcdClear=yes,
        castPresent=no,channelPresent=no,moving=no}
    local byID={[205]={learned=yes,ready=yes,usable=yes,insufficientPower=no,inRange=yes}}
    eq(T.Research.Priority(standard,byID,common),nil)
    common.targetAttackable=yes; common.gcdClear={state="UNKNOWN"}
    eq(T.Research.Priority(standard,byID,common),nil)
    common.gcdClear=yes; byID[205].learned={state="SECRET"}; eq(T.Research.Priority(standard,byID,common),nil)
end)
test("stale_samples_do_not_confirm_auto_proposal",function()
    samplingAPIs(); C_NamePlate.GetNamePlates=function() return {
        {namePlateUnitToken="nameplate1"},{namePlateUnitToken="nameplate2"},{namePlateUnitToken="nameplate3"}} end
    local e=engine(); e:Start(); T.Research:Sample(e)
    GetTime=function() return 12 end; T.Research:Sample(e); eq(T.Research.proposal,nil)
    GetTime=function() return 12.5 end; T.Research:Sample(e); eq(T.Research.proposal,"multi")
    GetTime=function() return secret end; T.Research:Sample(e); eq(T.Research.proposal,nil)
end)
test("confirmation_api_generation_change_rejected",function()
    local e=engine(); e.db.profiles.multi={{name="变形术",spellID=0,matchIDs={},unverified=true},T.StandardConfig[4]}; T.Profiles:Select(e,"multi"); e:Start(); cast(e,118,"poly")
    C_Spell.GetSpellInfo=function() e:Reset(); return {name="变形术"} end
    local ok,reason=T.Profiles:ConfirmObserved(e); eq(ok,false); eq(reason,"STALE_GENERATION")
    eq(e.steps[1].unverified,true)
end)
local allFrames={}
local uiThrowTexture=false
local function object(name)
    local o={name=name,scripts={},events={}}
    setmetatable(o,{__index=function(_,method)
        return function(self,...)
            if method=="SetScript" then local key,fn=...; self.scripts[key]=fn
            elseif method=="RegisterEvent" then self.events[(...)]=true
            elseif method=="CreateFontString" or method=="CreateTexture" then return object()
            elseif method=="SetTexture" then if uiThrowTexture then error("TEXTURE_EXCEPTION") end; self.texture=(...)
            elseif method=="SetText" then self.text=(...)
            elseif method=="GetText" then return self.text
            elseif method=="GetEffectiveScale" then return 1
            elseif method=="SetChecked" then self.checked=(...)
            elseif method=="GetChecked" then return self.checked
            elseif method=="GetPoint" then return "CENTER",UIParent,"CENTER",12,34 end
        end
    end})
    return o
end
CreateFrame=function(_,name) local o=object(name); if name then allFrames[name]=o end; return o end
UIParent=object("UIParent"); SlashCmdList={}; print=function() end
GetBuildInfo=function() return "1.60.1","70338","date",16001 end
InCombatLockdown=function() return false end
load("UI.lua"); load("HUD.lua"); load("Dispatch.lua"); load("Presentation.lua"); load("Transport.lua"); load("Core/Bootstrap.lua")
local realprint=io.write
test("toc_bootstrap_independent_namespace_sent_payload",function()
    local ef=allFrames.TEF_EventFrame
    assert(ef.events.UNIT_SPELLCAST_SENT and ef.events.UNIT_SPELLCAST_SUCCEEDED)
    local foreign={untouched=true}; TacticEchoDB=foreign; TEProbeDB=foreign
    ef.scripts.OnEvent(ef,"ADDON_LOADED","TACTIC-ECHO-FOREVER")
    assert(TEF_DB==T.engine.db); eq(T.engine.running,false); eq(TacticEchoDB,foreign); eq(TEProbeDB,foreign)
    local originalUnderscore=_G._
    SlashCmdList.TEF("start")
    ef.scripts.OnEvent(ef,"UNIT_SPELLCAST_SENT","player",secret,"cast",116)
    ef.scripts.OnEvent(ef,"UNIT_SPELLCAST_SUCCEEDED","player","cast",116)
    eq(T.engine.index,2); eq(_G._,originalUnderscore)
end)
test("ui_failure_does_not_change_sequence_or_schedule",function()
    uiThrowTexture=true; local before=T.engine.index; T.UI:Refresh(); eq(T.engine.index,before); uiThrowTexture=false
    assert(T.UI.errorLogged)
    eq(T.engine.castPresent,nil); eq(T.engine.channelPresent,nil)
end)
test("slash_lifecycle_and_logout",function()
    SlashCmdList.TEF("pause"); eq(T.engine.running,false)
    SlashCmdList.TEF("resume"); eq(T.engine.index,2); eq(T.engine.running,true)
    SlashCmdList.TEF("reset"); eq(T.engine.index,1); eq(T.engine.running,false)
    SlashCmdList.TEF("loop"); eq(T.engine.db.loop,true)
    SlashCmdList.TEF("start"); local ef=allFrames.TEF_EventFrame
    ef.scripts.OnEvent(ef,"PLAYER_LOGOUT"); eq(T.engine.running,false)
end)
test("settings_draft_not_overwritten_by_event_refresh",function()
    T.UI:OpenSettings(); T.UI:ShowPage("profiles")
    T.UI.editor.text="205\n143"; T.UI:Refresh(); eq(T.UI.editor.text,"205\n143")
    for _,page in ipairs({"overview","scene","hud","tek","diagnostics"}) do T.UI:ShowPage(page) end
    T.UI:ShowPage("profiles"); eq(T.UI.editor.text,"205\n143")
    eq(T.engine.index,1)
    -- Missing detector/config must leave even the settings readout usable.
    local original=T.UI.engine
    issecretvalue=nil
    local invalid=T.Engine.New(T.Config,{})
    T.UI.engine=invalid; T.UI:ShowPage("overview"); T.UI:ShowPage("profiles")
    eq(T.UI.editor.text,"205\n143") -- existing local draft stays intact.
    eq(T.Profiles:Text(invalid,"multi"),"")
    T.UI.engine=original; issecretvalue=detector
end)
test("hud_layout_delayed_in_combat",function()
    InCombatLockdown=function() return true end; T.UI:Layout(); eq(T.UI.layoutPending,true)
    local before=T.UI.settingsOpen; T.UI:OpenSettings(); eq(T.UI.settingsOpen,before)
    InCombatLockdown=function() return false end
    local ef=allFrames.TEF_EventFrame; ef.scripts.OnEvent(ef,"PLAYER_REGEN_ENABLED"); eq(T.UI.layoutPending,false)
end)
test("protocol_heartbeat_observation_only_no_steps",function()
    assert(T.Transport:SetEnabled(true)); local before=T.engine.index
    local signal=allFrames.TEF_ProtocolStrip; local fresh=T.Transport.freshness
    signal.scripts.OnUpdate(signal,0.06); assert(T.Transport.freshness~=fresh)
    eq(T.Transport.fields[15],0); eq(T.Transport.fields[16],0); eq(T.Transport.fields[17],T.engine.running and 2 or 0)
    eq(T.engine.index,before); T.Transport:SetEnabled(false)
    local disabled=T.Transport.freshness; signal.scripts.OnUpdate(signal,1); eq(T.Transport.freshness,disabled)
end)
test("protocol_bad_elapsed_or_scale_fails_closed",function()
    assert(T.Transport:SetEnabled(true)); allFrames.TEF_ProtocolStrip.scripts.OnUpdate(nil,secret)
    eq(T.Transport.enabled,false)
    local original=UIParent.GetEffectiveScale
    UIParent.GetEffectiveScale=function() return secret end
    eq(T.Transport:SetEnabled(true),false); eq(T.Transport.enabled,false)
    UIParent.GetEffectiveScale=original
end)
test("new_slash_switch_confirm_sample_and_protocol",function()
    SlashCmdList.TEF("multi"); eq(T.engine.scene,"multi"); eq(T.engine.running,false)
    SlashCmdList.TEF("single"); eq(T.engine.scene,"single"); eq(T.engine.index,1)
    SlashCmdList.TEF("settings"); assert(T.UI.settingsOpen)
    SlashCmdList.TEF("sample"); eq(T.engine.running,false)
    SlashCmdList.TEF("protocol"); eq(T.Transport.enabled,true)
    SlashCmdList.TEF("hide"); eq(T.Transport.enabled,false); eq(T.engine.running,false)
end)
test("delivery_hud_preserves_test_panel_and_combat_layout",function()
    assert(allFrames.TEF_DeliveryHUD and allFrames.TEF_PracticePanel)
    SlashCmdList.TEF("test"); SlashCmdList.TEF("hud")
    InCombatLockdown=function() return true end; T.HUD:Layout(); eq(T.HUD.pending,true)
    InCombatLockdown=function() return false end; T.HUD:Layout(); eq(T.HUD.pending,false)
    local before=T.engine.index; T.HUD:Refresh(); eq(T.engine.index,before)
end)
test("polymorph_migration_preserves_custom_profiles",function()
    local e=engine(nil,{profiles={multi={{name="变形术",spellID=0,matchIDs={},unverified=true},T.StandardConfig[4]}}})
    eq(e.db.profiles.multi[1].spellID,118)
    local custom=engine(nil,{profiles={multi={{name="自定义",spellID=12824,matchIDs={12824}},T.StandardConfig[4]}}})
    eq(custom.db.profiles.multi[1].spellID,12824)
end)
test("binding_codec_exact_and_secret",function()
    eq(T.Dispatch.Token("SHIFT-1"),197); eq(T.Dispatch.Token("CTRL-Q"),129)
    eq(T.Dispatch.Token("CTRL-SHIFT-1"),nil); eq(T.Dispatch.Token(secret),nil)
    detectorMode="error"; eq(T.Dispatch.Token("1"),nil)
end)
local function bindingFixture()
    ActionButton1={action=7,GetAttribute=function() return 7 end}
    GetActionInfo=function() return "spell",116 end; C_ActionBar=nil
    GetBindingKey=function() return "1" end
    UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
    T.UI.settingsOpen=false; T.Dispatch:SetEnabled(true); T.Profiles:Select(T.engine,"single"); T.engine:Start()
end
test("manual_request_packet_and_event_revoke_without_advance",function()
    bindingFixture(); assert(T.Dispatch:Request()); T.Transport:Paint()
    eq(T.Transport.fields[4],1); eq(T.Transport.fields[12],2); eq(T.Transport.fields[13],132)
    eq(T.Transport.fields[15],5); eq(T.Transport.fields[17],0); eq(T.engine.index,1)
    T.Dispatch:Event("UNIT_SPELLCAST_SENT","player",116); T.Transport:Paint()
    eq(T.Dispatch.pending,nil); eq(T.Transport.fields[15],0); eq(T.engine.index,1)
end)
test("request_secret_macro_binding_change_and_cast_fail_closed",function()
    bindingFixture(); GetActionInfo=function() return "macro",116 end; eq(T.Dispatch:Request(),false)
    GetActionInfo=function() return "spell",secret end; eq(T.Dispatch:Request(),false)
    GetActionInfo=function() return "spell",116 end; assert(T.Dispatch:Request())
    GetBindingKey=function() return "2" end; eq(T.Dispatch:Packet(),nil)
    bindingFixture(); assert(T.Dispatch:Request()); UnitCastingInfo=function() return secret end
    eq(T.Dispatch:Packet(),nil)
    bindingFixture(); assert(T.Dispatch:Request()); UnitChannelInfo=nil; eq(T.Dispatch:Packet(),nil)
end)
test("request_reset_pause_settings_and_late_work_invalidated",function()
    bindingFixture(); assert(T.Dispatch:Request()); T.engine:Pause(); eq(T.Dispatch.pending,nil)
    T.engine:Resume(); assert(T.Dispatch:Request()); T.engine:Reset(); eq(T.Dispatch:Packet(),nil)
    T.engine:Start(); assert(T.Dispatch:Request()); T.UI:OpenSettings(); eq(T.Dispatch.pending,nil)
    T.UI.settingsOpen=false; ActionButton1=nil
end)
test("permission_defaults_closed_and_block_reasons_persist",function()
    T.Dispatch:SetEnabled(false); T.UI.settingsOpen=false
    local ok,reason=T.Dispatch:Request(); eq(ok,false); eq(reason,"TEK_PERMISSION_DISABLED")
    eq(T.engine.db.diagnostics[#T.engine.db.diagnostics].reason,reason)
    T.Dispatch:SetEnabled(true); T.engine:Pause()
    ok,reason=T.Dispatch:Request(); eq(reason,"TEK_PRACTICE_PAUSED")
    T.engine:Resume(); T.UI.settingsOpen=true
    ok,reason=T.Dispatch:Request(); eq(reason,"TEK_SETTINGS_OPEN")
    T.UI.settingsOpen=false; T.Dispatch:SetEnabled(false)
end)
test("shared_run_permission_keys_and_stop_revoke",function()
    bindingFixture(); TEF_RunToggle(); eq(T.engine.running,false)
    TEF_RunToggle(); eq(T.engine.running,true)
    assert(T.Dispatch:Request()); TEF_StopAll()
    eq(T.Dispatch.enabled,false); eq(T.Dispatch.pending,nil); eq(T.engine.running,false)
    TEF_PermissionToggle(); eq(T.Dispatch.enabled,true); eq(T.Dispatch.pending,nil)
    T.Dispatch:SetEnabled(false); ActionButton1=nil
end)
test("hud_cd_event_only_own_cooldown_and_gcd",function()
    T.Presentation.cooldowns={}; GetTime=function() return 15 end
    C_Spell.GetSpellCooldown=function() return {startTime=10,duration=10,modRate=1,isEnabled=true,isOnGCD=false} end
    C_Spell.GetSpellCharges=function() return {currentCharges=1,maxCharges=2} end
    local view=T.Presentation:Read(116,false); eq(view.cd,"CD 未知"); eq(view.charges,"充能 1/2")
    view=T.Presentation:Read(116,true); eq(view.cd,"CD 5s")
    GetTime=function() return 16 end; view=T.Presentation:Read(116,false); eq(view.cd,"CD 4s")
    C_Spell.GetSpellCooldown=function() return {startTime=10,duration=10,modRate=1,isEnabled=true,isOnGCD=true} end
    view=T.Presentation:Read(116,true); eq(view.cd,"GCD"); eq(T.Presentation.cooldowns[116],nil)
end)
test("hud_secret_missing_failed_fields_do_not_guess",function()
    T.Presentation.cooldowns={}
    C_Spell.GetSpellCooldown=function() return {startTime=secret,duration=secret,modRate=1,isEnabled=true,isOnGCD=false} end
    C_Spell.GetSpellCharges=function() return {currentCharges=secret,maxCharges=2} end
    local view=T.Presentation:Read(116,true); eq(view.cd,"CD 未知"); eq(view.charges,"充能 未知")
    C_Spell.GetSpellCooldown=function() error("DO_NOT_EXPORT") end
    C_Spell.GetSpellCharges=nil
    view=T.Presentation:Read(116,true); eq(view.cd,"CD 未知"); eq(view.charges,"充能 未知")
    C_Spell.GetSpellCharges=function() return nil end
    view=T.Presentation:Read(116,false); eq(view.charges,"充能 —")
end)
test("one_duration_renderer_visual_only_and_tick_no_input",function()
    local renders=0; local called
    local card=T.HUD.cards[1]
    card.cooldown.SetCooldownFromDurationObject=function(_,value) renders=renders+1; assert(rawequal(value,secret)) end
    C_Spell.GetSpellCooldownDuration=function(id,ignore) called=ignore; return secret end
    C_Spell.GetSpellCharges=function() return nil end
    T.Presentation:Paint(card,T.engine.steps[1],false); eq(renders,1); eq(called,true)
    local index=T.engine.index; local fresh=T.Transport.freshness
    T.HUD.frame.scripts.OnUpdate(nil,.25); eq(T.engine.index,index); eq(T.Transport.freshness,fresh)
    T.HUD.frame.scripts.OnUpdate(nil,secret); eq(T.engine.index,index)
    card.cooldown.SetCooldownFromDurationObject=nil
end)
test("charge_duration_selected_once_and_no_permission_from_labels",function()
    local spells,charges=0,0
    C_Spell.GetSpellCharges=function() return {currentCharges=0,maxCharges=2} end
    C_Spell.GetSpellChargeDuration=function() charges=charges+1; return secret end
    C_Spell.GetSpellCooldownDuration=function() spells=spells+1; return secret end
    T.Dispatch:SetEnabled(false); local index=T.engine.index
    T.Presentation:Paint(T.HUD.cards[1],T.engine.steps[1],false)
    eq(charges,1); eq(spells,0); eq(T.Dispatch.pending,nil); eq(T.engine.index,index)
end)
test("locked_binding_survives_unrelated_action_updates",function()
    bindingFixture(); assert(T.Dispatch:Request())
    local pending=T.Dispatch.pending
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,pending)
    eq(T.Dispatch:Packet(),5); eq(T.engine.index,1)
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,pending)
    T.Dispatch:Cancel("TEK_MANUAL_STOP")
end)
test("locked_source_changed_or_unknown_revokes_immediately",function()
    bindingFixture(); assert(T.Dispatch:Request())
    GetActionInfo=function() return "spell",205 end
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,nil); eq(T.Transport.fields[15],0)
    bindingFixture(); assert(T.Dispatch:Request())
    GetBindingKey=function() return secret end
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,nil)
    bindingFixture(); assert(T.Dispatch:Request())
    ActionButton1={action=7,GetAttribute=function() return 7 end}
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,nil)
    bindingFixture(); assert(T.Dispatch:Request())
    GetActionInfo=function() error("PRIVATE_EXCEPTION") end
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,nil)
end)
test("production_request_keeps_success_confirmation_separate",function()
    bindingFixture(); SlashCmdList.TEF("dispatch"); assert(T.Dispatch.pending)
    T.Dispatch:Event("UNIT_SPELLCAST_FAILED","player",116)
    eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
    T.HUD:Refresh(); eq(T.Dispatch.pending,nil)
    TEF_StopAll(); eq(T.Dispatch.enabled,false); eq(T.engine.running,false)
end)
test("native_hud_public_cast_labels_remain_visual",function()
    bindingFixture(); T.Dispatch:SetEnabled(false)
    local index=T.engine.index
    UnitCastingInfo=function() return "公开读条" end; UnitChannelInfo=function() return nil end
    T.HUD:Refresh(); eq(T.HUD.cards[1].state.text,"施法")
    UnitCastingInfo=function() return secret end; UnitChannelInfo=function() return "公开引导" end
    T.HUD:Refresh(); eq(T.HUD.cards[1].state.text,"引导")
    UnitChannelInfo=function() return secret end
    T.HUD:Refresh(); eq(T.HUD.cards[1].state.text,"推荐")
    eq(T.engine.index,index); eq(T.Dispatch.pending,nil)
end)
test("native_hud_cd_and_charges_text_planes",function()
    GetTime=function() return 15 end
    C_Spell.GetSpellCooldown=function() return {startTime=10,duration=10,modRate=1,isEnabled=true,isOnGCD=false} end
    C_Spell.GetSpellCharges=function() return {currentCharges=1,maxCharges=2} end
    T.Presentation:Paint(T.HUD.cards[1],T.engine.steps[1],true)
    eq(T.HUD.cards[1].cooldownText.text,"5"); eq(T.HUD.cards[1].chargeText.text,"1/2")
    T.Presentation:Paint(T.HUD.cards[1],nil,false)
    eq(T.HUD.cards[1].cooldownText.text,""); eq(T.HUD.cards[1].chargeText.text,"")
end)
test("request_rejects_cast_channel_and_unknown_before_pending",function()
    for _,case in ipairs({"cast","channel","secret","missing","failed"}) do
        bindingFixture()
        if case=="cast" then UnitCastingInfo=function() return "读条" end
        elseif case=="channel" then UnitChannelInfo=function() return "引导" end
        elseif case=="secret" then UnitCastingInfo=function() return secret end
        elseif case=="missing" then UnitChannelInfo=nil
        else UnitCastingInfo=function() error("PRIVATE_ERROR") end end
        local index=T.engine.index
        local ok,reason=T.Dispatch:Request()
        eq(ok,false); eq(reason,"TEK_CAST_PRESENT_OR_UNKNOWN")
        eq(T.Dispatch.pending,nil); eq(T.engine.index,index)
    end
    bindingFixture(); assert(T.Dispatch:Request()); T.Dispatch:Cancel()
end)
realprint("TEF simulated tests: " .. count .. " passed\n")
