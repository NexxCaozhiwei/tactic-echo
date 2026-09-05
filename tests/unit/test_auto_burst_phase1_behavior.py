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
playerSpeed = 0
function GetUnitSpeed(unit) assert(unit == "player"); return playerSpeed end
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
    RuntimeSnapshot = {},
}
local TE = _G.TacticEcho
function TE:RegisterEventsSafe(frame, events) frame.events = events end
settings = {
    autoBurstEnabled = true,
    autoInjectionEnabled = true,
    autoBurstMode = "simple",
    autoBurstDebug = false,
    burstProfiles = {},
}
TacticEchoDB = { tactics = settings }
normalizeCalls = 0
function TE.Config.Normalize:All() normalizeCalls = normalizeCalls + 1; return {}, settings end
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
bindingTokens = { [343527] = 1, [31884] = 4 }
actionUsability = {}
spellUsability = {}
gcdPhase = "READY_NOW"

function TE.ActionBarBindingResolver:ResolveSpell(spellID)
    if bindings[spellID] ~= "ready" then
        return { status = "NoBinding", reason = "test_no_binding", spellID = spellID }, "test_no_binding"
    end
    local token = bindingTokens[spellID] or 1
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

function TE.RuntimeSnapshot:GetActionUsability(snapshot, actionSlot)
    local state = actionUsability[actionSlot]
    if state == "resource" then return false, true, nil end
    if state == "unusable" then return false, false, nil end
    if state == "ready" then return true, false, nil end
    return nil, nil, "test_action_usability_unknown"
end

function TE.RuntimeSnapshot:GetSpellUsability(snapshot, spellID)
    local state = spellUsability[spellID]
    if state == "resource" then return false, true, nil end
    if state == "unusable" then return false, false, nil end
    if state == "ready" then return true, false, nil end
    return nil, nil, "test_spell_usability_unknown"
end

function TE.IconState:CollectCooldownOnly(spellID, options)
    local state = cooldowns[spellID] or "ready"
    local identity = "spell:" .. tostring(spellID)
    if type(state) == "table" then
        return {
            cooldownKnown = true,
            cooldownActive = state.cooldownActive == true,
            cooldownOnGCD = false,
            charges = state.charges,
            maxCharges = state.maxCharges,
            cooldownLiveRead = true,
            cooldownSource = "spell_api",
            cooldownIdentityKey = identity,
            cooldownConfirmationPending = false,
        }
    end
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
dofile(ROOT .. "/addon/!TacticEcho/Tactics/AutoInjectionGroups.lua")
dofile(ROOT .. "/addon/!TacticEcho/Tactics/AutoInjectionCoordinator.lua")
dofile(ROOT .. "/addon/!TacticEcho/Tactics/AutoBurst.lua")
local AutoBurst = TE.AutoBurst
testContext = { class = "PALADIN", specIndex = 3 }
officialSpellID = 343527
local runtimeCycleId = 0

local function eval(intent, transportTick, forcedCycleId)
    intent = intent or "armed"
    runtimeCycleId = runtimeCycleId + 1
    return AutoBurst:Evaluate({ spellID = officialSpellID }, {
        inCombat = true,
        intentState = intent,
        effectiveState = intent,
        -- nil models direct AutoBurst unit calls as one fresh frame; false
        -- models a state/event Refresh that paints a hold but must not consume
        -- the 50 ms transport handoff budget.
        transportHandoffTick = transportTick,
        primary = { spellID = officialSpellID },
        context = testContext,
        runtimeSnapshot = { cycleId = forcedCycleId or runtimeCycleId },
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
        runtimeReason = "out_of_combat_auto_standby",
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


def test_multi_group_coordinator_keeps_one_plan_and_requires_a_new_missed_window_edge() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884)
local Groups = TE.AutoInjectionGroups
local ok, second = Groups:AddGroup(testContext)
assert(ok)
assert(Groups:SetGroupWindow(testContext, second, 400))
assert(Groups:AddInjection(testContext, second, 401))
assert(Groups:MoveStep(testContext, second, "injection:401", -1))
assert(Groups:SetGroupEnabled(testContext, second, true))
bindings[400], bindings[401] = "ready", "ready"
bindingTokens[400], bindingTokens[401] = 7, 8
cooldowns[400], cooldowns[401] = "ready", "ready"

officialSpellID = 400
local stillFirst = eval()
assert(stillFirst.kind == "candidate" and stillFirst.dispatchSpellID == 31884,
    "another group window must not preempt the current group")
AutoBurst:RecordSpellcastSucceeded(31884)
local firstWindow = eval()
assert(firstWindow.kind == "candidate" and firstWindow.dispatchSpellID == 343527,
    "the active group must retain its ordered window step")
AutoBurst:RecordSpellcastSucceeded(343527)
local completed = eval()
assert(completed.dispatchSpellID ~= 401, "a window observed while busy must not chain immediately")
assert(eval().kind == "none", "the missed group window must not replay while still visible")
officialSpellID = 999
assert(eval().kind == "none")
officialSpellID = 400
local secondStart = eval()
assert(secondStart.kind == "candidate" and secondStart.dispatchSpellID == 401,
    "a real leave/enter edge may start the second group")
local firstRuntime = AutoBurst.groupRuntime["PALADIN_3:group-1"]
assert(firstRuntime and firstRuntime.lastConfirmedWindowReceipt
    and firstRuntime.lastConfirmedWindowReceipt.groupId == "group-1",
    "the first group receipt must remain in its specialization-scoped runtime")
assert(AutoBurst.runtimeGroupKey == "PALADIN_3:" .. second,
    "the active scalar executor state must be namespaced by profile and group")
assert(AutoBurst.lastConfirmedWindowReceipt == nil,
    "the second group must not inherit the first group's window receipt")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.activeGroupId == second and snapshot.groupWindowSpellID == 400)
""")


def test_auto_injection_disabled_and_unmatched_windows_leave_official_path_unowned() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoInjectionEnabled = false
local disabled = eval()
assert(disabled.kind == "none" and AutoBurst.plan == nil,
    "the total switch must leave the official path unowned")
settings.autoInjectionEnabled = true
officialSpellID = 999001
local unmatched = eval()
assert(unmatched.kind == "none" and AutoBurst.plan == nil,
    "an unmatched official recommendation must stay on the official path")
""")


def test_active_group_configuration_change_aborts_without_old_candidate_leakage() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local candidate = eval()
assert(candidate.kind == "candidate" and candidate.dispatchSpellID == 31884)
local Groups = TE.AutoInjectionGroups
assert(Groups:SetGroupMode(testContext, "group-1", "focused"))
local changed = eval()
assert(changed.kind == "none" and changed.bindingToken == nil,
    "a changed active group must not leak its old candidate token")
assert(AutoBurst.plan == nil and AutoBurst.requireWindowDeparture == true,
    "a changed active group must terminate behind the existing departure lock")
""")


def test_autoburst_evaluate_stays_within_retail_upvalue_limit() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local info = debug.getinfo(AutoBurst.Evaluate, "u")
assert(type(info) == "table" and tonumber(info.nups) ~= nil)
assert(info.nups <= 60,
    "Retail rejects AutoBurst.Evaluate when captured upvalues exceed 60; observed " .. tostring(info.nups))
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


def test_confirmed_window_cooldown_reentry_does_not_create_a_second_plan() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527)
AutoBurst:RecordSpellcastSucceeded(343527)
local completed = eval()
assert(completed.kind == "hold", "confirmed window should enter the ordinary departure lock")

officialSpellID = 999001
assert(eval().kind == "none", "official departure should clear the ordinary visibility lock")

cooldowns[343527] = "cooldown"
officialSpellID = 343527
local duplicate = eval()
assert(duplicate.kind == "hold", "same confirmed window on own cooldown must be suppressed")
local suppressed = AutoBurst:GetSnapshot()
assert(suppressed.active == false, "cooldown reentry must not create a second plan")
assert(suppressed.requireWindowDeparture == false and suppressed.preWindowCaptureActive == true,
    "an unexecuted generation must retain revalidation ownership, not a consumed departure lock")
assert(suppressed.consumedWindowGeneration ~= suppressed.windowGeneration,
    "an own-CD observation must not consume the new window generation")
assert(suppressed.lastConfirmedWindowSpellID == 343527,
    "snapshot must retain the exact confirmed window receipt")
assert(suppressed.lastWindowRejectReason == "window_reentry_wait_ready",
    "diagnostics must identify the recoverable window readiness wait")

officialSpellID = 999001
assert(eval().kind == "none", "second departure should clear the suppressed generation")
cooldowns[343527] = "ready"
officialSpellID = 343527
local nextWindow = eval()
assert(nextWindow.kind == "candidate" and nextWindow.dispatchSpellID == 31884,
    "a later ready window must start the next normal sequence")
""")


WINDOW_REENTRY_HARNESS = AUTO_BURST_HARNESS + r"""
local function finish_test_sequence(order)
    for _, spellID in ipairs(order) do
        local result = eval()
        assert(result.kind == "candidate" and result.dispatchSpellID == spellID)
        assert(AutoBurst:RecordSpellcastSucceeded(spellID))
    end
    assert(eval().kind == "hold")
    officialSpellID = 999001
    assert(eval().kind == "none")
end
local function enter_cooldown_reentry()
    nowValue = 59.915
    cooldowns[343527] = "cooldown"
    officialSpellID = 343527
    assert(eval("armed", true, 100).kind == "hold")
end
"""


