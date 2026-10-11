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
load("Config.lua"); load("Safety.lua"); load("APL/Packs/Mage/Abilities.lua"); load("APL/Packs/Mage/Talents.lua"); load("APL/TalentState.lua"); load("APL/Registry.lua"); load("APL/PublicConditions.lua"); load("APL/Custom.lua"); load("APL/State.lua"); load("APL/Conditions.lua"); load("APL/Trace.lua"); load("APL/Packs/Mage/Mage60.lua"); load("APL/Packs/Mage/Rules.lua"); load("APL/Engine.lua"); load("Sequence.lua")
load("HudStyles.lua"); load("Profiles.lua"); load("Recommendation.lua"); load("Research.lua")
local standard=T.StandardConfig or T.Config
local count=0
local function test(name,fn)
    UnitClass=function() return "法师","MAGE" end; GetSpecialization=nil
    detectorMode=nil; issecretvalue=detector
    C_Spell={GetSpellInfo=function(id) return {name="spell" .. id} end,GetSpellTexture=function() return 123 end}
    C_Spell.IsSpellInRange=function() return true end; C_Spell.IsSpellUsable=function() return true,false end
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
    GetCurrentKeyBoardFocus=function() return nil end
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
            elseif method=="CreateFontString" or method=="CreateTexture" then
                local child=object(); child.parent=self; child.kind=method=="CreateTexture" and "Texture" or "FontString"
                child.layer=select(2,...); local children=rawget(self,"children") or {}; self.children=children
                children[#children+1]=child; return child
            elseif method=="SetTexture" then if uiThrowTexture then error("TEXTURE_EXCEPTION") end; self.texture=(...)
            elseif method=="SetText" then self.text=(...)
            elseif method=="GetText" then return self.text
            elseif method=="GetEffectiveScale" then return 1
            elseif method=="SetChecked" then self.checked=(...)
            elseif method=="SetBackdrop" then self.backdrop=(...)
            elseif method=="SetBackdropColor" then self.backdropColor={...}
            elseif method=="SetBackdropBorderColor" then self.backdropBorderColor={...}
            elseif method=="GetChecked" then return self.checked
            elseif method=="GetPoint" then return "CENTER",UIParent,"CENTER",12,34 end
            if method=="SetVertexColor" or method=="SetColorTexture" then self.color={...}
            elseif method=="Show" then self.shown=true
            elseif method=="Hide" then self.shown=false
            elseif method=="StartMoving" then self.moves=(rawget(self,"moves") or 0)+1 end
        end
    end})
    return o
end
CreateFrame=function(kind,name,parent,template) local o=object(name); o.kind=kind; o.parent=parent; o.template=template; if name then allFrames[name]=o end; return o end
UIParent=object("UIParent"); SlashCmdList={}; print=function() end
GetBuildInfo=function() return "1.60.1","70338","date",16001 end
InCombatLockdown=function() return false end
GetCurrentKeyBoardFocus=function() return nil end
UnitExists=function() return true end; UnitCanAttack=function() return true end
UnitIsDeadOrGhost=function() return false end; IsPlayerMoving=function() return false end
UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
load("UI.lua"); load("UIComponents.lua"); load("SequenceEditor.lua"); load("CustomAPLEditor.lua"); load("HUD.lua"); load("Dispatch.lua"); load("Presentation.lua"); load("Transport.lua"); load("Runtime.lua"); load("Hotkeys.lua"); load("Core/Bootstrap.lua")
local realprint=io.write
test("toc_bootstrap_independent_namespace_sent_payload",function()
    local ef=allFrames.TEF_EventFrame
    assert(ef.events.UNIT_SPELLCAST_SENT and ef.events.UNIT_SPELLCAST_SUCCEEDED)
    local foreign={untouched=true}; TacticEchoDB=foreign; TEProbeDB=foreign
    ef.scripts.OnEvent(ef,"ADDON_LOADED","TACTIC-ECHO-FOREVER")
    assert(TEF_DB==T.engine.db); eq(T.engine.running,false); eq(TacticEchoDB,foreign); eq(TEProbeDB,foreign)
    local originalUnderscore=_G._
    T.Runtime:SetMode("manual")
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
    eq(T.UI.editor.text,"") -- unknown identity cannot inherit another profile's draft.
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
    SlashCmdList.TEF("hide"); eq(T.Transport.enabled,true); eq(T.engine.running,false)
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
    bindingFixture(); T.Runtime:Initialize(T.engine); T.Runtime:SetMode("manual")
    TEF_RunToggle(); eq(T.engine.running,true)
    TEF_RunToggle(); eq(T.engine.running,false)
    TEF_RunToggle(); eq(T.engine.running,true)
    assert(T.Dispatch:Request(true)); TEF_StopAll()
    eq(T.Dispatch.enabled,true); eq(T.Dispatch.pending,nil); eq(T.engine.running,false)
    TEF_PermissionToggle(); eq(T.Dispatch.enabled,false); eq(T.Dispatch.pending,nil)
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
    T.Runtime:Initialize(T.engine); T.Runtime:SetPermission(true); TEF_StopAll(); eq(T.Dispatch.enabled,true); eq(T.engine.running,false)
end)
test("native_hud_public_cast_labels_remain_visual",function()
    bindingFixture(); T.Dispatch:SetEnabled(false)
    local index=T.engine.index
    UnitCastingInfo=function() return "公开读条" end; UnitChannelInfo=function() return nil end
    T.HUD:Refresh(); eq(T.HUD.cards[1].state.text,"施法")
    UnitCastingInfo=function() return secret end; UnitChannelInfo=function() return "公开引导" end
    T.HUD:Refresh(); eq(T.HUD.cards[1].state.text,"引导")
    UnitChannelInfo=function() return secret end
    T.HUD:Refresh(); eq(T.HUD.cards[1].state.text,"暂停")
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
local bootstrapEngine=T.engine
local function continuousFixture(config)
    bindingFixture(); T.Dispatch:ClearBindingCache()
    T.engine=T.Engine.New(config or T.Config,{loop=false}); T.UI.engine=T.engine
    T.Transport.engine=T.engine; T.engine:Start()
    GetActionInfo=function() return "spell",T.engine.steps[T.engine.index].spellID end
    GetCurrentKeyBoardFocus=function() return nil end
    UnitExists=function() return true end; UnitCanAttack=function() return true end
    UnitIsDeadOrGhost=function() return false end; IsPlayerMoving=function() return false end
    C_Spell.IsSpellInRange=function() return true end
    C_Spell.IsSpellUsable=function() return true,false end
    C_Spell.GetSpellCooldown=function() return {startTime=0,duration=0,isEnabled=true} end
    C_Spell.GetSpellCharges=function() return nil end
    assert(T.Dispatch:SetContinuous(true))
end
local function receipt(event,id,guid)
    local consumed=T.Dispatch:Event(event,"player",id,guid)
    if not consumed then T.engine:Handle(T.engine.generation,event,"player",guid,id) end
end
test("continuous_four_steps_success_only_next_business_tick",function()
    continuousFixture()
    for i,id in ipairs({116,205,205,143}) do
        T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
        receipt("UNIT_SPELLCAST_SENT",id,"continuous"..i)
        eq(T.Dispatch.pending,nil)
        T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
        UnitCastingInfo=function() return "cast" end
        receipt("UNIT_SPELLCAST_SUCCEEDED",id,"continuous"..i)
        T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
        UnitCastingInfo=function() return nil end
    end
    eq(T.engine.completed,true); T.Dispatch:TickContinuous(); eq(T.Dispatch.continuous,false)
end)
test("continuous_unknown_required_filters_never_requests",function()
    for _,which in ipairs({"target","range","focus","missing","failure","detector"}) do
        continuousFixture()
        if which=="target" then UnitExists=function() return secret end
        elseif which=="range" then C_Spell.IsSpellInRange=function() return secret end
        elseif which=="focus" then GetCurrentKeyBoardFocus=function() return secret end
        elseif which=="missing" then C_Spell.IsSpellUsable=nil
        elseif which=="failure" then C_Spell.IsSpellInRange=function() error("PRIVATE") end
        else detectorMode="error" end
        T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
        detectorMode=nil; T.Dispatch:SetContinuous(false)
    end
end)
test("continuous_failure_interruption_and_deviation_stop",function()
    for _,event in ipairs({"UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED"}) do
        continuousFixture(); T.Dispatch:TickContinuous(); receipt(event,116,"failed")
        eq(T.Dispatch.continuous,false); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
    end
    continuousFixture(); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"outside")
    eq(T.Dispatch.continuous,true); eq(T.engine.index,1)
end)
test("continuous_single_step_loop_and_child_no_double_consumption",function()
    continuousFixture({{name="missiles",spellID=5143,matchIDs={5143}}})
    T.engine:SetLoop(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",5143,"channel")
    receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"channel")
    eq(T.engine.index,1); eq(T.engine.receiptSerial,1)
    receipt("UNIT_SPELLCAST_SUCCEEDED",7268,"child")
    eq(T.Dispatch.continuous,true); eq(T.engine.receiptSerial,1)
    UnitChannelInfo=function() return "channel" end
    T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
    UnitChannelInfo=function() return nil end
    T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"channel")
    eq(T.engine.receiptSerial,1)
    T.Dispatch:SetContinuous(false)
end)
test("continuous_pause_reset_reload_and_settings_invalidate",function()
    for _,method in ipairs({"Pause","Reset","Start"}) do
        continuousFixture(); T.Dispatch:TickContinuous(); T.engine[method](T.engine)
        eq(T.Dispatch.continuous,false); eq(T.Dispatch.pending,nil)
    end
    continuousFixture(); T.UI:OpenSettings(); eq(T.Dispatch.continuous,false)
    T.UI.settingsOpen=false
    continuousFixture(); T.engine:Pause(); local old=T.engine.db
    T.engine=T.Engine.New(T.Config,old); eq(T.engine.running,false); eq(T.Dispatch.continuous,false)
end)
test("continuous_target_binding_permission_transport_stop",function()
    continuousFixture(); T.Dispatch:TickContinuous()
    local pending=T.Dispatch.pending
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,pending); eq(T.Dispatch.continuous,true)
    GetBindingKey=function() return "2" end; T.Dispatch:BindingsChanged()
    eq(T.Dispatch.continuous,false); eq(T.Dispatch.pending,nil)
    continuousFixture(); T.Dispatch:SetEnabled(false); eq(T.Dispatch.continuous,false)
    continuousFixture(); T.Transport:SetEnabled(false); eq(T.Dispatch.continuous,false)
