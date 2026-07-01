import time
from dataclasses import dataclass, replace
from pathlib import Path

from tek.src.engine import TEKEngine, TraceRecord
from tek.src.safety_gate import ForegroundSnapshot, SafetyContext
from tek.src.trace import write_trace


@dataclass
class RunnerConfig:
    interval_seconds: float = 0.05
    max_frames: int | None = None
    trace_path: str | Path | None = None
    tek_armed: bool = True
    assume_wow_foreground: bool = False
    dispatch_budget: int | None = None
    require_start_toggle: bool = False
    allow_initial_armed_dispatch: bool = False
    expected_protocol_version: int | None = None
    idle_interval_seconds: float = 0.20
    keep_records: int = 100
    trace_max_bytes: int | None = 5_000_000


class TEKRunner:
    def __init__(self, engine: TEKEngine, frame_source, foreground_source=None):
        self.engine = engine
        self.frame_source = frame_source
        self.foreground_source = foreground_source
        self.context = SafetyContext()
        self._budget_config_marker = object()

    def run(self, config: RunnerConfig) -> list[TraceRecord]:
        records = []
        frames_seen = 0
        self._apply_runtime_config(config)
        self.context.require_start_toggle = config.require_start_toggle
        self.context.allow_initial_armed_dispatch = config.allow_initial_armed_dispatch
        self.context.expected_protocol_version = config.expected_protocol_version

        while config.max_frames is None or frames_seen < config.max_frames:
            frames_seen += 1
            record = self.tick(config)
            records.append(record)
            if len(records) > config.keep_records:
                records.pop(0)
            if config.trace_path:
                write_trace(record, config.trace_path, max_bytes=config.trace_max_bytes)
            if config.interval_seconds > 0 and (config.max_frames is None or frames_seen < config.max_frames):
                time.sleep(self.next_interval_seconds(config, record))

        return records

    def tick(self, config: RunnerConfig) -> TraceRecord:
        # tick() is also used directly by the TEK.exe worker rather than only
        # through run(). Keep safety context synchronised on every tick so the
        # UI-linked startup toggle and any explicitly configured budget cannot
        # be bypassed by the in-process host.
        self.context.tek_armed = config.tek_armed
        self._apply_runtime_config(config)
        self.context.require_start_toggle = config.require_start_toggle
        self.context.allow_initial_armed_dispatch = config.allow_initial_armed_dispatch
        self.context.expected_protocol_version = config.expected_protocol_version
        self.context.foreground_before_read = self._foreground_snapshot(config)
        self.context.wow_foreground = self.context.foreground_before_read.ok
        self._set_frame_source_foreground(self.context.foreground_before_read)

        # UI linked mode may stay alive while WoW is closed or in the background.
        # Avoid repeatedly scanning the desktop until the foreground detector sees
        # a valid WoW window; this is both cheaper and less noisy than emitting a
        # screen-capture error on every tick.
        if not self.context.foreground_before_read.ok:
            self.context.foreground_before_dispatch = None
            self.context.state = "Waiting"
            return TraceRecord(
                accepted=False,
                reason=self.context.foreground_before_read.reason,
                sequence=-1,
                state="waiting",
                action_code=0,
                dispatcher_backend=self.engine.dispatcher_backend,
                dispatchBlocked=True,
                tekState="Waiting",
                diagnostics={"foreground": _foreground_diagnostics(self.context.foreground_before_read)},
            )

        try:
            frame = self.frame_source.read()
            self.context.foreground_before_dispatch = self._foreground_dispatch_snapshot(
                config,
                self.context.foreground_before_read,
            )
        except Exception as error:
            error_message = f"{type(error).__name__}:{error}"
            reason = error_message
            raw_reason = str(error)
            if raw_reason.startswith(("geometry_transition_wait", "layout_relocating")):
                reason = raw_reason
            else:
                reason = f"frame_read_error:{error_message}"
            return TraceRecord(
                accepted=False,
                reason=reason,
                sequence=-1,
                state="error",
                action_code=0,
                dispatcher_backend=self.engine.dispatcher_backend,
                dispatchBlocked=True,
                dispatchError=error_message,
                tekState="Waiting",
                diagnostics={"foreground": _foreground_diagnostics(self.context.foreground_before_read), "signal": _source_diagnostics(self.frame_source)},
            )
        return self.engine.process_frame(frame, self.context)

    def _apply_runtime_config(self, config: RunnerConfig) -> None:
        # A finite budget is decremented by SafetyGate after an actual input.
        # Do not overwrite it on every worker tick; only an explicit UI/config
        # change resets the budget for a new run.
        if config.dispatch_budget != self._budget_config_marker:
            self.context.dispatch_budget = config.dispatch_budget
            self._budget_config_marker = config.dispatch_budget

    def next_interval_seconds(self, config: RunnerConfig, record: TraceRecord) -> float:
        """Keep active/manual recovery sampling responsive and idle states cheap."""
        active_interval = max(0.0, float(config.interval_seconds))
        idle_interval = max(active_interval, float(config.idle_interval_seconds))
        if not self.context.wow_foreground:
            return idle_interval
        if record.state in {"paused", "waiting"} or record.tekState in {"Paused", "Waiting"}:
            return idle_interval
        return active_interval

    def _set_frame_source_foreground(self, snapshot: ForegroundSnapshot) -> None:
        setter = getattr(self.frame_source, "set_foreground_window", None)
        if callable(setter):
            try:
                setter(snapshot)
            except Exception:
                # Frame-source targeting is a performance/geometry hint. The
                # full foreground gate remains authoritative and fail-closed.
                pass

    def _foreground_dispatch_snapshot(
        self,
        config: RunnerConfig,
        expected: ForegroundSnapshot,
    ) -> ForegroundSnapshot:
        if config.assume_wow_foreground:
            return ForegroundSnapshot(ok=True, reason="assumed_foreground")
        if self.foreground_source:
            try:
                light = getattr(self.foreground_source, "light_snapshot", None)
                if callable(light):
                    return light(expected)
            except Exception as error:
                return ForegroundSnapshot(ok=False, reason=f"foreground_check_error:{type(error).__name__}:{error}")
        # Test/custom foreground sources that do not implement the optimized
        # light recheck retain the original full-snapshot semantics.
        return self._foreground_snapshot(config)

    def _foreground_snapshot(self, config: RunnerConfig) -> ForegroundSnapshot:
        if config.assume_wow_foreground:
            return ForegroundSnapshot(ok=True, reason="assumed_foreground")
        if self.foreground_source:
            try:
                if hasattr(self.foreground_source, "snapshot"):
                    return self.foreground_source.snapshot()
                ok = self.foreground_source.is_wow_foreground()
                return ForegroundSnapshot(ok=ok, reason="foreground_ok" if ok else "foreground_not_game")
            except Exception as error:
                return ForegroundSnapshot(ok=False, reason=f"foreground_check_error:{type(error).__name__}:{error}")
        return ForegroundSnapshot(ok=False, reason="foreground_not_game")


def _foreground_diagnostics(snapshot):
    if snapshot is None:
        return None
    return {"ok": snapshot.ok, "reason": snapshot.reason, "hwnd": snapshot.hwnd, "title": snapshot.title, "process_id": snapshot.process_id, "process_name": snapshot.process_name, "executable_path": snapshot.executable_path}

def _source_diagnostics(source):
    getter = getattr(source, "diagnostics", None)
    return getter() if callable(getter) else None
