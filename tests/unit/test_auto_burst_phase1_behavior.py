import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
LUA = shutil.which("lua") or shutil.which("texlua")


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
settings = {
    autoBurstEnabled = true,
    autoBurstMode = "simple",
    autoBurstDebug = false,
    burstProfiles = {},
}
TacticEchoDB = { tactics = settings }
function TE.Config.Normalize:All() return {}, settings end
function TE.Context:GetPlayer() return { class = "PALADIN", classFile = "PALADIN", specIndex = 3 } end

-- Ordered sequence helpers: these exercise the real specialization profile
-- instead of retired hand-entered Phase-1.5 SpellID overrides.
local function set_sequence(order, enabled)
    settings.burstProfiles.PALADIN_3 = {
        autoBurstSequence = { order = order, enabled = enabled or {} },
    }
end
function use_default_pre_sequence()
    set_sequence({ "injection:31884", "window", "trinket:13", "trinket:14" }, {
        ["injection:31884"] = true,
        ["trinket:13"] = false,
        ["trinket:14"] = false,
    })
end
function use_trinket_pre_sequence()
    set_sequence({ "trinket:13", "window", "injection:31884", "trinket:14" }, {
        ["trinket:13"] = true,
        ["injection:31884"] = false,
        ["trinket:14"] = false,
    })
end
function use_post_sequence()
    set_sequence({ "window", "injection:31884", "trinket:13", "trinket:14" }, {
        ["injection:31884"] = true,
        ["trinket:13"] = false,
        ["trinket:14"] = false,
    })
end
use_default_pre_sequence()
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
        actionBarStateTrusted = true,
    }, nil
end

function TE.IconState:CollectCooldownOnly(spellID, options)
    local state = cooldowns[spellID] or "ready"
    local identity = "spell:" .. tostring(spellID)
    if state == "ready" then
        return { cooldownKnown = true, cooldownActive = false, cooldownOnGCD = false, charges = 1, maxCharges = 1, cooldownLiveRead = true, cooldownSource = "spell_api", cooldownIdentityKey = identity, cooldownConfirmationPending = false }
    elseif state == "cooldown" then
        return { cooldownKnown = true, cooldownActive = true, cooldownOnGCD = false, charges = 1, maxCharges = 1, cooldownLiveRead = true, cooldownSource = "spell_api", cooldownIdentityKey = identity, cooldownConfirmationPending = false }
    elseif state == "cooldown_pending" then
        return { cooldownKnown = true, cooldownActive = true, cooldownOnGCD = false, charges = 1, maxCharges = 1, cooldownLiveRead = true, cooldownSource = "spell_api", cooldownIdentityKey = identity, cooldownConfirmationPending = true }
    elseif state == "actionbar_cooldown" then
        return {
            cooldownKnown = true,
            cooldownActive = true,
            cooldownOnGCD = false,
            charges = 1,
            maxCharges = 1,
            cooldownLiveRead = true,
            cooldownSource = "actionbar_api",
            cooldownDirectActionBarEvidence = true,
            cooldownIdentityKey = identity,
            cooldownConfirmationPending = false,
        }
    elseif state == "actionbar_duration_cooldown" then
        return {
            cooldownKnown = true,
            cooldownActive = true,
            cooldownOnGCD = false,
            charges = 1,
            maxCharges = 1,
            cooldownLiveRead = true,
            cooldownSource = "actionbar_duration",
            cooldownDirectActionBarEvidence = true,
            cooldownActionBarDurationOwnEvidence = true,
            cooldownIdentityKey = identity,
            cooldownConfirmationPending = false,
        }
    elseif state == "public_gcd" then
        return {
            cooldownKnown = false,
            cooldownPublicActiveKnown = true,
            cooldownPublicActive = true,
            cooldownPublicOnGCDKnown = true,
            cooldownPublicOnGCD = true,
            cooldownLiveRead = true,
            cooldownSource = "spell_api",
            cooldownIdentityKey = identity,
        }
    elseif state == "unknown" then
        return { cooldownKnown = false, cooldownUnknownReason = "test_unknown", cooldownLiveRead = true, cooldownSource = "spell_api", cooldownIdentityKey = identity }
    end
    error("unknown cooldown test state: " .. tostring(state))
end

