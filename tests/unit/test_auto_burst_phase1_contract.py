from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TEK = ROOT / "tek" / "src"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_autoburst_ordered_sequence_is_loaded_and_opt_in() -> None:
    toc = read(ADDON / "!TacticEcho.toc")
    defaults = read(ADDON / "Config" / "Defaults.lua")
    normalize = read(ADDON / "Config" / "Normalize.lua")
    profiles = read(ADDON / "Tactics" / "BurstProfiles.lua")
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "Tactics/GCDGate.lua" in toc
    assert "Tactics/BurstProfiles.lua" in toc
    assert "Tactics/AutoBurst.lua" in toc
    assert toc.index("Tactics/GCDGate.lua") < toc.index("Tactics/AutoBurst.lua")
    assert "autoBurstEnabled = false" in defaults
    assert "autoBurstMode = \"simple\"" in defaults
    assert "autoBurstWindowSpellID" not in defaults
    assert "autoBurstInjectionSpellID" not in defaults
    assert "AUTO_BURST_MAX_INJECTIONS = 3" in profiles
    assert "function BurstProfiles:GetAutoBurstSequence" in profiles
    assert "function BurstProfiles:MoveAutoBurstStep" in profiles
    assert "function BurstProfiles:SetAutoBurstStepEnabled" in profiles
    assert "tactics.autoBurstWindowSpellID = nil" in normalize
    assert "profile_sequence" in auto
    assert "preflightSequence" in auto


def test_autoburst_reads_only_cooldown_charge_and_normalized_gcd_states() -> None:
    source = read(ADDON / "Tactics" / "AutoBurst.lua")
    icon_state = read(ADDON / "Tactics" / "IconState.lua")
    assert "CollectCooldownOnly" in source
    assert "C_Spell.IsSpellUsable" not in source
    assert "UnitAura" not in source
    assert "C_UnitAuras" not in source
    assert "GCD_LOCKED" in source
    assert "QUEUE_WINDOW" in source
    assert "gcd_locked_delivery_continues" in source
    assert "public GCD" in source
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
    assert "PRE_INJECTION_COOLDOWN_CONFIRM_SAMPLES" in auto
    assert "PRE_INJECTION_COOLDOWN_CONFIRM_INTERVAL_SECONDS" in auto
    assert "explicitOwnCooldownEvidence" in auto
    assert "confirmPreInjectionOwnCooldown" in auto
    assert 'preInjectionSkipAllowed = false' in auto
    assert "confirmed_own_cooldown" in auto
    assert "UNKNOWN is not cooldown" in auto
    assert "revalidateUnknownStep" in auto
    assert "step_revalidate_persistent" in auto
    assert "step_revalidate_timeout" not in auto
    assert "normalizeCooldownAgainstGcd" in icon
    assert "cooldownGcdAlias" in icon
    assert "gcd_snapshot_aligned" in icon


def test_burst_candidate_is_auditable_persistent_and_uses_shared_rate_policy_without_new_protocol_bytes() -> None:
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
    assert "every fresh armed frame" in auto
    assert "configured global rate limiter" in auto
    assert "dispatch_origin=\"burst\"" in teap
    assert "Burst and official candidates intentionally share the same delivery" in gate
    assert "burst_sequence_already_dispatched" not in gate
    assert "last_burst_dispatch_sequence" in gate


def test_autoburst_latched_plan_has_no_arbitrary_retry_or_outer_timeout() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "inventoryRecoveryPersistent = true" in auto
    assert "step_confirmation_grace_elapsed" in auto
    assert "No outer plan timeout" in auto
    assert 'self:Abort("plan_timeout"' not in auto
    assert "step_revalidate_persistent" in auto
    assert "confirmWindowOwnCooldown" in auto
    assert "window_own_cooldown_confirmed" in auto
    assert "PRE_INJECTION_COOLDOWN_CONFIRM_SAMPLES = 2" in auto


def test_spellcast_success_is_confirmation_only_for_current_waiting_step() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert '"UNIT_SPELLCAST_SUCCEEDED"' in auto
    assert "function AutoBurst:RecordSpellcastSucceeded" in auto
    assert "plan.state == \"WAIT_CONFIRM\"" in auto
    assert "spellcastSucceededSpellID" in auto
    assert "spellcastMatchesCurrentStep" in auto
    assert "equivalentSpellIDs" in auto
    assert "unit_spellcast_succeeded" in auto
    assert "t < (number(plan.wait.dispatchedAt) or 0)" in auto
    assert "observeWindowQueueDelivery" in auto
    assert "window_queue_delivery_continues" in auto


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
    lock = source.split("local function lockWindowDeparture", 1)[1].split("local function observeWindowFrame", 1)[0]
    assert "lockWindowDeparture(self, self.plan)" in abort
    assert "self.lockedWindowSpellID = plan.rule.windowSpellID" in lock
    assert "self.requireWindowDeparture = true" in lock
    assert "self.consumedWindowGeneration = generation" in lock
    assert "Fail open" not in abort
    assert "planOwnsWindowBeforeDispatch" not in abort


