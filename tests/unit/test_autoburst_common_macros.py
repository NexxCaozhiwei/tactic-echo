from test_hud_cooldown_charge_behavior import run_lua
from test_macro_identity_p5 import _preamble
from test_auto_burst_phase1_behavior import AUTO_BURST_HARNESS
import pytest


@pytest.mark.parametrize("case", ["unique", "ambiguous", "missing", "dual", "no_key"])
def test_item_subtype_is_not_an_account_macro_index(case):
    run_lua(_preamble(32) + 'local case = "' + case + '"\n' + r'''
local R = _G.TacticEcho.ActionBarBindingResolver
GetNumMacros = function() return 32, 24 end
GetActionInfo = function(slot)
    if slot == 33 then return "macro", 32, "item" end
    if slot == 34 then return "macro", 144 end
end
GetActionText = function(slot)
    if slot == 33 then
        if case == "missing" then return nil end
        return "饰一"
    end
    if slot == 34 then return "饰二" end
end
GetBindingKey = function() if case ~= "no_key" then return "F" end end
GetMacroInfo = function(index)
    assert(type(index) == "number", "never read a macro by name")
    if index == 143 then
        return "饰一", 1, case == "dual" and "/use 13\n/use 14" or "#showtooltips\n/use 13"
    end
    if index == 144 then return "饰二", 1, "#showtooltips\n/use 14\n/use 14" end
    if index == 32 and case == "ambiguous" then return "饰一", 1, "/use 13" end
    return "Other" .. index, 1, "/cast 12345"
end
GetMacroSpell = function() return nil end
GetInventoryItemID = function(_, slot) return slot == 13 and 250215 or 250216 end
local first = R:ResolveInventorySlot(13, 250215)
if case == "unique" then
    assert(first.status == "Ready", first.reason)
    assert(first.macroID == 143 and first.actionSlot == 33 and first.bindingToken > 0)
    assert(R:IsAutoBurstMacroEligible(first))
else
    assert(first.bindingToken == 0, "unverified/unbound source must remain closed")
end
local second = R:ResolveInventorySlot(14, 250216)
if case ~= "no_key" then
    assert(second.status == "Ready" and second.macroID == 144 and second.actionSlot == 34)
end
''')


def test_common_macro_bindings_keep_tokens_but_do_not_mix_spell_state():
    run_lua(_preamble(1) + r'''
local R = _G.TacticEcho.ActionBarBindingResolver
local names = {[31884] = "复仇之怒", [343527] = "处决宣判", [44425] = "奥术弹幕", [321507] = "大法师之触"}
C_Spell.GetSpellInfo = function(value)
    for id, name in pairs(names) do
        if value == id or value == name then return {spellID=id, name=name} end
    end
end
local bodies = {
    "#showtooltip 处决宣判\n/cast 复仇之怒\n/cast 处决宣判",
    "#showtooltips\n/use 13",
    "#showtooltip 大法师之触\n/castsequence reset=2 奥术弹幕, 大法师之触",
    "#showtooltip 处决宣判\n/cast [@target] 处决宣判",
}
local current = 1
GetNumMacros = function() return 4, 0 end
GetActionInfo = function(slot) if slot == 1 then return "macro", current end end
GetMacroInfo = function(index) return "Macro" .. index, 1, bodies[index] end
GetMacroSpell = function() return 343527 end
GetInventoryItemID = function(_, slot) if slot == 13 then return 999001 end end
local function refresh(index)
    current = index
    R:Invalidate("UPDATE_MACROS")
end
local a = R:ResolveSpell(343527)
assert(a.status == "Ready" and a.bindingToken > 0 and R:IsAutoBurstMacroEligible(a))
assert(not a.actionBarStateTrusted and not R:IsSpellActionStateTrusted(a))
refresh(2)
local item = R:ResolveInventorySlot(13, 999001)
assert(item.status == "Ready" and item.bindingToken > 0 and R:IsAutoBurstMacroEligible(item))
assert(item.inventorySlot == 13 and item.itemID == 999001)
assert(R:ResolveInventorySlot(13, 999002).bindingToken == 0)
assert(R:ResolveInventorySlot(14).bindingToken == 0)
refresh(3)
for _, id in ipairs({44425, 321507}) do
    local b = R:ResolveSpell(id)
    assert(b.status == "Ready" and b.bindingToken > 0 and R:IsAutoBurstMacroEligible(b))
    assert(not b.actionBarStateTrusted and not R:IsSpellActionStateTrusted(b))
end
refresh(4)
local single = R:ResolveSpell(343527)
assert(single.status == "Ready" and single.actionBarStateTrusted and R:IsSpellActionStateTrusted(single))
''')


