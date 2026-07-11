local TE = _G.TacticEcho
local RecommendationResult = TE.RecommendationResult

local RecommendationAdapter = {}
TE.RecommendationAdapter = RecommendationAdapter

local API_NAME = "C_AssistedCombat.GetNextCastSpell"

-- Transport ticks read only the scalar recommendation identity. SignalFrame can
-- then reuse the previously parsed business snapshot while the spell is stable.
function RecommendationAdapter:ReadOfficialSpellID()
    if not C_AssistedCombat or type(C_AssistedCombat.GetNextCastSpell) ~= "function" then
        return nil, "missing", "api_missing"
    end
    local ok, value = pcall(C_AssistedCombat.GetNextCastSpell)
    if not ok then return nil, "error", tostring(value) end
    return tonumber(value), type(value) == "number" and "ok" or "empty", nil
end

-- SignalFrame owns the business-sampling cadence. Accept its already-sampled
-- player context and optional scalar API sample so neither context nor the
-- official recommendation API is read twice in one cycle.
function RecommendationAdapter:ReadOfficial(context, sampledSpellID, sampledStatus, sampledError)
    context = type(context) == "table" and context or TE.Context:GetPlayer()
    if sampledStatus == nil then
        sampledSpellID, sampledStatus, sampledError = self:ReadOfficialSpellID()
    end
    return RecommendationResult:New({
        spellID = sampledSpellID,
        source = "official",
        apiName = API_NAME,
        apiStatus = sampledStatus or "unknown",
        class = context.class,
        specIndex = context.specIndex,
        inCombat = context.inCombat,
        error = sampledError,
    })
end