def test_out_of_combat_is_a_hard_autoburst_boundary_without_bridge_authority() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    signal = read(ADDON / "Signal" / "SignalFrame.lua")
    assert "Hard encounter boundary. This runs before the enable check" in auto
    assert 'self:Abort("out_of_combat", true)' in auto
    assert 'local paused, pauseReason = isRuntimePaused(self, runtime)' in auto
    assert "canStartPreCombatBridge" not in auto
    assert "runtimeAllowsPreCombatBridge" not in auto
    assert "precombat_burst_bridge_combat_entered" not in auto
    assert 'local preCombatBurstBridgeFrame = false' in signal
    assert 'TE.AutoBurst:AuthorizePreCombatBridge("signal_state_armed")' not in signal


def test_world_transition_and_legacy_authorize_are_diagnostic_only_not_dispatch_authority() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    mapping = read(ADDON / "Diagnostics" / "MappingExport.lua")
    for token in (
        "PLAYER_LEAVING_WORLD",
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "ActivateWorldTransitionFence",
        "AuthorizePreCombatBridge",
        "precombat_bridge_removed",
        "preCombatBridgeWorldFence",
    ):
        assert token in auto
    assert "preCombatBridgeWorldFence" in mapping
    assert "lastWorldTransitionReason" in mapping


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
    assert "message.observationOnly == true and officialBinding" in tactical
    assert "message.binding or binding.binding or binding.rawBinding" in tactical
    assert "displayBindingToken" in tactical
    assert "message.observationOnly ~= true" in tactical


def test_autoburst_reads_fresh_spell_and_gcd_snapshots_for_each_step() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    icon = read(ADDON / "Tactics" / "IconState.lua")
    assert "liveCooldown = true" in auto
    assert "liveOnly = options.liveCooldown == true" in icon
    assert "spellCooldown(GLOBAL_COOLDOWN_SPELL_ID, {" in icon
    assert "liveOnly = true" in icon
    assert "liveApiAuthoritative" in icon


def test_front_window_cooldown_or_unknown_conflict_creates_persistent_latched_plan_instead_of_official_fallback() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "isOfficialWindowAvailabilityConflict" in auto
    assert "plan_gate_window_official_cooldown_conflict" in auto
    assert "window_official_cooldown_revalidate" in auto
    assert "observeLatchedPlanOfficialDeparture" in auto
    assert "official_window_departed_plan_latched" in auto
    assert "burst_window_not_ready" in auto


def test_plan_creation_requires_both_window_and_injection_bindings() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "validateRuleBindings" in auto
    assert "plan_gate_binding" in auto
    assert "burst_binding_not_ready" in auto
    assert auto.index("local bindingsReady") < auto.rindex("createPlan(self, rule, officialSpellID")


def test_runtime_unknown_optional_step_is_skipped_only_in_simple_mode() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "runtime_optional_unavailable" in auto
    assert "skipOptionalStep" in auto
    assert 'plan.rule and plan.rule.mode == "simple"' in auto
    assert "focused_optional_step_unavailable" in auto
    assert "sequence_optional_step_skipped" in auto
    assert "UNKNOWN is not cooldown" in auto


def test_hud_model_sanitizes_cast_timing_fields_used_by_effects() -> None:
    model = read(ADDON / "UI" / "TacticalHudModel.lua")
    effects = read(ADDON / "UI" / "TacticalIconEffects.lua")
    assert '"castingStartTimeMS"' in model
    assert '"castingEndTimeMS"' in model
    assert "item.castingStartTimeMS" in effects
    assert "item.castingEndTimeMS" in effects


def test_autoburst_exports_generation_and_candidate_diagnostics() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    mapping = read(ADDON / "Diagnostics" / "MappingExport.lua")
    for token in (
        "armedEpoch",
        "firstHealthyFramePending",
        "windowGeneration",
        "consumedWindowGeneration",
        "activePlanGeneration",
        "departureLockGeneration",
        "lastConfirmationSource",
        "lastAbortReason",
        "lastWindowRejectReason",
    ):
        assert token in auto
        assert token in mapping
    for token in ("officialBinding", "dispatchBinding", "stepStatusReason", "candidateOfferCount"):
        assert token in mapping