@pytest.mark.parametrize("window_first", [False, True])
@pytest.mark.parametrize("mode", ["simple", "focused"])
@pytest.mark.parametrize("charged", [False, True])
def test_window_reentry_recovers_without_another_official_departure(window_first, mode, charged) -> None:
    setup = "use_post_sequence()\n" if window_first else ""
    order = "{343527, 31884}" if window_first else "{31884, 343527}"
    ready = '{ charges = 1, maxCharges = 2, cooldownActive = true }' if charged else '"ready"'
    run_lua(WINDOW_REENTRY_HARNESS + setup + f'''
settings.autoBurstMode = "{mode}"
finish_test_sequence({order})
enter_cooldown_reentry()
local capture = AutoBurst.preWindowCapture
assert(capture and not AutoBurst.requireWindowDeparture)
local generation = capture.windowGeneration
local reads = 0
local collect = TE.IconState.CollectCooldownOnly
function TE.IconState:CollectCooldownOnly(spellID, options)
    assert(spellID == 343527, "pending reentry must not repeatedly scan optional steps")
    reads = reads + 1
    return collect(self, spellID, options)
end
nowValue = 60
cooldowns[343527] = "unknown"
assert(eval("armed", true, 101).kind == "hold")
assert(reads == 1)
cooldowns[343527] = {ready}
assert(eval("armed", false, 101).kind == "hold", "same business snapshot cannot resolve readiness")
assert(reads == 1)
TE.IconState.CollectCooldownOnly = collect
local recovered = eval("armed", true, 102)
assert(recovered.kind == "candidate" and recovered.dispatchSpellID == {343527 if window_first else 31884})
assert(AutoBurst.plan.windowGeneration == generation, "recovery must retain the original new generation")
assert(AutoBurst.preWindowCapture == nil and AutoBurst.requireWindowDeparture == false)
''')


@pytest.mark.parametrize("kind", ["cast", "channel", "empower"])
def test_window_reentry_does_not_probe_or_rebuild_during_cast(kind) -> None:
    run_lua(WINDOW_REENTRY_HARNESS + f'''
finish_test_sequence({{31884, 343527}})
enter_cooldown_reentry()
local capture = AutoBurst.preWindowCapture
assert(capture)
local collect = TE.IconState.CollectCooldownOnly
TE.IconState.CollectCooldownOnly = function() error("must not sample during cast protection") end
cooldowns[343527] = "ready"
local paused = AutoBurst:Evaluate({{ spellID = officialSpellID }}, {{
    inCombat = true, intentState = "armed", effectiveState = "{kind}", context = testContext,
    runtimeSnapshot = {{ cycleId = 101, castDisplay = {{ active = true, kind = "{kind}" }} }},
}})
assert(paused.kind == "hold" and paused.observationOnly == true)
assert(AutoBurst.preWindowCapture == capture and AutoBurst.plan == nil)
TE.IconState.CollectCooldownOnly = collect
assert(eval("armed", true, 102).dispatchSpellID == 31884)
''')


def test_window_reentry_recovery_preserves_full_order_and_existing_success_lock() -> None:
    run_lua(WINDOW_REENTRY_HARNESS + r"""
assert(TE.AutoInjectionGroups:AddInjection(testContext, "group-1", 375576))
assert(TE.AutoInjectionGroups:AddInjection(testContext, "group-1", 255937))
bindings[375576], bindings[255937] = "ready", "ready"
bindingTokens[375576], bindingTokens[255937] = 7, 8
finish_test_sequence({31884, 343527, 375576, 255937})
enter_cooldown_reentry()
assert(AutoBurst.preWindowCapture and not AutoBurst.requireWindowDeparture)
-- Actual cooldown can persist arbitrarily long without consuming this generation.
for i = 101, 105 do
    nowValue = i
    assert(eval("armed", true, i).kind == "hold")
    assert(AutoBurst.plan == nil and not AutoBurst.requireWindowDeparture)
end
cooldowns[343527] = "ready"
for _, spellID in ipairs({31884, 343527, 375576, 255937}) do
    local result = eval()
    assert(result.kind == "candidate" and result.dispatchSpellID == spellID)
    assert(eval().dispatchSpellID == spellID, "a candidate offer alone cannot advance the step")
    assert(AutoBurst:RecordSpellcastSucceeded(spellID))
end
assert(eval().kind == "hold")
assert(AutoBurst.requireWindowDeparture and not AutoBurst.preWindowCapture)
assert(eval().kind == "hold", "even ready samples must not replay a successfully consumed window")
""")


@pytest.mark.parametrize("boundary", ["departure", "disabled", "combat", "world", "configuration"])
def test_window_reentry_pending_respects_lifecycle_boundaries(boundary) -> None:
    actions = {
        "departure": 'officialSpellID = 999001; assert(eval().kind == "none")',
        "disabled": 'settings.autoInjectionEnabled = false; settings.autoBurstEnabled = false; assert(eval().kind == "none")',
        "combat": 'assert(eval_out_of_combat(true).kind == "none")',
        "world": 'AutoBurst:ActivateWorldTransitionFence("test")',
        "configuration": 'assert(TE.AutoInjectionGroups:SetGroupWindow(testContext, "group-1", 400)); eval()',
    }
    run_lua(WINDOW_REENTRY_HARNESS + r"""
finish_test_sequence({31884, 343527})
enter_cooldown_reentry()
assert(AutoBurst.preWindowCapture and not AutoBurst.requireWindowDeparture)
""" + actions[boundary] + r"""
assert(AutoBurst.preWindowCapture == nil and AutoBurst.plan == nil,
    "a stale pending generation must not survive a lifecycle or configuration boundary")
""")


def test_window_reentry_owner_does_not_replay_a_missed_other_group() -> None:
    run_lua(WINDOW_REENTRY_HARNESS + r"""
local Groups, Coordinator = TE.AutoInjectionGroups, TE.AutoInjectionCoordinator
local ok, second = Groups:AddGroup(testContext)
assert(ok and Groups:SetGroupWindow(testContext, second, 400))
assert(Groups:AddInjection(testContext, second, 31884))
assert(Groups:SetGroupEnabled(testContext, second, true))
bindings[400], bindingTokens[400] = "ready", 8
finish_test_sequence({31884, 343527})
enter_cooldown_reentry()
assert(Coordinator.activeGroupId == "group-1" and AutoBurst.preWindowCapture)
officialSpellID = 400
assert(eval().kind == "none")
assert(Coordinator.lastIgnoredGroupId == second)
assert(Coordinator.lastIgnoredEvent == "group_window_ignored_while_owner_active")
assert(AutoBurst.preWindowCapture == nil and AutoBurst.plan == nil)
assert(eval().kind == "none", "a missed group must not take over without a new edge")
""")


@pytest.mark.parametrize("window_first", [False, True])
def test_window_reentry_resume_keeps_the_existing_four_frame_handoff(window_first) -> None:
    setup = "use_post_sequence()\n" if window_first else ""
    order = "{343527, 31884}" if window_first else "{31884, 343527}"
    run_lua(WINDOW_REENTRY_HARNESS + setup + f'''
finish_test_sequence({order})
enter_cooldown_reentry()
local capture = AutoBurst.preWindowCapture
assert(capture)
eval("paused")
cooldowns[343527] = "ready"
for i = 1, 4 do
    local barrier = eval("armed", true)
    assert(barrier.kind == "hold", "resume must retain the authenticated handoff barrier")
end
assert(eval("armed", true).dispatchSpellID == {343527 if window_first else 31884})
''')


def test_window_reentry_binding_loss_cannot_authorize_a_new_plan() -> None:
    run_lua(WINDOW_REENTRY_HARNESS + r"""
finish_test_sequence({31884, 343527})
enter_cooldown_reentry()
assert(AutoBurst.preWindowCapture)
bindings[343527] = "missing"
cooldowns[343527] = "ready"
assert(eval().kind ~= "candidate")
assert(AutoBurst.preWindowCapture == nil and AutoBurst.plan == nil)
assert(AutoBurst.requireWindowDeparture, "hard-invalid owned capture still uses the existing abort lock")
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
local provisional = eval("armed")
assert(not (provisional.kind == "candidate" and provisional.dispatchSpellID == 343527),
    "first trinket own-CD sample must remain provisional")
nowValue = 6.21
local window = eval("armed")
assert(window.kind == "candidate" and window.dispatchSpellID == 343527, "later exact trinket own-CD proof must continue to the window")
""")


def test_inventory_fallback_requires_a_distinct_runtime_sample() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_trinket_pre_sequence()
local first = eval()
assert(first.kind == "candidate" and first.dispatchActionKind == "inventory")
inventoryCooldown = "cooldown"
nowValue = 0.05
local provisional = eval("armed", nil, 77)
assert(not (provisional.kind == "candidate" and provisional.dispatchSpellID == 343527))
nowValue = 0.30
local repeated = eval("armed", nil, 77)
assert(not (repeated.kind == "candidate" and repeated.dispatchSpellID == 343527),
    "elapsed time plus a repeated runtime snapshot must not confirm the trinket")
nowValue = 0.31
local distinct = eval("armed", nil, 78)
assert(distinct.kind == "candidate" and distinct.dispatchSpellID == 343527,
    "a second distinct runtime sample may complete the stable confirmation")
