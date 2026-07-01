from dataclasses import dataclass

from tek.src.action_catalog import ActionCatalog, ActionCatalogError
from tek.src.input_planner import DispatchResult, DryRunInputDispatcher, InputPlan, InputPlanError, plan_binding
from tek.src.binding_tokens import decode_binding_token
from tek.src.dispatch_rate_limiter import DispatchRateLimiter
from tek.src.dispatch_failure_tracker import DispatchFailureTracker
from tek.src.profile_resolver import ProfileResolver
from tek.src.safety_gate import SafetyContext, SafetyGate
from tek.src.teap import TEAPFrame


@dataclass(frozen=True)
class TraceRecord:
    accepted: bool
    reason: str
    sequence: int
    state: str
    action_code: int
    dispatcher_backend: str
    gatePassed: bool = False
    dispatchAttempted: bool = False
    inputSent: bool = False
    partialFailure: bool = False
    dispatchBlocked: bool = False
    dispatchError: str | None = None
    tekState: str = "Waiting"
    protocol_version: int | None = None
    session_epoch: int | None = None
    frame_freshness_counter: int | None = None
    catalog_version: int | None = None
    catalog_fingerprint: int | None = None
    in_combat: bool | None = None
    target_casting: bool = False
    target_interruptible: bool = False
    player_health_critical: bool = False
    monitor_flags: int = 0
    checksum: int | None = None
    raw_fields: tuple[int, ...] | None = None
    action_id: str | None = None
    binding: str | None = None
    binding_token: int | None = None
    input_plan: InputPlan | None = None
    dispatch_result: DispatchResult | None = None
    diagnostics: dict | None = None