inventoryCooldown = "ready"
function TE.ActionBarBindingResolver:ResolveInventorySlot(slot, expectedItemID)
    if slot ~= 13 then
        return { status = "NoBinding", reason = "test_inventory_slot", inventorySlot = slot }, "test_inventory_slot"
    end
    return {
        status = "Ready",
        inventorySlot = 13,
        itemID = 193701,
        expectedItemID = 193701,
        bindingToken = 6,
        binding = "6",
        rawBinding = "6",
        source = "item",
        directActionSlot = true,
        actionSlot = 6,
        actionBarStateTrusted = true,
    }, nil
end
function TE.IconState:CollectInventoryCooldownOnly(slot, expectedItemID, options)
    local identity = "inventory:" .. tostring(slot) .. ":item:193701"
    if inventoryCooldown == "ready" then
        return {
            cooldownKnown = true, cooldownActive = false, cooldownOnGCD = false,
            cooldownLiveRead = true, cooldownSource = "inventory_item_cooldown",
            cooldownIdentityKey = identity, cooldownConfirmationPending = false,
            inventorySlot = slot, currentItemID = 193701,
        }
    elseif inventoryCooldown == "cooldown" then
        return {
            cooldownKnown = true, cooldownActive = true, cooldownOnGCD = false,
            cooldownLiveRead = true, cooldownSource = "inventory_item_cooldown",
            cooldownIdentityKey = identity, cooldownConfirmationPending = false,
            inventorySlot = slot, currentItemID = 193701,
        }
    end
    error("unknown inventory cooldown test state: " .. tostring(inventoryCooldown))
end

function TE.GCDGate:BeginCycle(primary) return { phase = gcdPhase } end
function TE.GCDGate:Classify(cycle) return gcdPhase, "test_" .. tostring(gcdPhase) end

dofile(ROOT .. "/addon/!TacticEcho/Tactics/BurstProfiles.lua")
dofile(ROOT .. "/addon/!TacticEcho/Tactics/AutoBurst.lua")
local AutoBurst = TE.AutoBurst

local function eval(intent, transportTick)
    intent = intent or "armed"
    return AutoBurst:Evaluate({ spellID = 343527 }, {
        inCombat = true,
        intentState = intent,
        effectiveState = intent,
        -- nil models direct AutoBurst unit calls as one fresh frame; false
        -- models a state/event Refresh that paints a hold but must not consume
        -- the 50 ms transport handoff budget.
        transportHandoffTick = transportTick,
        primary = { spellID = 343527 },
        context = { class = "PALADIN", specIndex = 3 },
    })
end

-- Models the default session-policy encoded pause while the user intent remains
-- armed. P5.8 requires every out-of-combat frame to remain closed, including
-- an official front window that older builds could bridge.
local function eval_out_of_combat(transportTick, spellID)
    return AutoBurst:Evaluate({ spellID = spellID or 343527 }, {
        inCombat = false,
        intentState = "armed",
        effectiveState = "paused",
        runtimeReason = "out_of_combat_policy_pause",
        transportHandoffTick = transportTick,
        primary = { spellID = spellID or 343527 },
        context = { class = "PALADIN", specIndex = 3 },
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
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "matching injection receipt should immediately advance to window 1")
AutoBurst:RecordSpellcastSucceeded(343527)
local done = eval()
assert(done.kind == "hold", "completed plan should hold until official leaves window")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.requireWindowDeparture == true, "completed plan must keep departure lock")
""")



def test_official_window_cooldown_conflict_creates_plan_then_revalidates_before_window_dispatch() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoBurstMode = "focused"
cooldowns[343527] = "cooldown"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884, "official window cooldown conflict must still create the focused pre plan")
local created = AutoBurst:GetSnapshot()
assert(created.active == true and created.windowAvailabilityConflict == true, "plan must retain official-window cooldown conflict metadata")
AutoBurst:RecordSpellcastSucceeded(31884)
local waiting = eval()
assert(waiting.kind == "hold", "window own-cooldown conflict must revalidate without dispatching window")
cooldowns[343527] = "ready"
nowValue = 0.10
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "revalidated ready window must dispatch after injection confirmation")
""")