def test_generic_inventory_macro_with_opaque_handle_and_unique_name():
    run_lua(_preamble(900001) + r'''
local R = _G.TacticEcho.ActionBarBindingResolver
GetNumMacros = function() return 1, 0 end
GetActionText = function() return "通用饰品" end
GetMacroInfo = function(index)
    if index == 1 then return "通用饰品", 1, "#showtooltips\n/use 13" end
    if index == 900001 then return "通用饰品", 1, nil end
end
GetMacroSpell = function() return nil end
GetInventoryItemID = function(_, slot) if slot == 13 then return 999001 end end
local item = R:ResolveInventorySlot(13, 999001)
assert(item.status == "Ready" and item.bindingToken > 0 and item.macroID == 1)
assert(R:IsAutoBurstMacroEligible(item))
''')


def test_item_subtype_preserves_exact_use_item_body_compatibility():
    run_lua(_preamble(32) + r'''
local R = _G.TacticEcho.ActionBarBindingResolver
GetNumMacros = function() return 32, 24 end
GetActionInfo = function(slot) if slot == 1 then return "macro", 32, "item" end end
GetActionText = function() return "指定物品" end
GetMacroInfo = function(index)
    if index == 143 then return "指定物品", 1, "/use item:250215" end
    return "Other" .. index, 1, "/cast 12345"
end
GetMacroSpell = function() return nil end
local item = R:ResolveItem(250215)
assert(item.status == "Ready" and item.macroID == 143 and item.bindingToken > 0)
assert(R:IsVerifiedCurrentMacroSource(item))
assert(R:ResolveItem(250216).bindingToken == 0)
''')


def test_macro_other_action_unusable_does_not_drop_or_stall_exact_step():
    run_lua(AUTO_BURST_HARNESS + r'''
local resolve = TE.ActionBarBindingResolver.ResolveSpell
function TE.ActionBarBindingResolver:ResolveSpell(id, ...)
    local result = resolve(self, id, ...)
    if id == 31884 then
        result.source = "macro"
        result.directActionSlot = false
        result.actionBarStateTrusted = false
    end
    return result
end
function TE.ActionBarBindingResolver:IsAutoBurstMacroEligible() return true end
function TE.ActionBarBindingResolver:IsSpellActionStateTrusted() return false end
spellUsability[31884] = "ready"
actionUsability[4] = "resource"
local result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 31884)
nowValue = 0.2
result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 31884,
    "another macro action's resource state must not remove this injection")
assert(AutoBurst:RecordSpellcastSucceeded(343527) == false,
    "another spell from the macro must not confirm the current injection")
nowValue = 0.4
result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 31884)
assert(AutoBurst:RecordSpellcastSucceeded(31884) == true)
''')


def test_sequence_button_gcd_cannot_erase_requested_spell_own_cooldown():
    run_lua(r'''
function GetTime() return 100 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function()
        return {startTime=90, duration=45, isEnabled=true, isActive=true, isOnGCD=false}
    end,
    GetSpellCharges = function() return nil end,
}
C_ActionBar = {GetActionCooldown = function()
    error("an unrelated sequence action must not supply own cooldown evidence")
end}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(321507, {
    liveCooldown=true, actionSlot=1, directActionSlot=false, actionBarStateTrusted=false,
    gcdSnapshot={known=true, active=false, activeKnown=true},
})
assert(state.cooldownKnown and state.cooldownActive and state.cooldownOnGCD ~= true)
''')
