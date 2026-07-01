local TE = _G.TacticEcho

local RecommendationResult = {}
TE.RecommendationResult = RecommendationResult

function RecommendationResult:New(fields)
    fields = fields or {}

    return {
        spellID = fields.spellID,
        source = fields.source or "official",
        apiName = fields.apiName,
        apiStatus = fields.apiStatus or "unknown",
        observedAt = fields.observedAt or (GetTime and GetTime() or 0),
        class = fields.class,
        specIndex = fields.specIndex,
        inCombat = fields.inCombat == true,
        error = fields.error,
    }
end

function RecommendationResult:IsUsable(result)
    return type(result) == "table"
        and type(result.spellID) == "number"
        and result.source == "official"
        and result.apiStatus == "ok"
end

