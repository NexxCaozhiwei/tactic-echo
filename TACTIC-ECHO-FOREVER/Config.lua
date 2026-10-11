local _, TEF = ...
-- Explicitly observed IDs only. Names are user labels, not rank equivalence.
-- Edit this bounded list out of game, copy Config.lua to the TEF folder, reload.
TEF.StandardConfig = {
    { name = "寒冰箭", spellID = 205, matchIDs = {205} },
    { name = "火球术", spellID = 143, matchIDs = {143} },
    { name = "火焰冲击", spellID = 2136, matchIDs = {2136} },
    { name = "奥术飞弹", spellID = 5143, matchIDs = {5143} },
}
-- Preserved adjacent-only test and original four-step sequence.
TEF.AdjacentConfig = { TEF.StandardConfig[1], TEF.StandardConfig[1] }
-- Temporary exact-ID rank/order experiment. Restore with:
-- TEF.Config = TEF.StandardConfig
TEF.Config = {
    { name = "寒冰箭（116）", spellID = 116, matchIDs = {116} },
    TEF.StandardConfig[1],
    TEF.StandardConfig[1],
    TEF.StandardConfig[2],
}
-- Both profiles are manual practice, not a claim about optimal AoE spells.
TEF.ProfileDefaults = {
    single = TEF.Config,
    -- Public 118 successes observed in TEF sessions 16/17, 2026-10-11.
    multi = {{name="变形术",spellID=118,matchIDs={118}}, TEF.StandardConfig[4]},
}
TEF.Version = "0.5.1"
TEF.Placeholder = 134400