end)
test("continuous_saturation_deduplicates_wait_reason",function()
    continuousFixture(); UnitExists=function() return secret end
    for i=1,200 do T.engine:Log("observed","TEST_FILL") end
    T.Dispatch:TickContinuous(); local evicted=T.engine.db.evicted
    for i=1,200 do T.Dispatch:TickContinuous() end
    eq(#T.engine.db.diagnostics,128); eq(T.engine.db.evicted,evicted); eq(T.Dispatch.pending,nil)
end)
test("continuous_reentrant_lifecycle_discards_evidence",function()
    continuousFixture(); C_Spell.IsSpellUsable=function() T.engine:Reset(); return true,false end
    T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.Dispatch.continuous,false)
end)
test("continuous_explicit_opt_in_requires_running_permission",function()
    bindingFixture(); T.Dispatch:SetEnabled(false); eq(T.Dispatch:SetContinuous(true),false)
    T.Dispatch:SetEnabled(true); T.engine:Pause(); eq(T.Dispatch:SetContinuous(true),false)
    T.engine:Resume(); T.UI.settingsOpen=true; eq(T.Dispatch:SetContinuous(true),false)
    T.UI.settingsOpen=false
end)
test("continuous_packet_rechecks_evidence_and_revokes",function()
    continuousFixture(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    UnitExists=function() return secret end
    eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil); eq(T.Dispatch.continuous,false)
    eq(T.engine.index,1)
end)
test("continuous_start_stop_and_failure_never_advance",function()
    continuousFixture(); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_START",116,"startonly")
    receipt("UNIT_SPELLCAST_STOP",116,"startonly")
    T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
    T.Dispatch:SetContinuous(false)
end)
test("diagnostics_version_survives_reload_without_arming",function()
    continuousFixture(); T.engine:Log("observed","VERSION_TEST")
    local old=T.engine.db; T.engine:Pause()
    local reloaded=T.Engine.New(T.Config,old)
    eq(reloaded.db.diagnostics[#reloaded.db.diagnostics].version,T.Version)
    eq(reloaded.running,false); eq(T.Dispatch.continuous,false)
end)
test("packet_final_api_reentry_cannot_emit_stale_token",function()
    continuousFixture(); T.Dispatch:TickContinuous()
    InCombatLockdown=function() T.engine:Reset(); return false end
    eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil); eq(T.Dispatch.continuous,false)
end)
test("fixed_attempt_never_reads_unknown_cooldown_gcd_or_charges",function()
    continuousFixture()
    local queries=0
    C_Spell.GetSpellCooldown=function() queries=queries+1; error("MUST_NOT_READ") end
    C_Spell.GetSpellCharges=function() queries=queries+1; return secret end
    T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    InCombatLockdown=function() return false end
    eq(T.Dispatch:Packet(),5); eq(queries,0); eq(T.engine.index,1)
    T.Dispatch:SetContinuous(false)
end)
test("continuous_no_binding_lock_ignores_unrelated_refresh",function()
    continuousFixture(); T.Dispatch:BindingsChanged(); eq(T.Dispatch.continuous,true)
    T.Dispatch:TickContinuous(); local pending=T.Dispatch.pending
    T.Dispatch:BindingsChanged(); eq(T.Dispatch.pending,pending)
    T.Dispatch:SetContinuous(false)
end)
test("continuous_combat_entry_preserves_request_target_change_stops",function()
    continuousFixture()
    T.Dispatch:SetContinuous(false)
    T.engine=bootstrapEngine; T.Transport.engine=bootstrapEngine; T.UI.engine=bootstrapEngine
    T.Runtime:Initialize(bootstrapEngine); T.Runtime:SetMode("manual")
    bootstrapEngine:Start(); T.Dispatch:SetEnabled(true); assert(T.Dispatch:SetContinuous(true))
    T.Dispatch:TickContinuous(); local pending=T.Dispatch.pending; assert(pending)
    local ef=allFrames.TEF_EventFrame
    InCombatLockdown=function() return true end
    ef.scripts.OnEvent(ef,"PLAYER_REGEN_DISABLED")
    eq(T.Dispatch.continuous,true); eq(T.Dispatch.pending,pending)
    local token,combat=T.Dispatch:Packet(); eq(token,5); eq(combat,true)
    ef.scripts.OnEvent(ef,"PLAYER_TARGET_CHANGED")
    eq(T.Dispatch.continuous,false); eq(T.Dispatch.pending,nil)
end)
test("class_profiles_all_classes_isolated_and_legacy_mage_only",function()
    for _,class in ipairs({"WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT","SHAMAN","WARLOCK","MONK","DRUID","DEMONHUNTER","EVOKER"}) do
        UnitClass=function() return "职业",class end
        local e=engine(nil,{profiles={single=T.Config,multi=T.ProfileDefaults.multi}})
        eq(e.profileKey,class..":base"); eq(e.steps,nil); eq(#e.db.profiles.single,0)
        eq(e.db.classProfiles["MAGE:base"].single[1].spellID,116)
        assert(T.Profiles:Save(e,"single",{{name="明确技能",spellID=100,matchIDs={100}}}))
        eq(e.steps[1].spellID,100); eq(e.db.classProfiles["MAGE:base"].single[1].spellID,116)
    end
end)
test("profile_specialization_switch_invalidates_and_restores_own_rows",function()
    GetSpecialization=function() return 1 end; GetSpecializationInfo=function() return 62 end
    local e=engine(); T.Profiles:Select(e,"single"); e:Start(); local generation=e.generation
    GetSpecializationInfo=function() return 63 end; assert(T.Profiles:RefreshIdentity(e))
    eq(e.profileKey,"MAGE:63"); eq(e.running,false); eq(e.steps,nil); assert(e.generation>generation)
    assert(T.Profiles:Save(e,"single",{{name="火球",spellID=143,matchIDs={143}}}))
    GetSpecializationInfo=function() return 62 end; T.Profiles:RefreshIdentity(e); eq(e.steps[1].spellID,116)
end)
test("profile_secret_unknown_failed_identity_no_fallback",function()
    UnitClass=function() return "职业",secret end; eq(engine().steps,nil)
    UnitClass=function() error("PRIVATE") end; eq(engine().profileKey,nil)
    UnitClass=function() return "法师","MAGE" end; GetSpecialization=function() return secret end
    eq(engine().profileKey,nil)
    GetSpecialization=function() error("PRIVATE") end; eq(engine().steps,nil)
end)
test("recommendation_sources_explicit_code_no_manual_fallback",function()
    local e=engine(); assert(T.Profiles:Save(e,"single",{{name="火球",spellID=143,matchIDs={143}}}))
    eq(T.Recommendation:Current(e).source,"manual"); eq(e.steps[1].spellID,143)
    assert(T.Recommendation:SetSource(e,"code")); eq(e.steps[1].spellID,116)
    UnitClass=function() return "战士","WARRIOR" end; e=engine()
    assert(T.Profiles:Save(e,"single",{{name="明确",spellID=100,matchIDs={100}}}))
    eq(T.Recommendation:SetSource(e,"code"),false); eq(e.steps,nil); eq(T.Recommendation:Current(e),nil)
end)
local function runtimeFixture(mode)
    continuousFixture(); T.Dispatch:SetContinuous(false); T.engine:Reset()
    T.engine.db.dispatch={mode=mode or "auto"}
    T.Runtime:Initialize(T.engine); T.Runtime:SetSignal(true)
    T.UI.settingsOpen=false; InCombatLockdown=function() return false end
end
test("runtime_default_world_autostart_standby_and_combat",function()
    runtimeFixture(); local e=T.engine; eq(e.db.dispatch.permission,true); eq(e.db.dispatch.signal,true)
    eq(e.db.dispatch.autoStart,true); eq(T.Runtime.intent,false)
    T.Runtime:World(); eq(T.Runtime.intent,true); eq(T.Runtime.state,"standby"); eq(e.running,false)
    T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
    InCombatLockdown=function() return true end; T.Runtime:Tick(); T.Dispatch:TickContinuous()
    eq(e.running,true); assert(T.Dispatch.pending)
    InCombatLockdown=function() return false end; T.Runtime:Tick()
    eq(T.Runtime.intent,true); eq(T.Runtime.state,"standby"); eq(T.Dispatch.pending,nil)
    InCombatLockdown=function() return true end; T.Runtime:Tick(); eq(e.running,true)
end)
test("runtime_manual_pause_sticky_and_stop_mode",function()
    runtimeFixture("manual"); assert(T.Runtime:Start(false)); eq(T.engine.running,true)
    T.Runtime:Stop(); InCombatLockdown=function() return true end; T.Runtime:Tick()
    eq(T.Runtime.intent,false); eq(T.engine.running,false); eq(T.Dispatch.enabled,true)
    assert(T.Runtime:Start(false)); T.Runtime:SetMode("stop")
    InCombatLockdown=function() return false end; T.Runtime:Tick(); eq(T.Runtime.intent,false)
    InCombatLockdown=function() return true end; T.Runtime:Tick(); eq(T.engine.running,false)
end)
test("runtime_duplicate_single_request_preserves_automatic_wait",function()
    runtimeFixture("manual"); assert(T.Runtime:Start(false)); T.Dispatch:TickContinuous()
    local pending=T.Dispatch.pending; assert(pending)
    local ok,reason=T.Dispatch:Request(); eq(ok,true); eq(reason,"TEK_REQUEST_ALREADY_PENDING")
    eq(T.Dispatch.pending,pending); eq(T.Dispatch.continuous,true)
    receipt("UNIT_SPELLCAST_SENT",116,"s37-fixed")
    ok,reason=T.Dispatch:Request(); eq(ok,false); eq(reason,"TEK_AUTOMATIC_OWNS_REQUEST")
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"s37-fixed")
    T.Runtime:Tick(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); eq(T.engine.index,2)
    eq(T.engine.db.diagnostics[#T.engine.db.diagnostics].request,2)
end)
test("runtime_one_enable_completes_adjacent_steps_without_clicks",function()
    runtimeFixture("manual"); assert(T.Runtime:Start(false))
    for i,id in ipairs({116,205,205,143}) do
        T.Runtime:Tick(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
        receipt("UNIT_SPELLCAST_SENT",id,"new-run"..i); receipt("UNIT_SPELLCAST_SUCCEEDED",id,"new-run"..i)
    end
    eq(T.engine.completed,true); T.Runtime:Tick(); eq(T.Runtime.intent,false); eq(T.Dispatch.pending,nil)
    T.Runtime:Tick(); eq(T.engine.index,4)
end)
test("runtime_saved_preferences_reload_world_no_old_tasks",function()
    runtimeFixture("manual"); T.engine.db.dispatch.autoStart=false; T.Runtime:Start(false)
    receipt("UNIT_SPELLCAST_SENT",116,"old-run")
    local e=engine(T.Config,T.engine.db); T.engine=e; T.Transport.engine=e; T.UI.engine=e; T.Runtime:Initialize(e)
    T.Runtime:World(); eq(e.running,false); eq(T.Runtime.intent,false)
    T.Runtime:Start(false); receipt("UNIT_SPELLCAST_SUCCEEDED",116,"old-run"); eq(e.index,1)
    T.Runtime:SetPermission(false); eq(T.Runtime.intent,false); eq(T.Dispatch.pending,nil)
    e=engine(T.Config,e.db); eq(e.db.dispatch.permission,false); eq(e.db.dispatch.autoStart,false)
end)
test("runtime_world_settings_unknown_client_revoke",function()
    runtimeFixture("manual"); T.engine.clientValidated=false; eq(T.Runtime:Start(false),false)
    T.engine.clientValidated=true; T.Runtime:Start(false); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    T.UI.settingsOpen=true; T.Runtime:Tick(); eq(T.Dispatch.pending,nil); eq(T.engine.running,false)
    T.UI.settingsOpen=false; T.Runtime:Tick(); eq(T.engine.running,true)
    InCombatLockdown=function() return secret end; T.Runtime:Tick(); eq(T.engine.running,false)
    eq(T.Runtime.state,"blocked"); T.Runtime:World(); eq(T.Runtime.intent,true)
    T.Runtime:World(); eq(T.Runtime.intent,false)
end)
test("hotkey_conflicts_deferred_apply_and_no_actionbar_write",function()
    runtimeFixture(); local applied=0; local cleared=0
    local overrides={}; T.Hotkeys.appliedKey=nil
    ClearOverrideBindings=function() cleared=cleared+1; overrides={} end
    SetOverrideBinding=function(owner,priority,key,command) eq(command,"TEF_TOGGLE_DISPATCH"); applied=applied+1; overrides[key]=command end
    GetBindingAction=function() return "ACTIONBUTTON1" end
    local ok,reason=T.Hotkeys:Set("CTRL-Q"); eq(ok,false); eq(reason,"HOTKEY_CONFLICT"); eq(applied,0)
    GetBindingAction=function(key,checkOverrides) return checkOverrides and overrides[key] or "" end; assert(T.Hotkeys:Set("CTRL-Q")); eq(applied,1)
    InCombatLockdown=function() return true end; ok,reason=T.Hotkeys:Set("SHIFT-Q")
    eq(ok,false); eq(reason,"HOTKEY_DEFERRED"); eq(applied,1); eq(T.engine.db.dispatch.hotkey,"SHIFT-Q")
    InCombatLockdown=function() return false end; assert(T.Hotkeys:Apply()); eq(applied,2)
    GetBindingAction=function() return secret end; eq(T.Hotkeys:Apply(),false); eq(applied,2)
    GetBindingAction=function() return "" end; assert(T.Hotkeys:Set("")); eq(applied,2)
    eq(T.Hotkeys.Normalize("LCTRL"),nil); assert(cleared>=3)
end)
test("hotkey_capture_modifier_keeps_recording_and_esc_finishes",function()
    local editor=object(); IsControlKeyDown=function() return true end
    IsAltKeyDown=function() return false end; IsShiftKeyDown=function() return true end
    eq(T.Hotkeys:Capture(editor,"LCTRL"),false); eq(rawget(editor,"text"),nil)
    eq(T.Hotkeys:Capture(editor,"Q"),true); eq(editor.text,"CTRL-SHIFT-Q")
    eq(T.Hotkeys:Capture(editor,"ESCAPE"),true)
    IsShiftKeyDown=function() return secret end; eq(T.Hotkeys:Capture(editor,"R"),nil)
end)
local function deliveryFixture(mode)
    runtimeFixture(mode or "manual")
    T.HUD.engine=T.engine; T.UI.engine=T.engine
    T.UI.settings=nil; T.UI.controls={}; T.UI:CreateSettings()
    T.engine.db.loop=false; T.Runtime:Reconcile(); T.HUD:Refresh()
end
test("dispatch_intent_single_source",function()
    deliveryFixture(); eq(T.Runtime.intent,false)
    assert(T.Runtime:SetIntent(true)); local gen=T.engine.generation
    assert(T.Runtime:SetIntent(true)); eq(T.engine.generation,gen)
    T.Runtime:ToggleIntent(); eq(T.Runtime.intent,false); eq(T.Dispatch.continuous,false)
    eq(T.engine.running,false); eq(T.Dispatch.pending,nil)
    T.Runtime:ToggleIntent(); eq(T.Runtime.intent,true)
end)
test("legacy_toggle_wrappers_same_intent",function()
    deliveryFixture(); eq(TEF_RunToggle,TEF_ToggleDispatchIntent)
    eq(TEF_ContinuousToggle,TEF_ToggleDispatchIntent); eq(TEF_DispatchToggle,TEF_ToggleDispatchIntent)
    TEF_RunToggle(); eq(T.Runtime.intent,true)
    TEF_ContinuousToggle(); eq(T.Runtime.intent,false)
    TEF_DispatchToggle(); eq(T.Runtime.intent,true)
end)
test("settings_open_preserves_intent_and_zeroes_token",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); T.Transport:Paint(); eq(T.Transport.fields[15],5)
    T.UI:OpenSettings(); eq(T.Runtime.intent,true); eq(T.Runtime.state,"standby")
    eq(T.Dispatch.pending,nil); eq(T.Dispatch.continuous,false); eq(T.engine.running,false)
    eq(T.Transport.fields[15],0)
end)
test("settings_close_reconciles_without_restoring_old_pending",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    local old=T.Dispatch.pending; receipt("UNIT_SPELLCAST_SENT",116,"pre-settings")
    T.UI:OpenSettings(); T.UI:CloseSettings()
    eq(T.Runtime.intent,true); eq(T.Runtime.state,"running"); eq(T.Dispatch.pending,nil)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"pre-settings"); eq(T.engine.index,1)
    T.Dispatch:TickContinuous(); assert(T.Dispatch.pending and T.Dispatch.pending~=old)
    assert(T.Dispatch.pending.generation~=old.generation)
end)
test("temporary_block_does_not_disable_intent",function()
    for _,which in ipairs({"focus","target","combat","range","moving","usable"}) do
        deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
        local old=T.Dispatch.pending
        if which=="focus" then GetCurrentKeyBoardFocus=function() return secret end
        elseif which=="target" then UnitExists=function() return false end
        elseif which=="combat" then InCombatLockdown=function() return secret end
        elseif which=="range" then C_Spell.IsSpellInRange=function() return secret end
        elseif which=="moving" then IsPlayerMoving=function() return true end; C_Spell.IsSpellUsable=function() return false,false end
        else C_Spell.IsSpellUsable=function() return false,true end end
        T.Runtime:Reconcile(); eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked")
        eq(T.Dispatch.pending,nil); T.Transport:Paint(); eq(T.Transport.fields[15],0)
        GetCurrentKeyBoardFocus=function() return nil end; UnitExists=function() return true end
        InCombatLockdown=function() return false end; IsPlayerMoving=function() return false end
        C_Spell.IsSpellInRange=function() return true end; C_Spell.IsSpellUsable=function() return true,false end
        T.Runtime:Reconcile(); eq(T.Runtime.state,"running"); T.Dispatch:TickContinuous()
        assert(T.Dispatch.pending and T.Dispatch.pending~=old)
    end
end)
test("permission_off_hard_stops",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    T.Runtime:SetPermission(false); eq(T.Runtime.intent,false); eq(T.Dispatch.pending,nil)
    eq(T.engine.running,false); T.Runtime:SetPermission(true); eq(T.Runtime.intent,false)
end)
test("signal_off_hard_stops",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    T.Runtime:SetSignal(false); eq(T.Runtime.intent,false); eq(T.Transport.enabled,false)
    eq(T.Dispatch.pending,nil); T.Runtime:SetSignal(true); eq(T.Runtime.intent,false)
end)
test("hide_is_visual_only",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    local pending=T.Dispatch.pending; local gen=T.engine.generation
    SlashCmdList.TEF("hide"); eq(T.Runtime.intent,true); eq(T.engine.running,true)
    eq(T.Transport.enabled,true); eq(T.Dispatch.pending,pending); eq(T.engine.generation,gen)
    eq(T.HUD.frame.shown,false); SlashCmdList.TEF("show"); eq(T.HUD.frame.shown,true)
end)
test("ui_callback_failure_uses_runtime_fault",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    local b=T.UI:CreateActionButton(UIParent,"broken",0,0,100,function() error("DO_NOT_SAVE") end)
    b.scripts.OnClick(); eq(T.Runtime.intent,false); eq(T.Runtime.state,"error")
    eq(T.Dispatch.pending,nil); eq(T.engine.running,false)
    eq(T.Runtime.reason,"UI_CALLBACK_FAILED")
end)
test("hud_primary_left_click_toggles_intent_only",function()
    deliveryFixture(); local card=T.HUD.cards[1]; eq(card.frame.kind,"Button")
    local before=T.engine.index
    card.frame.scripts.OnClick(card.frame,"LeftButton")
    eq(T.Runtime.intent,true); eq(T.engine.index,before); eq(T.Dispatch.pending,nil)
    card.frame.scripts.OnClick(card.frame,"LeftButton"); eq(T.Runtime.intent,false)
end)
test("hud_primary_never_requests_or_casts",function()
    deliveryFixture(); local original=T.Dispatch.Request
    T.Dispatch.Request=function() error("DIRECT_REQUEST_FORBIDDEN") end
    local calls=0; local forbidden=function() calls=calls+1 end
    CastSpellByID=forbidden; UseAction=forbidden
    T.HUD.cards[1].frame.scripts.OnClick(T.HUD.cards[1].frame,"LeftButton")
    eq(T.Runtime.intent,true); eq(calls,0); eq(T.Dispatch.pending,nil)
    T.Dispatch.Request=original; CastSpellByID=nil; UseAction=nil
end)
test("hud_and_settings_toggle_stay_in_sync",function()
    deliveryFixture(); T.UI:OpenSettings(); T.UI:ShowPage("overview")
    T.UI.intentToggle.scripts.OnClick(); eq(T.Runtime.intent,true); eq(T.Runtime.state,"standby")
    eq(T.UI.intentToggle.text,"开启")
    T.HUD.cards[1].frame.scripts.OnClick(T.HUD.cards[1].frame,"LeftButton")
    eq(T.Runtime.intent,false); eq(T.UI.intentToggle.text,"关闭")
    T.UI:CloseSettings(); eq(T.Runtime.intent,false)
end)
test("hotkey_and_hud_toggle_stay_in_sync",function()
    deliveryFixture(); TEF_ToggleDispatchIntent(); eq(T.Runtime.intent,true)
    T.HUD.cards[1].frame.scripts.OnClick(T.HUD.cards[1].frame,"LeftButton"); eq(T.Runtime.intent,false)
    TEF_DispatchToggle(); eq(T.Runtime.intent,true)
end)
test("auto_mode_out_of_combat_standby_keeps_intent",function()
    deliveryFixture("auto"); T.Runtime:SetIntent(true)
    eq(T.Runtime.intent,true); eq(T.Runtime.state,"standby"); T.Transport:Paint(); eq(T.Transport.fields[15],0)
    InCombatLockdown=function() return true end; T.Runtime:Reconcile(); eq(T.Runtime.state,"running")
    eq(T.Runtime.intent,true)
end)
test("manual_mode_out_of_combat_runs",function()
    deliveryFixture("manual"); T.Runtime:SetIntent(true); eq(T.Runtime.state,"running"); eq(T.engine.running,true)
end)
test("combatstop_mode_clears_intent_on_leave_combat",function()
    deliveryFixture("stop"); InCombatLockdown=function() return true end
    T.Runtime:SetIntent(true); eq(T.Runtime.intent,true)
    InCombatLockdown=function() return false end; T.Runtime:Reconcile(); eq(T.Runtime.intent,false)
    InCombatLockdown=function() return true end; T.Runtime:Reconcile(); eq(T.engine.running,false)
end)
test("hud_visual_states_hover_pressed_and_right_click",function()
    deliveryFixture(); local c=T.HUD.cards[1]; local colors={}
    for _,state in ipairs({"paused","standby","running","blocked","completed","error"}) do
        T.Runtime:Changed(state,"TEST_VISUAL_STATE"); T.HUD:RefreshState()
        colors[table.concat(c.border.color,",")]=true
    end
    local n=0; for _ in pairs(colors) do n=n+1 end; eq(n,6)
    c.frame.scripts.OnEnter(); eq(c.overlay.color[4],.12)
    c.frame.scripts.OnMouseDown(); eq(c.overlay.color[4],.22)
    c.frame.scripts.OnMouseUp(); eq(c.overlay.color[4],.12)
    c.frame.scripts.OnLeave(); eq(c.overlay.color[4],.025)
    T.Runtime:SetIntent(true); c.frame.scripts.OnClick(c.frame,"RightButton")
    eq(T.UI.settingsOpen,true); eq(T.Runtime.intent,true); eq(T.Runtime.state,"standby")
    T.UI:CloseSettings()
end)
test("hud_lock_drag_and_primary_click_do_not_conflict",function()
    deliveryFixture(); local f=T.HUD.frame; local moves=rawget(f,"moves") or 0
    T.engine.db.hud.locked=true; f.scripts.OnDragStart(); eq(rawget(f,"moves") or 0,moves)
    T.engine.db.hud.locked=false; f.scripts.OnDragStart(); eq(f.moves,moves+1)
    T.HUD.cards[1].frame.scripts.OnClick(T.HUD.cards[1].frame,"LeftButton"); eq(T.Runtime.intent,false)
    f.scripts.OnDragStop(); T.HUD.cards[1].frame.scripts.OnClick(T.HUD.cards[1].frame,"LeftButton")
    eq(T.Runtime.intent,true); eq(f.moves,moves+1)
end)
test("mode_controls_do_not_change_advanced_gates_and_hud_has_no_test_buttons",function()
    deliveryFixture(); T.UI:OpenSettings(); local settings=T.engine.db.dispatch
    T.UI.modeControls.manual.scripts.OnClick(); eq(settings.mode,"manual")
    eq(settings.signal,true); eq(settings.permission,true)
    eq(T.HUD.permission,nil); eq(T.HUD.pause,nil)
    eq(T.UI.testReset.parent,T.UI.pages.diagnostics); eq(T.UI.testSingle.parent,T.UI.pages.diagnostics)
    eq(T.UI.signalToggle.parent,T.UI.pages.tek); eq(T.UI.intentToggle.parent,T.UI.pages.overview)
    T.UI:CloseSettings()
end)
test("hud_fallback_never_scans_metadata_bindings_or_spell_apis",function()
    deliveryFixture(); T.HUD:Refresh()
    local reads=0; local resolver=T.Dispatch.Resolve
    T.Dispatch.Resolve=function() reads=reads+1 end
    C_Spell.GetSpellInfo=function() reads=reads+1 end; C_Spell.GetSpellCooldown=function() reads=reads+1 end
    C_Spell.GetSpellCharges=function() reads=reads+1 end
    UnitCastingInfo=function() reads=reads+1 end; UnitChannelInfo=function() reads=reads+1 end
    for i=1,40 do T.HUD.frame.scripts.OnUpdate(nil,.25) end
    eq(reads,0); T.Dispatch.Resolve=resolver
end)
test("runtime_cast_block_preserves_success_and_never_writes_cast_absent",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"active-cast")
    UnitCastingInfo=function() return "施法" end; T.Runtime:Reconcile()
    eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked"); eq(T.engine.running,true)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"active-cast"); eq(T.engine.index,2)
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
    eq(T.engine.castPresent,nil)
    UnitCastingInfo=function() return nil end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
end)
test("runtime_target_suspend_rejects_old_receipt_and_reacquires_fresh",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"old-target")
    T.Runtime:Suspend("RUNTIME_TARGET_CHANGED"); eq(T.Runtime.intent,true); eq(T.Dispatch.pending,nil)
    T.Runtime:Reconcile(); receipt("UNIT_SPELLCAST_SUCCEEDED",116,"old-target"); eq(T.engine.index,1)
    T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
end)
test("runtime_api_reentry_cannot_resume_cleared_intent",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Runtime:Suspend("TEST_SUSPEND")
    UnitExists=function() T.Runtime:Stop(); return true end
    T.Runtime:Reconcile(); eq(T.Runtime.intent,false); eq(T.engine.running,false); eq(T.Dispatch.continuous,false)
end)
test("binding_miss_cache_prevents_heartbeat_rescans_and_event_recovers",function()
    deliveryFixture(); local scans=0; local original=T.Dispatch.Resolve
    T.Dispatch.Resolve=function() scans=scans+1; return nil,"TEK_EXACT_DIRECT_BINDING_UNAVAILABLE" end
    T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked")
    for i=1,100 do T.Runtime:Reconcile(); T.Dispatch:TickContinuous() end
    eq(scans,1); eq(T.Dispatch.pending,nil)
    T.Dispatch.Resolve=original; T.Dispatch:BindingsChanged(); T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
end)
test("ui_disabled_action_never_calls_callback_or_changes_intent",function()
    deliveryFixture(); local called=0
    local b=T.UI:CreateActionButton(T.UI.frame,"disabled",0,0,100,function() called=called+1 end)
    T.UI:SetControlEnabled(b,false); b.scripts.OnClick(); b.scripts.OnEnter()
    eq(called,0); eq(T.Runtime.intent,false)
    eq(T.UI.testSingle.tefControlEnabled,false)
    T.UI:SetControlEnabled(b,true); b.scripts.OnClick(); eq(called,1)
end)
test("movement_failure_keeps_intent_and_retries_same_step",function()
    for _,event in ipairs({"UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET"}) do
        deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
        receipt("UNIT_SPELLCAST_SENT",116,"moving-old"); IsPlayerMoving=function() return true end
        receipt(event,116,"moving-old"); eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked")
        eq(T.engine.index,1); eq(T.Dispatch.pending,nil); T.Transport:Paint(); eq(T.Transport.fields[15],0)
        IsPlayerMoving=function() return false end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
        assert(T.Dispatch.pending); eq(T.Runtime.state,"running")
        receipt("UNIT_SPELLCAST_SENT",116,"moving-new"); receipt("UNIT_SPELLCAST_SUCCEEDED",116,"moving-new")
        eq(T.engine.index,2); eq(T.engine.receiptSerial,1)
    end
end)
test("movement_old_failure_start_success_cannot_affect_retry",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"m-old"); IsPlayerMoving=function() return true end
    receipt("UNIT_SPELLCAST_INTERRUPTED",116,"m-old")
    IsPlayerMoving=function() return false end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    local pending=T.Dispatch.pending
    for _,event in ipairs({"UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_STOP"}) do receipt(event,116,"m-old") end
    eq(T.Runtime.intent,true); eq(T.engine.index,1); eq(T.Dispatch.pending,pending)
    eq(T.engine.associations["m-old"],nil)
