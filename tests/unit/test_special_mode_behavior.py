"""Executable replacement selection, fail-closed readiness and transport tests."""
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
LUA = shutil.which("lua") or shutil.which("texlua")

HARNESS = r'''
local TE = { Context = {}, BurstProfiles = {}, RuntimeSnapshot = {}, GCDGate = {}, ActionBarBindingResolver = {} }
_G.TacticEcho = TE
TacticEchoDB = {settings = {specialModeEnabled = true}, tactics = {}}
local context = {classFile = "MAGE", specIndex = 1, inCombat = true}
function TE.Context:GetPlayer() return context end
function TE.Context:GetRevision() return 1 end
function TE.BurstProfiles:SpecKey(class, spec) if class and spec then return class .. "_" .. spec end end
local icon = {cooldownKnown = true, cooldownActive = false}
local phase = "READY_NOW"
function TE.RuntimeSnapshot:CollectSpellCooldown(snapshot, id, binding) assert(id == 200); return icon end
function TE.GCDGate:BeginCycle() return {} end
function TE.GCDGate:Classify() return phase end
function TE.ActionBarBindingResolver:IsVerifiedCurrentMacroSource(binding) return binding.verified == true end
dofile(ROOT .. "/addon/!TacticEcho/Tactics/SpecialMode.lua")
local mode = TE.SpecialMode
local binding = {status = "Ready", bindingToken = 7, source = "spell"}
'''