def test_pre_inventory_recovery_freezes_pause_clock_and_accepts_later_real_slot_cooldown() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_trinket_pre_sequence()
local first = eval()
assert(first.kind == "candidate" and first.dispatchActionKind == "inventory", "pre trinket must publish an inventory candidate")
nowValue = 1.00
local paused = eval("paused")
assert(paused.kind == "hold", "runtime pause must hold the same inventory step")
nowValue = 6.00
local resumed = eval("armed")
assert(resumed.kind == "candidate" and resumed.dispatchActionKind == "inventory", "resume must preserve the pending trinket candidate")
local snap = AutoBurst:GetSnapshot()
assert(snap.inventoryRecoveryEligible == true, "paused trinket step must expose recovery eligibility")
inventoryCooldown = "cooldown"
nowValue = 6.05
local window = eval("armed")
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "later exact trinket own-CD proof must continue to the window")
""")


def test_pre_inventory_confirmation_grace_enters_persistent_recovery_and_later_manual_cd_continues_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_trinket_pre_sequence()
local first = eval()
assert(first.kind == "candidate" and first.dispatchActionKind == "inventory", "pre trinket must dispatch")
nowValue = 2.25
local recovery = eval()
assert(recovery.kind == "candidate" and recovery.dispatchActionKind == "inventory", "unconfirmed trinket must remain a candidate during recovery")
local snap = AutoBurst:GetSnapshot()
assert(snap.inventoryRecoveryActive == true and snap.inventoryRecoveryPersistent == true, "trinket grace must enter persistent recovery")
inventoryCooldown = "cooldown"
nowValue = 2.30
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "manual or delayed exact own-CD evidence must continue to window")
""")



def test_precombat_bridge_keeps_default_session_pause_closed_for_non_window_recommendations() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local ordinary = eval_out_of_combat(true, 999001)
assert(ordinary.kind == "none", "ordinary out-of-combat recommendation must not create a bridge candidate")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.preWindowCaptureActive == false, "ordinary out-of-combat recommendation must not create a plan or capture")
""")


def test_out_of_combat_front_window_never_creates_capture_plan_hold_or_candidate() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
AutoBurst.lastIntentState = "paused"
for index = 1, 8 do
    local decision = eval_out_of_combat(index % 2 == 0)
    assert(decision.kind == "none", "out-of-combat front window must always return none")
    assert(decision.preCombatBridge ~= true, "out-of-combat result must not carry bridge authority")
end
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.preWindowCaptureActive == false,
    "out-of-combat front window must not retain plan/capture")
assert(snapshot.preCombatBridgeDepartureLock == false,
    "out-of-combat cleanup must clear any old bridge departure lock")
""")


def test_paused_to_armed_first_healthy_window_rebases_stale_same_window_generation() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
-- Reproduce the field failure: paused frames already observed the same visible
-- window, and its old generation was consumed before the next armed epoch.
AutoBurst.lastIntentState = "paused"
AutoBurst.lastOfficialSpellID = 343527
AutoBurst.currentWindowSpellID = 343527
AutoBurst.windowGeneration = 3
AutoBurst.consumedWindowGeneration = 3
AutoBurst.firstHealthyFramePending = false
-- A state/event refresh immediately after arm may happen inside a few ms. It
-- paints the Burst hold but must not consume the transport-tick barrier.
local initial = eval("armed", false)
assert(initial.kind == "hold" and initial.observationOnly == true, "re-armed state refresh must be a no-token Burst handoff hold")
local initialSnap = AutoBurst:GetSnapshot()
assert(initialSnap.handoffBarrierRequiredFrames == 4 and initialSnap.handoffBarrierRemainingFrames == 4, "event refresh must not collapse the four-tick handoff barrier")
for index = 1, 4 do
    local hold = eval("armed", true)
    assert(hold.kind == "hold" and hold.observationOnly == true, "each scheduled handoff tick must remain observation-only")
    local snap = AutoBurst:GetSnapshot()
    assert(snap.handoffBarrierPublishedFrames == index, "handoff diagnostics must count scheduled hold frames")
    assert(snap.handoffBarrierRemainingFrames == (4 - index), "handoff diagnostics must expose remaining scheduled hold frames")