end)
test("movement_receipt_after_heartbeat_suspend_remains_temporary",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"m-suspend"); IsPlayerMoving=function() return true end
    C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Reconcile(); eq(T.Dispatch.continuous,false)
    receipt("UNIT_SPELLCAST_INTERRUPTED",116,"m-suspend"); eq(T.Runtime.intent,true)
    IsPlayerMoving=function() return false end; C_Spell.IsSpellUsable=function() return true,false end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_FAILED",116,"m-suspend"); eq(T.Runtime.intent,true); assert(T.Dispatch.pending)
end)
test("associated_stationary_failure_retries_without_disabling_intent",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"stationary-fail")
    receipt("UNIT_SPELLCAST_FAILED",116,"stationary-fail")
    eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked"); eq(T.engine.index,1)
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
end)
test("adjacent_old_success_failure_does_not_stop_current_request",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"a-1"); receipt("UNIT_SPELLCAST_SUCCEEDED",116,"a-1")
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",205,"a-2"); receipt("UNIT_SPELLCAST_SUCCEEDED",205,"a-2")
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); local pending=T.Dispatch.pending
    receipt("UNIT_SPELLCAST_FAILED",205,"a-2")
    eq(T.Runtime.intent,true); eq(T.engine.index,3); eq(T.Dispatch.pending,pending)
