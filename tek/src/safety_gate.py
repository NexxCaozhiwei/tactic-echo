from dataclasses import dataclass

from tek.src.action_catalog import ActionCatalog, RETRIBUTION_V2
from tek.src.profile_resolver import Profile
from tek.src.teap import PROTOCOL_VERSION
from tek.src.binding_tokens import decode_binding_token, BindingTokenError


NON_DISPATCH_PAUSE_STATES = frozenset({"paused", "manual_hold", "channeling", "empowering"})
NON_DISPATCH_WAITING_STATES = frozenset({"waiting"})


@dataclass(frozen=True)
class ForegroundSnapshot:
    ok: bool
    reason: str = "foreground_ok"
    hwnd: int | None = None
    process_id: int | None = None
    title: str | None = None
    process_name: str | None = None
    executable_path: str | None = None


@dataclass
class SafetyContext:
    tek_armed: bool = True
    wow_foreground: bool = True
    last_sequence: int = -1
    bootstrapped: bool = False
    current_session_epoch: int | None = None
    last_action_sequence: int | None = None
    last_frame_freshness_counter: int | None = None
    # AutoBurst re-offers one logical candidate for a short sampler-observation
    # window. Remember the native attempt so fresh duplicate frames cannot
    # produce a second physical keypress.
    last_burst_dispatch_sequence: int | None = None
    last_burst_dispatch_freshness: int | None = None
    state: str = "Waiting"
    dispatch_budget: int | None = None
    foreground_before_read: ForegroundSnapshot | None = None
    foreground_before_dispatch: ForegroundSnapshot | None = None
    require_start_toggle: bool = False
    # Only the UI-linked runtime opts in. CLI/dry-run callers retain their
    # bootstrap observation record for deterministic diagnostics.
    allow_initial_armed_dispatch: bool = False
    start_toggle_seen_disarmed: bool = False
    start_toggle_released: bool = False
    expected_protocol_version: int | None = None