def test_cooldown_text_is_unified_hud_badge_only_without_autoburst_dependency() -> None:
    defaults = read(ADDON / "Config" / "Defaults.lua")
    normalize = read(ADDON / "Config" / "Normalize.lua")
    button = read(ADDON / "UI" / "TacticalIconButton.lua")
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert 'mode = "custom"' in defaults
    # Legacy SavedVariables are normalized to the HUD-owned label; no stored
    # mode can restore Blizzard DurationObject countdown digits.
    assert 'style.mode = "custom"' in normalize
    assert "priorSchema < 10" in normalize
    assert 'cooldownText.mode = "custom"' in normalize
    assert "cooldownTextMode" in button
    assert 'return "custom"' in button
    assert "pcall(frame.SetHideCountdownNumbers, frame, true)" in button
    assert "nativeNumericFallback" not in button
    assert 'preferExactDirectActionbarDigits' not in button
    assert "cooldownText(" not in auto


def test_armed_rebase_and_priority_ring_preserve_field_diagnostics() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    mapping = read(ADDON / "Diagnostics" / "MappingExport.lua")
    assert "armed_window_observation_rebased" in auto
    assert "paused_to_armed_observation_rebase" in auto
    assert "PRIORITY_LOG_EVENTS" in auto
    assert "priorityEvents" in auto
    assert "QUIET_DECISION_LOG_MIN_SECONDS" in auto
    assert "lastArmedRebase" in mapping
    assert "recentPriorityEvents" in mapping


def test_unknown_and_cooldown_verification_icons_are_not_rendered_as_confirmed_gray_cooldown() -> None:
    styles = read(ADDON / "UI" / "TacticalHudStyles.lua")
    button = read(ADDON / "UI" / "TacticalIconButton.lua")
    assert 'return "burst_check"' in styles
    assert 'item.burstVerificationPending == true' in styles
    assert 'General post-cast cooldown tracking remains internal' in styles
    assert '"校验", false' in styles
    assert 'or item.usableState == "unknown"' not in button



def test_fresh_dispatchable_frames_advance_teap_sequence_for_burst_and_official_candidates() -> None:
    signal = read(ADDON / "Signal" / "SignalFrame.lua")
    assert "freshDispatchableFrame" in signal
    assert "Give every dispatchable armed frame a fresh" in signal
    assert "if freshDispatchableFrame then" in signal
    assert "sequence = sequence + 1" in signal


def test_official_window_cooldown_conflict_creates_bounded_plan_and_revalidates_before_dispatch() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    assert "isOfficialWindowAvailabilityConflict" in auto
    assert "plan_gate_window_official_cooldown_conflict" in auto
    assert "window_official_cooldown_revalidate" in auto
    assert "windowAvailabilityConflict" in auto
    assert "official_window_" in auto


def test_pre_window_capture_owns_front_window_before_teap_binding_and_faults_fail_closed() -> None:
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    signal = read(ADDON / "Signal" / "SignalFrame.lua")
    mapping = read(ADDON / "Diagnostics" / "MappingExport.lua")
    assert "preWindowCapture" in auto
    assert "pre_window_capture_handoff_barrier" in auto
    assert "PRE_WINDOW_HANDOFF_MIN_HOLD_FRAMES = 4" in auto
    assert "transportHandoffTick" in signal
    assert "isTransportHandoffTick(runtime)" in auto
    assert "pre_window_capture_handoff_ready" in auto
    assert "handoffBarrierRequiredFrames" in mapping
    assert "handoffBarrierRemainingFrames" in mapping
    assert "handoffBarrierPublishedFrames" in mapping
    assert "pre_window_capture_binding_pending" in auto
    assert "pre_window_capture_window_pending" in auto
    assert "lockPreWindowCaptureDeparture" in auto
    assert 'tostring(reason or "") == "evaluator_fault"' in auto
    assert "preWindowCaptureActive == true" in signal
    assert "heldBeforeAbort" in signal
    assert 'reason = "burst_evaluator_fault_hold"' in signal


def test_ordered_sequence_supports_window_three_injections_and_two_trinkets_per_spec() -> None:
    profiles = read(ADDON / "Tactics" / "BurstProfiles.lua")
    auto = read(ADDON / "Tactics" / "AutoBurst.lua")
    ui = read(ADDON / "UI" / "ControlPanel.lua")
    assert '"window"' in profiles
    assert '"trinket:13"' in profiles
    assert '"trinket:14"' in profiles
    assert '"injection:"' in profiles
    assert "AUTO_BURST_MAX_INJECTIONS = 3" in profiles
    assert "stable action identities" in profiles
    assert "selectedRuleForSequence" in auto
    assert "sequence_preflight_selected" in auto
    assert "sequence_preflight_no_eligible" in auto
    assert "爆发顺序（当前专精）" in ui
    assert "注入技能 1–3" in ui
    assert "Phase 1.5 测试规则" not in ui
    assert "官方窗口 SpellID" not in ui
