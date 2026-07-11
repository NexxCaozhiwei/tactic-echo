local TE = _G.TacticEcho

local BindingProfile = {}
TE.BindingProfile = BindingProfile

BindingProfile.profileId = "laptop"
BindingProfile.profileFingerprint = "fa6f775d78e31239"
BindingProfile.profileFingerprint16 = 64111
BindingProfile.catalogVersion = 2
BindingProfile.catalogFingerprint = "648482895f1293f5"

local bindings = {
    PALADIN_RETRIBUTION_JUDGMENT = "SHIFT-Z",
    PALADIN_RETRIBUTION_BLADE_OF_JUSTICE = "SHIFT-X",
    PALADIN_RETRIBUTION_DIVINE_STORM = "SHIFT-C",
    PALADIN_RETRIBUTION_TEMPLAR_STRIKE = "SHIFT-G",
    PALADIN_RETRIBUTION_HAMMER_OF_WRATH = "SHIFT-H",
    PALADIN_RETRIBUTION_WAKE_OF_ASHES = "SHIFT-N",
    PALADIN_RETRIBUTION_DIVINE_TOLL = "SHIFT-R",
    PALADIN_RETRIBUTION_HAMMER_OF_LIGHT = "SHIFT-T",
    PALADIN_RETRIBUTION_FINAL_VERDICT = "SHIFT-Y",
    PALADIN_RETRIBUTION_EXECUTION_SENTENCE = "SHIFT-0",
}

function BindingProfile:GetBinding(actionId)
    return bindings[actionId]
end

function BindingProfile:ListBindings()
    return bindings
end

function BindingProfile:ToTekBinding(wowBinding)
    return tostring(wowBinding or ""):gsub("%-", "+")
end