""")


def test_departure_lock_observes_direct_second_group_window_before_release() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local Groups = TE.AutoInjectionGroups
local Coordinator = TE.AutoInjectionCoordinator
local ok, second = Groups:AddGroup(testContext)
assert(ok and Groups:SetGroupWindow(testContext, second, 400))
assert(Groups:AddInjection(testContext, second, 31884))
assert(Groups:SetGroupEnabled(testContext, second, true))
cooldowns[400] = "ready"
bindings[400] = "ready"
bindingTokens[400] = 8

local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527)
AutoBurst:RecordSpellcastSucceeded(343527)
local locked = eval()
assert(locked.kind == "hold" and AutoBurst:GetSnapshot().requireWindowDeparture == true)

officialSpellID = 400
local transition = eval()
assert(transition.kind == "none", "departure transition remains observation-only")
assert(Coordinator.lastIgnoredGroupId == second)
assert(Coordinator.lastIgnoredEvent == "group_window_ignored_while_owner_active")
assert(AutoBurst:GetSnapshot().requireWindowDeparture == false)
local stillVisible = eval()
assert(stillVisible.kind == "none" and AutoBurst:GetSnapshot().active == false,
    "the directly observed second group window must not be supplemented")
""")


def test_active_capture_configuration_failure_establishes_departure_lock() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local Groups = TE.AutoInjectionGroups
local Coordinator = TE.AutoInjectionCoordinator
local rule = assert(Groups:BuildRule(testContext, "group-1"))
AutoBurst.runtimeGroupId = "group-1"
AutoBurst.runtimeGroupKey = "PALADIN_3:group-1"
AutoBurst.windowGeneration = 1
AutoBurst.currentWindowSpellID = rule.windowSpellID
AutoBurst.preWindowCapture = {
    id = 99, active = true, rule = rule, officialSpellID = rule.windowSpellID,
    windowGeneration = 1, armedEpoch = AutoBurst.armedEpoch,
}
Coordinator:Claim("group-1")
assert(Groups:SetGroupEnabled(testContext, "group-1", false))
local result = eval()
assert(result.kind == "none")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.preWindowCaptureActive == false)
assert(snapshot.requireWindowDeparture == true,
    "invalidating an owned capture must fail closed behind a departure lock")
assert(Coordinator.activeGroupId == "group-1")
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
local provisional = eval()
assert(not (provisional.kind == "candidate" and provisional.dispatchSpellID == 343527),
    "persistent recovery must not advance on one predicted cooldown sample")
nowValue = 2.46
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
AutoBurst.runtimeGroupId = "group-1"
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
spellUsability[31884] = "unusable"
actionUsability[4] = "unusable"
local result = eval()
assert(result.kind == "none", "own-CD injection must not claim the official window or create a Burst plan")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == false and snap.preWindowCaptureActive == false, "no plan or front capture may remain after CD preflight exclusion")
local preflight = AutoBurst:GetDiagnostics().lastInjectionPreflight
assert(preflight.status == "none_ready" and preflight.firstExcludedPhase == "COOLDOWN", "own-CD exclusion must be auditable")
""")


def test_preflight_holds_direct_actionbar_cooldown_edge_until_explicit_ready() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
nowValue = 100
cooldowns[31884] = "actionbar_cooldown"
local result = eval()
assert(result.kind == "hold" and result.observationOnly == true,
    "trusted direct action-bar own CD at the window edge must retain only an observation capture")
local pending = AutoBurst:GetSnapshot()
assert(pending.active == false and pending.preWindowCaptureActive == true,
    "cooldown-edge settling must not create a plan or candidate")
assert(pending.preWindowCaptureCooldownEdgePending == true
    and pending.preWindowCaptureCooldownEdgeSpellID == 31884,
    "the bounded direct-action edge must be auditable without raw cooldown values")
cooldowns[31884] = "ready"
nowValue = 100.90
local ready = eval()
assert(ready.kind == "candidate" and ready.dispatchSpellID == 31884,
    "the original ordered injection must survive the observed late-ready jitter and dispatch only once explicitly ready")
""")


def test_preflight_direct_actionbar_cooldown_edge_expires_to_original_simple_behavior() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
nowValue = 200
cooldowns[31884] = "actionbar_duration_cooldown"
local result = eval()
assert(result.kind == "hold" and result.observationOnly == true,
    "trusted duration evidence may only open the bounded no-token edge capture")
nowValue = 201.30
local expired = eval()
assert(expired.kind == "none", "a still-cooling action must return to the original simple exclusion after the edge budget")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.preWindowCaptureActive == false,
    "an expired edge must not retain a plan, capture, or dispatch authority")
""")


def test_preflight_excludes_pending_and_unknown_cooldown_until_positive_ready_evidence() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "cooldown_pending"
local pending = eval()
assert(pending.kind == "none" and AutoBurst:GetSnapshot().active == false, "pending own-CD state must not enter a Burst sequence")
""")
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "unknown"
gcdPhase = "GCD_LOCKED"
local unknown = eval()
assert(unknown.kind == "none",
    "unknown cooldown provenance must not create or dispatch a plan")
assert(AutoBurst:GetSnapshot().active == false)
local preflight = AutoBurst:GetDiagnostics().lastInjectionPreflight
assert(preflight.status == "none_ready" and preflight.excludedOrder:find("injection:31884", 1, true),
    "uncertain admission must remain auditable without a BindingToken")
cooldowns[31884] = "ready"
gcdPhase = "READY_NOW"
assert(eval().kind == "none",
    "a newly ready step behind the already observed window must not be inserted ahead of it")
officialSpellID = 184575
assert(eval().kind == "none")
officialSpellID = 343527
local nextWindow = eval()
assert(nextWindow.kind == "candidate" and nextWindow.dispatchSpellID == 31884,
    "the step may enter on a new window generation after a fresh positive own-ready sample")
""")


def test_public_gcd_is_not_own_cooldown_and_remains_preflight_eligible() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "public_gcd"
gcdPhase = "GCD_LOCKED"
local locked = eval()
assert(locked.kind == "hold" and locked.reason == "burst_step_wait_ready_now",
    "shared GCD alone must not remove a ready injection or authorize its first dispatch")
assert(AutoBurst:GetSnapshot().active == true and AutoBurst:GetSnapshot().dispatchAttempt == 0)
gcdPhase = "QUEUE_WINDOW"
local queued = eval()
assert(queued.kind == "hold" and queued.reason == "burst_step_wait_ready_now",
    "the first physical action in a plan must wait beyond the queue window")
gcdPhase = "READY_NOW"
local ready = eval()
assert(ready.kind == "candidate" and ready.dispatchSpellID == 31884)
assert(ready.cooldownUncertain ~= true, "shared GCD must remain a positive non-CD readiness result")
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
local confirming = eval()
assert(confirming.kind == "hold" and confirming.reason == "burst_step_revalidate",
    "a newly observed item cooldown must stop re-dispatch while confirmation stabilizes")
nowValue = 0.20
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


def test_cooling_tail_step_is_admitted_in_original_order_without_rebuilding_prefix() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 642 },
    injectionOrder = { 31884, 55342, 642 },
    autoBurstSequence = {
        order = { "injection:31884", "window", "injection:55342", "injection:642", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:31884"] = true,
            ["injection:55342"] = true,
            ["injection:642"] = true,
        },
    },
}
bindings[55342] = "ready"
bindings[642] = "ready"
bindingTokens[55342] = 5
bindingTokens[642] = 6
cooldowns[55342] = "ready"
cooldowns[642] = "cooldown"

local a = eval()
assert(a.kind == "candidate" and a.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
local w = eval()
assert(w.kind == "candidate" and w.dispatchSpellID == 343527)
AutoBurst:RecordSpellcastSucceeded(343527)
local b = eval()
assert(b.kind == "candidate" and b.dispatchSpellID == 55342)

cooldowns[642] = "ready"
local stillB = eval()
assert(stillB.kind == "candidate" and stillB.dispatchSpellID == 55342,
    "tail admission must not replace or replay the current locked step")
local admitted = AutoBurst:GetSnapshot()
assert(admitted.sequenceKeys == "injection:31884>window>injection:55342>injection:642")
assert(admitted.deferredTailAdmittedCount == 1 and admitted.deferredTailCount == 0)

AutoBurst:RecordSpellcastSucceeded(55342)
local c = eval()
assert(c.kind == "candidate" and c.dispatchSpellID == 642,
    "the newly ready tail step must dispatch after B in the original configured order")
""")


def test_deferred_step_behind_one_way_frontier_never_replays_but_future_tail_can_join() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 642 },
    injectionOrder = { 31884, 55342, 642 },
    autoBurstSequence = {
        order = { "injection:31884", "window", "injection:55342", "injection:642", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:31884"] = true,
            ["injection:55342"] = true,
            ["injection:642"] = true,
        },
    },
}
bindings[55342] = "ready"
bindings[642] = "ready"
bindingTokens[55342] = 5
bindingTokens[642] = 6
cooldowns[31884] = "cooldown"
cooldowns[55342] = "ready"
cooldowns[642] = "cooldown"

local w = eval()
assert(w.kind == "candidate" and w.dispatchSpellID == 343527,
    "initial plan must lock only W -> B while A and C cool")
local initial = AutoBurst:GetSnapshot()
assert(initial.sequenceKeys == "window>injection:55342" and initial.deferredTailCount == 1,
    "A is already behind the first active frontier; only future C remains eligible")

cooldowns[31884] = "ready"
cooldowns[642] = "ready"
local stillW = eval()
assert(stillW.kind == "candidate" and stillW.dispatchSpellID == 343527)
local appended = AutoBurst:GetSnapshot()
assert(appended.sequenceKeys == "window>injection:55342>injection:642")
assert(appended.deferredTailAdmittedCount == 1 and appended.deferredTailExpiredCount == 1,
    "the one-way frontier must reject late A and append only future C")