end)
test("failure_unknown_identity_or_movement_zero_token_no_advance",function()
    for _,which in ipairs({"secret-guid","nil-guid","unknown-moving","failed-moving"}) do
        deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
        receipt("UNIT_SPELLCAST_SENT",116,"unknown-m")
        local guid="unknown-m"
        if which=="secret-guid" then guid=secret elseif which=="nil-guid" then guid=nil
        elseif which=="unknown-moving" then IsPlayerMoving=function() return secret end
        else IsPlayerMoving=function() error("EXTERNAL") end end
        receipt("UNIT_SPELLCAST_FAILED",116,guid)
        eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked"); eq(T.engine.index,1)
        T.Transport:Paint(); eq(T.Transport.fields[15],0)
    end
end)
test("movement_failure_api_reentry_cannot_revive_manual_stop",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"reentry-m")
    IsPlayerMoving=function() T.Runtime:Stop(); return true end
    receipt("UNIT_SPELLCAST_INTERRUPTED",116,"reentry-m")
    eq(T.Runtime.intent,false); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
end)
test("movement_identity_capacity_fails_closed_and_reload_clears",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    T.engine.seenCount=4096; IsPlayerMoving=function() return true end
    receipt("UNIT_SPELLCAST_INTERRUPTED",116,"capacity-m")
    eq(T.Runtime.intent,false); eq(T.Runtime.state,"error"); eq(T.Dispatch.pending,nil)
    eq(T.Runtime:SetIntent(true),false)
    eq(T.Runtime.reason,"RUNTIME_IDENTITY_CAPACITY_RELOAD_REQUIRED")
    deliveryFixture(); eq(T.engine.seenCount,0); eq(T.engine.identitySaturated,nil)
    eq(T.Runtime:SetIntent(true),true)
end)
test("failed_attempts_beyond_128_retry_and_old_guid_stays_retired",function()
    deliveryFixture(); IsPlayerMoving=function() return true end; T.Runtime:SetIntent(true)
    for i=1,150 do
        T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
        local guid="over128-" .. i
        receipt("UNIT_SPELLCAST_SENT",116,guid)
        receipt("UNIT_SPELLCAST_FAILED",116,guid)
        eq(T.Runtime.intent,true); eq(T.engine.index,1)
    end
    eq(T.engine.seenCount,150)
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_START",116,"over128-1")
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"over128-1")
    eq(T.engine.index,1); eq(T.engine.associations["over128-1"],nil)
    T.Runtime:Stop(); T.Runtime:SetIntent(true); eq(T.Runtime.intent,true)
