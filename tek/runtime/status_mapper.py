from __future__ import annotations

from datetime import datetime, timezone

from tek.src.engine import TraceRecord
from tek.runtime.runtime_status import TEKStatusSnapshot, utc_now_iso


COLOR_BY_PROCESS_STATE = {
    "Stopped": "gray",
    "Starting": "blue",
    "Waiting": "blue",
    "WaitingForForeground": "blue",
    "Bootstrap": "blue",
    "Paused": "yellow",
    "AwaitingStartToggle": "yellow",
    "DryRunReady": "blue",
    "Armed": "green",
    "Blocked": "red",
    "Stale": "yellow",
    "ErrorLocked": "red",
    "WorkerExited": "red",
    "Stopping": "yellow",
}


def trace_record_to_snapshot(
    record: TraceRecord,
    *,
    mode: str,
    started_at: str | None,
    trace_path: str | None,
    log_dir: str | None = None,
    worker_alive: bool = True,
) -> TEKStatusSnapshot:
    process_state = map_process_state(record)
    return TEKStatusSnapshot(
        process_state=process_state,
        safety_state=record.tekState,
        mode=mode,
        started_at=started_at,
        updated_at=utc_now_iso(),
        signal_found=record.sequence >= 0,
        wow_foreground=_wow_foreground_from_reason(record.reason),
        last_reason=record.reason,
        last_action_code=record.action_code,
        last_action_id=record.action_id,
        last_binding=record.binding,
        last_gate_passed=record.gatePassed,
        last_input_sent=record.inputSent,
        error_message=record.dispatchError,
        trace_path=trace_path,
        worker_alive=worker_alive,
        log_dir=log_dir,
        foreground_diagnostics=(record.diagnostics or {}).get("foreground"),
        signal_diagnostics=(record.diagnostics or {}).get("signal"),
        reason_counts=(record.diagnostics or {}).get("reason_counts"),
        last_protocol_version=record.protocol_version,
        last_binding_token=record.binding_token,
        last_result=record.reason,
        last_in_combat=record.in_combat,
        monitor_flags=record.monitor_flags,
        last_target_casting=record.target_casting,
        last_target_interruptible=record.target_interruptible,
        last_player_health_critical=record.player_health_critical,
        rate_limiter=(record.diagnostics or {}).get("rate_limiter"),
        dispatch_failures=(record.diagnostics or {}).get("dispatch_failures"),
        physical_input_diagnostics=(record.diagnostics or {}).get("physical_input"),
    )


def map_process_state(record: TraceRecord) -> str:
    if record.reason in ("window_process_mismatch", "foreground_not_game", "window_handle_invalid") or record.reason.startswith("foreground_"):
        return "WaitingForForeground"
    if record.reason.startswith("frame_read_error"):
        return "Waiting"
    if record.tekState == "ErrorLocked":
        return "ErrorLocked"
    if record.dispatchError:
        return "Blocked"
    if record.reason == "bootstrap_observing_session":
        return "Bootstrap"
    if record.reason == "awaiting_start_toggle":
        return "AwaitingStartToggle"
    if record.reason == "stale_frame_freshness":
        return "Stale"
    if record.tekState == "Paused":
        return "Paused"
    if record.tekState == "Blocked":
        return "Blocked"
    if record.tekState == "Armed":
        return "Armed"
    if record.tekState == "Bootstrap":
        return "Bootstrap"
    return "Waiting"


def status_color(snapshot: TEKStatusSnapshot) -> str:
    if snapshot.process_state == "Armed":
        return "green"
    if snapshot.process_state in ("Blocked", "ErrorLocked", "WorkerExited"):
        return "red"
    if snapshot.process_state in ("Paused", "AwaitingStartToggle", "Stale", "Stopping"):
        return "yellow"
    return COLOR_BY_PROCESS_STATE.get(snapshot.process_state, "blue")


def is_snapshot_stale(snapshot: TEKStatusSnapshot, *, max_age_seconds: float = 2.0) -> bool:
    updated_at = datetime.fromisoformat(snapshot.updated_at)
    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - updated_at).total_seconds() > max_age_seconds


def stale_snapshot(snapshot: TEKStatusSnapshot) -> TEKStatusSnapshot:
    return TEKStatusSnapshot(
        **{
            **snapshot.to_dict(),
            "process_state": "Stale",
            "safety_state": "Stale",
            "updated_at": utc_now_iso(),
        }
    )


def tooltip_text(snapshot: TEKStatusSnapshot) -> str:
    action = snapshot.last_action_id or "-"
    return "\n".join(
        [
            f"TEK · {snapshot.process_state}",
            f"模式：{snapshot.mode}",
            f"最近动作：{action}",
            f"最近结果：{snapshot.last_reason or '-'}",
        ]
    )


def _wow_foreground_from_reason(reason: str) -> bool | None:
    if reason in ("foreground_ok", "gate_passed", "dry_run_planned", "input_sent"):
        return True
    if reason in ("window_process_mismatch", "foreground_not_game", "window_handle_invalid") or reason.startswith("foreground_"):
        return False
    return None