AutoBurst:RecordSpellcastSucceeded(343527)
assert(eval().dispatchSpellID == 55342)
AutoBurst:RecordSpellcastSucceeded(55342)
assert(eval().dispatchSpellID == 642, "the plan must continue directly to C without rebuilding A-W-B-C")
""")


def test_deferred_gap_uses_fresh_snapshot_and_rejoins_at_exact_configured_position() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 642 },
    injectionOrder = { 31884, 55342, 642 },
    autoBurstSequence = {
        order = { "injection:31884", "window", "injection:55342", "injection:642", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:31884"] = true,
            ["injection:55342"] = true,
            ["injection:642"] = true,
        },
    },
}
bindings[55342] = "ready"; bindingTokens[55342] = 5; cooldowns[55342] = "cooldown"
bindings[642] = "ready"; bindingTokens[642] = 6; cooldowns[642] = "ready"

assert(eval().dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
assert(eval().dispatchSpellID == 343527)
AutoBurst:RecordSpellcastSucceeded(343527)

local sameSnapshot = eval(nil, nil, 7001)
assert(sameSnapshot.kind == "hold" and sameSnapshot.reason == "deferred_tail_fresh_snapshot_pending",
    "window confirmation must not cross the B gap on the same business snapshot")
cooldowns[55342] = "ready"
local b = eval(nil, nil, 7002)
assert(b.kind == "candidate" and b.dispatchSpellID == 55342,
    "newly ready B must be inserted before the already-ready C")
local ordered = AutoBurst:GetSnapshot()
assert(ordered.sequenceKeys == "injection:31884>window>injection:55342>injection:642")
AutoBurst:RecordSpellcastSucceeded(55342)
assert(eval().dispatchSpellID == 642, "C may dispatch only after B is confirmed")
""")


def test_deferred_gap_expired_at_its_turn_never_replays_in_front_of_locked_successor() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 642 },
    injectionOrder = { 31884, 55342, 642 },
    autoBurstSequence = {
        order = { "injection:31884", "window", "injection:55342", "injection:642", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:31884"] = true,
            ["injection:55342"] = true,
            ["injection:642"] = true,
        },
    },
}
bindings[55342] = "ready"; bindingTokens[55342] = 5; cooldowns[55342] = "cooldown"
bindings[642] = "ready"; bindingTokens[642] = 6; cooldowns[642] = "ready"

assert(eval().dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
assert(eval().dispatchSpellID == 343527)
AutoBurst:RecordSpellcastSucceeded(343527)
assert(eval(nil, nil, 7101).reason == "deferred_tail_fresh_snapshot_pending")
local c = eval(nil, nil, 7102)
assert(c.kind == "candidate" and c.dispatchSpellID == 642,
    "B still on CD at its configured turn must be passed without blocking C")

cooldowns[55342] = "ready"
local stillC = eval(nil, nil, 7103)
assert(stillC.kind == "candidate" and stillC.dispatchSpellID == 642,
    "a passed B must never be inserted ahead of the already-dispatched C")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.deferredTailCount == 0 and snapshot.currentSpellID == 642)
""")


def test_admitting_one_deferred_gap_does_not_expire_later_gap_before_its_turn() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 642, 100001 },
    injectionOrder = { 31884, 55342, 642, 100001 },
    autoBurstSequence = {
        order = { "injection:31884", "window", "injection:55342", "injection:642", "injection:100001", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:31884"] = true,
            ["injection:55342"] = true,
            ["injection:642"] = true,
            ["injection:100001"] = true,
        },
    },
}
bindings[55342] = "ready"; bindingTokens[55342] = 5; cooldowns[55342] = "cooldown"
bindings[642] = "ready"; bindingTokens[642] = 6; cooldowns[642] = "cooldown"
bindings[100001] = "ready"; bindingTokens[100001] = 7; cooldowns[100001] = "ready"

assert(eval().dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
assert(eval().dispatchSpellID == 343527)
AutoBurst:RecordSpellcastSucceeded(343527)
assert(eval(nil, nil, 7201).reason == "deferred_tail_fresh_snapshot_pending")

cooldowns[55342] = "ready"
local b = eval(nil, nil, 7202)
assert(b.kind == "candidate" and b.dispatchSpellID == 55342)
local afterBAdmission = AutoBurst:GetSnapshot()
assert(afterBAdmission.deferredTailCount == 1,
    "admitting B must leave still-cooling C eligible until B is confirmed")

AutoBurst:RecordSpellcastSucceeded(55342)
assert(eval(nil, nil, 7203).reason == "deferred_tail_fresh_snapshot_pending")
cooldowns[642] = "ready"
local c = eval(nil, nil, 7204)
assert(c.kind == "candidate" and c.dispatchSpellID == 642,
    "C must rejoin at its own turn before the already-ready D")
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


def test_focused_runtime_cooldown_uncertainty_keeps_reoffering_same_step() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoBurstMode = "focused"
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884,
    "focused plan must initially offer its ready front step")
cooldowns[31884] = "unknown"
gcdPhase = "GCD_LOCKED"
local retry = eval()
assert(retry.kind == "hold" and retry.reason == "burst_wait_confirm_gcd_locked",
    "focused runtime uncertainty must retain ownership without publishing a GCD-locked token")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == true and snap.waitingForConfirmation == true,
    "the exact waiting step must retain ownership until success or matching failures")
""")


def test_profile_sequence_accepts_six_injections_and_two_trinket_slots() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 100001, 100002, 100003, 100004 },
    injectionOrder = { 31884, 55342, 100001, 100002, 100003, 100004 },
}
local sequence = TE.BurstProfiles:GetAutoBurstSequence(testContext)
local injectionCount = 0
for _, entry in ipairs(sequence.entries or {}) do
    if entry.category == "injection" then injectionCount = injectionCount + 1 end
end
assert(injectionCount == 6, "all six enabled injection identities must enter the sequence")
assert(#sequence.entries == 9, "window + six injections + two trinket slots must be retained")
assert(sequence.entries[1].key == "injection:31884" and sequence.entries[2].key == "window")
assert(sequence.entries[7].key == "injection:100004")
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


def test_sparse_registered_specs_accept_custom_trigger_and_injection_sequences() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
C_Spell = {
    IsSpellKnown = function(spellID)
        return spellID == 257001 or spellID == 257002
    end,
}
local cases = {
    {
        -- Holy Priest represents the existing registered specializations that
        -- intentionally ship without guessed built-in burst seeds.
        context = { class = "PRIEST", specIndex = 2, specID = 257 },
        key = "PRIEST_2",
        trigger = 257001,
        injection = 257002,
    },
}
for _, case in ipairs(cases) do
    local emptyProfile, emptyKey, emptyReason = TE.BurstProfiles:Get(case.context)
    assert(emptyProfile ~= nil and emptyKey == case.key and emptyProfile.noSeedNotice ~= nil,
        case.key .. " must begin as an explicitly registered sparse profile")
    local triggerAdded, triggerReason = TE.BurstProfiles:AddCustom(case.context, "trigger", case.trigger)
    assert(triggerAdded == true, case.key .. " custom trigger rejected: " .. tostring(triggerReason))
    local injectionAdded, injectionReason = TE.BurstProfiles:AddCustom(case.context, "injection", case.injection)
    assert(injectionAdded == true, case.key .. " custom injection rejected: " .. tostring(injectionReason))

    local profile, profileKey, profileReason = TE.BurstProfiles:Get(case.context)
    assert(profile ~= nil and profileKey == case.key and profileReason == nil and profile.noSeedNotice == nil,
        case.key .. " custom entries must clear the sparse-profile guard")
    assert(profile.triggerEntries[1].custom == true and profile.injectionEntries[1].custom == true,
        case.key .. " must preserve user-current-spec custom identity")
    local sequence, sequenceKey, sequenceReason = TE.BurstProfiles:GetAutoBurstSequence(case.context)
    assert(sequence ~= nil and sequenceKey == case.key and sequenceReason == nil,
        case.key .. " custom sequence rejected: " .. tostring(sequenceReason))
    assert(sequence.windowSpellID == case.trigger and sequence.injectionCount == 1,
        case.key .. " sequence must use the custom trigger and injection")
    assert(sequence.entries[1].key == "injection:" .. tostring(case.injection)
        and sequence.entries[2].key == "window",
        case.key .. " must retain the default front-injection order")
end
""")


def test_devourer_defaults_build_sequence_and_accept_additional_custom_skills() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local context = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
local profile, profileKey, profileReason = TE.BurstProfiles:Get(context)
assert(profile ~= nil and profileKey == "DEMONHUNTER_3" and profileReason == nil)
assert(profile.noSeedNotice == nil)
assert(profile.openerSpellIDs[1] == 1225826)
assert(profile.injectionSpellIDs[1] == 1217605)
assert(profile.triggerEntries[1].spellID == 1225826 and profile.triggerEntries[1].builtIn == true)
assert(profile.injectionEntries[1].spellID == 1217605 and profile.injectionEntries[1].builtIn == true)

local sequence, sequenceKey, sequenceReason = TE.BurstProfiles:GetAutoBurstSequence(context)
assert(sequence ~= nil and sequenceKey == "DEMONHUNTER_3" and sequenceReason == nil)
assert(sequence.windowSpellID == 1225826 and sequence.injectionCount == 1)
assert(sequence.entries[1].key == "window" and sequence.entries[1].spellID == 1225826)
assert(sequence.entries[2].key == "injection:1217605")

C_Spell = {
    IsSpellKnown = function(spellID)
        return spellID == 1217610 or spellID == 1217611
    end,
}
local triggerAdded, triggerReason = TE.BurstProfiles:AddCustom(context, "trigger", 1217610)
assert(triggerAdded == true, "Devourer custom trigger rejected: " .. tostring(triggerReason))
local injectionAdded, injectionReason = TE.BurstProfiles:AddCustom(context, "injection", 1217611)
assert(injectionAdded == true, "Devourer custom injection rejected: " .. tostring(injectionReason))

local updated = TE.BurstProfiles:Get(context)
local function containsCustom(entries, spellID)
    for _, entry in ipairs(entries or {}) do
        if entry.spellID == spellID and entry.custom == true then return true end
    end
    return false
end
assert(containsCustom(updated.triggerEntries, 1217610))
assert(containsCustom(updated.injectionEntries, 1217611))
""")


