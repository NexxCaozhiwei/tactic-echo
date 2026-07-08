local TE = _G.TacticEcho

local ActionRegistry = {}
TE.ActionRegistry = ActionRegistry

-- TEAP v3 dispatch is BindingToken-first.  The historical action catalog was
-- a Retribution Paladin table, which made that specialization follow a
-- different runtime path from every other class.  Keep only a generic empty
-- catalog so AddOn and TEK can agree on protocol identity without spell lists.
ActionRegistry.catalogVersion = 3
ActionRegistry.catalogFingerprint = "d005247012f71db9"
ActionRegistry.catalogFingerprint16 = 53253

local EMPTY = {}

function ActionRegistry:GetAction()
    return nil
end

function ActionRegistry:FindBySpellID()
    return nil
end

function ActionRegistry:ResolveRecommendation()
    return nil, "generic_binding_token_path"
end

function ActionRegistry:ListActions()
    return EMPTY
end

function ActionRegistry:ListActiveActions()
    return EMPTY
end

function ActionRegistry:Validate()
    return true
end