end
local armed = eval("armed", true)
assert(armed.kind == "candidate" and armed.dispatchSpellID == 31884, "only after four transport holds may the injection candidate appear")
assert(armed.dispatchSpellID ~= 343527, "pre-window ownership must never leak the official window before injection")
local snap = AutoBurst:GetSnapshot()
assert(snap.armedEpoch == 1 and snap.planWindowGeneration == 4, "armed rebase must create a fresh window generation")
assert(AutoBurst:GetDiagnostics().lastArmedRebase.reason == "paused_to_armed_observation_rebase", "rebase must be auditable")
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
local away = AutoBurst:Evaluate({ spellID = 999001 }, { inCombat = true, intentState = "armed", effectiveState = "armed", primary = { spellID = 999001 }, context = { class = "PALADIN", specIndex = 3 } })
assert(away.kind == "none", "departure releases lock")
local back = eval()
assert(back.kind == "candidate" and back.dispatchSpellID == 31884, "new window generation may start after departure")
""")


def test_preflight_excludes_spell_injection_on_own_cooldown_and_does_not_create_plan() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "cooldown"
local result = eval()
assert(result.kind == "none", "own-CD injection must not claim the official window or create a Burst plan")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.preWindowCaptureActive == false, "no plan or front capture may remain after CD preflight exclusion")
local preflight = AutoBurst:GetDiagnostics().lastInjectionPreflight
assert(preflight.status == "none_ready" and preflight.firstExcludedPhase == "COOLDOWN", "own-CD exclusion must be auditable")
""")


def test_preflight_excludes_direct_actionbar_own_cooldown_without_retrying_injection() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "actionbar_cooldown"
local result = eval()
assert(result.kind == "none", "trusted action-bar own CD must exclude injection before plan creation")
assert(AutoBurst:GetSnapshot().active == false, "no candidate may be retained for action-bar CD")
""")


def test_preflight_excludes_direct_actionbar_duration_own_cooldown_without_retrying_injection() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "actionbar_duration_cooldown"
local result = eval()
assert(result.kind == "none", "duration-based own CD must exclude injection before plan creation")
assert(AutoBurst:GetSnapshot().active == false, "no plan may exist for duration-CD injection")
""")


def test_preflight_requires_positive_readiness_and_never_queues_pending_or_unknown_injection() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "cooldown_pending"
local pending = eval()
assert(pending.kind == "none" and AutoBurst:GetSnapshot().active == false, "pending own-CD state must not enter a Burst sequence")
""")
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "unknown"
gcdPhase = "GCD_LOCKED"
local unknown = eval()
assert(unknown.kind == "none" and AutoBurst:GetSnapshot().active == false, "unknown cooldown provenance must be excluded at plan construction")
local preflight = AutoBurst:GetDiagnostics().lastInjectionPreflight
assert(preflight.status == "none_ready" and preflight.firstExcludedCooldownUncertain == true, "unknown exclusion must retain an auditable reason")
""")


def test_public_gcd_is_not_own_cooldown_and_remains_preflight_eligible() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "public_gcd"
gcdPhase = "GCD_LOCKED"
local locked = eval()
assert(locked.kind == "candidate" and locked.dispatchSpellID == 31884, "shared GCD alone must not remove a ready injection")
assert(locked.cooldownUncertain ~= true, "shared GCD must remain a positive non-CD readiness result")
""")


def test_profile_preflight_uses_next_ready_injection_and_omits_all_cooldown_candidates() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 31884, 55342 },
    autoBurstSequence = {
        order = { "injection:31884", "injection:55342", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:31884"] = true, ["injection:55342"] = true },
    },
}
bindings[55342] = "ready"
cooldowns[31884] = "cooldown"
cooldowns[55342] = "ready"
local result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 55342, "profile must select the next ready injection after excluding the first CD candidate")
local preflight = AutoBurst:GetDiagnostics().lastInjectionPreflight
assert(preflight.status == "selected" and preflight.selectedOptionalCount == 1, "selected profile candidate must be auditable")
""")
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 31884, 55342 },
    autoBurstSequence = {
        order = { "injection:31884", "injection:55342", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:31884"] = true, ["injection:55342"] = true },
    },
}
bindings[55342] = "ready"
cooldowns[31884] = "cooldown"
cooldowns[55342] = "cooldown"
local result = eval()
assert(result.kind == "none" and AutoBurst:GetSnapshot().active == false, "all-CD profile candidates must leave the official window unclaimed")
""")



def test_ordered_sequence_runs_trinket_then_window_then_second_injection() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 55342, 31884 },
    autoBurstSequence = {
        order = { "trinket:13", "window", "injection:55342", "injection:31884", "trinket:14" },
        enabled = {
            ["trinket:13"] = true,
            ["injection:55342"] = true,
            ["injection:31884"] = false,
            ["trinket:14"] = false,
        },
    },
}
bindings[55342] = "ready"
cooldowns[55342] = "ready"
local trinket = eval()
assert(trinket.kind == "candidate" and trinket.dispatchActionKind == "inventory" and trinket.dispatchInventorySlot == 13,
    "configured trinket must be the first real ordered step")
inventoryCooldown = "cooldown"
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527,
    "confirmed trinket must advance to the configured middle window step")
AutoBurst:RecordSpellcastSucceeded(343527)
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 55342,
    "the ordered post-window injection must remain in the same plan")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == true and snap.currentSpellID == 55342 and snap.sequenceLength == 3,
    "plan diagnostics must retain the three resolved ordered steps")
""")