def test_devourer_simple_preflight_defers_resource_blocked_void_metamorphosis() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "injection:1217605", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "unknown"
spellUsability[1217605] = "resource"
actionUsability[8] = "ready"

local result = eval()
assert(result.kind == "hold" and AutoBurst:GetSnapshot().active == true,
    "one resource sample must remain provisional inside the ordered plan")
result = eval()
assert(result.kind == "hold", "two distinct resource samples may skip only the optional injection")
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826)
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "runtime_optional_unavailable" and preflight.resourceBlocked == true)
""")


def test_devourer_simple_runtime_resource_drift_skips_injection_and_continues_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "injection:1217605", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "ready"
actionUsability[8] = "ready"

local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 1217605)
spellUsability[1217605] = "resource"
local confirming = eval()
assert(confirming.kind == "hold" and confirming.reason == "optional_injection_resource_confirming")
local skipped = eval()
assert(skipped.kind == "hold" and skipped.reason == "burst_next_step_pending")
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826,
    "simple mode must continue with Eradicate after resource-blocked Void Metamorphosis is skipped")
local observation = AutoBurst:GetDiagnostics().lastStepObservation
assert(observation.role == "window", "the plan must advance beyond the skipped injection")
""")


def test_arcane_late_injection_success_cannot_confirm_touch_after_runtime_skip() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "MAGE", specIndex = 1, specID = 62 }
officialSpellID = 321507
settings.burstProfiles.MAGE_1 = {
    autoBurstSequence = {
        order = { "injection:365350", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:365350"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[321507] = "ready"
bindings[365350] = "ready"
bindingTokens[321507] = 7
bindingTokens[365350] = 8
cooldowns[321507] = "ready"
cooldowns[365350] = "ready"
spellUsability[365350] = "ready"
actionUsability[8] = "ready"

local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 365350)
spellUsability[365350] = "resource"
actionUsability[8] = "resource"
local skipped = eval()
assert(skipped.kind == "hold" and skipped.reason == "optional_injection_resource_confirming")
skipped = eval()
assert(skipped.kind == "hold" and skipped.reason == "burst_next_step_pending")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.state == "PENDING" and snapshot.waitingForConfirmation == false,
    "skipping Arcane Surge must clear its WAIT_CONFIRM context atomically")
assert(AutoBurst:RecordSpellcastSucceeded(365350) == false,
    "a late Arcane Surge success must be rejected before Touch is dispatched")

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 321507)
assert(AutoBurst:RecordSpellcastSucceeded(365350) == false,
    "Arcane Surge must not confirm Touch through stale requestedSpellID metadata")
snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == true and snapshot.waitingForConfirmation == true
    and snapshot.pendingConfirmationSpellID == 321507)
assert(AutoBurst:RecordSpellcastSucceeded(321507) == true)
eval()
snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.requireWindowDeparture == true,
    "only an exact Touch success may complete the Arcane plan")
""")


def test_devourer_window_first_plan_finishes_when_post_injection_loses_special_resource() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "window", "injection:1217605", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "ready"

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826)
AutoBurst:RecordSpellcastSucceeded(1225826)
cooldowns[1217605] = "unknown"
spellUsability[1217605] = "resource"
    local settling = eval()
    assert(settling.kind == "hold" and AutoBurst:GetSnapshot().active == true)
    local confirming = eval()
    assert(confirming.kind == "hold" and AutoBurst:GetSnapshot().active == true)
    local skipped = eval()
    assert(skipped.kind == "hold", "resource-blocked post-window injection must finish without another dispatch")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.requireWindowDeparture == true,
    "window-first plan must keep only the normal departure lock after skipping its last optional step")
""")


def test_devourer_post_window_resource_preflight_is_deferred_and_ready_after_eradicate_dispatches_immediately() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "window", "injection:1217605", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "resource"
actionUsability[8] = "resource"

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826,
    "pre-Eradicate resource insufficiency must not discard the configured post-window injection")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "selected" and preflight.resourceCheckDeferred == true)
assert(preflight.firstDeferredResourceSpellID == 1217605)
assert(preflight.deferredResourceOrder == "injection:1217605")

AutoBurst:RecordSpellcastSucceeded(1225826)
spellUsability[1217605] = "ready"
actionUsability[8] = "ready"
gcdPhase = "QUEUE_WINDOW"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 1217605,
    "a fresh post-Eradicate ready sample must dispatch Void Metamorphosis in the same burst")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.state == "WAIT_CONFIRM" and snapshot.postWindowResourceSettling == false)
local observation = AutoBurst:GetDiagnostics().lastStepObservation
assert(observation.stage == "post_window_resource_ready" and observation.actionUsable == true)
""")


def test_devourer_post_window_resource_settlement_waits_for_gcd_and_two_distinct_unavailable_cycles() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "window", "injection:1217605", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "resource"
actionUsability[8] = "resource"

local window = eval(nil, nil, 100)
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826)
AutoBurst:RecordSpellcastSucceeded(1225826)

gcdPhase = "GCD_LOCKED"
local gcdHold = eval(nil, nil, 101)
assert(gcdHold.kind == "hold" and gcdHold.reason == "post_window_resource_settling")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.postWindowResourceSettling == true and snapshot.postWindowResourceFreshSamples == 0,
    "Root GCD must not dispatch or count an unavailable sample")

gcdPhase = "READY_NOW"
local first = eval(nil, nil, 102)
assert(first.kind == "hold" and AutoBurst:GetSnapshot().postWindowResourceFreshSamples == 1)
local duplicate = eval(nil, nil, 102)
assert(duplicate.kind == "hold" and AutoBurst:GetSnapshot().postWindowResourceFreshSamples == 1,
    "re-evaluating one RuntimeSnapshot cycle must not count twice")
local released = eval(nil, nil, 103)
assert(released.kind == "hold")
snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.requireWindowDeparture == true,
    "two distinct fresh unavailable samples must skip the optional injection without hanging")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "runtime_optional_unavailable")
assert(preflight.reason == "post_window_resource_unavailable_confirmed")
""")


def test_devourer_post_window_resource_unknown_remains_dispatchable() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "window", "injection:1217605", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "resource"

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826)
AutoBurst:RecordSpellcastSucceeded(1225826)
spellUsability[1217605] = nil
actionUsability[8] = nil
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 1217605,
    "opaque resource booleans must not discard an otherwise dispatchable injection")
assert(AutoBurst:GetSnapshot().active == true and AutoBurst:GetSnapshot().waitingForConfirmation == true)
""")


def test_devourer_window_first_plan_skips_post_injection_when_special_resource_flag_is_missing() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "window", "injection:1217605", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
-- Retail may expose the aura-backed resource gate only as unusable=false/false.
-- This compatibility signal must be rechecked after Eradicate, not used to
-- discard the configured post-window step during initial preflight.
spellUsability[1217605] = "unusable"
actionUsability[8] = "unusable"

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826)
AutoBurst:RecordSpellcastSucceeded(1225826)
cooldowns[1217605] = "unknown"
    local settling = eval()
    assert(settling.kind == "hold" and AutoBurst:GetSnapshot().active == true)
    local confirming = eval()
    assert(confirming.kind == "hold" and AutoBurst:GetSnapshot().active == true)
    local skipped = eval()
assert(skipped.kind == "hold",
    "Devourer special-resource unusable=false/false must skip the optional post injection")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.requireWindowDeparture == true,
    "skipping Void Metamorphosis must finish the plan with only the departure lock")
local observation = AutoBurst:GetDiagnostics().lastStepObservation
assert(observation.resourceBlocked == true and observation.notEnoughResource == false)
assert(observation.specialResourceUnusableCompat == true,
    "diagnostics must distinguish the Devourer compatibility classification")
""")


def test_special_resource_unusable_compat_is_scoped_to_devourer_void_metamorphosis() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
spellUsability[31884] = "unusable"
actionUsability[4] = "unusable"

local waiting = eval()
assert(waiting.kind == "hold" and waiting.reason == "burst_step_wait_usable",
    "ordinary false/false usability must retain the step without publishing a token")
assert(AutoBurst:GetSnapshot().active == true and AutoBurst:GetSnapshot().dispatchAttempt == 0)
spellUsability[31884] = "ready"
actionUsability[4] = "ready"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884,
    "the retained optional injection must dispatch as soon as its verified action becomes usable")
""")


def test_action_slot_temporary_unusable_overrides_spell_ready_and_resumes_without_rebuilding() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
spellUsability[31884] = "ready"
actionUsability[4] = "unusable"

local waiting = eval()
assert(waiting.kind == "hold" and waiting.reason == "burst_step_wait_usable")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "selected" and preflight.temporaryUsabilityDeferred == true,
    "the actual action-slot false must remain selected even when the spell probe says ready")
assert(preflight.deferredTemporaryOrder == "injection:31884")
local held = AutoBurst:GetSnapshot()
assert(held.active == true and held.currentSpellID == 31884 and held.dispatchAttempt == 0,
    "temporary unavailability must retain the original plan and step identity")

actionUsability[4] = "ready"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
assert(injection.dispatchAttempt == 1,
    "recovery must use the original plan's first logical attempt rather than rebuilding the chain")
""")


