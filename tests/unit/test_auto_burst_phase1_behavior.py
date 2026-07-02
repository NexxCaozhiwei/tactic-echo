import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
LUA = shutil.which("lua")


def run_lua(body: str) -> str:
    if not LUA:
        pytest.skip("lua executable is required for AutoBurst behavior tests")
    script = f"""
local ROOT = [[{ROOT.as_posix()}]]
{body}
"""
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
    return result.stdout


AUTO_BURST_HARNESS = r"""
local nowValue = 0
function GetTime() return nowValue end
function CreateFrame()
    return { SetScript = function(self, event, callback) self[event] = callback end }
end
TacticEchoDB = {}
_G.TacticEcho = {
    version = "test",
    Config = { Normalize = {} },
    Context = {},
    ActionBarBindingResolver = {},
    IconState = {},
    GCDGate = {},
}
local TE = _G.TacticEcho
function TE:RegisterEventsSafe(frame, events) frame.events = events end
function TE.Config.Normalize:All() return {}, settings end
function TE.Context:GetPlayer() return { classFile = "PALADIN", specIndex = 3 } end

settings = {
    autoBurstEnabled = true,
    autoBurstDirection = "pre",
    autoBurstMode = "simple",
    autoBurstWindowSpellID = 343527,
    autoBurstInjectionSpellID = 31884,
    autoBurstUseProfileFallback = false,
    autoBurstDebug = false,
}
cooldowns = { [343527] = "ready", [31884] = "ready" }
bindings = { [343527] = "ready", [31884] = "ready" }
gcdPhase = "READY_NOW"

function TE.ActionBarBindingResolver:ResolveSpell(spellID)
    if bindings[spellID] ~= "ready" then
        return { status = "NoBinding", reason = "test_no_binding", spellID = spellID }, "test_no_binding"
    end
    local token = spellID == 31884 and 4 or 1
    return {
        status = "Ready",
        spellID = spellID,
        matchedSpellID = spellID,
        requestedSpellID = spellID,
        bindingToken = token,
        binding = tostring(token),
        rawBinding = tostring(token),
        source = "spell",
        directActionSlot = true,
        actionSlot = token,
    }, nil
end

function TE.IconState:CollectCooldownOnly(spellID, options)
    local state = cooldowns[spellID] or "ready"
    if state == "ready" then
        return { cooldownKnown = true, cooldownActive = false, cooldownOnGCD = false, charges = 1, maxCharges = 1, cooldownLiveRead = true }
    elseif state == "cooldown" then
        return { cooldownKnown = true, cooldownActive = true, cooldownOnGCD = false, charges = 1, maxCharges = 1, cooldownLiveRead = true }
    elseif state == "public_gcd" then
        return {
            cooldownKnown = false,
            cooldownPublicActiveKnown = true,
            cooldownPublicActive = true,
            cooldownPublicOnGCDKnown = true,
            cooldownPublicOnGCD = true,
            cooldownLiveRead = true,
        }
    elseif state == "unknown" then
        return { cooldownKnown = false, cooldownUnknownReason = "test_unknown", cooldownLiveRead = true }
    end
    error("unknown cooldown test state: " .. tostring(state))
end

function TE.GCDGate:BeginCycle(primary) return { phase = gcdPhase } end
function TE.GCDGate:Classify(cycle) return gcdPhase, "test_" .. tostring(gcdPhase) end

dofile(ROOT .. "/addon/!TacticEcho/Tactics/AutoBurst.lua")
local AutoBurst = TE.AutoBurst

local function eval(intent)
    intent = intent or "armed"
    return AutoBurst:Evaluate({ spellID = 343527 }, {
        inCombat = true,
        intentState = intent,
        effectiveState = intent,
        primary = { spellID = 343527 },
        context = {},
    })
end
"""


def test_pre_simple_strict_sequence_persists_candidate_until_spellcast_confirmation() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884, "first candidate must be injection 4")
local repeatOffer = eval()
assert(repeatOffer.kind == "candidate" and repeatOffer.dispatchSpellID == 31884, "same injection candidate should persist")
assert(repeatOffer.dispatchAttempt == first.dispatchAttempt, "same logical candidate must keep one attempt id")
AutoBurst:RecordSpellcastSucceeded(31884)
local afterInjection = eval()
assert(afterInjection.kind == "hold", "confirmation frame should advance without same-frame window dispatch")
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "window 1 must follow confirmed injection")
AutoBurst:RecordSpellcastSucceeded(343527)
local done = eval()
assert(done.kind == "hold", "completed plan should hold until official leaves window")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.requireWindowDeparture == true, "completed plan must keep departure lock")
""")


def test_paused_to_armed_first_healthy_window_creates_plan_without_icon_edge() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local paused = eval("paused")
assert(paused.kind == "none", "paused frame must not dispatch")
local armed = eval("armed")
assert(armed.kind == "candidate" and armed.dispatchSpellID == 31884, "first healthy armed frame should claim visible window")
local snap = AutoBurst:GetSnapshot()
assert(snap.armedEpoch == 1 and snap.planWindowGeneration == 1, "plan should carry armed/window generation")
""")


