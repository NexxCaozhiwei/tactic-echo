local TE = _G.TacticEcho
local RecommendationResult = TE.RecommendationResult

local RecommendationAdapter = {}
TE.RecommendationAdapter = RecommendationAdapter

local API_NAME = "C_AssistedCombat.GetNextCastSpell"

function RecommendationAdapter:ReadOfficial()
    local context = TE.Context:GetPlayer()

    if not C_AssistedCombat or type(C_AssistedCombat.GetNextCastSpell) ~= "function" then
        return RecommendationResult:New({
            source = "official",
            apiName = API_NAME,
            apiStatus = "missing",
            class = context.class,
            specIndex = context.specIndex,
            inCombat = context.inCombat,
            error = "api_missing",
        })
    end

    local ok, spellID = pcall(C_AssistedCombat.GetNextCastSpell)
    if not ok then
        return RecommendationResult:New({
            source = "official",
            apiName = API_NAME,
            apiStatus = "error",
            class = context.class,
            specIndex = context.specIndex,
            inCombat = context.inCombat,
            error = tostring(spellID),
        })
    end

    return RecommendationResult:New({
        spellID = tonumber(spellID),
        source = "official",
        apiName = API_NAME,
        apiStatus = type(spellID) == "number" and "ok" or "empty",
        class = context.class,
        specIndex = context.specIndex,
        inCombat = context.inCombat,
    })
end