def test_movement_does_not_veto_positive_own_ready_admission() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
playerSpeed = 7
spellUsability[31884] = "ready"
actionUsability[4] = "unusable"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884,
    "movement must not suppress an otherwise positively ready configured step")
local observation = AutoBurst:GetDiagnostics().lastStepObservation
assert(observation.temporaryUnusableIgnoredForMovement == true and observation.playerMoving == true)
""")


def test_failed_injection_becoming_temporarily_unusable_does_not_trip_release_breaker() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
spellUsability[31884] = "ready"
actionUsability[4] = "ready"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED") == true)

-- The next fresh client snapshot exposes the recoverable gate (for example,
-- the player started moving between the ready sample and the physical press).
spellUsability[31884] = "unusable"
actionUsability[4] = "unusable"
local waiting = eval()
assert(waiting.kind == "hold" and waiting.reason == "burst_step_wait_usable")
local held = AutoBurst:GetSnapshot()
assert(held.active == true and held.currentSpellID == 31884)
assert(held.matchingFailureCount == 0,
    "a failure followed by temporary unavailability must be removed from the release certificate")
assert(held.failureExcludedByTemporaryUnavailable == true)

-- Remaining unavailable must not consume the retry barrier or leak a token.
waiting = eval()
assert(waiting.kind == "hold" and waiting.reason == "burst_step_wait_usable")

spellUsability[31884] = "ready"
actionUsability[4] = "ready"
assert(eval().reason == "burst_failure_retry_barrier")
assert(eval().reason == "burst_failure_retry_barrier")
local retry = eval()
assert(retry.kind == "candidate" and retry.dispatchSpellID == 31884)
assert(retry.dispatchAttempt == 2,
    "the same ordered step must resume through a fresh logical TEK attempt")
assert(AutoBurst:GetSnapshot().active == true)
""")


def test_post_window_resource_deferral_applies_to_all_optional_injections() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_post_sequence()
spellUsability[31884] = "resource"
actionUsability[4] = "resource"

local result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 343527,
    "a single resource sample must not discard an ordinary post-window injection")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "selected" and preflight.resourceCheckDeferred == true)
""")


def test_locked_optional_step_keeps_shared_retry_cadence_while_moving() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)

playerSpeed = 7
assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED") == true)
local moving = eval()
assert(moving.kind == "hold" and moving.reason == "burst_failure_retry_barrier")
local movingSnapshot = AutoBurst:GetSnapshot()
assert(movingSnapshot.failureObservedMoving == true and movingSnapshot.movementRetryHold == false,
    "movement is diagnostic and must not create a persistent no-token hold")

assert(eval().reason == "burst_failure_retry_barrier")
local retry2 = eval()
assert(retry2.kind == "candidate" and retry2.dispatchAttempt == 2 and playerSpeed > 0,
    "the admitted step must resume through the normal shared cadence even while moving")

assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED") == true)
assert(eval().reason == "burst_failure_retry_barrier")
assert(eval().reason == "burst_failure_retry_barrier")
local retry3 = eval()
assert(retry3.kind == "candidate" and retry3.dispatchSpellID == 31884 and retry3.dispatchAttempt == 3,
    "two exact failures must not remove a step already admitted to the locked chain")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == true and snapshot.currentSpellID == 31884 and snapshot.matchingFailureCount == 2)
""")


def test_devourer_wait_confirm_releases_when_special_resource_becomes_unusable() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "window", "injection:1217605", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "ready"
actionUsability[8] = "ready"

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 1225826)
AutoBurst:RecordSpellcastSucceeded(1225826)
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 1217605,
    "the test must first enter Void Metamorphosis WAIT_CONFIRM")
spellUsability[1217605] = "unusable"
actionUsability[8] = "unusable"
local released = eval()
assert(released.kind == "hold" and released.reason == "optional_injection_resource_confirming",
    "one generic unusable sample must remain provisional")
released = eval()
assert(released.kind == "hold", "two fresh unavailable samples may release the optional injection")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == false and snapshot.requireWindowDeparture == true)
local observation = AutoBurst:GetDiagnostics().lastStepObservation
assert(observation.stage == "wait_confirm" and observation.resourceBlocked == true)
assert(observation.specialResourceUnusableCompat == true)
""")


def test_devourer_focused_resource_block_refuses_plan_without_claiming_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.autoBurstMode = "focused"
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "injection:1217605", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"
bindings[1217605] = "ready"
bindingTokens[1225826] = 7
bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"
cooldowns[1217605] = "ready"
spellUsability[1217605] = "resource"

local result = eval()
assert(result.kind == "hold" and AutoBurst:GetSnapshot().active == true,
    "focused mode must retain a single resource sample for confirmation")
result = eval()
assert(result.kind == "none" and AutoBurst:GetSnapshot().active == false)
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "runtime_optional_unavailable")
""")


def test_action_slot_resource_boolean_remains_compatibility_fallback() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[31884] = "unknown"
actionUsability[4] = "resource"

local result = eval()
assert(result.kind == "hold" and AutoBurst:GetSnapshot().active == true,
    "one action-slot resource sample must remain provisional")
result = eval()
assert(result.kind == "hold" and AutoBurst:GetSnapshot().active == true,
    "two action-slot resource samples may skip only the optional step while retaining the window")
local preflight = AutoBurst:GetDiagnostics().lastSequencePreflight
assert(preflight.status == "runtime_optional_unavailable")
""")


def test_runtime_snapshot_preserves_false_action_usability_for_resource_gate() -> None:
    run_lua(r"""
_G.TacticEcho = {}
local TE = _G.TacticEcho
C_ActionBar = {
    IsUsableAction = function(actionSlot)
        assert(actionSlot == 8)
        return false, true
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/RuntimeSnapshot.lua")
local snapshot = TE.RuntimeSnapshot:Begin("resource_boolean_test", {})
local usable, notEnough, reason = TE.RuntimeSnapshot:GetActionUsability(snapshot, 8)
assert(usable == false, "explicit action unusable=false must not collapse to nil")
assert(notEnough == true and reason == nil)
local cachedUsable, cachedNotEnough = TE.RuntimeSnapshot:GetActionUsability(snapshot, 8)
assert(cachedUsable == false and cachedNotEnough == true, "cached resource booleans must preserve false/true")
""")


def test_runtime_snapshot_preserves_special_spell_resource_boolean() -> None:
    run_lua(r"""
_G.TacticEcho = {}
local TE = _G.TacticEcho
C_Spell = {
    IsSpellUsable = function(spellID)
        assert(spellID == 1217605)
        return false, true
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/RuntimeSnapshot.lua")
local snapshot = TE.RuntimeSnapshot:Begin("special_resource_boolean_test", {})
local usable, notEnough, reason = TE.RuntimeSnapshot:GetSpellUsability(snapshot, 1217605)
assert(usable == false, "explicit spell unusable=false must not collapse to nil")
assert(notEnough == true and reason == nil)
local cachedUsable, cachedNotEnough = TE.RuntimeSnapshot:GetSpellUsability(snapshot, 1217605)
assert(cachedUsable == false and cachedNotEnough == true, "cached special-resource booleans must preserve false/true")
""")


def test_resource_exception_does_not_apply_to_window_or_non_resource_unusable_result() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_post_sequence()
spellUsability[343527] = "resource"
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527,
    "resource exception must never suppress the immutable window step")
""")
    run_lua(AUTO_BURST_HARNESS + r"""
spellUsability[31884] = "unusable"
actionUsability[4] = "unusable"
local waiting = eval()
assert(waiting.kind == "hold" and waiting.reason == "burst_step_wait_usable",
    "usable=false without explicit notEnoughResource=true must wait rather than skip or dispatch")
assert(AutoBurst:GetSnapshot().active == true)
""")


def test_unknown_window_after_confirmed_injection_waits_for_positive_ready_evidence() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[343527] = "unknown"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884, "official window uncertainty must not prevent the pre step")
AutoBurst:RecordSpellcastSucceeded(31884)
gcdPhase = "GCD_LOCKED"
local locked = eval()
assert(locked.kind == "hold" and locked.reason == "burst_step_revalidate",
    "the next latched window must not publish a token from unknown cooldown evidence")
gcdPhase = "QUEUE_WINDOW"
assert(eval().kind == "hold", "public queue state alone must not authorize the unknown window")
cooldowns[343527] = "ready"
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527,
    "the latched window may dispatch after its own readiness becomes explicit")
assert(window.cooldownUncertain ~= true)
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
local provisional = eval()
assert(not (provisional.kind == "candidate" and provisional.dispatchSpellID == 343527))
nowValue = 20.21
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
local provisional = eval()
assert(not (provisional.kind == "candidate" and provisional.dispatchSpellID == 343527))
nowValue = 0.26
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


def test_optional_predictive_cooldown_stays_latched_until_exact_result() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
cooldowns[31884] = "cooldown"
nowValue = 0.05
local provisional = eval()
assert(provisional.kind == "hold" and provisional.reason == "burst_step_revalidate",
    "an observed own cooldown must immediately stop re-dispatch while success evidence stabilizes")
assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED") == true)
cooldowns[31884] = "ready"
nowValue = 0.10
local barrierOne = eval()
assert(barrierOne.kind == "hold" and barrierOne.reason == "burst_failure_retry_barrier",
    "the first failed logical attempt must publish a no-token retry barrier")
nowValue = 0.15
local barrierTwo = eval()
assert(barrierTwo.kind == "hold" and barrierTwo.reason == "burst_failure_retry_barrier",
    "the retry barrier must cover two fresh transport frames")
nowValue = 0.20
local retry = eval()
assert(retry.kind == "candidate" and retry.dispatchSpellID == 31884,
    "a matching failure must retry through a new logical attempt")