def test_simple_sequence_preflight_filters_cd_steps_but_preserves_remaining_order() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 31884, 55342 },
    autoBurstSequence = {
        order = { "trinket:13", "injection:31884", "window", "injection:55342", "trinket:14" },
        enabled = {
            ["trinket:13"] = true,
            ["injection:31884"] = true,
            ["injection:55342"] = true,
            ["trinket:14"] = false,
        },
    },
}
bindings[55342] = "ready"
cooldowns[31884] = "cooldown"
cooldowns[55342] = "ready"
local first = eval()
assert(first.kind == "candidate" and first.dispatchActionKind == "inventory",
    "simple preflight must retain the first ready trinket after excluding a CD injection")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "selected" and preflight.selectedOptionalCount == 2 and preflight.excludedCount == 1,
    "preflight must separately audit selected and excluded optional steps")
assert(preflight.selectedOrder == "trinket:13>window>injection:55342",
    "CD filtering must not reorder surviving sequence steps")
""")



def test_simple_sequence_skips_cd_trinket_but_keeps_window_then_ready_injection() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    autoBurstSequence = {
        order = { "trinket:13", "window", "injection:31884", "trinket:14" },
        enabled = { ["trinket:13"] = true, ["injection:31884"] = true },
    },
}
inventoryCooldown = "cooldown"
cooldowns[31884] = "ready"
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 343527,
    "simple mode must exclude only the CD trinket and retain window -> ready injection")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "selected" and preflight.selectedOptionalCount == 1 and preflight.excludedCount == 1,
    "the ready injection must remain eligible when the trinket alone is on CD")
assert(preflight.selectedOrder == "window>injection:31884" and preflight.excludedOrder == "trinket:13",
    "preflight must preserve the configured window -> injection order after trinket exclusion")
""")


def test_focused_sequence_refuses_build_when_any_enabled_optional_step_is_cd() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoBurstMode = "focused"
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 31884, 55342 },
    autoBurstSequence = {
        order = { "injection:31884", "window", "injection:55342", "trinket:13", "trinket:14" },
        enabled = { ["injection:31884"] = true, ["injection:55342"] = true },
    },
}
bindings[55342] = "ready"
cooldowns[31884] = "cooldown"
cooldowns[55342] = "ready"
local result = eval()
assert(result.kind == "none" and AutoBurst:GetSnapshot().active == false,
    "focused mode must refuse the entire enabled sequence before ownership is claimed")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "none_ready" and preflight.reason == "focused_optional_step_unavailable",
    "focused refusal must remain auditable as a plan-build decision")
""")


def test_focused_runtime_drift_releases_untouched_window_to_official_path() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoBurstMode = "focused"
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884,
    "focused plan must initially offer its ready front step")
cooldowns[31884] = "unknown"
local released = eval()
assert(released.kind == "none", "focused runtime drift before the window must release to official flow")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.requireWindowDeparture ~= true,
    "an untouched official window may not be departure-locked by a failed focused optional step")
""")


