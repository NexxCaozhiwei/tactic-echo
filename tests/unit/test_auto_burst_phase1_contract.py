from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TEK = ROOT / "tek" / "src"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_autoburst_phase1_is_loaded_and_opt_in() -> None:
    toc = read(ADDON / "!TacticEcho.toc")
    defaults = read(ADDON / "Config" / "Defaults.lua")
    normalize = read(ADDON / "Config" / "Normalize.lua")
    assert "Tactics/GCDGate.lua" in toc
    assert "Tactics/AutoBurst.lua" in toc
    assert toc.index("Tactics/GCDGate.lua") < toc.index("Tactics/AutoBurst.lua")
    assert "autoBurstEnabled = false" in defaults
    assert "autoBurstDirection = \"pre\"" in defaults
    assert "autoBurstMode = \"simple\"" in defaults
    assert "autoBurstWindowSpellID = 0" in defaults
    assert "autoBurstInjectionSpellID = 0" in defaults
    assert "autoBurstUseProfileFallback = true" in defaults
    assert "tactics.autoBurstWindowSpellID" in normalize
    assert "tactics.autoBurstInjectionSpellID" in normalize


def test_autoburst_reads_only_cooldown_charge_and_normalized_gcd_states() -> None:
    source = read(ADDON / "Tactics" / "AutoBurst.lua")
    icon_state = read(ADDON / "Tactics" / "IconState.lua")
    assert "CollectCooldownOnly" in source
    assert "C_Spell.IsSpellUsable" not in source
    assert "UnitAura" not in source
    assert "C_UnitAuras" not in source
    assert "GCD_LOCKED" in source
    assert "QUEUE_WINDOW" in source
    assert "STEP_REVALIDATE_SECONDS" in source
    assert "SendInput(" not in source
    assert "function IconState:CollectCooldownOnly" in icon_state
    cooldown_only = icon_state.split("function IconState:CollectCooldownOnly", 1)[1].split("function IconState:Collect(", 1)[0]
    assert "usableState(" not in cooldown_only
    assert "targetState(" not in cooldown_only
    assert "hasProc(" not in cooldown_only


def test_unknown_and_ambiguous_gcd_never_become_skip_eligible_own_cooldown() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    icon = read(ADDON / "Tactics" / "IconState.lua")
    assert "cooldown_active_origin_unknown" in auto
    assert 'creation.preInjectionSkipAllowed = injectionSample.phase == "COOLDOWN"' in auto
    assert "UNKNOWN is not cooldown" in auto
    assert "revalidateUnknownStep" in auto
    assert "step_revalidate_timeout" in auto
    assert "normalizeCooldownAgainstGcd" in icon
    assert "cooldownGcdAlias" in icon
    assert "gcd_snapshot_aligned" in icon


def test_burst_candidate_is_auditable_persistent_and_deduplicated_without_new_protocol_bytes() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    encoder = read(ADDON / "Signal" / "SignalEncoder.lua")
    signal_frame = read(ADDON / "Signal" / "SignalFrame.lua")
    teap = read(TEK / "teap.py")
    gate = read(TEK / "safety_gate.py")
    assert "flags = flags + 32" in encoder
    assert "burstPlanMetadata" in encoder
    assert "officialSpellID" in signal_frame
    assert "dispatchOrigin" in signal_frame
    assert "dispatchAttempt" in signal_frame
    assert "lastCandidate" in auto
    assert "candidateOfferCount" in auto
    assert "until confirmation, explicit invalidation" in auto
    assert "dispatch_origin=\"burst\"" in teap
    assert "burst_sequence_already_dispatched" in gate
    assert "last_burst_dispatch_sequence" in gate


def test_spellcast_success_is_confirmation_only_for_current_waiting_step() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert '"UNIT_SPELLCAST_SUCCEEDED"' in auto
    assert "function AutoBurst:RecordSpellcastSucceeded" in auto
    assert "plan.state == \"WAIT_CONFIRM\"" in auto
    assert "spellcastSucceededSpellID" in auto
    assert "unit_spellcast_succeeded" in auto
    assert "t < (number(plan.wait.dispatchedAt) or 0)" in auto


def test_burst_internal_hold_and_evaluator_fault_are_armed_observation_not_global_pause() -> None:
    source = read(ADDON / "Tactics" / "AutoBurst.lua")
    signal_frame = read(ADDON / "Signal" / "SignalFrame.lua")
    assert "observationOnly = true" in source
    assert "burstHoldObservation" in signal_frame
    assert "not observationOnly" in signal_frame
    assert 'if outputState == "armed" then outputState = "paused" end' not in signal_frame
    assert "TEAP observation_only prevents" in signal_frame
    assert "burst_evaluator_fault_hold" in signal_frame
    assert 'TE.AutoBurst, "evaluator_fault", false' in signal_frame


def test_window_departure_lock_runs_after_real_auto_run_gates() -> None:
    source = read(ADDON / "Tactics" / "AutoBurst.lua")
    lock_index = source.index("if self.requireWindowDeparture and officialSpellID == self.lockedWindowSpellID")
    enabled_index = source.index("if settings.autoBurstEnabled ~= true then")
    intent_index = source.index('if runtime.intentState ~= "armed" then')
    paused_index = source.index("local paused, pauseReason = isRuntimePaused")
    assert enabled_index < intent_index < paused_index < lock_index


def test_any_created_plan_keeps_window_ownership_after_terminal_abort() -> None:
    source = read(ADDON / "Tactics" / "AutoBurst.lua")
    abort = source.split("function AutoBurst:Abort", 1)[1].split("function AutoBurst:BeginCombatEpoch", 1)[0]
    assert "self.lockedWindowSpellID = self.plan.rule.windowSpellID" in abort
    assert "self.requireWindowDeparture = true" in abort
    assert "Fail open" not in abort
    assert "planOwnsWindowBeforeDispatch" not in abort


def test_window_edge_and_departure_lock_reset_at_new_combat_epoch() -> None:
    source = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert '\"PLAYER_REGEN_DISABLED\"' in source
    assert "function AutoBurst:BeginCombatEpoch" in source
    assert 'AutoBurst:BeginCombatEpoch("player_regen_disabled")' in source
    assert "self.requireWindowDeparture = false" in source
    assert "self.lockedWindowSpellID = nil" in source
    assert "self.lastOfficialSpellID = nil" in source
    assert "combat_epoch_started" in source


def test_burst_hold_keeps_display_only_official_binding() -> None:
    signal = read(ADDON / "Signal" / "SignalFrame.lua")
    tactical = read(ADDON / "Tactics" / "TacticalState.lua")
    assert "officialBindingInfo" in signal
    assert "officialBindingReason" in signal
    assert "message.bindingInfo or message.officialBindingInfo" in tactical
    assert "message.observationOnly ~= true" in tactical


def test_autoburst_reads_fresh_spell_and_gcd_snapshots_for_each_step() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    icon = read(ADDON / "Tactics" / "IconState.lua")
    assert "liveCooldown = true" in auto
    assert "liveOnly = options.liveCooldown == true" in icon
    assert "spellCooldown(GLOBAL_COOLDOWN_SPELL_ID, {" in icon
    assert "liveOnly = true" in icon
    assert "liveApiAuthoritative" in icon


def test_front_window_unknown_creates_bounded_plan_instead_of_official_fallback() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "plan_gate_window_unknown" in auto
    assert "create a bounded plan and revalidate" in auto
    assert "burst_window_not_ready" in auto