assert(AutoBurst:GetSnapshot().dispatchAttempt == 2,
    "the retry must not reuse the original logical dispatch attempt")
""")


def test_two_matching_failures_keep_locked_optional_step_and_never_advance_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED") == true)
assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED_QUIET") == false,
    "duplicate receipts for one logical attempt must not count as a second rejection")
local barrierOne = eval()
assert(barrierOne.kind == "hold" and barrierOne.reason == "burst_failure_retry_barrier")
local barrierTwo = eval()
assert(barrierTwo.kind == "hold" and barrierTwo.reason == "burst_failure_retry_barrier")
local retry = eval()
assert(retry.kind == "candidate" and retry.dispatchSpellID == 31884)
assert(AutoBurst:GetSnapshot().matchingFailureCount == 1)
assert(AutoBurst:RecordSpellcastFailed(31884, "UNIT_SPELLCAST_FAILED_QUIET") == true)
local secondBarrierOne = eval()
assert(secondBarrierOne.kind == "hold" and secondBarrierOne.reason == "burst_failure_retry_barrier")
local secondBarrierTwo = eval()
assert(secondBarrierTwo.kind == "hold" and secondBarrierTwo.reason == "burst_failure_retry_barrier")
local retryAgain = eval()
assert(retryAgain.kind == "candidate" and retryAgain.dispatchSpellID == 31884,
    "a locked optional step must retry itself rather than advancing to the window")
assert(AutoBurst:GetSnapshot().dispatchAttempt == 3
    and AutoBurst:GetSnapshot().matchingFailureCount == 2)
""")


def test_arcane_surge_enters_queue_window_then_retries_only_when_ready_now() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "MAGE", specIndex = 1, specID = 62 }
officialSpellID = 321507
settings.burstProfiles.MAGE_1 = {
    customInjectionSpellIDs = { 55342 },
    injectionOrder = { 55342, 365350 },
    autoBurstSequence = {
        order = { "injection:55342", "injection:365350", "window", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:55342"] = true,
            ["injection:365350"] = true,
            ["trinket:13"] = false,
            ["trinket:14"] = false,
        },
    },
}
bindings[321507] = "ready"; bindings[55342] = "ready"; bindings[365350] = "ready"
bindingTokens[321507] = 1; bindingTokens[55342] = 2; bindingTokens[365350] = 3
cooldowns[321507] = "ready"; cooldowns[55342] = "ready"; cooldowns[365350] = "ready"

local mirrorImage = eval()
assert(mirrorImage.kind == "candidate" and mirrorImage.dispatchSpellID == 55342)
assert(AutoBurst:RecordSpellcastSucceeded(55342) == true)

gcdPhase = "GCD_LOCKED"
local locked = eval()
assert(locked.kind == "hold" and locked.reason == "burst_step_wait_queue_window",
    "Arcane Surge must not create a logical attempt while the preceding GCD is locked")
local lockedSnapshot = AutoBurst:GetSnapshot()
assert(lockedSnapshot.dispatchAttempt == 1 and lockedSnapshot.currentSpellID == 365350,
    "GCD waiting must retain the locked Arcane Surge without incrementing attempt identity")

gcdPhase = "QUEUE_WINDOW"
local arcaneSurge = eval()
assert(arcaneSurge.kind == "candidate" and arcaneSurge.dispatchSpellID == 365350,
    "Arcane Surge must make its first logical attempt in the public queue window")
assert(arcaneSurge.dispatchAttempt == 2)
assert(AutoBurst:RecordSpellcastFailed(365350, "UNIT_SPELLCAST_FAILED") == true)
assert(eval().reason == "burst_failure_retry_barrier")
assert(eval().reason == "burst_failure_retry_barrier")

local queueRetry = eval()
assert(queueRetry.kind == "hold" and queueRetry.reason == "burst_failure_retry_wait_ready_now",
    "a rejected queue-window Arcane Surge must not retry inside the same queue opportunity")
local waiting = AutoBurst:GetSnapshot()
assert(waiting.dispatchAttempt == 2 and waiting.matchingFailureCount == 1,
    "READY_NOW waiting must preserve the rejected attempt without incrementing retry identity")
assert(waiting.failureObservedPhase == "QUEUE_WINDOW")

gcdPhase = "READY_NOW"
local retry = eval()
assert(retry.kind == "candidate" and retry.dispatchSpellID == 365350,
    "Arcane Surge must retry only after the public gate reaches full readiness")
local retried = AutoBurst:GetSnapshot()
assert(retried.dispatchAttempt == 3 and retried.failureRetryObservedPhase == "READY_NOW",
    "the safe retry must use a fresh logical attempt and audit its GCD phase")
""")


def test_normal_cast_pauses_plan_before_usability_or_sequence_mutation() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
testContext = { class = "DEMONHUNTER", specIndex = 3, specID = 1480 }
officialSpellID = 1225826
settings.burstProfiles.DEMONHUNTER_3 = {
    autoBurstSequence = {
        order = { "injection:1217605", "window", "trinket:13", "trinket:14" },
        enabled = { ["injection:1217605"] = true, ["trinket:13"] = false, ["trinket:14"] = false },
    },
}
bindings[1225826] = "ready"; bindings[1217605] = "ready"
bindingTokens[1225826] = 7; bindingTokens[1217605] = 8
cooldowns[1225826] = "ready"; cooldowns[1217605] = "ready"
spellUsability[1217605] = "ready"; actionUsability[8] = "ready"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 1217605)
spellUsability[1217605] = "unusable"; actionUsability[8] = "unusable"
local retry = AutoBurst:Evaluate({ spellID = officialSpellID }, {
    inCombat = true, intentState = "armed", effectiveState = "armed",
    primary = { spellID = officialSpellID }, context = testContext,
    runtimeSnapshot = {
        cycleId = 9001,
        castDisplay = { active = true, kind = "cast", spellID = 999999 },
    },
})
assert(retry.kind == "hold" and retry.reason == "runtime_cast",
    "an active cast must pause detection before any new candidate or usability decision")
local snapshot = AutoBurst:GetSnapshot()
assert(snapshot.active == true and snapshot.currentSpellID == 1217605 and snapshot.dispatchAttempt == 1,
    "cast observation must preserve the exact admitted step and cursor")
""")


def test_active_cast_before_plan_does_not_consume_window_observation_or_create_plan() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local paused = AutoBurst:Evaluate({ spellID = officialSpellID }, {
    inCombat = true, intentState = "armed", effectiveState = "cast",
    runtimeReason = "runtime_cast",
    primary = { spellID = officialSpellID }, context = testContext,
    runtimeSnapshot = {
        cycleId = 9100,
        castDisplay = { active = true, kind = "cast", spellID = 999999 },
    },
})
assert(paused.kind == "hold" and paused.reason == "burst_cast_window_fence"
    and paused.observationOnly == true and paused.bindingToken == 0
    and AutoBurst:GetSnapshot().active == false,
    "a configured window must be fenced without creating a plan while another cast is active")
assert(AutoBurst.lastOfficialSpellID == nil and AutoBurst.currentWindowSpellID == nil,
    "cast protection must run before consuming the official window edge")
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884,
    "the first healthy frame after the cast must still observe the untouched window")
""")


def test_casting_step_success_is_retained_while_wait_confirm_is_soft_paused() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
settings.burstProfiles.PALADIN_3 = {
    customInjectionSpellIDs = { 55342, 365350 },
    injectionOrder = { 55342, 365350 },
    autoBurstSequence = {
        order = { "injection:55342", "injection:365350", "window", "trinket:13", "trinket:14" },
        enabled = {
            ["injection:55342"] = true,
            ["injection:365350"] = true,
            ["trinket:13"] = false,
            ["trinket:14"] = false,
        },
    },
}
bindings[55342] = "ready"; bindingTokens[55342] = 5; cooldowns[55342] = "ready"
bindings[365350] = "ready"; bindingTokens[365350] = 6; cooldowns[365350] = "ready"

assert(eval().dispatchSpellID == 55342)
AutoBurst:RecordSpellcastSucceeded(55342)
local surge = eval()
assert(surge.kind == "candidate" and surge.dispatchSpellID == 365350)

local casting = AutoBurst:Evaluate({ spellID = officialSpellID }, {
    inCombat = true, intentState = "armed", effectiveState = "armed",
    primary = { spellID = officialSpellID }, context = testContext,
    runtimeSnapshot = {
        cycleId = 9200,
        castDisplay = { active = true, kind = "cast", spellID = 365350 },
    },
})
assert(casting.kind == "hold" and casting.reason == "runtime_cast")
assert(AutoBurst:RecordSpellcastSucceeded(365350) == true,
    "the exact success receipt must survive the SOFT_PAUSED wrapper around WAIT_CONFIRM")
local pausedSnapshot = AutoBurst:GetSnapshot()
assert(pausedSnapshot.state == "SOFT_PAUSED" and pausedSnapshot.confirmationEventSpellID == 365350)

local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == officialSpellID,
    "the first healthy frame must confirm the casting step and advance to the window")
""")


def test_waiting_window_accepts_current_resolver_override_equivalent() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
function TE.ActionBarBindingResolver:GetEquivalentSpellIDs(spellID)
    if spellID == 343527 then return { 343527, 999343 } end
    return { spellID }