def test_burst_sequence_persistence_is_scoped_by_specialization_and_stable_keys() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 55342, 31884 },
    autoBurstSequence = {
        order = { "injection:55342", "window", "trinket:13", "injection:31884", "trinket:14" },
        enabled = { ["injection:55342"] = true, ["injection:31884"] = false, ["trinket:13"] = true },
    },
}
settings.burstProfiles.HUNTER_2 = {
    autoBurstSequence = {
        order = { "window", "trinket:14", "injection:288613", "trinket:13" },
        enabled = { ["trinket:14"] = true, ["injection:288613"] = true },
    },
}
local paladin = TE.BurstProfiles:GetAutoBurstSequence({ class = "PALADIN", specIndex = 3 })
local hunter = TE.BurstProfiles:GetAutoBurstSequence({ class = "HUNTER", specIndex = 2 })
assert(paladin.entries[1].key == "injection:55342" and paladin.entries[2].key == "window",
    "paladin sequence must retain its SpellID-keyed local order")
assert(hunter.entries[1].key == "window" and hunter.entries[2].key == "trinket:14",
    "hunter sequence must retain a separate specialization-local order")
local moved = TE.BurstProfiles:MoveAutoBurstStep({ class = "PALADIN", specIndex = 3 }, "trinket:13", -1)
assert(moved == true, "paladin order must remain editable by stable action key")
local hunterAfter = TE.BurstProfiles:GetAutoBurstSequence({ class = "HUNTER", specIndex = 2 })
assert(hunterAfter.entries[1].key == "window" and hunterAfter.entries[2].key == "trinket:14",
    "moving a paladin step must not mutate hunter specialization storage")
""")


def test_unknown_window_after_confirmed_injection_keeps_latched_candidate() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[343527] = "unknown"
gcdPhase = "GCD_LOCKED"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884, "official window uncertainty must not prevent the pre step")
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "unknown window cooldown must continue the latched window candidate")
assert(window.cooldownUncertain == true, "window candidate must mark uncertainty without treating it as success")
""")


def test_pre_inventory_retries_persistently_after_multiple_unconfirmed_attempts() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_trinket_pre_sequence()
local first = eval()
assert(first.kind == "candidate" and first.dispatchActionKind == "inventory", "first inventory attempt must be offered")
local firstAttempt = first.dispatchAttempt
nowValue = 2.25
local afterFirstGrace = eval()
assert(afterFirstGrace.kind == "candidate" and afterFirstGrace.dispatchActionKind == "inventory", "first interruption must keep reoffering inventory")
nowValue = 7.00
local afterSecondInterruption = eval()
assert(afterSecondInterruption.kind == "candidate" and afterSecondInterruption.dispatchActionKind == "inventory", "second interruption must not terminally cap the sequence")
nowValue = 20.00
local stillRetrying = eval()
assert(stillRetrying.kind == "candidate" and stillRetrying.dispatchActionKind == "inventory", "persistent retry continues without count or outer timeout")
assert(stillRetrying.dispatchAttempt == firstAttempt, "retries share one logical confirmation step while fresh TEAP frames provide physical attempts")
inventoryCooldown = "cooldown"
nowValue = 20.05
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "manual/delayed exact trinket CD must continue to the window after repeated interruptions")
""")


def test_created_plan_latches_window_after_official_rotation_until_rule_disposition() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_trinket_pre_sequence()
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchActionKind == "inventory")
inventoryCooldown = "cooldown"
nowValue = 0.10
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "confirmed pre step must move to window")
-- The assisted recommendation rotates during the burst. The created plan must
-- keep its immutable window step rather than releasing to ordinary 184575.
cooldowns[343527] = "ready"
local rotated = AutoBurst:Evaluate({ spellID = 184575 }, {
    inCombat = true, intentState = "armed", effectiveState = "armed",
    primary = { spellID = 184575 }, context = { class = "PALADIN", specIndex = 3 },
})
assert(rotated.kind == "candidate" and rotated.dispatchSpellID == 343527, "latched window remains the candidate after official rotation")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == true and snap.officialDepartureObserved == true, "rotation is diagnostic only, not a release")
""")