end)

test("foreign_skill_combat_opener_keeps_auto_intent_and_first_step",function()
    deliveryFixture("auto"); T.Runtime:World(); eq(T.Runtime.state,"standby")
    receipt("UNIT_SPELLCAST_SENT",5019,"opener"); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"opener")
    InCombatLockdown=function() return true end; UnitCastingInfo=function() return "shoot" end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); eq(T.Runtime.intent,true); eq(T.Dispatch.pending,nil)
    UnitCastingInfo=function() return nil end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,116); eq(T.engine.index,1)
end)
test("foreign_cast_releases_uninitiated_candidate_wait",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    local pending=T.Dispatch.pending; assert(pending); eq(T.Dispatch.waitReceipt,0)
    receipt("UNIT_SPELLCAST_SENT",143,"foreign"); UnitCastingInfo=function() return "foreign" end
    T.Runtime:Reconcile(); eq(T.Dispatch.pending,nil); eq(T.Dispatch.waitReceipt,nil)
    receipt("UNIT_SPELLCAST_SUCCEEDED",143,"foreign"); eq(T.engine.index,1)
    UnitCastingInfo=function() return nil end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending and T.Dispatch.pending~=pending); eq(T.Runtime.intent,true)
end)
test("cast_without_sent_releases_uninitiated_wait_without_progress",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    UnitCastingInfo=function() return "foreign" end; T.Runtime:Reconcile()
    eq(T.Dispatch.waitReceipt,nil); eq(T.engine.index,1)
    UnitCastingInfo=function() return nil end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.engine.index,1)
end)
test("current_initiation_retains_success_wait_through_other_cast_events",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"current-locked"); UnitCastingInfo=function() return "cast" end
    receipt("UNIT_SPELLCAST_SENT",5019,"other-locked"); T.Runtime:Reconcile()
    eq(T.Dispatch.waitReceipt,0); assert(T.Dispatch:HasCurrentInitiation())
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"current-locked"); eq(T.engine.index,2)
    T.Runtime:Reconcile(); eq(T.Dispatch.pending,nil)
    UnitCastingInfo=function() return nil end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,205)
end)
test("movement_is_not_a_global_binding_token_gate",function()
    deliveryFixture(); IsPlayerMoving=function() return true end
    T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); eq(T.Runtime.state,"running")
    assert(T.Dispatch.pending); local token=T.Dispatch:Packet(); assert(token and token>0)
    -- This is an authorized attempt, not evidence that a cast-time spell can fire.
    eq(T.engine.index,1); eq(T.engine.receiptSerial,nil)
end)
test("repeated_current_failures_retry_only_current_step_and_ignore_late_success",function()
    deliveryFixture(); T.Runtime:SetIntent(true)
    for i=1,3 do
        T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
        local guid="retry-"..i; receipt("UNIT_SPELLCAST_SENT",116,guid)
        receipt("UNIT_SPELLCAST_FAILED",116,guid); eq(T.Runtime.intent,true); eq(T.engine.index,1)
        receipt("UNIT_SPELLCAST_SUCCEEDED",116,guid); eq(T.engine.index,1)
    end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    receipt("UNIT_SPELLCAST_SENT",116,"retry-good"); receipt("UNIT_SPELLCAST_SUCCEEDED",116,"retry-good")
    eq(T.engine.index,2); eq(T.engine.receiptSerial,1)
end)
test("manual_stop_during_foreign_cast_remains_sticky",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",143,"stop-foreign"); UnitCastingInfo=function() return "foreign" end
    T.Runtime:Reconcile(); T.Runtime:Stop(); UnitCastingInfo=function() return nil end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); eq(T.Runtime.intent,false); eq(T.Dispatch.pending,nil)
end)
test("channel_child_and_out_of_sequence_success_never_finish_current_wait",function()
    deliveryFixture(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"locked-main")
    receipt("UNIT_SPELLCAST_SUCCEEDED",7268,"child-extra"); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"shoot-extra")
    eq(T.engine.index,1); eq(T.Dispatch.waitReceipt,0); eq(T.Runtime.intent,true)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"locked-main"); eq(T.engine.index,2)
end)
test("moving_unusable_and_unknown_values_still_zero_token_then_recover",function()
    for _,value in ipairs({false,secret}) do
        deliveryFixture(); IsPlayerMoving=function() return true end
        C_Spell.IsSpellUsable=function() return value,false end
        T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); eq(T.Runtime.intent,true)
        eq(T.Runtime.state,"blocked"); eq(T.Dispatch.pending,nil); T.Transport:Paint(); eq(T.Transport.fields[15],0)
        C_Spell.IsSpellUsable=function() return true,false end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
        assert(T.Dispatch.pending)
    end
end)
test("sixteen_steps_boundary_and_explicit_repeat_syntax",function()
    local rows=T.Profiles:Parse(string.rep("205\n",16)); eq(#rows,16); assert(T.Engine.Validate(rows))
    eq(T.Profiles:Parse(string.rep("205\n",17)),nil)
    rows=T.Profiles:Parse("205:205*3\n143*2"); eq(rows[1].repeatCount,3); eq(rows[2].repeatCount,2)
    eq(T.Profiles:RowsText(rows),"205:205*3\n143:143*2")
    for _,raw in ipairs({"205*0","205*100","205*-1","205*1.5","205*abc","205*2*3"}) do eq(T.Profiles:Parse(raw),nil) end
end)
test("repeat_fields_secret_unknown_and_invalid_rejected",function()
    for _,value in ipairs({secret,0,100,1.5,"3",true}) do
        local rows={{name="a",spellID=205,matchIDs={205},repeatCount=value}}
        eq(T.Profiles:Clean(rows),nil); eq(T.Engine.Validate(rows),nil)
    end
    local rows={{name="a",spellID=205,matchIDs={205}}}
    eq(T.Profiles:Clean(rows)[1].repeatCount,1)
    detectorMode="error"; eq(T.Profiles:Clean(rows),nil); detectorMode=nil
end)
test("repeat_count_success_only_and_duplicate_identity",function()
    local e=engine(T.Profiles:Parse("205*3\n143")); e:Start()
    cast(e,143,"outside"); eq(e.stepCasts,0)
    for i=1,3 do
        cast(e,205,"rep"..i); eq(e.receiptSerial,i)
        if i<3 then eq(e.index,1); eq(e.stepCasts,i); eq(e.lastReason,"STEP_REPEAT_MATCH") end
        event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"rep"..i); eq(e.receiptSerial,i)
    end
    eq(e.index,2); eq(e.stepCasts,0); cast(e,143,"last"); eq(e.completed,true); eq(e.stepCasts,1)
end)
test("repeat_adjacent_same_spell_requires_fresh_initiation",function()
    local e=engine(T.Profiles:Parse("205*2\n205*2\n143")); e:Start()
    event(e,"UNIT_SPELLCAST_SENT",205,"early"); cast(e,205,"first")
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"early"); eq(e.stepCasts,1)
    cast(e,205,"second"); eq(e.index,2); eq(e.stepCasts,0)
    cast(e,205,"third"); cast(e,205,"fourth"); eq(e.index,3)
end)
test("repeat_pause_resume_reset_reload_and_late_tasks",function()
    local config=T.Profiles:Parse("205*3\n143"); local e=engine(config); e:Start(); cast(e,205,"a")
    local old=e.generation; e:Pause(); cast(e,205,"ignored"); eq(e.stepCasts,1)
    e:Resume(); event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"late","player",old); eq(e.stepCasts,1)
    cast(e,205,"b"); eq(e.stepCasts,2)
    local reload=engine(config,e.db); eq(reload.stepCasts,0); eq(reload.running,false)
    e:Reset(); eq(e.stepCasts,0); e:Start(); eq(e.stepCasts,0)