def test_consumed_window_generation_does_not_retrigger_until_departure() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
AutoBurst:RecordSpellcastSucceeded(31884)
eval()
local window = eval()
AutoBurst:RecordSpellcastSucceeded(343527)
eval()
local stillWindow = eval()
assert(stillWindow.kind == "hold", "same consumed window must stay observation-only")
local away = AutoBurst:Evaluate({ spellID = 999001 }, { inCombat = true, intentState = "armed", effectiveState = "armed", primary = { spellID = 999001 }, context = {} })
assert(away.kind == "none", "departure releases lock")
local back = eval()
assert(back.kind == "candidate" and back.dispatchSpellID == 31884, "new window generation may start after departure")
""")


def test_pre_simple_skips_injection_only_when_initial_edge_proves_own_cooldown() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "cooldown"
local first = eval()
assert(first.kind == "hold", "own-cooldown injection skip should not same-frame dispatch window")
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "simple pre may skip injection only after own cooldown proof")
""")


def test_public_gcd_active_holds_and_rechecks_without_skipping_injection() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "public_gcd"
gcdPhase = "GCD_LOCKED"
local locked = eval()
assert(locked.kind == "hold", "public GCD active should hold")
assert(AutoBurst:GetSnapshot().currentSpellID == 31884, "injection remains current step")
cooldowns[31884] = "ready"
gcdPhase = "READY_NOW"
local ready = eval()
assert(ready.kind == "candidate" and ready.dispatchSpellID == 31884, "ready recheck must offer injection, not window")
""")


def test_unknown_injection_revalidates_then_aborts_with_departure_lock() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "unknown"
local first = eval()
assert(first.kind == "hold", "unknown injection must enter bounded revalidation")
nowValue = 3.0
local timeout = eval()
assert(timeout.kind == "hold", "timeout should hold owned window")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.requireWindowDeparture == true, "unknown timeout must not fall through to official 1")
assert(AutoBurst:GetDiagnostics().lastAbortReason:find("step_revalidate_timeout", 1, true), "abort reason should identify revalidation timeout")
""")


def test_plan_creation_requires_both_window_and_injection_bindings() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
bindings[343527] = "missing"
local result = eval()
assert(result.kind == "none", "missing window binding should reject plan")
assert(AutoBurst:GetSnapshot().active == false, "no plan should exist when either binding is unavailable")
bindings[343527] = "ready"
bindings[31884] = "missing"
result = AutoBurst:Evaluate({ spellID = 999001 }, { inCombat = true, intentState = "armed", effectiveState = "armed", primary = { spellID = 999001 }, context = {} })
result = eval()
assert(result.kind == "none", "missing injection binding should reject plan")
""")


def test_spellcast_success_is_accepted_only_for_current_waiting_step() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(343527)
local stillInjection = eval()
assert(stillInjection.kind == "candidate" and stillInjection.dispatchSpellID == 31884, "wrong success event must not advance step")
AutoBurst:RecordSpellcastSucceeded(31884)
eval()
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "matching event should advance to window")
assert(AutoBurst:GetDiagnostics().lastConfirmationSource == "unit_spellcast_succeeded", "event confirmation should be audited")
""")


def test_post_simple_unknown_injection_is_optional_after_confirmed_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoBurstDirection = "post"
cooldowns[31884] = "unknown"
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "post mode starts with window")
AutoBurst:RecordSpellcastSucceeded(343527)
eval()
local skipped = eval()
assert(skipped.kind == "hold", "unknown post injection should be skipped only after window confirmation")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.requireWindowDeparture == true, "post simple skip completes under departure lock")
""")


def test_tactical_state_observation_frame_displays_official_binding_with_zero_dispatch_token() -> None:
    run_lua(r"""
local nowValue = 1
function GetTime() return nowValue end
_G.TacticEcho = {}
C_Spell = { GetSpellInfo = function(spellID) return { name = tostring(spellID), iconID = spellID } end }
dofile(ROOT .. "/addon/!TacticEcho/Tactics/TacticalState.lua")
local snap = TacticEcho.TacticalState:Publish({
    state = "armed",
    intentState = "armed",
    observationOnly = true,
    officialSpellID = 343527,
    dispatchOrigin = "burst",
    bindingToken = 0,
    officialBindingInfo = { status = "Ready", binding = "1", rawBinding = "1", bindingToken = 1, source = "spell" },
}, {})
assert(snap.binding == "1", "observation HUD should show official binding")
assert(snap.bindingToken == 0, "transport token must remain zero")
assert(snap.displayBindingToken == 1, "display binding token is diagnostic-only")
assert(snap.dispatchAllowed == false, "observation frame is never dispatchable")
""")