def test_plan_creation_requires_both_window_and_injection_bindings() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
bindings[343527] = "missing"
local result = eval()
assert(result.kind == "hold" and result.observationOnly == true, "missing window binding must capture the pre-window rather than leak the official window token")
assert(AutoBurst:GetSnapshot().active == false, "no plan should exist when either binding is unavailable")
bindings[343527] = "ready"
bindings[31884] = "missing"
result = AutoBurst:Evaluate({ spellID = 999001 }, { inCombat = true, intentState = "armed", effectiveState = "armed", primary = { spellID = 999001 }, context = { class = "PALADIN", specIndex = 3 } })
result = eval()
assert(result.kind == "none", "missing injection binding must not create or retain a Burst plan")
assert(AutoBurst:GetSnapshot().active == false and AutoBurst:GetSnapshot().preWindowCaptureActive == false, "missing injection binding must leave no Burst ownership")
""")


def test_spellcast_success_is_accepted_only_for_current_waiting_step() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(343527)
local stillInjection = eval()
assert(stillInjection.kind == "candidate" and stillInjection.dispatchSpellID == 31884, "wrong success event must not advance step")
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "matching event should immediately advance to window")
assert(AutoBurst:GetDiagnostics().lastConfirmationSource == "unit_spellcast_succeeded_exact", "event confirmation should be audited with its match kind")
""")


def test_post_mode_requires_eligible_injection_before_claiming_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_post_sequence()
cooldowns[31884] = "unknown"
gcdPhase = "GCD_LOCKED"
local result = eval()
assert(result.kind == "none" and AutoBurst:GetSnapshot().active == false, "post mode must not claim the window when its injection is not positively eligible")
""")


def test_post_mode_own_cooldown_omits_entire_burst_plan() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_post_sequence()
cooldowns[31884] = "cooldown"
local result = eval()
assert(result.kind == "none" and AutoBurst:GetSnapshot().active == false, "post mode must omit a CD injection at window detection rather than build and skip later")
""")


def test_cooldown_only_direct_actionbar_ready_overrides_stale_spell_api_own_cooldown() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        -- Simulate an override/talent mismatch: the declared SpellID still
        -- reports a stale 120s own cooldown although the actual bound button is
        -- already ready.
        return {
            startTime = 90,
            duration = 120,
            isEnabled = true,
            isActive = true,
            isOnGCD = false,
        }
    end,
    GetSpellCharges = function(spellID) return nil end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        return { isActive = false, isOnGCD = false }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(31884, {
    liveCooldown = true,
    actionSlot = 4,
    directActionSlot = true,
    actionBarStateTrusted = true,
    gcdSnapshot = { known = true, active = false, activeKnown = true },
})
assert(state.cooldownKnown == true and state.cooldownActive == false,
    "explicit ready state on the exact direct action button must clear stale SpellID own CD")
assert(state.cooldownSource == "actionbar_api_ready", "ready correction must retain a diagnostic source")
assert(state.cooldownDirectActionBarReadyEvidence == true,
    "ready correction must be auditable separately from own-CD evidence")
""")


def test_cooldown_only_direct_actionbar_numeric_ready_overrides_stale_spell_api_own_cooldown() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        return { startTime = 90, duration = 120, isEnabled = true, isActive = true, isOnGCD = false }
    end,
    GetSpellCharges = function(spellID) return nil end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        -- Client variant: public booleans hidden, but the exact visible button
        -- exposes an ordinary zero-duration cooldown snapshot.
        return { startTime = 0, duration = 0 }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(31884, {
    liveCooldown = true, actionSlot = 4, directActionSlot = true,
    actionBarStateTrusted = true,
    gcdSnapshot = { known = true, active = false, activeKnown = true },
})
assert(state.cooldownKnown == true and state.cooldownActive == false,
    "a zero-duration exact direct button must clear stale SpellID own CD")
assert(state.cooldownActionBarNumericReady == true and state.cooldownDirectActionBarReadyEvidence == true,
    "numeric direct-button ready evidence must remain auditable")
""")