end)
test("repeat_loop_one_event_one_count_and_128_history",function()
    local e=engine(T.Profiles:Parse("205*2")); e:SetLoop(true); e:Start()
    for i=1,140 do cast(e,205,"looprep"..i) end
    eq(e.index,1); eq(e.stepCasts,0); eq(e.receiptSerial,140); eq(#e.db.diagnostics,128)
    event(e,"UNIT_SPELLCAST_SUCCEEDED",205,"looprep140"); eq(e.stepCasts,0)
end)
test("legacy_17_step_configuration_preserved_but_not_runnable",function()
    local rows=T.Profiles:Parse(string.rep("205\n",17),32)
    local e=engine(T.Config,{classProfiles={["MAGE:base"]={single=rows,multi={}}}})
    eq(#e.db.profiles.single,17); eq(T.Profiles:Select(e,"single"),false); eq(e.steps,nil)
    eq(#T.Profiles:Text(e,"single"):gsub("[^\n]",""),16)
end)
test("repeat_channel_start_semantics_child_and_cancel",function()
    local e=engine(T.Profiles:Parse("5143*2\n143")); e:Start(); cast(e,5143,"arc1"); eq(e.stepCasts,1)
    event(e,"UNIT_SPELLCAST_CHANNEL_STOP",5143,"arc1"); cast(e,7268,"tick"); eq(e.stepCasts,1)
    cast(e,5143,"arc2"); eq(e.index,2)
end)
local function editorFixture(text)
    deliveryFixture(); T.UI.editScene="single"; T.UI:ShowPage("profiles")
    T.UI:Paint(T.UI.editor,"SetText",text or "205:205"); T.UI:RefreshSequenceEditor(true)
end
test("editor_exact_id_add_move_delete_and_count",function()
    editorFixture(); assert(T.UI:AddSequenceSpell(143)); assert(T.UI:EditSequenceRow(2,"count","3"))
    assert(T.UI:EditSequenceRow(2,"move",-1)); local rows=T.UI:DraftRows()
    eq(rows[1].spellID,143); eq(rows[1].repeatCount,3); eq(rows[1].matchIDs[1],143)
    eq(rows[2].spellID,205); assert(T.UI:EditSequenceRow(2,"delete")); eq(#T.UI:DraftRows(),1)
    eq(T.engine.db.profiles.single[1].spellID,116) -- only draft changed
    eq(T.UI:EditSequenceRow(1,"count","100"),false); eq(T.UI:DraftRows()[1].repeatCount,3)
end)
test("editor_delete_last_save_empty_disables_recommendation",function()
    editorFixture(); assert(T.UI:EditSequenceRow(1,"delete")); eq(#T.UI:DraftRows(),0)
    assert(T.Profiles:Save(T.engine,"single",T.UI:DraftRows())); eq(T.engine.steps,nil)
    eq(T.Recommendation:Current(T.engine),nil); eq(T.Runtime.intent,false)
end)
test("editor_drop_fourth_field_exact_not_spellbook_slot",function()
    editorFixture(); local cleared=0
    GetCursorInfo=function() return "spell",7,secret,116 end; ClearCursor=function() cleared=cleared+1 end
    assert(T.UI:ReceiveSequenceSpell(1)); local rows=T.UI:DraftRows()
    eq(rows[1].spellID,116); eq(#rows[1].matchIDs,1); eq(rows[1].matchIDs[1],116); eq(cleared,1)
    eq(T.engine.index,1)
end)
test("editor_drop_invalid_payloads_and_failed_detector_keep_cursor",function()
    editorFixture(); local cleared=0; ClearCursor=function() cleared=cleared+1 end
    for _,fn in ipairs({function() return "spell",205,nil,nil end,function() return "spell",205,nil,secret end,
        function() return secret,nil,nil,205 end,function() return "macro",205,nil,205 end,
        function() return "item",205,nil,205 end,function() error("RAW_EXCEPTION") end}) do
        GetCursorInfo=fn; eq(T.UI:ReceiveSequenceSpell(),false)
    end
    GetCursorInfo=nil; eq(T.UI:ReceiveSequenceSpell(),false)
    GetCursorInfo=function() return "spell",7,nil,205 end
    detectorMode="nil"; eq(T.UI:ReceiveSequenceSpell(),false); detectorMode="error"; eq(T.UI:ReceiveSequenceSpell(),false)
    detectorMode=nil; eq(cleared,0); eq(#T.UI:DraftRows(),1)
end)
test("editor_drop_full_limit_never_clears_cursor_or_changes_draft",function()
    editorFixture(string.rep("205\n",16)); local cleared=0
    GetCursorInfo=function() return "spell",7,nil,143 end; ClearCursor=function() cleared=cleared+1 end
    local original=T.UI.editor.text; eq(T.UI:ReceiveSequenceSpell(),false); eq(cleared,0); eq(T.UI.editor.text,original)
end)
test("editor_metadata_failures_placeholder_and_clear_failure",function()
    editorFixture(); C_Spell.GetSpellInfo=function() error("RAW") end; C_Spell.GetSpellTexture=function() return secret end
    GetCursorInfo=function() return "spell",7,nil,5019 end; ClearCursor=function() error("RAW") end
    assert(T.UI:ReceiveSequenceSpell()); eq(T.UI:DraftRows()[2].spellID,5019)
    eq(T.UI.sequenceRows[2].icon.texture,T.Placeholder); eq(T.engine.lastReason,"CURSOR_CLEAR_FAILED")
end)
test("editor_class_scene_drafts_and_code_source_independent",function()
    editorFixture(); T.UI:EditSequenceRow(1,"count","3")
    T.UI.editScene="multi"; T.UI:ShowPage("profiles"); T.UI:Paint(T.UI.editor,"SetText","5019:5019*2")
    T.UI.editScene="single"; T.UI:ShowPage("profiles"); eq(T.UI:DraftRows()[1].repeatCount,3)
    T.engine.db.sourceByProfile[T.engine.profileKey]={single="code"}
    assert(T.Profiles:Save(T.engine,"single",T.UI:DraftRows()))
    eq(T.engine.db.sourceByProfile[T.engine.profileKey].single,"code"); eq(T.engine.steps[1].spellID,116)
    assert(T.Recommendation:SetSource(T.engine,"manual")); eq(T.engine.steps[1].repeatCount,3)
    UnitClass=function() return "战士","WARRIOR" end; T.Profiles:RefreshIdentity(T.engine); T.UI:ShowPage("profiles")
    eq(T.UI:DraftRows()[1],nil)
end)
test("editor_refresh_does_not_overwrite_in_progress_count",function()
    editorFixture(); T.UI.sequenceRows[1].count.text="7"
    T.UI:RefreshPage(); eq(T.UI.sequenceRows[1].count.text,"7")
    T.UI.sequenceRows[1].count.scripts.OnEnterPressed(T.UI.sequenceRows[1].count)
    eq(T.UI:DraftRows()[1].repeatCount,7)
end)
test("repeat_hud_and_test_panel_progress",function()
    deliveryFixture(); assert(T.Profiles:Save(T.engine,"single",T.Profiles:Parse("116*3\n205")))
    T.Runtime:SetIntent(true); receipt("UNIT_SPELLCAST_SENT",116,"progress"); receipt("UNIT_SPELLCAST_SUCCEEDED",116,"progress")
    T.UI:Refresh(); assert(T.HUD.status.text:find("次数 1/3",1,true),T.HUD.status.text); assert(T.UI.progress.text:find("次数 1/3",1,true),T.UI.progress.text)
end)
test("repeat_continuous_same_step_new_request_after_success",function()
    continuousFixture(T.Profiles:Parse("205*2\n143"))
    for i=1,2 do
        T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); eq(T.Dispatch.pending.receiptSerial,i-1)
        receipt("UNIT_SPELLCAST_SENT",205,"samecont"..i); receipt("UNIT_SPELLCAST_SUCCEEDED",205,"samecont"..i)
    end
    eq(T.engine.index,2); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,143)
end)
local function shootFixture()
    continuousFixture(T.Profiles:Parse("5019*2\n143"))
    C_ActionBar=nil; IsCurrentAction=function() return false end
end
test("shoot_starts_then_active_zero_token_own_success_counts",function()
    shootFixture(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    IsCurrentAction=function() return true end; eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil)
    receipt("UNIT_SPELLCAST_SENT",5019,"shot1"); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"shot1"); eq(T.engine.stepCasts,1)
    T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.Dispatch.continuousReason,"SHOOT_ACTIVE_WAIT_SUCCESS")
    receipt("UNIT_SPELLCAST_SENT",5019,"shot2"); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"shot2"); eq(T.engine.index,2)
    T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,143)
end)
test("shoot_final_success_handoff_public_5019_without_postshot_timer",function()
    shootFixture(); receipt("UNIT_SPELLCAST_SENT",5019,"handoff1"); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"handoff1")
    UnitCastingInfo=function() return "射击",nil,nil,nil,nil,nil,nil,nil,5019 end
    eq(T.Dispatch:CastIdle(),false); eq(T.engine.stepCasts,1)
    receipt("UNIT_SPELLCAST_SENT",5019,"handoff2"); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"handoff2")
    eq(T.engine.index,2); assert(T.Dispatch:CastIdle()); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    local serial=T.engine.receiptSerial
    receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"handoff2"); eq(T.engine.receiptSerial,serial)
    eq(T.Dispatch.pending.binding.spellID,143); assert(T.Dispatch:Packet())
    receipt("UNIT_SPELLCAST_SENT",143,"handoff-next"); eq(T.engine.shootHandoff,nil); eq(T.Dispatch:CastIdle(),false)
end)
test("shoot_handoff_never_bypasses_unknown_other_cast_or_channel",function()
    shootFixture(); cast(T.engine,5019,"narrow1"); cast(T.engine,5019,"narrow2")
    for _,id in ipairs({secret,143}) do
        UnitCastingInfo=function() return "施法",nil,nil,nil,nil,nil,nil,nil,id end; eq(T.Dispatch:CastIdle(),false)
    end
    UnitCastingInfo=function() return "射击",nil,nil,nil,nil,nil,nil,nil,5019 end
    UnitChannelInfo=function() return "引导" end; eq(T.Dispatch:CastIdle(),false)
    UnitChannelInfo=function() return nil end; assert(T.Dispatch:CastIdle())
    T.engine:Pause(); eq(T.engine.shootHandoff,nil); eq(T.Dispatch:CastIdle(),false)
    shootFixture(); cast(T.engine,5019,"stale1"); cast(T.engine,5019,"stale2"); T.engine:Reset(); eq(T.engine.shootHandoff,nil)
    continuousFixture(T.Profiles:Parse("5019\n5019\n143")); cast(T.engine,5019,"adjacent-shoot")
    eq(T.engine.index,2); eq(T.engine.shootHandoff,nil)
end)
test("shoot_active_unknown_api_failure_never_toggle_or_count",function()
    for _,fn in ipairs({function() return secret end,function() return nil end,function() error("RAW") end,function() return true end}) do
        shootFixture(); IsCurrentAction=fn; T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.engine.stepCasts,0)
        eq(T.engine.running,true); eq(T.Dispatch.continuous,true); eq(T.Dispatch:Request(true),false)
    end
    shootFixture(); IsCurrentAction=nil; T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
end)
test("shoot_exact_slot_nil_range_fallback_not_secret_or_false",function()
    shootFixture(); C_Spell.IsSpellInRange=function() return nil end
    C_ActionBar={IsCurrentAction=function() return false end,IsActionInRange=function(slot,unit) eq(slot,7); eq(unit,"target"); return true end}
    assert(T.Dispatch:ContinuousEvidence(5019)); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    for _,value in ipairs({secret,false}) do C_Spell.IsSpellInRange=function() return value end; eq(T.Dispatch:ContinuousEvidence(5019),false) end
    C_Spell.IsSpellInRange=function() return nil end; C_ActionBar.IsActionInRange=function() return secret end
    eq(T.Dispatch:ContinuousEvidence(5019),false); C_ActionBar=nil
end)
test("shoot_active_api_reentry_cannot_revive_stopped_generation",function()
    shootFixture(); IsCurrentAction=function() T.engine:Reset(); return false end
    T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.engine.stepCasts,0); eq(T.Dispatch.continuous,false)
end)
test("shoot_no_initiation_no_progress_and_child_no_count",function()
    shootFixture(); receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"unassociated"); eq(T.engine.stepCasts,0)
    receipt("UNIT_SPELLCAST_SENT",5019,"failed"); receipt("UNIT_SPELLCAST_FAILED",5019,"failed")
    receipt("UNIT_SPELLCAST_SUCCEEDED",5019,"failed"); eq(T.engine.stepCasts,0)
    receipt("UNIT_SPELLCAST_SENT",7268,"child"); receipt("UNIT_SPELLCAST_SUCCEEDED",7268,"child"); eq(T.engine.stepCasts,0)