def run_lua(tmp_path, body):
    if not LUA:
        pytest.skip("Lua executable required")
    path = tmp_path / "special.lua"
    path.write_text(f'local ROOT = [[{ROOT.as_posix()}]]\n' + HARNESS + body, encoding="utf-8")
    result = subprocess.run([LUA, str(path)], cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_three_groups_configuration_and_spec_isolation(tmp_path):
    run_lua(tmp_path, r'''
assert(mode:Select(100) == nil)
for i = 1, 3 do assert(mode:Configure(i, 99+i, 199+i, false)) end
assert(mode:Select(100) == nil)
assert(mode:Configure(1, 100, 200, true))
assert(mode:Configure(2, 101, 201, true))
assert(mode:Configure(3, 102, 202, true))
assert(mode:Select(100).spellID == 200)
assert(mode:Select(101).spellID == 201)
assert(mode:Select(102).spellID == 202)
assert(mode:Select(200) == nil) -- no recursive replacement
assert(not mode:Configure(4, 100, 200, true))
assert(not mode:Configure(2, 100, 201, true))
assert(not mode:Configure(1, 100, 100, true))
assert(not mode:Configure(1, 1.2, 200, true))
TacticEchoDB.settings.specialModeEnabled = false
assert(mode:Select(100) == nil)
TacticEchoDB.settings.specialModeEnabled = true
context.specIndex = 2
assert(mode:Select(100) == nil)
context.specIndex = 1
local groups = mode:GetGroups()
groups[2] = {sourceSpellID = 100, targetSpellID = 201, enabled = true}
assert(mode:Select(100).spellID == nil) -- corrupt duplicate fails closed
groups[2].enabled = false
groups[1].targetSpellID = 0
assert(mode:Select(100).spellID == nil)
''')


@pytest.mark.parametrize("case", [
    'binding.bindingToken = 0',
    'binding.status = "Blocked"',
    'binding.source = "macro"; binding.verified = false',
    'binding.specialActionBar = {active = true}',
    'icon = {}',
    'icon = {cooldownKnown=true,cooldownActive=true,cooldownOnGCD=false}',
    'icon = {maxCharges=2,charges=0}',
    'icon = {cooldownPublicActiveKnown=true,cooldownPublicActive=true}',
    'phase = "GCD_LOCKED"',
    'phase = "UNKNOWN"',
])
def test_replacement_never_inherits_official_readiness(tmp_path, case):
    run_lua(tmp_path, case + '\nassert(not mode:CanDispatch(200, binding, {}))')


@pytest.mark.parametrize("case", [
    '', 'phase = "QUEUE_WINDOW"',
    'icon = {maxCharges=2,charges=1}',
    'icon = {cooldownPublicActiveKnown=true,cooldownPublicActive=false}',
    'icon = {cooldownPublicActiveKnown=true,cooldownPublicActive=true,cooldownPublicOnGCDKnown=true,cooldownPublicOnGCD=true}',
    'binding.source="macro"; binding.verified=true',
])
def test_replacement_positive_readiness(tmp_path, case):
    run_lua(tmp_path, case + '\nassert(mode:CanDispatch(200, binding, {}))')


def test_real_signal_frame_keeps_official_and_burst_ownership(tmp_path):
    run_lua(tmp_path, r'''
function GetTime() return 10 end
function CreateFrame()
    return setmetatable({CreateTexture=CreateFrame}, {__index=function() return function() end end})
end
function TE:RegisterEventSafe() end
function TE:RegisterEventsSafe() end
TE.RecommendationAdapter = {ReadOfficial=function() return {spellID=100} end}
TE.ActionRegistry = {ResolveRecommendation=function(_, rec) return {actionCode=0} end}
function TE.ActionBarBindingResolver:ResolveSpell(id) return binding end
function TE.RuntimeSnapshot:Begin() return {} end
local manual = false
TE.ManualActionPriority = {GetActive=function() return {active=manual} end}
local decision
TE.AutoBurst = {Evaluate=function() return decision end}
assert(mode:Configure(1,100,200,true))
dofile(ROOT .. "/addon/!TacticEcho/Signal/SignalFrame.lua")
-- Test the real business selector independently of raster painting.
TE.SignalFrame.Refresh = function() end
TE.SignalFrame:SetState("armed")
local function message() return TE.SignalFrame:BuildBusinessMessage("test",100,"Ready") end
local m = message()
assert(m.officialSpellID == 100 and m.dispatchSpellID == 200 and m.bindingToken == 7)
assert(m.dispatchOrigin == "official")
icon = {}; m=message()
assert(m.officialSpellID==100 and m.dispatchSpellID==200 and m.bindingToken==0 and m.observationOnly)
decision={kind="candidate",dispatchSpellID=300,bindingInfo=binding}
m=message(); assert(m.dispatchSpellID==300 and m.dispatchOrigin=="burst" and m.bindingToken==7)
decision={kind="hold",observationOnly=true,reason="burst_wait"}
m=message(); assert(m.dispatchSpellID==nil and m.dispatchOrigin=="burst" and m.bindingToken==0)
decision=nil; manual=true
m=message(); assert(m.dispatchSpellID==nil and m.bindingToken==0 and m.state=="manual_hold")
manual=false; TacticEchoDB.settings.specialModeEnabled=false
m=message(); assert(m.dispatchSpellID==100 and m.bindingToken==7)
''')


def test_hotkey_conflicts_combat_deferral_and_toggle(tmp_path):
    run_lua(tmp_path, r'''
local frames, writes, clears = {}, 0, 0
function CreateFrame(_, name)
    local frame = {scripts={}}
    function frame:SetScript(event, callback) self.scripts[event]=callback end
    setmetatable(frame, {__index=function() return function() end end})
    if name then frames[name]=frame end
    return frame
end
function TE:RegisterEventsSafe(frame) TE.events=frame end
SlashCmdList={}
local combat=false
function InCombatLockdown() return combat end
function ClearOverrideBindings() clears=clears+1 end
function SetOverrideBindingClick(_, _, key, name) writes=writes+1; assert(key=="CTRL-F8"); assert(name=="TacticEchoSpecialModeToggleHotkeyButton") end
TE.Config={Normalize={All=function() return TacticEchoDB.settings end}}
dofile(ROOT .. "/addon/!TacticEcho/UI/ControlPanel.lua")
local ui=TE.ControlPanel
ui.UpdateInputStatus=function() end
ui.ApplyVisuals=function() end
TacticEchoDB.settings.toggleHotkey="F6"
TacticEchoDB.settings.autoBurstToggleHotkey="F7"
assert(not ui:ApplySpecialModeHotkey("F6",false))
assert(not ui:ApplySpecialModeHotkey("F7",false))
assert(writes==0 and clears==0)
combat=true
assert(not ui:ApplySpecialModeHotkey("CTRL-F8",false))
assert(writes==0 and clears==0)
combat=false
TE.events.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
assert(writes==1 and clears==1)
local callback=frames.TacticEchoSpecialModeToggleHotkeyButton.scripts.OnClick
combat=true
callback(); assert(not mode:IsEnabled())
callback(); assert(mode:IsEnabled())
assert(writes==1) -- toggling in combat does not edit protected bindings
assert(not ui:ApplyToggleHotkey("CTRL-F8",false))
assert(not ui:ApplyAutoBurstHotkey("CTRL-F8",false))
combat=false
assert(ui:ApplySpecialModeHotkey("",false)); assert(clears==2 and writes==1)
''')
