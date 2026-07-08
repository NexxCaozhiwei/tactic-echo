local TE = _G.TacticEcho

local BindingProfile = {}
TE.BindingProfile = BindingProfile

BindingProfile.profileId = "generic-binding-token"
BindingProfile.profileFingerprint = "62ed6d3fb2704e8a"
BindingProfile.profileFingerprint16 = 25325
BindingProfile.catalogVersion = 3
BindingProfile.catalogFingerprint = "d005247012f71db9"

local bindings = {}

function BindingProfile:GetBinding(actionId)
    return bindings[actionId]
end

function BindingProfile:ListBindings()
    return bindings
end

function BindingProfile:ToTekBinding(wowBinding)
    return tostring(wowBinding or ""):gsub("%-", "+")
end
