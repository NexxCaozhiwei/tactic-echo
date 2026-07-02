from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone


STATUS_SCHEMA_VERSION = 5


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class TEKStatusSnapshot:
    process_state: str
    safety_state: str
    mode: str
    started_at: str | None
    updated_at: str
    signal_found: bool
    wow_foreground: bool | None
    last_reason: str | None
    last_action_code: int | None
    last_action_id: str | None
    last_binding: str | None
    last_gate_passed: bool
    last_input_sent: bool
    error_message: str | None
    trace_path: str | None
    worker_alive: bool
    last_dispatch_origin: str = "official"
    log_dir: str | None = None
    foreground_diagnostics: dict | None = None
    signal_diagnostics: dict | None = None
    reason_counts: dict | None = None
    last_protocol_version: int | None = None
    last_binding_token: int | None = None
    last_result: str | None = None
    last_in_combat: bool | None = None
    monitor_flags: int = 0
    last_target_casting: bool = False
    last_target_interruptible: bool = False
    last_player_health_critical: bool = False
    rate_limiter: dict | None = None
    dispatch_failures: dict | None = None
    physical_input_diagnostics: dict | None = None
    schema_version: int = STATUS_SCHEMA_VERSION

    @classmethod
    def stopped(cls, *, log_dir: str | None = None) -> "TEKStatusSnapshot":
        return cls(
            process_state="Stopped",
            safety_state="Stopped",
            mode="Stopped",
            started_at=None,
            updated_at=utc_now_iso(),
            signal_found=False,
            wow_foreground=None,
            last_reason=None,
            last_action_code=None,
            last_action_id=None,
            last_dispatch_origin="official",
            last_binding=None,
            last_gate_passed=False,
            last_input_sent=False,
            error_message=None,
            trace_path=None,
            worker_alive=False,
            log_dir=log_dir,
            foreground_diagnostics=None,
            signal_diagnostics=None,
            reason_counts=None,
            last_protocol_version=None,
            last_binding_token=None,
            last_result=None,
            last_in_combat=None,
            monitor_flags=0,
            last_target_casting=False,
            last_target_interruptible=False,
            last_player_health_critical=False,
            rate_limiter=None,
            dispatch_failures=None,
            physical_input_diagnostics=None,
        )

    def to_dict(self) -> dict:
        return asdict(self)

    def to_runtime_dict(self) -> dict:
        """Return the disk mirror without deep-copying discarded diagnostics."""
        return {
            "schema_version": self.schema_version,
            "process_state": self.process_state,
            "safety_state": self.safety_state,
            "mode": self.mode,
            "started_at": self.started_at,
            "updated_at": self.updated_at,
            "signal_found": self.signal_found,
            "wow_foreground": self.wow_foreground,
            "last_reason": self.last_reason,
            "last_action_code": self.last_action_code,
            "last_action_id": self.last_action_id,
            "last_dispatch_origin": self.last_dispatch_origin,
            "last_binding": self.last_binding,
            "last_gate_passed": self.last_gate_passed,
            "last_input_sent": self.last_input_sent,
            "error_message": self.error_message,
            "trace_path": self.trace_path,
            "worker_alive": self.worker_alive,
            "log_dir": self.log_dir,
            "last_protocol_version": self.last_protocol_version,
            "last_binding_token": self.last_binding_token,
            "last_result": self.last_result,
            "last_in_combat": self.last_in_combat,
            "monitor_flags": self.monitor_flags,
            "last_target_casting": self.last_target_casting,
            "last_target_interruptible": self.last_target_interruptible,
            "last_player_health_critical": self.last_player_health_critical,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "TEKStatusSnapshot":
        stored_version = data.get("schema_version", data.get("schemaVersion", 1))
        if stored_version not in (1, 2, 3, 4, STATUS_SCHEMA_VERSION):
            raise ValueError("unsupported_status_schema")
        normalized = dict(data)
        normalized.pop("schemaVersion", None)
        normalized.setdefault("schema_version", STATUS_SCHEMA_VERSION)
        normalized.setdefault("foreground_diagnostics", None)
        normalized.setdefault("signal_diagnostics", None)
        normalized.setdefault("reason_counts", None)
        normalized.setdefault("last_protocol_version", None)
        normalized.setdefault("last_binding_token", None)
        normalized.setdefault("last_result", None)
        normalized.setdefault("last_in_combat", None)
        normalized.setdefault("monitor_flags", 0)
        normalized.setdefault("last_target_casting", False)
        normalized.setdefault("last_target_interruptible", False)
        normalized.setdefault("last_player_health_critical", False)
        normalized.setdefault("rate_limiter", None)
        normalized.setdefault("dispatch_failures", None)
        normalized.setdefault("physical_input_diagnostics", None)
        normalized["schema_version"] = STATUS_SCHEMA_VERSION
        return cls(**normalized)