end)
test("repeat_success_during_request_api_invalidates_same_index_candidate",function()
    shootFixture(); event(T.engine,"UNIT_SPELLCAST_SENT",5019,"api-repeat")
    IsCurrentAction=function() event(T.engine,"UNIT_SPELLCAST_SUCCEEDED",5019,"api-repeat"); return false end
    local ok,reason=T.Dispatch:Request(true); eq(ok,false); eq(reason,"TEK_REQUEST_STALE")
    eq(T.engine.index,1); eq(T.engine.stepCasts,1); eq(T.Dispatch.pending,nil)
end)
test("repeat_partial_save_and_scene_switch_clear_count",function()
    local e=engine(T.Profiles:Parse("205*3")); e:Start(); cast(e,205,"partialsave")
    assert(T.Profiles:Save(e,"single",T.Profiles:Parse("205*3"))); eq(e.stepCasts,0); eq(e.running,false)
    e:Start(); cast(e,205,"partialscene"); T.Profiles:Select(e,"multi"); eq(e.stepCasts,0); eq(e.running,false)
end)
local function hotkeyFixture()
    deliveryFixture("manual"); T.Hotkeys.owner=nil; T.Hotkeys.appliedKey=nil
    T.Hotkeys.lastReason=nil; T.Hotkeys.applying=false; T.Hotkeys.pending=false
    local f={overrides={},base={},sets=0,clears=0}
    GetBindingAction=function(key,overrides) return overrides and f.overrides[key] or f.base[key] or "" end
    ClearOverrideBindings=function() f.clears=f.clears+1; f.overrides={} end
    SetOverrideBinding=function(_,priority,key,command)
        eq(priority,true); eq(command,"TEF_TOGGLE_DISPATCH"); f.sets=f.sets+1; f.overrides[key]=command
        return true
    end
    SaveBindings=function() error("FORBIDDEN_SAVE_BINDINGS") end; SetBinding=function() error("FORBIDDEN_BASE_BINDING") end
    IsControlKeyDown=function() return false end; IsAltKeyDown=function() return false end; IsShiftKeyDown=function() return false end
    return f
end
test("hotkey_capture_click_saves_immediately_and_toggle_command_runs",function()
    local f=hotkeyFixture(); T.UI.captureHotkeyButton.scripts.OnClick()
    eq(T.UI.captureHotkey,true); T.UI.hotkey.scripts.OnKeyDown(T.UI.hotkey,"F8")
    eq(T.UI.captureHotkey,false); eq(T.engine.db.dispatch.hotkey,"F8")
    eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH"); eq(T.Hotkeys.lastReason,"HOTKEY_APPLIED")
    eq(T.Runtime.intent,false); TEF_ToggleDispatchIntent(); eq(T.Runtime.intent,true)
    TEF_ToggleDispatchIntent(); eq(T.Runtime.intent,false)
end)
test("hotkey_recording_modifiers_esc_and_conflict_keep_previous_saved_key",function()
    local f=hotkeyFixture(); assert(T.Hotkeys:Set("F8"))
    T.UI.captureHotkeyButton.scripts.OnClick(); T.UI.hotkey.scripts.OnKeyDown(T.UI.hotkey,"LCTRL")
    eq(T.UI.captureHotkey,true); eq(T.engine.db.dispatch.hotkey,"F8")
    T.UI.hotkey.scripts.OnKeyDown(T.UI.hotkey,"ESCAPE"); eq(T.UI.captureHotkey,false); eq(T.engine.db.dispatch.hotkey,"F8")
    f.base.F9="ACTIONBUTTON1"; T.UI.captureHotkeyButton.scripts.OnClick(); T.UI.hotkey.scripts.OnKeyDown(T.UI.hotkey,"F9")
    eq(T.engine.db.dispatch.hotkey,"F8"); eq(T.UI.hotkey.text,"F8"); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
    eq(T.Hotkeys.lastReason,"HOTKEY_CONFLICT"); eq(T.Runtime.intent,false)
end)
test("hotkey_typed_enter_and_save_button_persist_combo_and_clear",function()
    local f=hotkeyFixture(); T.UI.hotkey.text=" ctrl-shift-f8 "
    T.UI.hotkey.scripts.OnEnterPressed(); eq(T.engine.db.dispatch.hotkey,"CTRL-SHIFT-F8")
    T.UI.hotkey.text="F9"; T.UI.applyHotkeyButton.scripts.OnClick(); eq(T.engine.db.dispatch.hotkey,"F9")
    eq(f.overrides["CTRL-SHIFT-F8"],nil); eq(f.overrides.F9,"TEF_TOGGLE_DISPATCH")
    T.UI.clearHotkeyButton.scripts.OnClick(); eq(T.engine.db.dispatch.hotkey,""); eq(next(f.overrides),nil)
end)
test("hotkey_reload_whitelist_retains_key_and_reinstalls_fresh_override",function()
    local f=hotkeyFixture(); assert(T.Hotkeys:Set("CTRL-SHIFT-F8"))
    local old=T.engine.db; T.engine=engine(T.Config,old); T.UI.engine=T.engine; T.Runtime:Initialize(T.engine)
    eq(T.engine.db.dispatch.hotkey,"CTRL-SHIFT-F8"); eq(T.Runtime.intent,false)
    f.overrides={}; T.Hotkeys.owner=nil; T.Hotkeys.appliedKey=nil
    assert(T.Hotkeys:Apply()); eq(f.overrides["CTRL-SHIFT-F8"],"TEF_TOGGLE_DISPATCH")
end)
test("hotkey_verification_rejects_silent_setter_or_false_secret_return",function()
    for _,fn in ipairs({function() return nil end,function() return false end,function() return secret end,function() error("RAW") end}) do
        local f=hotkeyFixture(); SetOverrideBinding=fn
        eq(T.Hotkeys:Set("F8"),false); eq(T.engine.db.dispatch.hotkey,"F8")
        assert(T.Hotkeys.lastReason~="HOTKEY_APPLIED"); eq(T.Hotkeys.pending,true); eq(f.overrides.F8,nil)
    end
end)
test("hotkey_missing_verification_or_secret_result_never_claims_applied",function()
    for _,fn in ipairs({function(_,override) if override then return secret end; return "" end,
        function() error("RAW") end,function() return nil end}) do
        local f=hotkeyFixture(); GetBindingAction=fn
        eq(T.Hotkeys:Set("F8"),false); eq(T.Hotkeys.lastReason,"HOTKEY_CONFLICT_UNKNOWN"); eq(f.sets,0)
    end
    hotkeyFixture(); GetBindingAction=nil; eq(T.Hotkeys:Set("F8"),false)
end)
test("hotkey_binding_refresh_idempotent_and_recovers_removed_override",function()
    local f=hotkeyFixture(); assert(T.Hotkeys:Set("F8")); local sets,clears=f.sets,f.clears
    for i=1,25 do assert(T.Hotkeys:Apply()) end
    eq(f.sets,sets); eq(f.clears,clears)
    f.overrides={}; assert(T.Hotkeys:Apply()); eq(f.sets,sets+1); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
end)
test("hotkey_setter_synchronous_binding_event_does_not_recurse",function()
    local f=hotkeyFixture(); local base=SetOverrideBinding
    SetOverrideBinding=function(...)
        local ok,reason=T.Hotkeys:Apply(); eq(ok,false); eq(reason,"HOTKEY_REENTRANT")
        return base(...)
    end
    assert(T.Hotkeys:Set("F8")); eq(f.sets,1); eq(T.Hotkeys.applying,false)
end)
test("hotkey_combat_saved_reload_deferred_and_existing_key_stays_valid",function()
    local f=hotkeyFixture(); assert(T.Hotkeys:Set("F8")); InCombatLockdown=function() return true end
    assert(T.Hotkeys:Apply()); eq(f.sets,1)
    local ok,reason=T.Hotkeys:Set("F9"); eq(ok,false); eq(reason,"HOTKEY_DEFERRED")
    eq(T.engine.db.dispatch.hotkey,"F9"); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
    local e=engine(T.Config,T.engine.db); eq(e.db.dispatch.hotkey,"F9")
    InCombatLockdown=function() return false end; assert(T.Hotkeys:Apply()); eq(f.overrides.F8,nil); eq(f.overrides.F9,"TEF_TOGGLE_DISPATCH")
end)
test("hotkey_clear_failure_preserves_saved_key_and_reports_not_applied",function()
    hotkeyFixture(); ClearOverrideBindings=function() error("RAW") end
    eq(T.Hotkeys:Set("F8"),false); eq(T.Hotkeys.lastReason,"HOTKEY_CLEAR_FAILED"); eq(T.engine.db.dispatch.hotkey,"F8")
    assert(T.Hotkeys:Status():find("F8",1,true)); eq(T.Runtime.intent,false)
end)
test("hotkey_bootstrap_login_world_and_update_binding_reapply_saved_key",function()
    local f=hotkeyFixture(); assert(T.Hotkeys:Set("F8")); TEF_DB=T.engine.db
    T.Hotkeys.owner=nil; T.Hotkeys.appliedKey=nil; f.overrides={}
    -- Simulate ADDON_LOADED before the binding subsystem accepts the command.
    local setter=SetOverrideBinding; SetOverrideBinding=function() return false end
    load("Core/Bootstrap.lua"); local ef=allFrames.TEF_EventFrame
    ef.scripts.OnEvent(ef,"ADDON_LOADED","TACTIC-ECHO-FOREVER")
    eq(T.engine.db.dispatch.hotkey,"F8"); eq(T.Hotkeys.lastReason,"HOTKEY_APPLY_FAILED")
    assert(ef.events.PLAYER_LOGIN); SetOverrideBinding=setter
    ef.scripts.OnEvent(ef,"PLAYER_LOGIN"); eq(T.Hotkeys.lastReason,"HOTKEY_APPLIED"); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
    f.overrides={}; ef.scripts.OnEvent(ef,"PLAYER_ENTERING_WORLD"); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
    f.overrides={}; ef.scripts.OnEvent(ef,"UPDATE_BINDINGS"); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
end)
test("hotkey_new_base_binding_not_hidden_by_own_override",function()
    local f=hotkeyFixture(); assert(T.Hotkeys:Set("F8")); f.base.F8="ACTIONBUTTON1"
    local ok,reason=T.Hotkeys:Apply(); eq(ok,false); eq(reason,"HOTKEY_CONFLICT")
    eq(f.overrides.F8,nil); eq(T.engine.db.dispatch.hotkey,"F8")
    f.base.F8=nil; assert(T.Hotkeys:Apply()); eq(f.overrides.F8,"TEF_TOGGLE_DISPATCH")
end)
test("f5_explicit_override_preserves_native_and_survives_reload",function()
    local f=hotkeyFixture(); f.base.F5="TARGETPARTYMEMBER4"
    eq(T.Hotkeys:Set("F5"),false); eq(T.engine.db.dispatch.hotkey,"")
    T.engine.db.dispatch.hotkeyOverride=true; assert(T.Hotkeys:Set("F5"))
    eq(f.base.F5,"TARGETPARTYMEMBER4"); eq(f.overrides.F5,"TEF_TOGGLE_DISPATCH")
    local e=engine(T.Config,T.engine.db); eq(e.db.dispatch.hotkey,"F5"); eq(e.db.dispatch.hotkeyOverride,true)
    T.engine=e; T.UI.engine=e; T.Runtime:Initialize(e); f.overrides={}; assert(T.Hotkeys:Apply())
    e.db.dispatch.hotkeyOverride=false; eq(T.Hotkeys:Apply(),false)
    eq(f.overrides.F5,nil); eq(f.base.F5,"TARGETPARTYMEMBER4")
end)
test("control_f5_never_becomes_spell_dispatch_with_alternate_binding",function()
    local f=hotkeyFixture(); f.base.F5="ACTIONBUTTON1"; T.engine.db.dispatch.hotkeyOverride=true
    assert(T.Hotkeys:Set("F5")); GetBindingKey=function() return "F5","2" end
    local binding=T.Dispatch:Resolve(116); assert(binding); eq(binding.key,"2")
    eq(T.Dispatch.SkillToken("F5"),nil)
    GetBindingKey=function() return "F5" end; eq(T.Dispatch:Resolve(116),nil)
    eq(T.Dispatch:VerifyCurrent(binding),false)
    InCombatLockdown=function() return true end; T.Hotkeys:Set("F6")
    eq(T.Dispatch.SkillToken("F5"),nil); eq(T.Dispatch.SkillToken("F6"),nil)
end)
test("f5_override_still_rejects_unknown_detector_and_api",function()
    hotkeyFixture(); T.engine.db.dispatch.hotkeyOverride=true
    GetBindingAction=function() return secret end; eq(T.Hotkeys:Set("F5"),false)
    GetBindingAction=function() error("RAW") end; eq(T.Hotkeys:Set("F5"),false)
end)
test("loop_mode_legacy_migration_reload_and_validation",function()
    eq(engine(nil,{loop=true}).db.loopMode,"normal"); eq(engine(nil,{loop=false}).db.loopMode,"none")
    for _,mode in ipairs({"none","normal","target","combat"}) do
        local e=engine(); assert(e:SetLoopMode(mode)); local copy=engine(nil,e.db)
        eq(copy.db.loopMode,mode); eq(copy.db.loop,mode~="none"); eq(copy.running,false)
    end
    eq(engine(nil,{loopMode=secret}).db.loopMode,"none")
    local e=engine(); eq(e:SetLoopMode("BAD"),false); eq(e.db.loopMode,"none")
end)
test("all_loop_modes_one_receipt_one_step_and_reset_count",function()
    for _,mode in ipairs({"normal","target","combat"}) do
        local e=engine({{name="x",spellID=205,matchIDs={205},repeatCount=2}}); e:SetLoopMode(mode); e:Start()
        cast(e,205,"one"); eq(e.stepCasts,1); cast(e,205,"one"); eq(e.stepCasts,1)
        cast(e,205,"two"); eq(e.index,1); eq(e.stepCasts,0); eq(e.completed,false); eq(e.running,true)
        cast(e,205,"two"); eq(e.stepCasts,0)
    end
end)
test("runtime_cycle_reset_preserves_intent_rejects_old_receipt",function()
    runtimeFixture("manual"); T.engine:SetLoopMode("target"); T.Runtime:Start(false)
    local e=T.engine; receipt("UNIT_SPELLCAST_SENT",116,"old-reset"); local g=e.generation
    e.index=2; e.stepCasts=1; assert(T.Runtime:ResetCycle("LOOP_TARGET_RESET"))
    eq(T.Runtime.intent,true); eq(e.index,1); eq(e.stepCasts,0); assert(e.generation>g)
    eq(T.Dispatch.pending,nil); T.Runtime:Tick()
    receipt("UNIT_SPELLCAST_START",116,"old-reset")
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"old-reset"); eq(e.index,1)
    T.Runtime:Stop(); T.Runtime:ResetCycle("LOOP_TARGET_RESET"); T.Runtime:Tick(); eq(T.Runtime.intent,false); eq(e.running,false)
