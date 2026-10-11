local _,TEF=...
local R={}
TEF.Recommendation=R
-- Code providers are explicit bounded configurations, never official WoW hints.
TEF.CodeProfiles={MAGE={single=TEF.Config,multi=TEF.ProfileDefaults.multi}}
function R:Source(e,scene)
    scene=scene or e.scene
    local apl=e.db.aplByClass and e.db.aplByClass[e.classToken or ""]
    if apl and apl[scene]==true then return "apl" end
    local by=e.db.sourceByProfile and e.db.sourceByProfile[e.profileKey or ""]
    return by and by[scene]=="code" and "code" or "manual"
end
function R:Configured(e)
    if self:Source(e)=="apl" then return TEF.APL.Packs[e.classToken]~=nil end
    return self:Current(e)~=nil
end
function R:Rows(e,scene)
    local source=self:Source(e,scene)
    if source=="apl" then return {},"apl" end
    if source=="code" then
        local configured=TEF.CodeProfiles[e.profileKey] or TEF.CodeProfiles[e.classToken]
        return TEF.Profiles:Clean(configured and configured[scene]),"code"
    end
    return TEF.Profiles:Clean(e.db.profiles[scene]),"manual"
end
function R:Current(e)
    local step=e.steps and e.steps[e.index]
    if self:Source(e)=="apl" then
        local c=e.aplCandidate
        if not c or not step or step.spellID~=c.spellID then return nil,"APL_NO_CANDIDATE" end
        return {spellID=c.spellID,index=1,generation=e.generation,source="apl",rule=c.rule,
            profileKey=e.classToken,receiptSerial=e.receiptSerial or 0},"APL_CANDIDATE"
    end
    if not e.profileKey or not step or step.unverified then return nil,"RECOMMENDATION_UNCONFIGURED" end
    local configured=e.db.sourceByProfile and e.db.sourceByProfile[e.profileKey]
    local source=configured and configured[e.scene]=="code" and "code" or "manual"
    return {spellID=step.spellID,index=e.index,generation=e.generation,
        source=source,profileKey=e.profileKey,receiptSerial=e.receiptSerial or 0},"RECOMMENDATION_FIXED"
end
function R:SetSource(e,source,scene)
    if not e.classToken then return false,"PROFILE_IDENTITY_UNKNOWN" end
    if source~="manual" and source~="code" and source~="apl" then return false,"RECOMMENDATION_SOURCE_INVALID" end
    scene=scene or e.scene
    if scene~="single" and scene~="multi" then return false,"SCENE_INVALID" end
    if source=="apl" and not TEF.APL.Packs[e.classToken] then return false,"APL_CLASS_UNSUPPORTED" end
    if source~="apl" and not e.profileKey then return false,"PROFILE_IDENTITY_UNKNOWN" end
    e.db.aplByClass[e.classToken]=e.db.aplByClass[e.classToken] or {}
    e.db.aplByClass[e.classToken][scene]=source=="apl"
    if source~="apl" then
        e.db.sourceByProfile[e.profileKey]=e.db.sourceByProfile[e.profileKey] or {}
        e.db.sourceByProfile[e.profileKey][scene]=source
    end
    e.aplCandidate=nil; e.aplSnapshot=nil; e.aplTrace=nil; TEF.APL:Invalidate(true)
    return TEF.Profiles:Select(e,scene)
end