def test_cooldown_only_promotes_trusted_direct_actionbar_non_gcd_cooldown() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        return {
            startTime = 0,
            duration = 0,
            isEnabled = true,
            isActive = false,
            isOnGCD = false,
        }
    end,
    GetSpellCharges = function(spellID) return nil end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        return { isActive = true, isOnGCD = false }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(288613, {
    liveCooldown = true,
    actionSlot = 10,
    directActionSlot = true,
    actionBarStateTrusted = true,
})
assert(state.cooldownKnown == true, "trusted direct action-bar active state must be usable as cooldown evidence")
assert(state.cooldownActive == true and state.cooldownOnGCD == false, "non-GCD action-bar cooldown must remain personal")
assert(state.cooldownSource == "actionbar_api", "direct action-bar cooldown must expose an explicit source")
assert(state.cooldownIdentityKey == "spell:288613", "direct action-bar cooldown must retain the requested spell identity")
assert(state.cooldownDirectActionBarEvidence == true, "direct action-bar certificate must be auditable")
""")


def test_cooldown_only_never_promotes_actionbar_shared_gcd_to_own_cooldown() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        return {
            startTime = 0,
            duration = 0,
            isEnabled = true,
            isActive = false,
            isOnGCD = false,
        }
    end,
    GetSpellCharges = function(spellID) return nil end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        return { isActive = true, isOnGCD = true }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(288613, {
    liveCooldown = true,
    actionSlot = 10,
    directActionSlot = true,
    actionBarStateTrusted = true,
})
assert(state.cooldownDirectActionBarEvidence ~= true, "shared GCD may never become direct own-CD evidence")
assert(state.cooldownActive ~= true or state.cooldownOnGCD == true, "shared GCD must not be promoted as a personal cooldown")
""")


def test_preflight_race_guard_releases_unconfirmed_injection_when_cooldown_becomes_unknown() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884, "ready preflight must initially construct the injection step")
cooldowns[31884] = "unknown"
local released = eval()
assert(released.kind == "hold", "simple mode must consume the unavailable optional step without reoffering it")
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "after the skip, the next ordered window step must be offered")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == true and snap.currentSpellID == 343527, "runtime drift must advance to the next ordered step without a retry loop")
local preflight = AutoBurst:GetDiagnostics().lastInjectionPreflight
assert(preflight.status == "runtime_optional_unavailable" and preflight.cooldownUncertain == true, "runtime skip must be auditable")
""")


def test_hud_collect_uses_safe_direct_actionbar_numeric_snapshot_for_custom_cd_text() -> None:
    run_lua(r"""
function GetTime() return 100 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        if spellID == 61304 then
            return { startTime = 0, duration = 0, isEnabled = true, isActive = false, isOnGCD = false }
        end
        -- Base/declared spell identity is stale at 120s; the visible direct
        -- action button below is the actual 60s variant currently in use.
        return { startTime = 90, duration = 120, isEnabled = true, isActive = true, isOnGCD = false }
    end,
    GetSpellCharges = function(spellID) return nil end,
    IsSpellUsable = function(spellID) return true, false end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        return { startTime = 70, duration = 60, isActive = true, isOnGCD = false }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:Collect(31884, {
    actionSlot = 4,
    directActionSlot = true,
    actionBarStateTrusted = true,
})
assert(state.cooldownKnown == true and state.cooldownActive == true)
assert(state.cooldownSource == "actionbar_numeric", "HUD must use the exact bound action-bar numeric source")
assert(state.cooldownDuration == 60 and state.cooldownRemaining == 30,
    "custom HUD CD label must inherit the real current 60s action-bar cooldown")
assert(state.cooldownOnGCD ~= true, "own cooldown must not be collapsed into the shared GCD")
""")


def test_world_transition_and_legacy_authorize_call_cannot_reopen_out_of_combat_burst() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
AutoBurst:ActivateWorldTransitionFence("test_zone_changed")
local fenced = AutoBurst:GetSnapshot()
assert(fenced.active == false and fenced.preWindowCaptureActive == false,
    "world transition must clear carried plan/capture")
local authorized = AutoBurst:AuthorizePreCombatBridge("legacy_manual_run")
assert(authorized == false, "legacy authorization entry must be a no-op")
for index = 1, 6 do
    local blocked = eval_out_of_combat(true)
    assert(blocked.kind == "none", "no legacy authorization may reopen out-of-combat burst")
end
""")


def test_real_combat_clears_world_transition_fence_without_replaying_old_precombat_plan() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
AutoBurst:ActivateWorldTransitionFence("test_zone_changed")
AutoBurst:BeginCombatEpoch("test_real_combat")
local snap = AutoBurst:GetSnapshot()
assert(snap.preCombatBridgeWorldFence == false,
    "PLAYER_REGEN_DISABLED path must restore normal in-combat evaluation")
assert(snap.active == false and snap.requireWindowDeparture == false,
    "combat entry must not replay any plan carried from the transition")
""")