class SafetyGate:
    def __init__(self, catalog: ActionCatalog = RETRIBUTION_V2, profile: Profile | None = None):
        self.catalog = catalog
        self.profile = profile

    def evaluate(self, frame, context: SafetyContext, *, send_input: bool = False) -> tuple[bool, str]:
        if context.state == "ErrorLocked":
            return False, "error_locked"
        if not context.tek_armed:
            context.state = "Paused"
            return False, "tek_not_armed"
        if frame.protocol_version != PROTOCOL_VERSION:
            context.state = "Blocked"
            return False, f"unsupported_protocol_version:{frame.protocol_version}"
        # The protocol is v3-only. Keep the optional expected value as a
        # caller-side assertion for tests and future explicit deployments, but
        # never accept a legacy version as a compatibility path.
        if context.expected_protocol_version is not None and context.expected_protocol_version != PROTOCOL_VERSION:
            context.state = "Blocked"
            return False, f"invalid_expected_protocol_version:{context.expected_protocol_version}"
        if frame.observation_only:
            context.state = "Waiting"
            return False, "observation_frame"

        # An authenticated TEAP non-dispatch state is authoritative for the
        # current tick.  A paused/waiting/manual_hold frame must never be
        # relabelled as a catalog or binding failure merely because its action
        # metadata is intentionally empty or temporarily stale.  The decoder
        # has already validated RGB, commit and CRC before SafetyGate sees it.
        # CLI start-toggle observation still records the disarmed transition,
        # but preserves the actual plugin state for UI and diagnostics.
        if frame.state in NON_DISPATCH_PAUSE_STATES:
            if send_input and context.require_start_toggle and not context.start_toggle_released:
                context.start_toggle_seen_disarmed = True
            context.state = "Paused"
            return False, f"frame_state_{frame.state}"
        if frame.state in NON_DISPATCH_WAITING_STATES:
            if send_input and context.require_start_toggle and not context.start_toggle_released:
                context.start_toggle_seen_disarmed = True
            context.state = "Waiting"
            return False, f"frame_state_{frame.state}"
        if frame.state != "armed":
            context.state = self._non_dispatch_context_state(frame.state)
            return False, f"frame_state_{frame.state}"

        # Catalog/action binding validation applies only to dispatchable armed
        # frames.  This preserves fail-closed input safety while keeping TEAP
        # pause/wait/manual ownership visible as their real state.
        if frame.catalog_version != self.catalog.version:
            context.state = "Blocked"
            return False, f"catalog_version_mismatch:{frame.catalog_version}:{self.catalog.version}"
        if frame.catalog_fingerprint != self.catalog.fingerprint16:
            context.state = "Blocked"
            return False, f"catalog_fingerprint_mismatch:{frame.catalog_fingerprint}:{self.catalog.fingerprint16}"

        # Explicit CLI safety mode may still require a non-armed frame before
        # releasing. UI-linked SendInput does not: once its first real armed
        # frame satisfies the ordinary protocol, foreground and freshness gates,
        # it may dispatch immediately rather than requiring an artificial
        # pause→arm round trip in-game.
        if send_input and context.require_start_toggle and not context.start_toggle_released:
            if not context.start_toggle_seen_disarmed:
                context.state = "Blocked"
                return False, "awaiting_start_toggle"
            context.start_toggle_released = True

        try:
            decode_binding_token(frame.binding_token)
        except BindingTokenError as error:
            context.state = "Blocked"
            return False, f"binding_token_invalid:{error}"

        foreground_ok, foreground_reason = self._evaluate_foreground(context)
        if not foreground_ok:
            context.state = "Blocked"
            return False, foreground_reason

        if context.current_session_epoch is None:
            context.current_session_epoch = frame.session_epoch
            context.last_action_sequence = None
            context.last_frame_freshness_counter = None
            context.last_burst_dispatch_sequence = None
            context.last_burst_dispatch_freshness = None
        elif context.current_session_epoch != frame.session_epoch:
            context.current_session_epoch = frame.session_epoch
            context.last_action_sequence = None
            context.last_frame_freshness_counter = None
            context.last_burst_dispatch_sequence = None
            context.last_burst_dispatch_freshness = None
            context.bootstrapped = False

        # Preserve the dry-run/bootstrap diagnostic path. The real UI-linked
        # dispatcher deliberately accepts the first valid armed frame after the
        # foreground check, removing the previous one-frame startup delay.
        if not context.bootstrapped:
            context.bootstrapped = True
            if not context.allow_initial_armed_dispatch:
                # Record the bootstrap frame as observed even though dry-run /
                # CLI mode does not dispatch it. Replaying that same captured
                # freshness value on the next tick must still be rejected.
                context.last_frame_freshness_counter = frame.frame_freshness_counter
                context.state = "Bootstrap"
                return False, "bootstrap_observing_session"

        if context.last_frame_freshness_counter is not None:
            freshness_delta = sequence_delta(frame.frame_freshness_counter, context.last_frame_freshness_counter)
            if freshness_delta == 0:
                context.state = "Blocked"
                return False, "stale_frame_freshness"
            if freshness_delta > 32768:
                context.state = "Blocked"
                return False, "old_frame_freshness"
        context.last_frame_freshness_counter = frame.frame_freshness_counter

        if context.last_action_sequence is not None:
            delta = sequence_delta(frame.sequence, context.last_action_sequence)
            if delta > 32768:
                context.state = "Blocked"
                return False, "old_action_sequence"

        # A Burst candidate remains visible until the AddOn sees success,
        # explicit invalidation or its bounded deadline. It keeps one stable
        # sequence for that entire logical attempt. Once TEK has attempted it,
        # never send it again; a controlled retry/next step gets a new sequence.
        if frame.dispatch_origin == "burst" and context.last_burst_dispatch_sequence == frame.sequence:
            context.state = "Armed"
            return False, "burst_sequence_already_dispatched"

        if send_input and context.dispatch_budget is not None and context.dispatch_budget <= 0:
            context.state = "Blocked"
            return False, "dispatch_budget_exhausted"

        context.state = "Armed"
        return True, "gate_passed"

    @staticmethod
    def _non_dispatch_context_state(frame_state: str) -> str:
        if frame_state in NON_DISPATCH_PAUSE_STATES:
            return "Paused"
        if frame_state in NON_DISPATCH_WAITING_STATES:
            return "Waiting"
        return "Blocked"

    def mark_dispatched(self, frame, context: SafetyContext, *, sent: bool, attempted: bool = False) -> None:
        context.last_sequence = frame.sequence
        context.last_action_sequence = frame.sequence
        # "attempted" is intentionally broader than native sent=True. A
        # Windows dispatcher can report a non-sent/ambiguous result after a
        # native attempt; repeating the same burst offer would be less safe than
        # waiting for the normal confirmation timeout and one controlled retry.
        if attempted and getattr(frame, "dispatch_origin", "official") == "burst":
            context.last_burst_dispatch_sequence = frame.sequence
            context.last_burst_dispatch_freshness = frame.frame_freshness_counter
        if sent:
            if context.dispatch_budget is not None:
                context.dispatch_budget -= 1

    def lock_error(self, context: SafetyContext) -> None:
        context.state = "ErrorLocked"

    def _evaluate_foreground(self, context: SafetyContext) -> tuple[bool, str]:
        before = context.foreground_before_read
        after = context.foreground_before_dispatch
        if before is None and after is None:
            return (context.wow_foreground, "foreground_not_game" if not context.wow_foreground else "foreground_ok")
        for snapshot in (before, after):
            if snapshot and not snapshot.ok:
                return False, snapshot.reason
        if before and after:
            if before.hwnd != after.hwnd or before.process_id != after.process_id:
                return False, "foreground_changed_before_dispatch"
        return True, "foreground_ok"


def sequence_delta(current: int, previous: int) -> int:
    return (current - previous) % 65536
