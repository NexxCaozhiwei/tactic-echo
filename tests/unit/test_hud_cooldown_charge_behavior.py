from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
LUA = shutil.which("lua") or shutil.which("texlua")
ADDON = ROOT / "addon" / "!TacticEcho"


def run_lua(body: str) -> None:
    if not LUA:
        pytest.skip("lua executable is required for HUD cooldown behavior tests")
    script = f"local ROOT = [[{ROOT.as_posix()}]]\n{body}"
    with tempfile.NamedTemporaryFile("w", suffix=".lua", encoding="utf-8", delete=False) as handle:
        handle.write(script)
        path = Path(handle.name)
    try:
        result = subprocess.run(
            [LUA, str(path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
    finally:
        path.unlink(missing_ok=True)
    assert result.returncode == 0, result.stderr + result.stdout


TRACKER_HARNESS = r"""
local nowValue = 100
local combat = false
local baseCooldowns = {}
local liveCooldowns = {}
local chargeInfo = {}

function GetTime() return nowValue end
function InCombatLockdown() return combat end
function GetSpellBaseCooldown(spellID) return baseCooldowns[spellID] end
UIParent = {}

local function frameStub()
    return {
        SetOwner = function() end,
        ClearLines = function() end,
        SetSpellByID = function() end,
        NumLines = function() return 0 end,
        SetScript = function(self, kind, callback) self[kind] = callback end,
    }
end
function CreateFrame() return frameStub() end

_G.TacticEcho = {
    RegisterEventsSafe = function() end,
}
C_Timer = { After = function() end }
C_Spell = {
    GetSpellCooldown = function(spellID)
        return liveCooldowns[spellID] or {
            startTime = 0,
            duration = 0,
            isActive = false,
            isOnGCD = false,
        }
    end,
    GetSpellCharges = function(spellID) return chargeInfo[spellID] end,
}

dofile(ROOT .. "/addon/!TacticEcho/Tactics/CooldownTracker.lua")
local Tracker = _G.TacticEcho.CooldownTracker
"""


def test_base_cooldown_milliseconds_are_converted_at_the_api_boundary() -> None:
    run_lua(TRACKER_HARNESS + r"""
baseCooldowns[44425] = 500
Tracker:RegisterSpell(44425, { allowStaticFallback = true })
combat = true
liveCooldowns[44425] = {
    startTime = nowValue,
    duration = 1.5,
    isActive = true,
    isOnGCD = true,
}
Tracker:RecordCast(44425)
assert(Tracker:GetCooldown(44425, {}) == nil,
    "500 ms Arcane Barrage base/GCD data must not become a 500 second HUD timer")

combat = false
baseCooldowns[90001] = 30000
Tracker:RegisterSpell(90001, { allowStaticFallback = true })
combat = true
liveCooldowns[90001] = {
    startTime = nowValue,
    duration = 1.5,
    isActive = true,
    isOnGCD = true,
}
Tracker:RecordCast(90001)
local fallback = Tracker:GetCooldown(90001, {})
assert(fallback and fallback.duration == 30,
    "GetSpellBaseCooldown 30000 ms must seed exactly 30 seconds")
""")


def test_second_based_runtime_values_are_not_rescaled_and_global_reconcile_corrects_fallback() -> None:
    run_lua(TRACKER_HARNESS + r"""
baseCooldowns[90002] = 60000
Tracker:RegisterSpell(90002, { allowStaticFallback = true })
combat = true
liveCooldowns[90002] = {
    startTime = nowValue,
    duration = 1.5,
    isActive = true,
    isOnGCD = true,
}
Tracker:RecordCast(90002)
assert(Tracker:GetCooldown(90002, {}).duration == 60)

liveCooldowns[90002] = {
    startTime = nowValue,
    duration = 1200,
    isActive = true,
    isOnGCD = false,
}
Tracker:ReconcileAllCooldowns()
local corrected = Tracker:GetCooldown(90002, {})
assert(corrected and corrected.duration == 1200,
    "C_Spell cooldown durations are already seconds and must not be divided by 1000")
assert(corrected.fallback == false and corrected.source == "spell_api_confirmation")
""")


def test_explicit_non_charge_state_clears_stale_tracker_but_opaque_state_does_not() -> None:
    run_lua(TRACKER_HARNESS + r"""
chargeInfo[90003] = {
    currentCharges = 2,
    maxCharges = 2,
    cooldownStartTime = 0,
    cooldownDuration = 20,
}
Tracker:RegisterSpell(90003, {})
local initial = Tracker:GetCharges(90003, {})
assert(initial and initial.current == 2 and initial.maximum == 2)

chargeInfo[90003] = {}
Tracker:ReconcileAllCharges()
assert(Tracker:GetCharges(90003, {}) ~= nil,
    "opaque charge data must not erase the last confirmed state")

Tracker:RegisterSpell(90003, { equivalentSpellIDs = { 90005 } })
chargeInfo[90003] = { currentCharges = 1, maxCharges = 1 }
chargeInfo[90005] = {}
Tracker:ReconcileAllCharges()
assert(Tracker:GetCharges(90003, {}) ~= nil,
    "one readable 1/1 alias must not erase charges while an equivalent identity is opaque")

chargeInfo[90003] = { currentCharges = 1, maxCharges = 1 }
chargeInfo[90005] = { currentCharges = 1, maxCharges = 1 }
Tracker:ReconcileAllCharges()
assert(Tracker:GetCharges(90003, {}) == nil,
    "an explicit 1/1 ordinary cooldown state must clear stale multi-charge data")
""")


def test_icon_state_only_projects_real_multi_charge_spells() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {}
local chargeInfo = { currentCharges = 1, maxCharges = 1 }
C_Spell = {
    GetSpellCooldown = function()
        return { startTime = 0, duration = 0, isActive = false, isOnGCD = false }
    end,
    GetSpellCharges = function() return chargeInfo end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(90004, {
    gcdSnapshot = { known = true, active = false, activeKnown = true },
})
assert(state.charges == nil and state.maxCharges == nil,
    "ordinary 1/1 cooldown semantics must not become a HUD charge label")

chargeInfo = {
    currentCharges = 1,
    maxCharges = 2,
    cooldownStartTime = 90,
    cooldownDuration = 20,
}
state = _G.TacticEcho.IconState:CollectCooldownOnly(90004, {
    gcdSnapshot = { known = true, active = false, activeKnown = true },
})
assert(state.charges == 1 and state.maxCharges == 2,
    "a readable 1/2 charge spell must remain visible")
""")


def test_hud_consumers_defensively_require_more_than_one_charge() -> None:
    source = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
    assert source.count("maxCharges > 1") >= 3
    assert '"充能：" .. tostring(charges)' in source


def test_opaque_direct_action_clears_stale_120_second_hud_timer() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {
    CooldownTracker = {
        IsConfirmationPending = function() return true end,
        GetCooldown = function()
            return {
                remaining = 110,
                duration = 120,
                start = 90,
                source = "local_tracker_cached",
                fallback = true,
                fallbackOrigin = "base_cache",
            }
        end,
    },
}
C_Spell = {
    GetSpellCooldown = function(spellID)
        if spellID == 61304 then
            return { startTime = 0, duration = 0, isActive = false, isOnGCD = false }
        end
        return { startTime = 90, duration = 120, isActive = true, isOnGCD = false }
    end,
    GetSpellCharges = function() return nil end,
    IsSpellUsable = function() return true, false end,
}
C_ActionBar = {
    GetActionCooldown = function()
        -- Exact current button proves a non-GCD own cooldown, while protected
        -- timing values are unavailable to addon code this frame.
        return { isActive = true, isOnGCD = false }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local options = {
    actionSlot = 8,
    directActionSlot = true,
    actionBarStateTrusted = true,
    gcdSnapshot = { known = true, active = false, activeKnown = true },
}
local full = _G.TacticEcho.IconState:Collect(31884, options)
assert(full.cooldownKnown == true and full.cooldownActive == true,
    "HUD state must still permit the native cooldown swipe")
assert(full.cooldownRemaining == nil and full.cooldownDuration == nil and full.cooldownStart == nil,
        "HUD badge must stay hidden until the exact action exposes safe numeric timing: "
        .. tostring(full.cooldownRemaining) .. "/" .. tostring(full.cooldownDuration) .. "/"
        .. tostring(full.cooldownStart) .. " source=" .. tostring(full.cooldownSource)
        .. " action=" .. tostring(full.cooldownActionBarPublicActive) .. "/"
        .. tostring(full.cooldownActionBarPublicOnGCD))
assert(full.cooldownSource == "actionbar_api", "opaque exact action must remain the semantic source")

local cooldownOnly = _G.TacticEcho.IconState:CollectCooldownOnly(31884, options)
assert(cooldownOnly.cooldownKnown == true and cooldownOnly.cooldownActive == true,
    "opaque exact action must retain the semantic own-cooldown veto")
assert(cooldownOnly.cooldownRemaining == nil and cooldownOnly.cooldownDuration == nil and cooldownOnly.cooldownStart == nil,
    "cooldown-only state must not retain the stale 120 second requested-spell timer")
""")