end
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527)
assert(AutoBurst:RecordSpellcastSucceeded(999343) == true, "current resolver override must confirm the exact waiting window")
local completed = eval()
assert(completed.kind ~= "candidate" and AutoBurst:GetSnapshot().active == false, "override confirmation must complete the sequence")
assert(AutoBurst:GetDiagnostics().lastConfirmationSource == "unit_spellcast_succeeded_resolver_equivalent")
""")


def test_transient_charge_decrease_followed_by_failure_does_not_complete_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[343527] = { charges = 2, maxCharges = 2, cooldownActive = false }
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527)

-- Retail can optimistically consume a charge before reporting that the queued
-- cast failed.  The first charge transition must remain provisional.
cooldowns[343527] = { charges = 1, maxCharges = 2, cooldownActive = false }
nowValue = 0.10
local provisional = eval()
assert(provisional.kind == "candidate" and AutoBurst:GetSnapshot().active == true,
    "one transient charge sample must not complete the window")
assert(AutoBurst:RecordSpellcastFailed(343527, "UNIT_SPELLCAST_FAILED") == true)
cooldowns[343527] = { charges = 2, maxCharges = 2, cooldownActive = false }
nowValue = 0.20
local barrierOne = eval()
assert(barrierOne.kind == "hold" and barrierOne.reason == "burst_failure_retry_barrier")
nowValue = 0.25
local barrierTwo = eval()
assert(barrierTwo.kind == "hold" and barrierTwo.reason == "burst_failure_retry_barrier")
nowValue = 0.30
local retry = eval()
assert(retry.kind == "candidate" and retry.dispatchSpellID == 343527,
    "a failed optimistic charge transition must keep reoffering the same window")
AutoBurst:RecordSpellcastSucceeded(343527)
local completed = eval()
assert(completed.kind ~= "candidate" and AutoBurst:GetSnapshot().active == false,
    "an exact later success must still complete the window immediately")
""")


def test_persistent_charge_decrease_confirms_after_stability_window() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
cooldowns[343527] = { charges = 2, maxCharges = 2, cooldownActive = false }
local injection = eval()
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527)
cooldowns[343527] = { charges = 1, maxCharges = 2, cooldownActive = false }
nowValue = 0.05
local provisional = eval()
assert(provisional.kind == "candidate" and AutoBurst:GetSnapshot().active == true)
nowValue = 0.25
local completed = eval()
assert(completed.kind ~= "candidate" and AutoBurst:GetSnapshot().active == false,
    "persistent charge evidence must remain a valid fallback when success events are unavailable")
assert(AutoBurst:GetDiagnostics().lastConfirmationSource == "charge_decreased")
""")


def test_unconfirmed_dispatched_window_releases_after_observed_departure_and_grace() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
AutoBurst:RecordSpellcastSucceeded(31884)
local window = eval()
assert(window.kind == "candidate" and window.dispatchSpellID == 343527)
local rotated = AutoBurst:Evaluate({ spellID = 184575 }, {
    inCombat = true, intentState = "armed", effectiveState = "armed",
    primary = { spellID = 184575 }, context = { class = "PALADIN", specIndex = 3 },
})
assert(rotated.kind == "candidate", "window stays latched during its confirmation grace")
nowValue = 2.30
local released = AutoBurst:Evaluate({ spellID = 184575 }, {
    inCombat = true, intentState = "armed", effectiveState = "armed",
    primary = { spellID = 184575 }, context = { class = "PALADIN", specIndex = 3 },
})
assert(released.kind == "none", "unconfirmed departed window must release ordinary scheduling")
assert(AutoBurst:GetSnapshot().active == false, "unconfirmed window must not remain in WAIT_CONFIRM")
local events = AutoBurst:GetDiagnostics().recentPriorityEvents
local event = events and events[#events]
assert(event and event.event == "window_confirmation_unobserved_released", "safe release must remain auditable")
""")


def test_post_mode_defers_future_unknown_injection_until_positive_ready_evidence() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_post_sequence()
cooldowns[31884] = "unknown"
gcdPhase = "GCD_LOCKED"
local firstLocked = eval()
assert(firstLocked.kind == "hold" and firstLocked.reason == "burst_step_wait_ready_now",
    "the ready window may own the plan while the unknown future step stays deferred")
gcdPhase = "READY_NOW"
local result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 343527)
cooldowns[31884] = "ready"
AutoBurst:RecordSpellcastSucceeded(343527)
gcdPhase = "GCD_LOCKED"
local injectionLocked = eval()
assert(injectionLocked.kind == "hold" and injectionLocked.reason == "burst_step_wait_queue_window",
    "the future step may join only after positive own-ready evidence and still observes the shared GCD")
gcdPhase = "QUEUE_WINDOW"
local injection = eval()
assert(injection.kind == "candidate" and injection.dispatchSpellID == 31884)
""")


def test_post_mode_never_dispatches_future_step_that_remains_on_own_cooldown() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
use_post_sequence()
cooldowns[31884] = "cooldown"
local result = eval()
assert(result.kind == "candidate" and result.dispatchSpellID == 343527,
    "the ready window may proceed while the future CD step remains deferred")
AutoBurst:RecordSpellcastSucceeded(343527)
local pending = eval()
assert(pending.kind == "hold" and pending.reason == "deferred_tail_fresh_snapshot_pending"
    and AutoBurst:GetSnapshot().active == true,
    "the confirmation snapshot cannot also advance over the deferred configured position")
local completed = eval()
assert(completed.kind ~= "candidate" and AutoBurst:GetSnapshot().active == false,
    "a future step still on own cooldown when its position is reached must never be dispatched")
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


def test_cooldown_only_trusted_numeric_ready_wins_over_contradictory_active_boolean() -> None:
    run_lua(r"""
function GetTime() return 150 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        -- The declared/base SpellID still exposes its old 120s cooldown after
        -- the actual talented action has recovered at roughly 60s.
        return { startTime = 90, duration = 120, isEnabled = true, isActive = true, isOnGCD = false }
    end,
    GetSpellCharges = function(spellID) return nil end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        -- Retail field disagreement observed in the Retribution test: the
        -- exact current button is numerically ready while `isActive` lags.
        return { startTime = 0, duration = 0, isActive = true, isOnGCD = false }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(31884, {
    liveCooldown = true, actionSlot = 8, directActionSlot = true,
    actionBarStateTrusted = true,
    gcdSnapshot = { known = true, active = false, activeKnown = true },
})
assert(state.cooldownKnown == true and state.cooldownActive == false,
    "trusted exact-button 0/0 must correct the stale base SpellID cooldown")
assert(state.cooldownDirectActionBarReadyEvidence == true,
    "the correction must remain limited to explicit direct-button ready evidence")
assert(state.cooldownActionBarReadyConflict == true
    and state.cooldownActionBarReadyConflictReason == "trusted_numeric_ready_overrode_active",
    "the contradictory public scalars must be exported as a bounded audit reason")
""")


def test_cooldown_only_untrusted_numeric_ready_cannot_override_spell_cooldown() -> None:
    run_lua(r"""
function GetTime() return 150 end
_G.TacticEcho = {}
C_Spell = {
    GetSpellCooldown = function(spellID)
        return { startTime = 90, duration = 120, isEnabled = true, isActive = true, isOnGCD = false }
    end,
    GetSpellCharges = function(spellID) return nil end,
}
C_ActionBar = {
    GetActionCooldown = function(slot)
        return { startTime = 0, duration = 0, isActive = true, isOnGCD = false }
    end,
}
dofile(ROOT .. "/addon/!TacticEcho/Tactics/IconState.lua")
local state = _G.TacticEcho.IconState:CollectCooldownOnly(31884, {
    liveCooldown = true, actionSlot = 8, directActionSlot = false,
    actionBarStateTrusted = true,
    gcdSnapshot = { known = true, active = false, activeKnown = true },
})
assert(state.cooldownKnown == true and state.cooldownActive == true,
    "macro/indirect action slots must not inherit the direct-button ready correction")
assert(state.cooldownDirectActionBarReadyEvidence ~= true
    and state.cooldownActionBarReadyConflict ~= true,
    "an untrusted 0/0 observation must not authorize or claim a correction")
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


def test_preflight_race_guard_reoffers_unconfirmed_injection_when_cooldown_becomes_unknown() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
local first = eval()
assert(first.kind == "candidate" and first.dispatchSpellID == 31884, "ready preflight must initially construct the injection step")
cooldowns[31884] = "unknown"
gcdPhase = "GCD_LOCKED"
local retry = eval()
assert(retry.kind == "hold" and retry.reason == "burst_wait_confirm_gcd_locked",
    "simple mode must retain an uncertain waiting injection without publishing a GCD-locked token")
local snap = AutoBurst:GetSnapshot()
assert(snap.active == true and snap.currentSpellID == 31884 and snap.waitingForConfirmation == true)
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


def test_evaluate_normalizes_once_then_reads_live_settings_table() -> None:
    run_lua(AUTO_BURST_HARNESS + r"""
for index = 1, 8 do eval() end
assert(normalizeCalls == 1, "high-frequency Evaluate must not run full Normalize every frame")
settings.autoInjectionEnabled = false
local disabled = eval()
assert(disabled.kind == "none", "live setting mutation must be visible on the next Evaluate")
assert(normalizeCalls == 1)
""")


def test_source_contracts_for_epoch_recovery_inventory_stability_and_diagnostics() -> None:
    source = (ROOT / "addon" / "!TacticEcho" / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    assert "firstHealthyFramePending == true and self.recoveredArmedEpoch ~= self.armedEpoch" in source
    assert 'if success then\n            success = confirmStableFallback(self, plan, step, source, cycle)' in source
    for field in (
        "persistentRecoveryActive",
        "persistentRecoveryElapsed",
        "persistentRecoveryStepKey",
        "persistentRecoveryActionKind",
        "persistentRecoveryCandidateOffers",
        "persistentRecoveryConfirmationAvailable",
        "persistentRecoveryLastReason",
    ):
        assert field in source


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
