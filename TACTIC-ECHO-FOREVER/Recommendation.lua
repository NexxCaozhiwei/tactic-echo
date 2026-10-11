local _,TEF=...
local R={}
TEF.Recommendation=R
-- Code providers are explicit bounded configurations, never official WoW hints.
TEF.CodeProfiles={MAGE={single=TEF.Config,multi=TEF.ProfileDefaults.multi}}
function R:Rows(e,scene)
    local source=e.db.sourceByProfile and e.db.sourceByProfile[e.profileKey or ""]
    source=source and source[scene] or "manual"
    if source=="code" then
        local configured=TEF.CodeProfiles[e.profileKey] or TEF.CodeProfiles[e.classToken]
        return TEF.Profiles:Clean(configured and configured[scene]),"code"
    end
    return TEF.Profiles:Clean(e.db.profiles[scene]),"manual"
end
function R:Current(e)
    local step=e.steps and e.steps[e.index]
    if not e.profileKey or not step or step.unverified then return nil,"RECOMMENDATION_UNCONFIGURED" end
    local configured=e.db.sourceByProfile and e.db.sourceByProfile[e.profileKey]
    local source=configured and configured[e.scene]=="code" and "code" or "manual"
    return {spellID=step.spellID,index=e.index,generation=e.generation,
        source=source,profileKey=e.profileKey,receiptSerial=e.receiptSerial or 0},"RECOMMENDATION_FIXED"
end
function R:SetSource(e,source,scene)
    if not e.profileKey then return false,"PROFILE_IDENTITY_UNKNOWN" end
    if source~="manual" and source~="code" then return false,"RECOMMENDATION_SOURCE_INVALID" end
    scene=scene or e.scene
    if scene~="single" and scene~="multi" then return false,"SCENE_INVALID" end
    e.db.sourceByProfile[e.profileKey]=e.db.sourceByProfile[e.profileKey] or {}
    e.db.sourceByProfile[e.profileKey][scene]=source
    return TEF.Profiles:Select(e,scene)
end
