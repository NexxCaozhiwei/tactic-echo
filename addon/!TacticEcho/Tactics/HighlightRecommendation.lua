-- Selects a currently highlighted, action-bar-bound spell as the ordinary
-- dispatch candidate. The official recommendation remains immutable.
local TE = _G.TacticEcho
local Highlight = {}
TE.HighlightRecommendation = Highlight

local MAX_CANDIDATES = 36

local function positiveSpellID(value)
    local id = tonumber(value)
    if id and id > 0 and id < 2147483647 and id == math.floor(id) then return id end
end

local function publicBoolean(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret == true then return nil end
    end
    if type(value) == "boolean" then return value end
    return nil
end

local function overlayState(spellID)
    if C_SpellActivationOverlay and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function" then
        local ok, value = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if ok then return publicBoolean(value), "C_SpellActivationOverlay.IsSpellOverlayed" end
        return nil, "overlay_query_error"
    end
    if type(IsSpellOverlayed) == "function" then
        local ok, value = pcall(IsSpellOverlayed, spellID)
        if ok then return publicBoolean(value), "IsSpellOverlayed" end
        return nil, "overlay_query_error"
    end
    return nil, "overlay_api_missing"
end

function Highlight:IsEnabled()
    local settings = TacticEchoDB and TacticEchoDB.settings
    return type(settings) == "table" and settings.highlightRecommendationEnabled == true
end

function Highlight:GetProfile(context, create)
    context = context or (TE.Context and TE.Context:GetPlayer()) or {}
    local key = TE.BurstProfiles and TE.BurstProfiles:SpecKey(context.classFile or context.class, context.specIndex)
    if not key then return nil end
    local tactics = TacticEchoDB and TacticEchoDB.tactics
    if create then
        TacticEchoDB = TacticEchoDB or {}
        TacticEchoDB.tactics = type(tactics) == "table" and tactics or {}
        tactics = TacticEchoDB.tactics
        tactics.highlightRecommendationProfiles = type(tactics.highlightRecommendationProfiles) == "table"
            and tactics.highlightRecommendationProfiles or {}
    end
    local profiles = tactics and tactics.highlightRecommendationProfiles
    if create and type(profiles) == "table" then
        profiles[key] = type(profiles[key]) == "table" and profiles[key] or {}
        profiles[key].disabledSpellIDs = type(profiles[key].disabledSpellIDs) == "table"
            and profiles[key].disabledSpellIDs or {}
    end
    local profile = profiles and profiles[key]
    if type(profile) == "table" then
        profile.disabledSpellIDs = type(profile.disabledSpellIDs) == "table" and profile.disabledSpellIDs or {}
    end
    return type(profile) == "table" and profile or nil, key
end

function Highlight:SetEnabled(value)
    TacticEchoDB = TacticEchoDB or {}
    TacticEchoDB.settings = type(TacticEchoDB.settings) == "table" and TacticEchoDB.settings or {}
    TacticEchoDB.settings.highlightRecommendationEnabled = value == true
end

function Highlight:IsSpellEnabled(spellID, context)
    local profile = self:GetProfile(context, false)
    local id = positiveSpellID(spellID)
    return id ~= nil and not (profile and profile.disabledSpellIDs[tostring(id)] == true)
end

function Highlight:SetSpellEnabled(spellID, enabled, context)
    local id = positiveSpellID(spellID)
    if not id then return false, "invalid_spell_id" end
    local profile = self:GetProfile(context, true)
    if not profile then return false, "specialization_unavailable" end
    if enabled == false then profile.disabledSpellIDs[tostring(id)] = true
    else profile.disabledSpellIDs[tostring(id)] = nil end
    return true
end

local function candidateIDs(cache)
    local found, out = {}, {}
    local function add(id, order)
        id = positiveSpellID(id)
        if not id or found[id] then return end
        found[id] = true
        out[#out + 1] = { spellID = id, order = tonumber(order) or 99999 }
    end
    for _, entry in ipairs(cache and cache.entries or {}) do
        if entry.source == "spell" then
            add(entry.spellID, entry.visualOrder)
        elseif entry.source == "macro" then
            local resolver = TE.ActionBarBindingResolver
            -- Macro-derived IDs enter through the shared current-source and
            -- parsed-body identity policy. Opaque represented IDs cannot seed
            -- a new automatic recommendation.
            if resolver and type(resolver.IsVerifiedCurrentMacroSource) == "function"
                and resolver:IsVerifiedCurrentMacroSource(entry) == true then
                add(entry.macroSpellID, entry.visualOrder)
                add(entry.macroResolvedSpellID, entry.visualOrder)
                add(entry.macroActionInfoSpellID, entry.visualOrder)
            end
        end
    end
    table.sort(out, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        return left.spellID < right.spellID
    end)
    while #out > MAX_CANDIDATES do table.remove(out) end
    return out
end

function Highlight:GetCandidates(context, resolveContext)
    local resolver = TE.ActionBarBindingResolver
    if not resolver or type(resolver.GetButtonCache) ~= "function" then return {} end
    local ok, cache = pcall(resolver.GetButtonCache, resolver, resolveContext)
    if not ok or type(cache) ~= "table" then return {} end
    local out = {}
    for _, candidate in ipairs(candidateIDs(cache)) do
        local id = candidate.spellID
        local bindingOK, binding = pcall(resolver.ResolveSpell, resolver, id, resolveContext)
        if bindingOK and type(binding) == "table" and binding.status == "Ready"
            and (tonumber(binding.bindingToken) or 0) > 0 then
            local macroOK = binding.source ~= "macro"
            if not macroOK and type(resolver.IsVerifiedCurrentMacroSource) == "function" then
                macroOK = resolver:IsVerifiedCurrentMacroSource(binding) == true
            end
            if macroOK then
                local name
                if C_Spell and type(C_Spell.GetSpellName) == "function" then
                    local nameOK, value = pcall(C_Spell.GetSpellName, id)
                    if nameOK and type(value) == "string" then name = value end
                elseif type(GetSpellInfo) == "function" then
                    local nameOK, value = pcall(GetSpellInfo, id)
                    if nameOK and type(value) == "string" then name = value end
                end
                out[#out + 1] = { spellID = id, name = type(name) == "string" and name or tostring(id), order = candidate.order }
            end
        end
    end
    return out
end

local function currentCache(resolver, resolveContext)
    if not resolver or type(resolver.GetButtonCache) ~= "function" then return nil end
    local ok, cache = pcall(resolver.GetButtonCache, resolver, resolveContext)
    return ok and type(cache) == "table" and cache or nil
end

local function spellReady(spellID, binding, snapshot)
    if not TE.RuntimeSnapshot or not snapshot then return false, "highlight_snapshot_missing" end
    local state = TE.RuntimeSnapshot:CollectSpellCooldown(snapshot, spellID, binding, { liveCooldown = true })
    if type(state) ~= "table" then return false, "highlight_cooldown_unknown" end
    local ready
    if (tonumber(state.maxCharges) or 0) > 1 then
        ready = (tonumber(state.charges) or 0) > 0
    elseif state.cooldownKnown == true then
        ready = state.cooldownActive ~= true or state.cooldownOnGCD == true or state.cooldownGcdAlias == true
    elseif state.cooldownPublicActiveKnown == true then
        ready = state.cooldownPublicActive == false or (state.cooldownPublicActive == true
            and state.cooldownPublicOnGCDKnown == true and state.cooldownPublicOnGCD == true)
    end
    if ready ~= true then return false, "highlight_wait_cooldown" end
    if not TE.GCDGate then return false, "highlight_gcd_unknown" end
    local phase = TE.GCDGate:Classify(TE.GCDGate:BeginCycle(nil, snapshot))
    if phase ~= "READY_NOW" and phase ~= "QUEUE_WINDOW" then return false, "highlight_wait_gcd" end
    -- A cooldown-ready spender may still lack the resource needed to cast.
    -- This exact SpellID probe is read only and runs only after the current
    -- action-bar route has supplied a verified, nonzero BindingToken.
    if type(TE.RuntimeSnapshot.GetSpellUsability) ~= "function" then
        return false, "highlight_usability_unknown"
    end
    local ok, usable, notEnoughResource = pcall(TE.RuntimeSnapshot.GetSpellUsability,
        TE.RuntimeSnapshot, snapshot, spellID)
    if not ok then return false, "highlight_usability_unknown" end
    if usable == false and notEnoughResource == true then
        return false, "highlight_insufficient_resource"
    end
    if usable == false then return false, "highlight_unusable" end
    if usable ~= true or notEnoughResource == true then
        return false, "highlight_usability_unknown"
    end
    return true
end

function Highlight:Evaluate(context, resolveContext, snapshot)
    if not self:IsEnabled() then return nil, { reason = "highlight_disabled" } end
    local resolver = TE.ActionBarBindingResolver
    if not resolver then return nil, { reason = "highlight_resolver_unavailable" } end
    local cache = currentCache(resolver, resolveContext)
    if not cache then return nil, { reason = "highlight_actionbar_unavailable" } end
    local candidates = candidateIDs(cache)
    local unknownCount, enabledCount = 0, 0
    local resourceBlockedCount, unusableCount, usabilityUnknownCount = 0, 0, 0
    for _, candidate in ipairs(candidates) do
        local id = candidate.spellID
        if self:IsSpellEnabled(id, context) then
            enabledCount = enabledCount + 1
            local highlighted, source = overlayState(id)
            if highlighted == nil then
                unknownCount = unknownCount + 1
            elseif highlighted == true then
                local binding, bindingReason
                if type(TE.RuntimeSnapshot) == "table" and type(TE.RuntimeSnapshot.ResolveSpell) == "function" then
                    binding, bindingReason = TE.RuntimeSnapshot:ResolveSpell(snapshot, id)
                else
                    binding, bindingReason = resolver:ResolveSpell(id, resolveContext)
                end
                local macroVerified = type(binding) == "table" and binding.source ~= "macro"
                if type(binding) == "table" and binding.source == "macro"
                    and type(resolver.IsVerifiedCurrentMacroSource) == "function" then
                    macroVerified = resolver:IsVerifiedCurrentMacroSource(binding) == true
                end
                if type(binding) == "table" and macroVerified and binding.status == "Ready"
                    and (tonumber(binding.bindingToken) or 0) > 0 then
                    local allowed, readyReason = spellReady(id, binding, snapshot)
                    if allowed then
                        return { spellID = id, bindingInfo = binding, source = source, reason = "highlight_dispatch" }, {
                            reason = "highlight_selected", spellID = id, unknownCount = unknownCount,
                            enabledCount = enabledCount, candidateCount = #candidates,
                            resourceBlockedCount = resourceBlockedCount, unusableCount = unusableCount,
                            usabilityUnknownCount = usabilityUnknownCount,
                        }
                    end
                    if readyReason == "highlight_insufficient_resource" then
                        resourceBlockedCount = resourceBlockedCount + 1
                    elseif readyReason == "highlight_unusable" then
                        unusableCount = unusableCount + 1
                    elseif readyReason == "highlight_usability_unknown" then
                        usabilityUnknownCount = usabilityUnknownCount + 1
                    end
                    bindingReason = readyReason
                end
                candidate.reason = bindingReason or "highlight_binding_unavailable"
            end
        end
    end
    return nil, {
        reason = resourceBlockedCount > 0 and "highlight_insufficient_resource"
            or (unusableCount > 0 and "highlight_unusable"
            or (usabilityUnknownCount > 0 and "highlight_usability_unknown"
            or (unknownCount > 0 and "highlight_state_unknown" or "highlight_none_ready"))),
        unknownCount = unknownCount, enabledCount = enabledCount, candidateCount = #candidates,
        resourceBlockedCount = resourceBlockedCount, unusableCount = unusableCount,
        usabilityUnknownCount = usabilityUnknownCount,
    }
end