end)
test("cycle_reset_respects_auto_standby_and_stop_mode",function()
    for _,mode in ipairs({"auto","stop"}) do
        runtimeFixture(mode); InCombatLockdown=function() return true end; T.Runtime:Start(false)
        T.engine.index=2; InCombatLockdown=function() return false end
        T.Runtime:ResetCycle("LOOP_COMBAT_RESET"); T.Runtime:Tick(); eq(T.engine.index,1); eq(T.engine.running,false)
        eq(T.Runtime.intent,mode=="auto"); eq(T.Runtime.state,mode=="auto" and "standby" or "paused")
    end
end)
test("bootstrap_loop_events_only_reset_matching_mode_and_not_revive",function()
    local f=hotkeyFixture(); TEF_DB=T.engine.db; load("Core/Bootstrap.lua")
    local ef=allFrames.TEF_EventFrame; ef.scripts.OnEvent(ef,"ADDON_LOADED","TACTIC-ECHO-FOREVER")
    local e=T.engine
    for _,mode in ipairs({"normal","target","combat","none"}) do
        T.Runtime:Stop(); e:SetLoopMode(mode); e.index=2; e.stepCasts=1
        ef.scripts.OnEvent(ef,"PLAYER_TARGET_CHANGED"); eq(e.index,mode=="target" and 1 or 2); eq(T.Runtime.intent,false)
        e.index=2; e.stepCasts=1; ef.scripts.OnEvent(ef,"PLAYER_REGEN_ENABLED")
        eq(e.index,mode=="combat" and 1 or 2); eq(T.Runtime.intent,false)
    end
end)
test("hud_style_whitelist_bounds_secret_reload_independence",function()
    local clean=T.HudStyles.Clean({main={key={fontSize=99,scale=.1,point="BAD",offsetX=-200,color={r=2,g=secret}}},global={status={enabled=false}}})
    eq(clean.main.key.fontSize,30); eq(clean.main.key.scale,.6); eq(clean.main.key.point,"TOPRIGHT")
    eq(clean.main.key.offsetX,-100); eq(clean.main.key.color.r,1); eq(clean.main.key.color.g,1)
    eq(clean.global.status.enabled,false); eq(clean.preview.key.fontSize,12)
    local e=engine(); e.db.hud.styles=clean; local copy=engine(nil,e.db)
    eq(copy.db.hud.styles.main.key.fontSize,30); eq(copy.db.hud.styles.global.status.enabled,false)
    clean.main.key.fontSize=8; eq(copy.db.hud.styles.main.key.fontSize,30)
end)
test("hud_styles_apply_hidden_labels_defer_combat_no_dispatch_change",function()
    deliveryFixture("manual"); local h=T.HUD; local e=T.engine
    local calls=0; local font,point,color
    h.cards[1].key.SetFont=function(_,_,size) calls=calls+1; font=size end
    h.cards[1].key.SetPoint=function(_,p) point=p end
    h.cards[1].key.SetTextColor=function(_,r) color=r end
    e.db.hud.styles.main.key.fontSize=22; e.db.hud.styles.main.key.point="BOTTOMRIGHT"
    e.db.hud.styles.main.key.color.r=.3; e.db.hud.styles.main.key.enabled=false
    local g=e.generation; local intent=T.Runtime.intent; local index=e.index
    InCombatLockdown=function() return true end; h:Layout(); eq(calls,0); eq(h.pending,true)
    InCombatLockdown=function() return false end; h:Layout(); eq(font,22); eq(point,"BOTTOMRIGHT"); eq(color,.3)
    eq(h.cards[1].key.shown,false); h:Refresh(); eq(h.cards[1].key.shown,false)
    eq(g,e.generation); eq(index,e.index); eq(intent,T.Runtime.intent)
end)
test("reset_retires_identites_without_exceeding_bounded_budget",function()
    local e=engine(); e:Start(); event(e,"UNIT_SPELLCAST_SENT",205,"retire-me")
    e.seenCount=4096; e:Reset(); eq(e.identitySaturated,true); e:Resume()
    eq(e.running,false); eq(e.seenCount,4096); eq(e.associationCount,0)
end)
test("hud_style_individual_api_failure_does_not_stop_paint",function()
    deliveryFixture("manual"); local h=T.HUD; local changed=false
    h.cards[1].key.SetFont=function() error("RAW") end
    h.cards[1].key.SetTextColor=function() changed=true end
    h:Layout(); eq(changed,true); eq(T.engine.index,1)
end)
test("loop_selection_survives_hover_leave_and_page_refresh",function()
    deliveryFixture("manual"); T.UI:OpenSettings(); T.UI:ShowPage("looping")
    for _,mode in ipairs({"normal","target","combat","none"}) do
        local selected=T.UI.loopModeControls[mode]; selected.scripts.OnClick()
        eq(T.engine.db.loopMode,mode); eq(selected.tefControlSelected,true)
        selected.scripts.OnEnter(); selected.scripts.OnLeave()
        eq(selected.backdropBorderColor[2],.85); eq(selected.backdropColor[2],.23)
        assert(selected.text:find("●",1,true)); assert(T.UI.readouts.looping.text:find("当前模式",1,true))
        for key,b in pairs(T.UI.loopModeControls) do eq(b.tefControlSelected,key==mode) end
        T.UI:ShowPage("hud"); T.UI:ShowPage("looping"); eq(selected.tefControlSelected,true)
        eq(T.Runtime.intent,false)
    end
end)
test("section_decoration_stays_on_page_background_below_text",function()
    local parent=object("test-page"); local bg=T.UI:CreateSectionCard(parent,"title",0,0,580,100)
    eq(bg.kind,"Texture"); eq(bg.parent,parent); eq(bg.layer,"BACKGROUND")
    local labels=0
    for _,child in ipairs(parent.children) do
        assert(child.kind~="Frame")
        if child.kind=="FontString" then labels=labels+1; eq(child.parent,parent); eq(child.layer,"OVERLAY"); eq(child.text,"title") end
    end
    eq(labels,1)
end)
test("hud_no_settings_button_or_root_backdrop_right_click_still_opens",function()
    deliveryFixture("manual"); eq(rawget(T.HUD,"settingsButton"),nil)
    eq(rawget(T.HUD.frame,"template"),nil); eq(rawget(T.HUD.frame,"backdrop"),nil)
    local index,generation=T.engine.index,T.engine.generation
    T.HUD.cards[1].frame.scripts.OnClick(nil,"RightButton")
    eq(T.UI.settingsOpen,true); eq(T.engine.index,index); eq(T.engine.generation,generation)
    T.UI:CloseSettings()
end)
realprint("TEF simulated tests: " .. count .. " passed\n")

assert(loadfile(root .. "/tests/apl.lua"))("TACTIC-ECHO-FOREVER",T,{runtimeFixture=runtimeFixture,deliveryFixture=deliveryFixture,receipt=receipt})