class TEKEngine:
    def __init__(
        self,
        catalog: ActionCatalog,
        profile_resolver: ProfileResolver,
        safety_gate: SafetyGate | None = None,
        input_dispatcher=None,
        rate_limiter: DispatchRateLimiter | None = None,
        failure_tracker: DispatchFailureTracker | None = None,
        physical_input_guard=None,
        physical_input_monitor=None,
    ):
        self.catalog = catalog
        self.profile_resolver = profile_resolver
        self.safety_gate = safety_gate or SafetyGate(catalog=catalog, profile=profile_resolver.profile)
        self.input_dispatcher = input_dispatcher or DryRunInputDispatcher()
        self.dispatcher_backend = getattr(self.input_dispatcher, "backend", "unknown")
        self.send_input = self.dispatcher_backend != "dry_run"
        self.rate_limiter = rate_limiter or DispatchRateLimiter()
        self.failure_tracker = failure_tracker or DispatchFailureTracker()
        self.physical_input_guard = physical_input_guard
        self.physical_input_monitor = physical_input_monitor

    def _runtime_diagnostics(self) -> dict:
        diagnostics = {
            "rate_limiter": self.rate_limiter.snapshot(),
            "dispatch_failures": self.failure_tracker.snapshot(),
        }
        guard = self.physical_input_guard
        reporter = getattr(guard, "diagnostics", None)
        if callable(reporter):
            diagnostics["physical_input"] = reporter()
        monitor = self.physical_input_monitor
        reporter = getattr(monitor, "diagnostics", None)
        if callable(reporter):
            diagnostics["physical_input"] = reporter()
        return diagnostics

    def _hook_block_reason(self) -> str | None:
        """Fail closed only for the real Windows SendInput backend.

        Unit-test/fake backends keep their existing safety-gate tests and dry
        runs deliberately do not require a Windows hook. A real dispatch path
        must never send while the physical-input monitor is absent, starting,
        failed, or has lost its hook thread.
        """
        if self.dispatcher_backend != "windows_sendinput":
            return None
        monitor = self.physical_input_monitor
        if monitor is None:
            return "physical_input_hook_unavailable"
        checker = getattr(monitor, "health_reason", None)
        if callable(checker):
            reason = checker()
            return str(reason) if reason else None
        healthy = getattr(monitor, "is_healthy", None)
        if callable(healthy) and healthy():
            return None
        return "physical_input_hook_unhealthy"

    def _manual_gate_reason(self, frame: TEAPFrame) -> str | None:
        guard = self.physical_input_guard
        if guard is None:
            return None
        teap_state = getattr(guard, "observe_teap_state", None)
        if callable(teap_state):
            teap_state(frame.state)
        observe_freshness = getattr(guard, "observe_freshness", None)
        if callable(observe_freshness):
            observe_freshness(frame.frame_freshness_counter)
        decision = getattr(guard, "dispatch_block_reason", None)
        if callable(decision):
            return decision(binding_token=frame.binding_token, action_sequence=frame.sequence)
        # Compatibility for a simple guard used by historical tests/custom
        # runners. The new gate always exposes dispatch_block_reason.
        checker = getattr(guard, "is_paused", None)
        return "physical_input_pause" if callable(checker) and checker() else None

    def _manual_epoch(self) -> int | None:
        guard = self.physical_input_guard
        getter = getattr(guard, "epoch", None)
        if callable(getter):
            return int(getter())
        value = getattr(guard, "manual_epoch", None)
        return int(value) if isinstance(value, int) else None

    def _consume_manual_frame(self, frame: TEAPFrame, context: SafetyContext, reason: str) -> TraceRecord:
        # This visible frame is intentionally consumed while ownership belongs
        # to the player. A recovery phase must therefore observe new TEAP
        # freshness rather than dispatch a frame seen during manual input.
        context.last_frame_freshness_counter = frame.frame_freshness_counter
        context.last_action_sequence = frame.sequence
        context.state = "Paused"
        return self._trace(
            frame,
            context,
            accepted=False,
            reason=reason,
            dispatch_blocked=True,
            diagnostics=self._runtime_diagnostics(),
        )

    def _reserve_rate_slot(self, input_plan: InputPlan):
        # Go through the historical ``allow`` entry point so existing wrappers
        # and instrumentation still observe the reservation. The built-in
        # limiter exposes the matching one-shot claim API, letting TEK roll the
        # exact provisional slot back if a late safety gate blocks dispatch.
        allow = getattr(self.rate_limiter, "allow", None)
        if callable(allow):
            allowed, reason = allow(input_plan)
            if not allowed:
                return None, reason
            claim = getattr(self.rate_limiter, "claim_last_allow_reservation", None)
            reservation = claim() if callable(claim) else object()
            return reservation, reason
        reserve = getattr(self.rate_limiter, "reserve", None)
        if callable(reserve):
            return reserve(input_plan)
        raise RuntimeError("rate_limiter_missing_allow")

    def _rollback_rate_slot(self, reservation) -> None:
        rollback = getattr(self.rate_limiter, "rollback", None)
        if callable(rollback):
            rollback(reservation)

    def _commit_rate_slot(self, reservation) -> None:
        commit = getattr(self.rate_limiter, "commit", None)
        if callable(commit):
            commit(reservation)

    def _classify_dispatch_result(self, dispatch_result: DispatchResult | None) -> str:
        """Classify a completed dispatcher call without over-escalating config errors."""
        if dispatch_result is None:
            return "system_failure"
        if dispatch_result.sent:
            return "success"
        reason = str(dispatch_result.reason or "dispatch_not_sent")
        # Dry-run is a successful simulation, not a native SendInput failure.
        if self.dispatcher_backend == "dry_run" or reason == "dry_run_planned":
            return "success"
        if reason.startswith("sendinput_partial") or reason.startswith("sendinput_exception"):
            return "system_failure"
        # Unknown/unsupported key mappings are deterministic configuration
        # issues. They must show blocked diagnostics but never consume the
        # dispatch-failure budget or push the worker into ErrorLocked.
        if reason.startswith(("unsupported_key:", "invalid_binding:", "binding_")):
            return "mapping_blocked"
        # A dispatcher that explicitly reports no send but no native failure is
        # still non-dispatchable. Treat it as blocked rather than escalating a
        # worker-wide native failure on ambiguous data.
        return "mapping_blocked"

    def process_frame(self, frame: TEAPFrame, context: SafetyContext) -> TraceRecord:
        hook_reason = self._hook_block_reason()
        if hook_reason:
            context.state = "Blocked"
            return self._trace(
                frame,
                context,
                accepted=False,
                reason=hook_reason,
                dispatch_blocked=True,
                diagnostics=self._runtime_diagnostics(),
            )

        manual_reason = self._manual_gate_reason(frame)
        if manual_reason:
            return self._consume_manual_frame(frame, context, manual_reason)

        accepted, reason = self.safety_gate.evaluate(frame, context, send_input=self.send_input)
        if not accepted:
            return self._trace(
                frame,
                context,
                accepted=False,
                reason=reason,
                dispatch_blocked=True,
                diagnostics=self._runtime_diagnostics(),
            )

        epoch_before = self._manual_epoch()
        action_id = None
        binding = None
        input_plan = None
        dispatch_result = None
        reservation = None
        dispatch_started = False
        try:
            decoded = decode_binding_token(frame.binding_token)
            binding = decoded.binding
            # TEAP v3 dispatches an explicit BindingToken. A nonzero action code
            # remains trace-only and may belong to a currently unlisted spell.
            if frame.action_code > 0:
                try:
                    action_id = self.catalog.resolve(frame.action_code)
                except ActionCatalogError:
                    action_id = None
            input_plan = plan_binding(binding)
            reservation, limiter_reason = self._reserve_rate_slot(input_plan)
            if reservation is None:
                self.safety_gate.mark_dispatched(frame, context, sent=False)
                return self._trace(
                    frame,
                    context,
                    accepted=True,
                    reason=limiter_reason,
                    gate_passed=True,
                    dispatch_blocked=True,
                    action_id=action_id,
                    binding=binding,
                    binding_token=frame.binding_token,
                    input_plan=input_plan,
                    diagnostics=self._runtime_diagnostics(),
                )

            # The second check closes the race between initial frame gating and
            # SendInput. Any real keydown during parsing/rate limiting increments
            # manualEpoch and prevents this frame from being dispatched. The rate
            # slot is provisional until dispatch begins and is returned on any
            # such late gate rejection.
            hook_reason = self._hook_block_reason()
            if hook_reason:
                self._rollback_rate_slot(reservation)
                context.state = "Blocked"
                return self._trace(
                    frame,
                    context,
                    accepted=False,
                    reason=hook_reason,
                    gate_passed=True,
                    dispatch_blocked=True,
                    action_id=action_id,
                    binding=binding,
                    binding_token=frame.binding_token,
                    input_plan=input_plan,
                    diagnostics=self._runtime_diagnostics(),
                )
            epoch_after = self._manual_epoch()
            if epoch_before is not None and epoch_after is not None and epoch_after != epoch_before:
                self._rollback_rate_slot(reservation)
                return self._consume_manual_frame(frame, context, "manual_epoch_changed")
            guard = self.physical_input_guard
            decision = getattr(guard, "dispatch_block_reason", None)
            if callable(decision):
                late_reason = decision(binding_token=frame.binding_token, action_sequence=frame.sequence)
                if late_reason:
                    self._rollback_rate_slot(reservation)
                    return self._consume_manual_frame(frame, context, late_reason)

            # Once dispatch begins, retain the slot even if Windows reports a
            # partial/native failure: part of the input sequence may have reached
            # the foreground process.
            self._commit_rate_slot(reservation)
            dispatch_started = True
            dispatch_result = self.input_dispatcher.dispatch(input_plan)
        except InputPlanError as error:
            # Input-plan errors are deterministic mapping failures; no native
            # SendInput attempt has a meaningful payload to preserve, so their
            # provisional rate slot is always returned.
            self._rollback_rate_slot(reservation)
            context.state = "Blocked"
            result_reason = f"binding_plan_invalid:{error}"
            return self._trace(
                frame,
                context,
                accepted=False,
                reason=result_reason,
                gate_passed=True,
                dispatch_blocked=True,
                dispatch_error=result_reason,
                action_id=action_id,
                binding=binding,
                binding_token=frame.binding_token,
                input_plan=input_plan,
                diagnostics=self._runtime_diagnostics(),
            )
        except Exception as error:
            if not dispatch_started:
                self._rollback_rate_slot(reservation)
            self._release_modifiers(input_plan)
            locked, failure_state = self.failure_tracker.record_failure()
            if locked:
                self.safety_gate.lock_error(context)
            else:
                context.state = "Blocked"
            return self._trace(
                frame,
                context,
                accepted=True,
                reason=(f"dispatch_exception:{type(error).__name__}:{error}" + (":error_locked" if locked else ":blocked_retry")),
                gate_passed=True,
                dispatch_attempted=dispatch_started,
                dispatch_error=f"{type(error).__name__}:{error}",
                action_id=action_id,
                binding=binding,
                binding_token=frame.binding_token,
                input_plan=input_plan,
                dispatch_result=dispatch_result,
                diagnostics={**self._runtime_diagnostics(), "dispatch_failures": failure_state},
            )

        outcome = self._classify_dispatch_result(dispatch_result)
        result_reason = dispatch_result.reason if dispatch_result else "dispatch_missing_result"
        partial_failure = bool(dispatch_result and dispatch_result.reason.startswith("sendinput_partial"))
        if outcome == "system_failure":
            self._release_modifiers(input_plan)
            locked, failure_state = self.failure_tracker.record_failure()
            if locked:
                self.safety_gate.lock_error(context)
            else:
                context.state = "Blocked"
            result_reason = result_reason + (":error_locked" if context.state == "ErrorLocked" else ":blocked_retry")
            diagnostics = {**self._runtime_diagnostics(), "dispatch_failures": failure_state}
            return self._trace(
                frame,
                context,
                accepted=True,
                reason=result_reason,
                gate_passed=True,
                dispatch_attempted=True,
                partial_failure=partial_failure,
                dispatch_error=dispatch_result.reason if dispatch_result else "dispatch_missing_result",
                action_id=action_id,
                binding=binding,
                binding_token=frame.binding_token,
                input_plan=input_plan,
                dispatch_result=dispatch_result,
                diagnostics=diagnostics,
            )

        if outcome == "mapping_blocked":
            # No successful/native input was sent. Return the provisional rate
            # slot so a valid subsequent recommendation is not rate-limited.
            self._rollback_rate_slot(reservation)
            context.state = "Blocked"
            return self._trace(
                frame,
                context,
                accepted=False,
                reason=result_reason,
                gate_passed=True,
                dispatch_attempted=True,
                dispatch_blocked=True,
                dispatch_error=result_reason,
                action_id=action_id,
                binding=binding,
                binding_token=frame.binding_token,
                input_plan=input_plan,
                dispatch_result=dispatch_result,
                diagnostics=self._runtime_diagnostics(),
            )

        self.failure_tracker.record_success()
        self.safety_gate.mark_dispatched(frame, context, sent=bool(dispatch_result and dispatch_result.sent))
        if dispatch_result and dispatch_result.sent:
            recorder = getattr(self.physical_input_guard, "note_auto_dispatch", None)
            if callable(recorder):
                recorder(frame.binding_token, frame.sequence)

        return self._trace(
            frame,
            context,
            accepted=True,
            reason=result_reason,
            gate_passed=True,
            dispatch_attempted=True,
            input_sent=bool(dispatch_result and dispatch_result.sent),
            action_id=action_id,
            binding=binding,
            binding_token=frame.binding_token,
            input_plan=input_plan,
            dispatch_result=dispatch_result,
            diagnostics=self._runtime_diagnostics(),
        )

    def _trace(self, frame: TEAPFrame, context: SafetyContext, **kwargs) -> TraceRecord:
        return TraceRecord(
            accepted=kwargs.get("accepted", False),
            reason=kwargs.get("reason", "unknown"),
            sequence=frame.sequence,
            state=frame.state,
            action_code=frame.action_code,
            dispatcher_backend=self.dispatcher_backend,
            gatePassed=kwargs.get("gate_passed", False),
            dispatchAttempted=kwargs.get("dispatch_attempted", False),
            inputSent=kwargs.get("input_sent", False),
            partialFailure=kwargs.get("partial_failure", False),
            dispatchBlocked=kwargs.get("dispatch_blocked", False),
            dispatchError=kwargs.get("dispatch_error"),
            tekState=context.state,
            protocol_version=frame.protocol_version,
            session_epoch=frame.session_epoch,
            frame_freshness_counter=frame.frame_freshness_counter,
            catalog_version=frame.catalog_version,
            catalog_fingerprint=frame.catalog_fingerprint,
            in_combat=frame.in_combat,
            target_casting=frame.target_casting,
            target_interruptible=frame.target_interruptible,
            player_health_critical=frame.player_health_critical,
            monitor_flags=frame.monitor_flags,
            checksum=frame.checksum,
            raw_fields=frame.raw_fields,
            action_id=kwargs.get("action_id"),
            binding=kwargs.get("binding"),
            binding_token=kwargs.get("binding_token", frame.binding_token),
            input_plan=kwargs.get("input_plan"),
            dispatch_result=kwargs.get("dispatch_result"),
            diagnostics=kwargs.get("diagnostics"),
        )

    def _release_modifiers(self, input_plan: InputPlan | None) -> None:
        releaser = getattr(self.input_dispatcher, "release_modifiers", None)
        if callable(releaser):
            releaser(input_plan)
