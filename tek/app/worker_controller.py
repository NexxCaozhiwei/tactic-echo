from __future__ import annotations

import logging
import threading
import time
from collections import OrderedDict, deque
from dataclasses import dataclass, replace
from pathlib import Path
from types import SimpleNamespace

from tek.app.app_paths import AppPaths
from tek.app.settings_store import AppSettings, SettingsStore
from tek.runtime.runtime_status import TEKStatusSnapshot, utc_now_iso
from tek.runtime.status_mapper import trace_record_to_snapshot
from tek.runtime.status_store import StatusStore
from tek.runtime.status_publisher import StatusPublisher
from tek.runtime.trace_writer import TraceWriter
from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.cli import ScreenFrameSource
from tek.src.engine import TEKEngine
from tek.src.dispatch_rate_limiter import DispatchRateLimiter
from tek.src.diagnostic_bundle import create_diagnostic_bundle
from tek.src.profile_resolver import ProfileResolver
from tek.src.physical_input import PhysicalInputPause, WindowsPhysicalInputMonitor
from tek.src.keyboard_whitelist import KeyboardInterventionWhitelist
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.screen_sampler import (
    CaptureBounds,
    GDIBlitStripSampler,
    PillowScreenSampler,
    RelativeSignalLayout,
    SignalLayout,
    locate_te_signal_layout_in_region,
    locate_te_signal_layout_progressive_in_region,
    runtime_pixel_sampler,
)
from tek.src.safety_gate import SafetyContext
from tek.src.trace import (
    DEFAULT_TRACE_BACKUP_COUNT,
    DEFAULT_TRACE_MAX_BYTES,
    TraceSampler,
    trace_to_dict,
)
from tek.src.windows_foreground import WindowsForegroundDetector
from tek.src.windows_sendinput import WindowsSendInputDispatcher
from tek.src.windows_display import client_capture_bounds, inspect_client_geometry, inspect_window_calibration


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class WorkerOptions:
    mode: str
    send_input: bool = False
    require_start_toggle: bool = False
    allow_initial_armed_dispatch: bool = False
    interval_seconds: float = 0.05
    dispatch_budget: int | None = None
    wait_notice_seconds: int = 0
    max_dispatch_per_second: int = 10
    max_wheel_dispatch_per_second: int = 5
    expected_protocol_version: int | None = 3


class WorkerController:
    """Owns the in-process TEK runner used by TEK.exe.

    UI linked mode deliberately has no artificial dispatch budget. It still
    relies on the existing TEAP, profile, foreground, Armed/Pause and
    ErrorLocked gates in TEK Core.
    """

    def __init__(
        self,
        *,
        paths: AppPaths,
        status_store: StatusStore,
        settings_store: SettingsStore | None = None,
        profile_path: str | Path | None = None,
        runner_factory=None,
        modifier_releaser=None,
    ):
        self.paths = paths
        self.status_store = status_store
        self.settings_store = settings_store or SettingsStore(paths.settings_json)
        self._profile_override = Path(profile_path) if profile_path else None
        self.runner_factory = runner_factory
        self.modifier_releaser = modifier_releaser
        self._lock = threading.RLock()
        self._thread: threading.Thread | None = None
        self._runner: TEKRunner | None = None
        self._active_dispatcher = None
        self._physical_input_guard = None
        self._physical_input_monitor = None
        self._active_frame_source = None
        self._recent_events: deque[str] = deque(maxlen=20)
        self._recent_trace_records: deque[dict] = deque(maxlen=1000)
        self._reason_counts: dict[str, int] = {}
        self._stop = threading.Event()
        self._paused = threading.Event()
        self._snapshot = TEKStatusSnapshot.stopped(log_dir=str(paths.logs))
        self._status_publisher: StatusPublisher | None = None
        self._trace_write_failures = 0
        self._last_trace_error_log_at = 0.0
        self._trace_writer: TraceWriter | None = None
        # One best-effort startup mirror is safe before a high-frequency worker
        # exists. Runtime snapshots are published by StatusPublisher instead.
        try:
            self.status_store.write(self._snapshot)
        except Exception as error:
            # Lifecycle/status persistence is advisory. A locked status mirror
            # must never prevent TEK from creating a worker.
            LOGGER.warning("initial TEK status mirror deferred: %s", error)

    @property
    def snapshot(self) -> TEKStatusSnapshot:
        with self._lock:
            return self._snapshot

    @property
    def paused(self) -> bool:
        return self._paused.is_set()

    @property
    def recent_events(self) -> tuple[str, ...]:
        with self._lock:
            return tuple(self._recent_events)

    def is_running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())

    def start_dry_run(self) -> bool:
        settings = self.settings_store.load()
        return self.start(WorkerOptions(
            mode="Dry-run", send_input=False, interval_seconds=self._interval_seconds(),
            expected_protocol_version=3,
        ))

    def start_ui_linked(self) -> bool:
        settings = self.settings_store.load()
        return self.start(
            WorkerOptions(
                mode="UI 联动",
                send_input=True,
                # UI startup is released by the normal bootstrap + fresh-frame
                # gates. Requiring a manual paused→armed transition made an
                # already-running TEAP session appear unresponsive.
                require_start_toggle=False,
                allow_initial_armed_dispatch=True,
                interval_seconds=settings.sampling_interval_ms / 1000.0,
                dispatch_budget=None,
                wait_notice_seconds=settings.ui_link_wait_seconds,
                max_dispatch_per_second=settings.max_dispatch_per_second,
                max_wheel_dispatch_per_second=settings.max_wheel_dispatch_per_second,
                expected_protocol_version=3,
            )
        )

    def start(self, options: WorkerOptions) -> bool:
        with self._lock:
            if self._hook_shutdown_pending_locked():
                self._publish_hook_stopping_snapshot_locked()
                return False
            if self._thread and self._thread.is_alive():
                return False
            self._stop.clear()
            self._paused.clear()
            self._ensure_status_publisher()
            starting = TEKStatusSnapshot(
                process_state="Starting",
                safety_state="Starting",
                mode=options.mode,
                started_at=utc_now_iso(),
                updated_at=utc_now_iso(),
                signal_found=False,
                wow_foreground=None,
                last_reason=None,
                last_action_code=None,
                last_action_id=None,
                last_binding=None,
                last_gate_passed=False,
                last_input_sent=False,
                error_message=None,
                trace_path=str(self.paths.trace_path_for_today()),
                worker_alive=True,
                log_dir=str(self.paths.logs),
            )
            self._set_snapshot(starting, urgent=True)
            self._thread = threading.Thread(
                target=self._run_worker,
                args=(options, starting.started_at),
                name="TEKWorker",
                daemon=True,
            )
            self._thread.start()
            return True

    def calibrate_signal_layout(self) -> tuple[SignalLayout, dict]:
        """Retry the bounded client-anchor locator and persist a verified hint.

        This is a read-only operation. Runtime auto-location never scans the
        full desktop and never promotes a one-frame candidate to input authority.
        """
        source = self._active_frame_source
        if not isinstance(source, AutoLocateFrameSource):
            source = AutoLocateFrameSource.from_settings(self.settings_store.load())
        layout = source.calibrate()
        settings = self.settings_store.load()
        self.settings_store.save(AppSettings.from_dict({
            **settings.to_dict(),
            "fixed_signal_x": layout.x,
            "fixed_signal_y": layout.y,
            "fixed_signal_block_size": layout.block_size,
            "fixed_signal_block_gap": layout.block_gap,
        }))
        return layout, source.diagnostics()

    def create_diagnostic_bundle(self, destination: str | Path | None = None) -> tuple[Path, dict]:
        """Create a local support ZIP without stopping the current worker.

        A configured TacticEcho.lua path is optional.  When present only the
        addon's sanitized mapping-export snapshot is included; the raw
        SavedVariables file is never copied to the bundle.
        """
        settings = self.settings_store.load()
        saved_variables_path = settings.wow_savedvariables_path or None
        return create_diagnostic_bundle(
            paths=self.paths,
            settings_store=self.settings_store,
            status_snapshot=self.snapshot,
            saved_variables_path=saved_variables_path,
            destination=destination,
            recent_trace_records=self._recent_trace_records_copy(),
        )

    def pause(self) -> bool:
        if not self.is_running():
            return False
        self._paused.set()
        snapshot = self.snapshot
        self._set_snapshot(
            TEKStatusSnapshot(
                **{
                    **snapshot.to_dict(),
                    "process_state": "Paused",
                    "safety_state": "Paused",
                    "updated_at": utc_now_iso(),
                    "last_reason": "local_pause",
                }
            )
        )
        return True

    def resume(self) -> bool:
        if not self.is_running():
            return False
        self._paused.clear()
        snapshot = self.snapshot
        self._set_snapshot(
            TEKStatusSnapshot(
                **{
                    **snapshot.to_dict(),
                    "process_state": "Waiting",
                    "safety_state": "Waiting",
                    "updated_at": utc_now_iso(),
                    "last_reason": "local_resume_waiting_for_signal",
                }
            )
        )
        return True

    def recover_error(self) -> bool:
        """Explicitly reset a live ErrorLocked runner without restarting TEK.exe."""
        with self._lock:
            if not self._thread or not self._thread.is_alive() or not self._runner:
                return False
            if self._snapshot.process_state != "ErrorLocked":
                return False
            settings = self.settings_store.load()
            engine = getattr(self._runner, "engine", None)
            failure_tracker = getattr(engine, "failure_tracker", None)
            reset_failures = getattr(failure_tracker, "reset", None)
            if callable(reset_failures):
                reset_failures()
            rate_limiter = getattr(engine, "rate_limiter", None)
            reset_limiter = getattr(rate_limiter, "reset", None)
            if callable(reset_limiter):
                reset_limiter()
            physical_guard = getattr(engine, "physical_input_guard", None)
            reset_guard = getattr(physical_guard, "reset_recovery_gate", None)
            if callable(reset_guard):
                reset_guard()
            self._runner.context = SafetyContext(
                dispatch_budget=None,
                require_start_toggle=False,
                allow_initial_armed_dispatch=True,
                expected_protocol_version=3,
            )
            self._paused.clear()
            self._set_snapshot(
                TEKStatusSnapshot(
                    **{
                        **self._snapshot.to_dict(),
                        "process_state": "Waiting",
                        "safety_state": "Waiting",
                        "updated_at": utc_now_iso(),
                        "last_reason": "manual_recover_waiting_for_valid_armed_frame",
                        "error_message": None,
                    }
                )
            )
            LOGGER.info("manual ErrorLocked recovery requested; settings=%s", settings.profile_id)
            return True

    def stop(self, *, timeout_seconds: float = 5.0) -> bool:
        """Stop the worker and confirm its keyboard hook has also exited.

        The UI worker may stop before Windows confirms the low-level hook
        thread has consumed WM_QUIT.  Treat that intermediate state as
        ``Stopping`` rather than silently starting another monitor.
        """

        with self._lock:
            thread = self._thread
            if thread and thread.is_alive():
                snapshot = self._snapshot
                self._set_snapshot(
                    TEKStatusSnapshot(
                        **{**snapshot.to_dict(), "process_state": "Stopping", "updated_at": utc_now_iso()}
                    )
                )
        self._stop.set()
        source = self._active_frame_source
        closer = getattr(source, "close", None)
        if callable(closer):
            try:
                closer()
            except Exception:
                LOGGER.debug("signal source close deferred", exc_info=True)
        self._release_modifiers()
        hook_stopped = self._stop_physical_input_monitor()
        if thread and thread.is_alive() and thread is not threading.current_thread():
            thread.join(timeout_seconds)
        worker_stopped = not thread or not thread.is_alive()

        with self._lock:
            if worker_stopped:
                self._thread = None
                self._runner = None
                self._active_dispatcher = None
                self._active_frame_source = None
                if hook_stopped:
                    self._set_snapshot(TEKStatusSnapshot.stopped(log_dir=str(self.paths.logs)), urgent=True)
                else:
                    self._publish_hook_stopping_snapshot_locked()

        if worker_stopped:
            self._stop_trace_writer()
        if worker_stopped and hook_stopped:
            self._stop_status_publisher()
        return bool(worker_stopped and hook_stopped)

    def _run_worker(self, options: WorkerOptions, started_at: str | None) -> None:
        trace_path = self.paths.trace_path_for_today()
        waiting_since: float | None = None
        settings = self.settings_store.load()
        trace_sampler = TraceSampler(full_debug=settings.full_trace_debug)
        capture_diagnostics = bool(settings.diagnostics_enabled)
        last_ui_signature = None
        last_ui_snapshot_at = 0.0
        try:
            runner = self._build_runner(options)
            with self._lock:
                self._runner = runner
            config = RunnerConfig(
                interval_seconds=options.interval_seconds,
                max_frames=1,
                trace_path=None,
                tek_armed=True,
                assume_wow_foreground=False,
                dispatch_budget=options.dispatch_budget,
                require_start_toggle=options.require_start_toggle,
                allow_initial_armed_dispatch=options.allow_initial_armed_dispatch,
                expected_protocol_version=options.expected_protocol_version,
            )
            while not self._stop.is_set():
                config.tek_armed = not self._paused.is_set()
                record = runner.tick(config)
                trace_record = record
                for sampled_record in trace_sampler.records_to_write(record):
                    # Keep expensive diagnostic collection and JSONL I/O out of
                    # the 50 ms sampling path unless a transition, heartbeat or
                    # bounded success-dispatch aggregate is actually persisted.
                    trace_record = sampled_record
                    if capture_diagnostics:
                        merged_diagnostics = dict(sampled_record.diagnostics or {})
                        merged_diagnostics.update(self._diagnostics_for_runner(runner))
                        trace_record = replace(sampled_record, diagnostics=merged_diagnostics)
                    self._append_event(trace_record.reason)
                    self._remember_trace_record(trace_record, include_diagnostics=capture_diagnostics)
                    self._write_trace_safely(
                        trace_record,
                        trace_path,
                        include_diagnostics=capture_diagnostics,
                    )

                # UI/state objects are presentation-only. They remain in memory
                # and refresh independently from the one-second disk heartbeat.
                # dispatch.  UI/status object construction is presentation-only
                # and is coalesced to transitions or 100 ms heartbeats.
                ui_now = time.monotonic()
                ui_signature = self._ui_snapshot_signature(record)
                if ui_signature != last_ui_signature or (ui_now - last_ui_snapshot_at) >= 0.10:
                    # Hook/manual-gate diagnostics are deliberately shown in
                    # the UI even when verbose trace capture is disabled. They
                    # are sampled only on this 100 ms presentation path.
                    ui_record = trace_record if capture_diagnostics else record
                    ui_diagnostics = dict(ui_record.diagnostics or {})
                    runtime_ui_diagnostics = self._diagnostics_for_runner(runner)
                    physical = runtime_ui_diagnostics.get("physical_input")
                    if physical is not None:
                        ui_diagnostics["physical_input"] = physical
                    ui_record = replace(ui_record, diagnostics=ui_diagnostics)
                    snapshot = trace_record_to_snapshot(
                        ui_record,
                        mode=options.mode,
                        started_at=started_at,
                        trace_path=str(trace_path),
                        log_dir=str(self.paths.logs),
                        worker_alive=True,
                    )
                    # The status window needs sampler/backend visibility even
                    # when verbose trace diagnostics are disabled.  This small
                    # dictionary is collected only with the 100 ms UI snapshot,
                    # never on every 20 ms worker tick or disk publish.
                    signal_diagnostics = self._signal_diagnostics_for_ui(runner)
                    if signal_diagnostics is not None:
                        snapshot = replace(snapshot, signal_diagnostics=signal_diagnostics)
                    self._persist_signal_layout_cache(runner)
                    if options.wait_notice_seconds > 0 and snapshot.process_state in {"Waiting", "WaitingForForeground", "Bootstrap", "AwaitingStartToggle"}:
                        if waiting_since is None:
                            waiting_since = ui_now
                        waited = int(ui_now - waiting_since)
                        if waited >= options.wait_notice_seconds:
                            snapshot = replace(snapshot, last_reason=f"{record.reason}; ui_link_waiting:{waited}s")
                    else:
                        waiting_since = None
                    self._set_snapshot(snapshot)
                    last_ui_signature = ui_signature
                    last_ui_snapshot_at = ui_now
                next_interval = getattr(runner, "next_interval_seconds", None)
                delay = next_interval(config, record) if callable(next_interval) else options.interval_seconds
                self._stop.wait(delay)
        except Exception as error:
            LOGGER.exception("TEK worker exited with error")
            self._set_snapshot(
                TEKStatusSnapshot(
                    process_state="WorkerExited",
                    safety_state="ErrorLocked",
                    mode=options.mode,
                    started_at=started_at,
                    updated_at=utc_now_iso(),
                    signal_found=False,
                    wow_foreground=None,
                    last_reason="worker_exception",
                    last_action_code=None,
                    last_action_id=None,
                    last_binding=None,
                    last_gate_passed=False,
                    last_input_sent=False,
                    error_message=f"{type(error).__name__}:{error}",
                    trace_path=str(trace_path),
                    worker_alive=False,
                    log_dir=str(self.paths.logs),
                ),
                urgent=True,
            )
        finally:
            source = self._active_frame_source
            closer = getattr(source, "close", None)
            if callable(closer):
                try:
                    closer()
                except Exception:
                    LOGGER.debug("signal source close deferred", exc_info=True)
            self._stop_trace_writer()
            with self._lock:
                self._runner = None
                self._active_dispatcher = None
                self._active_frame_source = None
                self._stop_physical_input_monitor()

    def _build_runner(self, options: WorkerOptions) -> TEKRunner:
        if self.runner_factory:
            return self.runner_factory(options)
        settings = self.settings_store.load()
        profile_path = self._profile_path(settings)
        resolver = ProfileResolver.from_file(profile_path, catalog=RETRIBUTION_V2)
        dispatcher = WindowsSendInputDispatcher() if options.send_input else None
        self._active_dispatcher = dispatcher
        physical_input_guard = None
        physical_input_monitor = None
        if options.send_input:
            intervention_whitelist = KeyboardInterventionWhitelist.from_keys(settings.auto_dispatch_exempt_keys)
            physical_input_guard = PhysicalInputPause(
                profile=settings.manual_priority_mode,
                recovery_seconds=settings.manual_priority_custom_recovery_ms / 1000.0,
                custom_freshness_frames=settings.manual_priority_custom_freshness_frames,
                custom_replay_guard_seconds=settings.manual_priority_custom_replay_guard_ms / 1000.0,
            )
            monitor = WindowsPhysicalInputMonitor(physical_input_guard, intervention_whitelist=intervention_whitelist)
            monitor.start()
            # Do not fall back to unguarded dispatch while the asynchronous hook
            # is starting.  The engine treats "not ready" as a hard SendInput
            # block; waiting here only makes the initial UI status deterministic.
            monitor.wait_until_ready(timeout_seconds=0.75)
            physical_input_monitor = monitor
            self._physical_input_guard = physical_input_guard
            self._physical_input_monitor = monitor
            limiter = DispatchRateLimiter(
            max_per_second=settings.max_dispatch_per_second,
            max_wheel_per_second=settings.max_wheel_dispatch_per_second,
        )
        engine = TEKEngine(
            RETRIBUTION_V2,
            resolver,
            input_dispatcher=dispatcher,
            rate_limiter=limiter,
            physical_input_guard=physical_input_guard,
            physical_input_monitor=physical_input_monitor,
        )
        source = AutoLocateFrameSource.from_settings(settings)
        self._active_frame_source = source
        foreground = WindowsForegroundDetector(allowed_process_names=settings.allowed_process_names())
        return TEKRunner(engine, source, foreground_source=foreground)


    # Legacy WoW-cache discovery was intentionally removed from the runtime path.
    # Local intervention whitelist settings are the sole input-classification source.

    def _profile_path(self, settings: AppSettings) -> Path:
        if self._profile_override:
            return self._profile_override
        candidate = self.paths.profiles / f"{settings.profile_id}.json"
        return candidate if candidate.exists() else self.paths.default_profile_path()

    def _interval_seconds(self) -> float:
        return self.settings_store.load().sampling_interval_ms / 1000.0

    def _release_modifiers(self) -> None:
        try:
            if self.modifier_releaser:
                self.modifier_releaser()
                return
            dispatcher = self._active_dispatcher
            releaser = getattr(dispatcher, "release_modifiers", None)
            if callable(releaser):
                releaser()
        except Exception:
            LOGGER.exception("modifier release failed during worker shutdown")

    def _ui_snapshot_signature(self, record) -> tuple:
        """State fields that warrant an immediate in-memory UI refresh."""
        return (
            record.state,
            record.tekState,
            record.reason,
            record.protocol_version,
            record.sequence >= 0,
            bool(record.dispatchError),
            record.binding_token,
        )

    def _remember_trace_record(self, record, *, include_diagnostics: bool) -> None:
        # Keep a bounded lightweight history for manual diagnostic bundles.  It
        # mirrors only records that passed TraceSampler, never each 20 ms tick.
        payload = trace_to_dict(record, include_diagnostics=include_diagnostics)
        with self._lock:
            self._recent_trace_records.append(payload)

    def _recent_trace_records_copy(self) -> list[dict]:
        with self._lock:
            return list(self._recent_trace_records)

    def _append_event(self, reason: str) -> None:
        with self._lock:
            self._recent_events.append(f"{utc_now_iso()}  {reason}")
            self._reason_counts[reason] = self._reason_counts.get(reason, 0) + 1
            if len(self._reason_counts) > 30:
                # Preserve the most frequent recent reasons; diagnostics are not a permanent metric store.
                keep = sorted(self._reason_counts.items(), key=lambda item: item[1], reverse=True)[:20]
                self._reason_counts = dict(keep)

    def _persist_signal_layout_cache(self, runner: TEKRunner) -> None:
        """Persist only newly verified relative geometry outside the 50 ms path."""
        source = getattr(runner, "frame_source", None)
        consume = getattr(source, "take_layout_cache_update", None)
        if not callable(consume):
            return
        try:
            cache = consume()
            if not cache:
                return
            settings = self.settings_store.load()
            if settings.signal_layout_cache == cache:
                return
            self.settings_store.save(AppSettings.from_dict({**settings.to_dict(), "signal_layout_cache": cache}))
        except Exception as error:
            LOGGER.warning("signal layout cache persistence deferred: %s", error)

    def _diagnostics_for_runner(self, runner: TEKRunner) -> dict:
        context = getattr(runner, "context", None)
        foreground = getattr(context, "foreground_before_read", None) or getattr(context, "foreground_before_dispatch", None)
        foreground_data = None
        if foreground is not None:
            foreground_data = {
                "ok": foreground.ok,
                "reason": foreground.reason,
                "hwnd": foreground.hwnd,
                "title": foreground.title,
                "process_id": foreground.process_id,
                "process_name": foreground.process_name,
                "executable_path": foreground.executable_path,
            }
        source = getattr(runner, "frame_source", None)
        source_diagnostics = getattr(source, "diagnostics", None)
        signal = source_diagnostics() if callable(source_diagnostics) else None
        with self._lock:
            reasons = dict(sorted(self._reason_counts.items(), key=lambda item: item[1], reverse=True)[:10])
        limiter = getattr(getattr(runner, "engine", None), "rate_limiter", None)
        limiter_snapshot = limiter.snapshot() if limiter and callable(getattr(limiter, "snapshot", None)) else None
        physical_guard = getattr(getattr(runner, "engine", None), "physical_input_guard", None)
        physical = physical_guard.diagnostics() if physical_guard and callable(getattr(physical_guard, "diagnostics", None)) else None
        monitor = self._physical_input_monitor
        if monitor and callable(getattr(monitor, "diagnostics", None)):
            physical = monitor.diagnostics()
        trace_writer = self._trace_writer
        trace_writer_diagnostics = trace_writer.diagnostics() if trace_writer is not None else None
        return {
            "foreground": foreground_data,
            "signal": signal,
            "reason_counts": reasons,
            "rate_limiter": limiter_snapshot,
            "physical_input": physical,
            "trace_writer": trace_writer_diagnostics,
        }

    def _signal_diagnostics_for_ui(self, runner: TEKRunner) -> dict | None:
        source = getattr(runner, "frame_source", None)
        getter = getattr(source, "diagnostics", None)
        if not callable(getter):
            return None
        try:
            return getter()
        except Exception as error:
            # UI diagnostics are advisory.  A formatting/inspection failure can
            # never disturb live frame reads or the SafetyGate.
            return {"recent_decode_error": f"diagnostics_error:{type(error).__name__}:{error}"}

    def hook_shutdown_pending(self) -> bool:
        with self._lock:
            return self._hook_shutdown_pending_locked()

    def _hook_shutdown_pending_locked(self) -> bool:
        monitor = self._physical_input_monitor
        checker = getattr(monitor, "is_stopping", None)
        return bool(callable(checker) and checker())

    def _publish_hook_stopping_snapshot_locked(self) -> None:
        snapshot = self._snapshot
        self._set_snapshot(
            TEKStatusSnapshot(
                **{
                    **snapshot.to_dict(),
                    "process_state": "Stopping",
                    "safety_state": "Blocked",
                    "updated_at": utc_now_iso(),
                    "last_reason": "physical_input_hook_stopping",
                    "last_gate_passed": False,
                    "last_input_sent": False,
                    "worker_alive": bool(self._thread and self._thread.is_alive()),
                }
            ),
            urgent=True,
        )

    def _stop_physical_input_monitor(self) -> bool:
        monitor = self._physical_input_monitor
        if monitor is None:
            self._physical_input_guard = None
            return True
        stopper = getattr(monitor, "stop", None)
        stopped = True
        if callable(stopper):
            try:
                result = stopper()
                stopped = True if result is None else bool(result)
            except Exception:
                stopped = False
                LOGGER.exception("physical input hook shutdown failed")
        if stopped:
            with self._lock:
                if self._physical_input_monitor is monitor:
                    self._physical_input_monitor = None
                    self._physical_input_guard = None
        else:
            LOGGER.warning("physical input hook is still stopping; UI-linked restart remains blocked")
        return stopped

    def _ensure_status_publisher(self) -> StatusPublisher:
        with self._lock:
            publisher = self._status_publisher
            if publisher is None:
                publisher = StatusPublisher(self.status_store)
                publisher.start()
                self._status_publisher = publisher
            return publisher

    def _stop_status_publisher(self) -> None:
        with self._lock:
            publisher = self._status_publisher
            self._status_publisher = None
        if publisher is not None:
            publisher.stop(timeout_seconds=1.0)

    def _ensure_trace_writer(self) -> TraceWriter:
        with self._lock:
            writer = self._trace_writer
            if writer is None:
                writer = TraceWriter()
                writer.start()
                self._trace_writer = writer
            return writer

    def _stop_trace_writer(self) -> None:
        with self._lock:
            writer = self._trace_writer
            self._trace_writer = None
        if writer is not None:
            writer.stop(timeout_seconds=1.0)

    def _write_trace_safely(self, record, trace_path: Path, *, include_diagnostics: bool) -> None:
        try:
            writer = self._ensure_trace_writer()
            if not writer.submit(
                record,
                trace_path,
                max_bytes=DEFAULT_TRACE_MAX_BYTES,
                backup_count=DEFAULT_TRACE_BACKUP_COUNT,
                include_diagnostics=include_diagnostics,
            ):
                self._trace_write_failures += 1
        except Exception as error:
            # Trace is strictly observational. A queue/serialization failure can
            # never leave the worker sampling loop.
            self._trace_write_failures += 1
            now = time.monotonic()
            if now - self._last_trace_error_log_at >= 30.0:
                LOGGER.warning("TEK trace write deferred: %s", error)
                self._last_trace_error_log_at = now

    def _set_snapshot(self, snapshot: TEKStatusSnapshot, *, urgent: bool = False) -> None:
        with self._lock:
            self._snapshot = snapshot
            publisher = self._status_publisher
        if publisher is not None:
            publisher.submit(snapshot, urgent=urgent)
        else:
            # Startup/shutdown fallback only. Status persistence is a mirror
            # and must never make lifecycle control fail.
            try:
                self.status_store.write(snapshot)
            except Exception as error:
                LOGGER.warning("fallback TEK status mirror deferred: %s", error)



class _LayoutReadWriteLock:
    """Small writer-preferred lock for the TEAP layout pointer.

    Sampling only needs an immutable ``SignalLayout`` snapshot, while manual
    calibration and automatic re-location replace that snapshot wholesale. A
    dedicated read/write lock makes the hand-off explicit: readers observe the
    full old layout or the full new layout, never a partially updated set of
    geometry fields.
    """

    def __init__(self) -> None:
        self._condition = threading.Condition(threading.RLock())
        self._readers = 0
        self._writer = False
        self._waiting_writers = 0

    class _ReadLease:
        def __init__(self, owner: "_LayoutReadWriteLock") -> None:
            self.owner = owner

        def __enter__(self):
            owner = self.owner
            with owner._condition:
                while owner._writer or owner._waiting_writers:
                    owner._condition.wait()
                owner._readers += 1
            return self

        def __exit__(self, exc_type, exc, tb):
            owner = self.owner
            with owner._condition:
                owner._readers -= 1
                if owner._readers == 0:
                    owner._condition.notify_all()
            return False

    class _WriteLease:
        def __init__(self, owner: "_LayoutReadWriteLock") -> None:
            self.owner = owner

        def __enter__(self):
            owner = self.owner
            with owner._condition:
                owner._waiting_writers += 1
                try:
                    while owner._writer or owner._readers:
                        owner._condition.wait()
                    owner._writer = True
                finally:
                    owner._waiting_writers -= 1
            return self

        def __exit__(self, exc_type, exc, tb):
            owner = self.owner
            with owner._condition:
                owner._writer = False
                owner._condition.notify_all()
            return False

    def read_lock(self):
        return self._ReadLease(self)

    def write_lock(self):
        return self._WriteLease(self)


@dataclass(frozen=True)
class _ClientGeometry:
    """One screen-global WoW client observation used for P2-B recovery.

    TEAP is placed in WoW UI coordinates. A pure window move keeps those
    coordinates stable relative to the client area, while client-size, DPI,
    monitor, mode or HWND changes can invalidate a projected pixel layout.
    The object deliberately contains no input state and is only used to decide
    whether a failed strip read should immediately re-locate inside the current
    verified WoW client rectangle.
    """

    hwnd: int
    bounds: CaptureBounds
    dpi: int | None
    window_mode: str | None
    monitor_rect: tuple[int, int, int, int] | None

    def to_dict(self) -> dict:
        return {
            "hwnd": self.hwnd,
            "client_bounds": self.bounds.to_dict(),
            "dpi": self.dpi,
            "window_mode": self.window_mode,
            "monitor_rect": self.monitor_rect,
        }


@dataclass(frozen=True)
class _LayoutReadPlan:
    """Immutable source-read decision for one sampling tick."""

    layout: SignalLayout
    geometry: _ClientGeometry | None
    geometry_change_reasons: tuple[str, ...] = ()

    @property
    def requires_relocation_on_failure(self) -> bool:
        return bool(self.geometry_change_reasons)

    @property
    def has_material_geometry_change(self) -> bool:
        return any(
            reason in {
                "hwnd_changed",
                "client_resized",
                "dpi_changed",
                "window_mode_changed",
                "monitor_changed",
            }
            for reason in self.geometry_change_reasons
        )



class AutoLocateFrameSource:
    """Read TEAP through a client-relative layout with bounded recovery work.

    P2-A separates two capture paths:

    * initial locate, re-locate and manual calibration capture only the verified
      WoW client area;
    * normal 50 ms operation projects the known TEAP strip into the current
      client area and captures only that narrow strip.

    The full virtual-desktop locator remains available only to explicitly
    supplied legacy/test callables. UI-linked runtime never uses it.
    """

    def __init__(
        self,
        *,
        auto_locate: bool = True,
        fallback_layout: SignalLayout | None = None,
        sampler=None,
        sampler_backend: str | None = None,
        locate_function=None,
        client_locate_function=locate_te_signal_layout_progressive_in_region,
        background_relocation: bool = False,
        layout_cache: dict | None = None,
        failure_threshold: int = 3,
        sampler_failure_threshold: int = 3,
        calibration_provider=inspect_window_calibration,
        fast_calibration_provider=None,
        full_calibration_interval_seconds: float = 0.75,
        pillow_sampler_factory=PillowScreenSampler,
        clock=time.monotonic,
        auto_locate_initial_backoff_seconds: float = 1.0,
        auto_locate_max_backoff_seconds: float = 8.0,
        layout_verification_frames: int = 2,
        layout_verification_interval_seconds: float = 0.06,
        geometry_transition_settle_seconds: float = 0.35,
    ):
        self.auto_locate = auto_locate
        self.fallback_layout = fallback_layout or SignalLayout()
        configured = str(sampler_backend or getattr(sampler, "backend", "auto") or "auto").strip().lower()
        self._configured_sampler_backend = configured if configured in {"auto", "pillow", "gdi", "gdi_blt"} else "auto"
        self._auto_sampler_mode = self._configured_sampler_backend == "auto"
        self._auto_pillow_successes = 0
        self._auto_promotion_successes_required = 3
        self.sampler = sampler or runtime_pixel_sampler("pillow" if self._auto_sampler_mode else self._configured_sampler_backend)
        # ``locate_function`` is a test/CLI compatibility fallback. UI-linked
        # runtime supplies a foreground HWND and therefore uses only the client
        # locator below.
        self.locate_function = locate_function
        self.client_locate_function = client_locate_function
        self._background_relocation_enabled = bool(background_relocation)
        self._relocation_thread: threading.Thread | None = None
        self._background_relocation_active = False
        self._relocation_generation = 0
        self._closed = False
        self._layout_cache_dirty = False
        self._layout_cache_signature = None
        self.failure_threshold = max(1, int(failure_threshold))
        self.sampler_failure_threshold = max(1, int(sampler_failure_threshold))
        self.calibration_provider = calibration_provider
        # Direct/test callers retain their supplied full provider every read.
        # UI-linked construction opts into the fast client-rectangle provider.
        self.fast_calibration_provider = fast_calibration_provider
        self._full_calibration_interval_seconds = max(0.10, float(full_calibration_interval_seconds))
        self._last_full_calibration = None
        self._next_full_calibration_at = 0.0
        self._last_calibration_mode = "full"
        self._pillow_sampler_factory = pillow_sampler_factory
        self._clock = clock
        self._layout_lock = _LayoutReadWriteLock()
        self._window_lock = threading.RLock()
        self._cached_layout: SignalLayout | None = None
        self._last_verified_layout: SignalLayout | None = None
        # ``_relative_layout`` follows the current (possibly only candidate)
        # geometry.  The verified copy is retained separately so a failed
        # re-location can fall back to the last proofed client-relative strip,
        # never to an untrusted candidate or desktop absolute coordinate.
        self._relative_layout: RelativeSignalLayout | None = None
        self._last_verified_relative_layout: RelativeSignalLayout | None = None
        self._target_hwnd: int | None = None
        self._candidate_geometry: _ClientGeometry | None = None
        self._last_verified_geometry: _ClientGeometry | None = None
        self._last_geometry_change_reasons: tuple[str, ...] = ()
        self._relocation_pending = False
        self._last_relocation_reason: str | None = None
        self._geometry_transition_signature = None
        self._geometry_transition_last_changed_at = 0.0
        self._geometry_transition_reasons: tuple[str, ...] = ()
        self._geometry_transition_settle_seconds = max(0.0, float(geometry_transition_settle_seconds))
        self._using_fallback = not auto_locate
        self._consecutive_failures = 0
        self._sampler_consecutive_failures = 0
        self._last_error: str | None = None
        self._recent_decode_error: str | None = None
        self._sampler_fallback_locked = False
        self._last_sampler_switch_reason: str | None = None
        self._display_calibration = None
        self._last_runtime_capture_bounds: CaptureBounds | None = None
        # Hot 50 ms path: reuse immutable reader wrappers for the active
        # sampler/layout pair instead of allocating ScreenFrameSource each tick.
        self._reader_cache: OrderedDict[tuple[int, SignalLayout], ScreenFrameSource] = OrderedDict()
        self._auto_locate_initial_backoff_seconds = max(0.1, float(auto_locate_initial_backoff_seconds))
        self._auto_locate_max_backoff_seconds = max(
            self._auto_locate_initial_backoff_seconds,
            float(auto_locate_max_backoff_seconds),
        )
        self._auto_locate_backoff_seconds = self._auto_locate_initial_backoff_seconds
        self._next_auto_locate_at = 0.0
        # A discovered T/E/3 header is only a candidate.  It becomes trusted
        # after two complete, CRC/commit-valid v3 frames with advancing
        # freshness; until then TEK does not receive a dispatchable frame.
        self._layout_verification_frames = max(2, int(layout_verification_frames))
        # Production defaults to 60 ms.  A zero interval remains useful for
        # deterministic tests; it does not change the two-frame proof itself.
        self._layout_verification_interval_seconds = max(0.0, float(layout_verification_interval_seconds))
        self._layout_verification_required = False
        self._last_layout_verification_reason: str | None = None
        self._restore_layout_cache(layout_cache)

    @classmethod
    def from_settings(cls, settings: AppSettings) -> "AutoLocateFrameSource":
        return cls(
            auto_locate=settings.auto_locate_signal,
            fallback_layout=SignalLayout(
                x=settings.fixed_signal_x,
                y=settings.fixed_signal_y,
                block_size=settings.fixed_signal_block_size,
                block_gap=settings.fixed_signal_block_gap,
            ),
            sampler_backend=settings.signal_sampler_backend,
            client_locate_function=locate_te_signal_layout_progressive_in_region,
            fast_calibration_provider=inspect_client_geometry,
            background_relocation=True,
            layout_cache=settings.signal_layout_cache,
        )

    def set_foreground_window(self, snapshot) -> None:
        """Receive the already-validated foreground identity from TEKRunner."""
        if not getattr(snapshot, "ok", False):
            return
        hwnd = int(getattr(snapshot, "hwnd", 0) or 0)
        if not hwnd:
            return
        with self._window_lock:
            changed = self._target_hwnd != hwnd
            self._target_hwnd = hwnd
        if changed:
            # A recreated/fullscreen WoW HWND must not inherit stale display
            # metadata. The next read performs one full calibration.
            with self._layout_lock.write_lock():
                self._last_full_calibration = None
                self._next_full_calibration_at = 0.0
                self._relocation_generation += 1
                self._geometry_transition_signature = None

    def close(self) -> None:
        """Invalidate any asynchronous locator result during worker shutdown."""
        with self._layout_lock.write_lock():
            self._closed = True
            self._relocation_generation += 1

    def take_layout_cache_update(self) -> dict | None:
        """Return one newly verified cross-start geometry hint, if it changed."""
        with self._layout_lock.write_lock():
            if not self._layout_cache_dirty:
                return None
            self._layout_cache_dirty = False
            layout = self._last_verified_layout
            relative = self._last_verified_relative_layout
            if layout is None or relative is None:
                return None
            return {
                "schema_version": 1,
                "relative_layout": relative.to_dict(),
                "layout": layout.to_dict(),
            }

    @property
    def cached_layout(self) -> SignalLayout | None:
        with self._layout_lock.read_lock():
            return self._cached_layout

    @property
    def using_fallback(self) -> bool:
        with self._layout_lock.read_lock():
            return self._using_fallback

    @property
    def sampler_backend(self) -> str:
        with self._layout_lock.read_lock():
            backend = str(getattr(self.sampler, "backend", self._configured_sampler_backend) or self._configured_sampler_backend)
        return backend.lower()

    def diagnostics(self) -> dict:
        with self._layout_lock.read_lock():
            layout = self._cached_layout
            last_verified = self._last_verified_layout
            relative = self._relative_layout
            verified_relative = self._last_verified_relative_layout
            using_fallback = self._using_fallback
            sampler_backend = str(getattr(self.sampler, "backend", self._configured_sampler_backend) or self._configured_sampler_backend).lower()
            sampler_fallback_locked = self._sampler_fallback_locked
            sampler_failures = self._sampler_consecutive_failures
            last_sampler_switch_reason = self._last_sampler_switch_reason
            failures = self._consecutive_failures
            last_error = self._last_error
            recent_decode_error = self._recent_decode_error
            next_auto_locate_at = self._next_auto_locate_at
            auto_locate_backoff_seconds = self._auto_locate_backoff_seconds
            display_calibration = self._display_calibration
            runtime_capture_bounds = self._last_runtime_capture_bounds
            last_verified_geometry = self._last_verified_geometry
            last_geometry_change_reasons = self._last_geometry_change_reasons
            relocation_pending = self._relocation_pending
            last_relocation_reason = self._last_relocation_reason
            background_relocation_active = self._background_relocation_active
            background_relocation_enabled = self._background_relocation_enabled
            layout_verification_required = self._layout_verification_required
            layout_verification_reason = self._last_layout_verification_reason
            layout_verification_frames = self._layout_verification_frames
            geometry_transition_signature = self._geometry_transition_signature
            geometry_transition_reasons = self._geometry_transition_reasons
            geometry_transition_last_changed_at = self._geometry_transition_last_changed_at
            geometry_transition_settle_seconds = self._geometry_transition_settle_seconds
        with self._window_lock:
            target_hwnd = self._target_hwnd
        if using_fallback and layout:
            source = "fallback"
        elif layout and relative:
            source = "client_relative"
        elif layout:
            source = "auto"
        else:
            source = "none"
        remaining = max(0.0, next_auto_locate_at - self._clock())
        return {
            "layout_source": source,
            "runtime_capture_strategy": "teap_strip_only",
            "locator_capture_strategy": "bounded_top_left_te_v3_header",
            "layout_verification_required": layout_verification_required,
            "layout_verification_frames": layout_verification_frames,
            "last_layout_verification_reason": layout_verification_reason,
            "target_hwnd": target_hwnd,
            "last_verified_layout": None if last_verified is None else {
                "x": last_verified.x, "y": last_verified.y,
                "block_size": last_verified.block_size, "gap": last_verified.block_gap,
            },
            "layout": None if layout is None else {
                "x": layout.x, "y": layout.y, "block_size": layout.block_size,
                "gap": layout.block_gap, "block_count": layout.block_count,
                "strip_bounds": layout.strip_bounds().to_dict(),
                "sample_points": list(layout.sample_points()),
            },
            "relative_layout": None if relative is None else relative.to_dict(),
            "last_verified_relative_layout": None if verified_relative is None else verified_relative.to_dict(),
            "runtime_capture_bounds": None if runtime_capture_bounds is None else runtime_capture_bounds.to_dict(),
            "last_verified_client_geometry": None if last_verified_geometry is None else last_verified_geometry.to_dict(),
            "last_geometry_change_reasons": list(last_geometry_change_reasons),
            "geometry_transition_active": geometry_transition_signature is not None,
            "geometry_transition_reasons": list(geometry_transition_reasons),
            "geometry_transition_age_ms": (
                0
                if geometry_transition_signature is None
                else int(round(max(0.0, self._clock() - geometry_transition_last_changed_at) * 1000))
            ),
            "geometry_transition_settle_ms": int(round(geometry_transition_settle_seconds * 1000)),
            "relocation_pending": relocation_pending,
            "background_relocation_enabled": background_relocation_enabled,
            "background_relocation_active": background_relocation_active,
            "last_relocation_reason": last_relocation_reason,
            "fallback_layout": {
                "x": self.fallback_layout.x,
                "y": self.fallback_layout.y,
                "block_size": self.fallback_layout.block_size,
                "gap": self.fallback_layout.block_gap,
            },
            "sampler_backend": sampler_backend,
            "configured_sampler_backend": self._configured_sampler_backend,
            "sampler_fallback_locked": sampler_fallback_locked,
            "sampler_failure_count": sampler_failures,
            "sampler_failure_threshold": self.sampler_failure_threshold,
            "last_sampler_switch_reason": last_sampler_switch_reason,
            "consecutive_failures": failures,
            "failure_threshold": self.failure_threshold,
            "last_decode_error": last_error,
            "recent_decode_error": recent_decode_error,
            "auto_locate_backoff_remaining_ms": int(round(remaining * 1000)),
            "auto_locate_backoff_seconds": auto_locate_backoff_seconds,
            "display": display_calibration.to_dict() if display_calibration and hasattr(display_calibration, "to_dict") else None,
            "calibration_read_mode": self._last_calibration_mode,
            "full_calibration_interval_ms": int(round(self._full_calibration_interval_seconds * 1000)),
        }

    def calibrate(self) -> SignalLayout:
        if not self.auto_locate:
            raise OSError("auto_locate_disabled")
        calibration = self._read_window_calibration()
        # The manual button is now only an explicit request to retry the same
        # background-safe v3 header locator.  Hold the writer lease through both
        # proof frames so readers observe either the old verified layout or the
        # fully verified replacement, never a one-frame candidate.
        with self._layout_lock.write_lock():
            layout = self._locate_layout_locked(calibration)
            self._install_located_layout_locked(layout, calibration)
            reader = ScreenFrameSource(layout, sampler=self.sampler)
            first = reader.read()
            verified = self._verify_layout_frames(
                layout,
                first,
                calibration=calibration,
                next_reader=reader.read,
                hold_layout_writer=True,
            )
            self._last_runtime_capture_bounds = layout.strip_bounds()
            self._last_layout_verification_reason = (
                f"manual_verified:{self._layout_verification_frames}:freshness={verified.frame_freshness_counter}"
            )
            return layout

    def read(self):
        calibration = self._read_window_calibration()
        plan = self._layout_for_read(calibration)
        layout = plan.layout
        try:
            frame = self._read_layout(layout)
            frame = self._verify_layout_if_required(layout, frame, calibration)
        except Exception as error:
            should_switch = self._remember_read_error(error)
            if should_switch:
                self._switch_to_pillow(error)
                try:
                    frame = self._read_layout(layout)
                    frame = self._verify_layout_if_required(layout, frame, calibration)
                except Exception as retry_error:
                    self._remember_read_error(retry_error)
                    self._handle_layout_failure(
                        preserve_verified_layout=plan.requires_relocation_on_failure,
                    )
                    raise retry_error
                self._mark_read_success(layout, calibration)
                return frame

            # P2-B: a material client-geometry transition first tries the
            # predicted narrow TEAP strip. If that validation fails, re-locate
            # immediately inside *this* WoW client rectangle. The locator never
            # scans the virtual desktop in UI-linked operation. During the
            # transition the failed frame is propagated, so TEK cannot dispatch
            # to a possibly recreated/moved game window until a fresh valid
            # frame has been read.
            relocated = None
            if plan.requires_relocation_on_failure:
                relocated = self._relocate_after_geometry_change(calibration, plan, error)
            if relocated is not None:
                try:
                    frame = self._read_layout(relocated)
                    frame = self._verify_layout_if_required(relocated, frame, calibration)
                except Exception as retry_error:
                    self._remember_read_error(retry_error)
                    self._handle_layout_failure(preserve_verified_layout=True)
                    raise retry_error
                self._mark_read_success(relocated, calibration)
                return frame

            self._handle_layout_failure(
                preserve_verified_layout=plan.requires_relocation_on_failure,
            )
            raise
        self._mark_read_success(layout, calibration)
        return frame

    def _verify_layout_if_required(self, layout: SignalLayout, first_frame, calibration):
        with self._layout_lock.read_lock():
            required = self._layout_verification_required
        if not required:
            return first_frame
        return self._verify_layout_frames(layout, first_frame, calibration=calibration)

    def _verify_layout_frames(
        self,
        layout: SignalLayout,
        first_frame,
        *,
        calibration,
        next_reader=None,
        hold_layout_writer: bool = False,
    ):
        """Require multiple whole-frame reads before trusting new geometry.

        Header discovery has already decoded one CRC/commit-valid frame.  The
        second proof must also be complete and must advance the TEAP freshness
        counter.  This prevents a static game image or a cached/old screenshot
        from installing a layout that could later authorize input.
        """
        reader = next_reader or (lambda: self._read_layout(layout))
        frame = first_frame
        session_epoch = frame.session_epoch
        freshness = frame.frame_freshness_counter
        for _ in range(1, self._layout_verification_frames):
            time.sleep(self._layout_verification_interval_seconds)
            next_frame = reader()
            if next_frame.session_epoch != session_epoch:
                raise OSError("te_signal_layout_verification_session_changed")
            if next_frame.frame_freshness_counter == freshness:
                raise OSError("te_signal_layout_verification_freshness_stalled")
            frame = next_frame
            freshness = frame.frame_freshness_counter

        # The manual-calibration path already owns the writer lease.  Normal
        # reads acquire it only for the atomic candidate→verified transition.
        if hold_layout_writer:
            # Manual calibration already owns the write lease.
            self._install_verified_layout_locked(layout, calibration)
            self._last_layout_verification_reason = (
                f"verified:{self._layout_verification_frames}:freshness={freshness}"
            )
        else:
            with self._layout_lock.write_lock():
                # A concurrent relocation cannot turn another layout into a
                # trusted result while this caller was validating its own.
                current_layout = self._cached_layout
                if current_layout != layout:
                    projected = self._project_layout(
                        self._relative_layout,
                        self._client_bounds(calibration),
                    )
                    if projected != layout:
                        raise OSError("te_signal_layout_verification_layout_changed")
                self._install_verified_layout_locked(layout, calibration)
                self._last_layout_verification_reason = (
                    f"verified:{self._layout_verification_frames}:freshness={freshness}"
                )
        return frame

    def _read_window_calibration(self):
        """Return fresh client bounds with throttled full display metadata.

        Hot reads only need ``GetClientRect`` + ``ClientToScreen``. Full DPI,
        monitor and style inspection remains available on a bounded cadence and
        after an HWND change, preserving P2-B mode-change detection without
        repeating the full WinAPI chain every 50 ms.
        """
        with self._window_lock:
            hwnd = self._target_hwnd
        provider = self.calibration_provider
        fast_provider = self.fast_calibration_provider
        try:
            if not hwnd or not callable(fast_provider):
                self._last_calibration_mode = "full"
                if hwnd:
                    try:
                        calibration = provider(hwnd)
                    except TypeError:
                        calibration = provider()
                else:
                    calibration = provider()
                with self._layout_lock.write_lock():
                    self._last_full_calibration = calibration
                    self._next_full_calibration_at = self._clock() + self._full_calibration_interval_seconds
                return calibration

            now = self._clock()
            with self._layout_lock.read_lock():
                cached_full = self._last_full_calibration
                full_due = (
                    cached_full is None
                    or int(getattr(cached_full, "hwnd", 0) or 0) != int(hwnd)
                    or now >= self._next_full_calibration_at
                )
            if full_due:
                try:
                    calibration = provider(hwnd)
                except TypeError:
                    calibration = provider()
                with self._layout_lock.write_lock():
                    self._last_full_calibration = calibration
                    self._next_full_calibration_at = now + self._full_calibration_interval_seconds
                self._last_calibration_mode = "full"
                return calibration

            try:
                fast = fast_provider(hwnd)
            except TypeError:
                fast = fast_provider()
            if fast is None or getattr(fast, "client_rect", None) is None or getattr(fast, "client_origin", None) is None:
                # Fail closed to the cached full result rather than constructing
                # a partial geometry object that could project the strip wrongly.
                self._last_calibration_mode = "cached_full"
                return cached_full
            # Preserve expensive metadata from the most recent full inspection
            # while replacing only hot client bounds/origin.
            calibration = replace(
                fast,
                dpi=getattr(cached_full, "dpi", None),
                window_mode=getattr(cached_full, "window_mode", "unknown"),
                window_rect=getattr(cached_full, "window_rect", None),
                monitor_rect=getattr(cached_full, "monitor_rect", None),
                virtual_desktop=getattr(cached_full, "virtual_desktop", None),
                reason=getattr(fast, "reason", None) or getattr(cached_full, "reason", None),
            )
            self._last_calibration_mode = "fast_client"
            return calibration
        except Exception as error:
            with self._layout_lock.write_lock():
                self._last_error = f"calibration_error:{type(error).__name__}:{error}"
            return None

    @staticmethod
    def _client_bounds(calibration) -> CaptureBounds | None:
        try:
            raw = client_capture_bounds(calibration)
        except Exception:
            raw = None
        if not raw:
            return None
        left, top, right, bottom = raw
        bounds = CaptureBounds(int(left), int(top), int(right), int(bottom))
        return bounds if bounds.width > 0 and bounds.height > 0 else None

    def _layout_for_read(self, calibration) -> _LayoutReadPlan:
        """Return one immutable projected layout and client-geometry decision."""
        now = self._clock()
        bounds = self._client_bounds(calibration)
        geometry = self._geometry_from_calibration(calibration, bounds)
        with self._layout_lock.read_lock():
            layout = self._cached_layout
            relative = self._relative_layout
            previous_geometry = self._last_verified_geometry
            relocation_pending = self._relocation_pending
            background_active = self._background_relocation_active
            retry_auto_locate = bool(
                self.auto_locate
                and (self._using_fallback or relocation_pending)
                and now >= self._next_auto_locate_at
                and not (self._background_relocation_enabled and layout is not None)
                and not background_active
            )
            if layout is not None and not retry_auto_locate:
                changes = self._geometry_change_reasons(previous_geometry, geometry)
                if changes and self._layout_verification_required:
                    candidate_signature = self._geometry_signature(self._candidate_geometry)
                    if candidate_signature != self._geometry_signature(geometry):
                        raise OSError(f"layout_relocating:{','.join(changes)}")
                    projected = self._project_layout(relative, bounds)
                    return _LayoutReadPlan(
                        layout=projected or layout,
                        geometry=geometry,
                        geometry_change_reasons=changes,
                    )
                if changes and self._is_material_geometry_change(changes):
                    pass
                else:
                    projected = self._project_layout(relative, bounds)
                    return _LayoutReadPlan(
                        layout=projected or layout,
                        geometry=geometry,
                        geometry_change_reasons=changes,
                    )
        with self._layout_lock.write_lock():
            current_layout = self._cached_layout
            previous_geometry = self._last_verified_geometry
            changes = self._geometry_change_reasons(previous_geometry, geometry)
            if current_layout is not None and changes and self._layout_verification_required:
                candidate_signature = self._geometry_signature(self._candidate_geometry)
                if candidate_signature != self._geometry_signature(geometry):
                    raise OSError(f"layout_relocating:{','.join(changes)}")
                projected = self._project_layout(self._relative_layout, bounds)
                return _LayoutReadPlan(
                    layout=projected or current_layout,
                    geometry=geometry,
                    geometry_change_reasons=changes,
                )
            if current_layout is not None and changes and self._is_material_geometry_change(changes):
                self._prepare_geometry_transition_locked(
                    geometry=geometry,
                    reasons=changes,
                    now=now,
                )
                raise OSError(self._last_error or self._geometry_transition_wait_reason_locked(now))

            layout = self._ensure_layout_locked(calibration, bounds)
            previous_geometry = self._last_verified_geometry
            changes = self._geometry_change_reasons(previous_geometry, geometry)
            if changes and self._layout_verification_required:
                candidate_signature = self._geometry_signature(self._candidate_geometry)
                if candidate_signature != self._geometry_signature(geometry):
                    raise OSError(f"layout_relocating:{','.join(changes)}")
            if changes and self._is_material_geometry_change(changes):
                self._prepare_geometry_transition_locked(
                    geometry=geometry,
                    reasons=changes,
                    now=now,
                )
                raise OSError(self._last_error or self._geometry_transition_wait_reason_locked(now))
            return _LayoutReadPlan(
                layout=layout,
                geometry=geometry,
                geometry_change_reasons=changes,
            )

    @staticmethod
    def _is_material_geometry_change(reasons: tuple[str, ...]) -> bool:
        return any(
            reason in {
                "hwnd_changed",
                "client_resized",
                "dpi_changed",
                "window_mode_changed",
                "monitor_changed",
            }
            for reason in reasons
        )

    @staticmethod
    def _geometry_signature(geometry: _ClientGeometry | None):
        if geometry is None:
            return None
        return (
            geometry.hwnd,
            geometry.bounds.left,
            geometry.bounds.top,
            geometry.bounds.width,
            geometry.bounds.height,
            geometry.dpi,
            geometry.window_mode,
            geometry.monitor_rect,
        )

    def _prepare_geometry_transition_locked(
        self,
        *,
        geometry: _ClientGeometry | None,
        reasons: tuple[str, ...],
        now: float,
    ) -> None:
        signature = self._geometry_signature(geometry)
        if self._geometry_transition_signature != signature:
            self._geometry_transition_signature = signature
            self._geometry_transition_last_changed_at = now
        self._geometry_transition_reasons = reasons
        self._last_geometry_change_reasons = reasons
        self._relocation_pending = True
        self._last_relocation_reason = f"geometry_transition_wait:{','.join(reasons)}"
        self._last_error = self._geometry_transition_wait_reason_locked(now)
        self._recent_decode_error = self._last_error
        if now < self._next_auto_locate_at:
            return
        if now - self._geometry_transition_last_changed_at < self._geometry_transition_settle_seconds:
            return
        self._relocate_after_stable_geometry_locked(geometry=geometry, reasons=reasons)

    def _geometry_transition_wait_reason_locked(self, now: float) -> str:
        reasons = ",".join(self._geometry_transition_reasons) or "geometry_changed"
        remaining = max(
            0.0,
            self._geometry_transition_settle_seconds - (now - self._geometry_transition_last_changed_at),
        )
        if remaining > 0:
            return f"geometry_transition_wait:{reasons}:remaining_ms={int(round(remaining * 1000))}"
        return f"layout_relocating:{reasons}"

    def _relocate_after_stable_geometry_locked(
        self,
        *,
        geometry: _ClientGeometry | None,
        reasons: tuple[str, ...],
    ) -> None:
        if not self.auto_locate:
            return
        reason = ",".join(reasons) or "geometry_changed"
        try:
            layout = self._locate_layout_locked_from_geometry(geometry)
            self._install_located_layout_locked(layout, self._calibration_from_geometry(geometry))
            self._last_relocation_reason = f"geometry_transition_relocated:{reason}"
            self._last_error = f"layout_relocating:{reason}"
            self._recent_decode_error = self._last_error
            self._geometry_transition_signature = None
            self._geometry_transition_reasons = ()
        except Exception as error:
            message = f"{type(error).__name__}:{error}"
            self._last_error = message
            self._recent_decode_error = message
            self._relocation_pending = True
            self._last_relocation_reason = f"layout_relocating:{reason}:{message}"
            self._schedule_auto_locate_backoff_locked()

    def _locate_layout_locked_from_geometry(self, geometry: _ClientGeometry | None) -> SignalLayout:
        if geometry is not None:
            return self.client_locate_function(geometry.bounds)
        raise OSError("wow_client_area_unavailable")

    @staticmethod
    def _calibration_from_geometry(geometry: _ClientGeometry | None):
        if geometry is None:
            return None
        return SimpleNamespace(
            hwnd=geometry.hwnd,
            client_origin=(geometry.bounds.left, geometry.bounds.top),
            client_rect=(0, 0, geometry.bounds.width, geometry.bounds.height),
            dpi=geometry.dpi,
            window_mode=geometry.window_mode,
            monitor_rect=geometry.monitor_rect,
        )

    def _geometry_from_calibration(self, calibration, bounds: CaptureBounds | None) -> _ClientGeometry | None:
        if bounds is None:
            return None
        with self._window_lock:
            target_hwnd = int(self._target_hwnd or 0)
        hwnd = int(getattr(calibration, "hwnd", 0) or target_hwnd or 0)
        dpi = getattr(calibration, "dpi", None)
        try:
            dpi = int(dpi) if dpi is not None else None
        except (TypeError, ValueError):
            dpi = None
        mode = str(getattr(calibration, "window_mode", "") or "").strip() or None
        monitor = getattr(calibration, "monitor_rect", None)
        try:
            monitor = tuple(int(value) for value in monitor) if monitor else None
        except (TypeError, ValueError):
            monitor = None
        return _ClientGeometry(
            hwnd=hwnd,
            bounds=bounds,
            dpi=dpi,
            window_mode=mode,
            monitor_rect=monitor,
        )

    @staticmethod
    def _geometry_change_reasons(
        previous: _ClientGeometry | None,
        current: _ClientGeometry | None,
    ) -> tuple[str, ...]:
        if previous is None or current is None:
            return ()
        reasons: list[str] = []
        if previous.hwnd and current.hwnd and previous.hwnd != current.hwnd:
            reasons.append("hwnd_changed")
        if (previous.bounds.left, previous.bounds.top) != (current.bounds.left, current.bounds.top):
            reasons.append("client_moved")
        if (previous.bounds.width, previous.bounds.height) != (current.bounds.width, current.bounds.height):
            reasons.append("client_resized")
        if previous.dpi is not None and current.dpi is not None and previous.dpi != current.dpi:
            reasons.append("dpi_changed")
        if previous.window_mode and current.window_mode and previous.window_mode != current.window_mode:
            reasons.append("window_mode_changed")
        if previous.monitor_rect and current.monitor_rect and previous.monitor_rect != current.monitor_rect:
            reasons.append("monitor_changed")
        return tuple(reasons)

    @staticmethod
    def _project_layout(relative: RelativeSignalLayout | None, bounds: CaptureBounds | None) -> SignalLayout | None:
        if relative is None or bounds is None:
            return None
        return relative.project(
            client_left=bounds.left,
            client_top=bounds.top,
            client_width=bounds.width,
            client_height=bounds.height,
        )

    def _read_layout(self, layout: SignalLayout):
        with self._layout_lock.read_lock():
            sampler = self.sampler
            key = (id(sampler), layout)
            reader = self._reader_cache.get(key)
        if reader is None:
            with self._layout_lock.write_lock():
                sampler = self.sampler
                key = (id(sampler), layout)
                reader = self._reader_cache.get(key)
                if reader is None:
                    reader = ScreenFrameSource(layout, sampler=sampler)
                    self._reader_cache[key] = reader
                    if len(self._reader_cache) > 32:
                        self._reader_cache.popitem(last=False)
                else:
                    self._reader_cache.move_to_end(key)
        # Pillow now captures only layout.strip_bounds(); GDI already samples
        # twenty pixels directly. Both paths avoid full virtual-desktop capture
        # during normal operation.
        frame = reader.read()
        with self._layout_lock.write_lock():
            self._last_runtime_capture_bounds = layout.strip_bounds()
        return frame

    def _mark_read_success(self, layout: SignalLayout, calibration) -> None:
        bounds = self._client_bounds(calibration)
        geometry = self._geometry_from_calibration(calibration, bounds)
        with self._layout_lock.write_lock():
            previous_geometry = self._last_verified_geometry
            self._cached_layout = layout
            self._last_verified_layout = layout
            if bounds is not None:
                # A pure client move preserves the existing ratio exactly; do
                # not allocate a new RelativeSignalLayout on every move/tick.
                projected = self._project_layout(self._relative_layout, bounds)
                if projected != layout:
                    relative = RelativeSignalLayout.from_layout(
                        layout,
                        client_left=bounds.left,
                        client_top=bounds.top,
                        client_width=bounds.width,
                        client_height=bounds.height,
                    )
                    if relative is not None:
                        self._relative_layout = relative
            self._last_verified_relative_layout = self._relative_layout
            if geometry is not None:
                changes = self._geometry_change_reasons(previous_geometry, geometry)
                # Keep a just-observed mode/DPI transition visible through the
                # successful proof read. A subsequent steady-state tick may
                # clear it naturally when a later real change is observed.
                if changes or previous_geometry is None:
                    self._last_geometry_change_reasons = changes
                self._last_verified_geometry = geometry
            self._candidate_geometry = None
            if calibration is not None:
                self._display_calibration = calibration
            self._using_fallback = False
            self._relocation_pending = False
            self._consecutive_failures = 0
            self._sampler_consecutive_failures = 0
            self._last_error = None
            self._maybe_promote_auto_sampler_locked()
            self._mark_layout_cache_dirty_locked()

    def _maybe_promote_auto_sampler_locked(self) -> None:
        if not self._auto_sampler_mode or self._sampler_fallback_locked:
            return
        backend = str(getattr(self.sampler, "backend", "") or "").lower()
        if backend != "pillow":
            return
        self._auto_pillow_successes += 1
        if self._auto_pillow_successes < self._auto_promotion_successes_required:
            return
        try:
            self.sampler = GDIBlitStripSampler()
            self._reader_cache.clear()
            self._last_sampler_switch_reason = "auto_promoted_pillow_to_gdi_blt"
        except Exception as error:
            # Unsupported hosts and constrained desktops remain on Pillow; this
            # is an optimization failure, never a TEAP/dispatch failure.
            self._last_sampler_switch_reason = f"auto_promotion_unavailable:{type(error).__name__}:{error}"
            self._sampler_fallback_locked = True

    def _remember_read_error(self, error: Exception) -> bool:
        message = f"{type(error).__name__}:{error}"
        with self._layout_lock.write_lock():
            self._last_error = message
            self._recent_decode_error = message
            sampler_backend = str(getattr(self.sampler, "backend", self._configured_sampler_backend) or self._configured_sampler_backend).lower()
            if sampler_backend in {"gdi", "gdi_blt"} and not self._sampler_fallback_locked:
                self._sampler_consecutive_failures += 1
                return self._sampler_consecutive_failures >= self.sampler_failure_threshold
            return False

    def _switch_to_pillow(self, error: Exception) -> None:
        message = f"{type(error).__name__}:{error}"
        with self._layout_lock.write_lock():
            previous_backend = str(
                getattr(self.sampler, "backend", self._configured_sampler_backend)
                or self._configured_sampler_backend
            ).lower()
            self.sampler = self._pillow_sampler_factory()
            self._reader_cache.clear()
            self._sampler_fallback_locked = True
            self._sampler_consecutive_failures = 0
            fallback_prefix = "gdi_to_pillow" if previous_backend == "gdi" else f"{previous_backend}_to_pillow"
            self._last_sampler_switch_reason = f"{fallback_prefix}:{message}"

    def _handle_layout_failure(self, *, preserve_verified_layout: bool = False) -> None:
        with self._layout_lock.write_lock():
            self._consecutive_failures += 1
            if self._consecutive_failures < self.failure_threshold:
                return
            if self.auto_locate:
                if self._background_relocation_enabled and self._background_relocation_active and self._last_verified_layout is not None:
                    self._cached_layout = self._last_verified_layout
                    self._relative_layout = self._last_verified_relative_layout
                    self._using_fallback = False
                    self._relocation_pending = True
                    self._consecutive_failures = 0
                    return
                # P2-B keeps a known-good relative layout alive while a display
                # mode transition is in progress. It remains non-dispatchable
                # because reads keep failing, but avoids regressing to a fixed
                # desktop coordinate before the current-client re-location
                # backoff expires.
                if preserve_verified_layout and self._last_verified_layout is not None:
                    self._cached_layout = self._last_verified_layout
                    self._relative_layout = self._last_verified_relative_layout
                    self._using_fallback = False
                    self._relocation_pending = True
                    self._last_relocation_reason = self._last_relocation_reason or "geometry_change_retry"
                else:
                    # A proven layout never falls back to default 12,12. The
                    # next read re-locates inside the current WoW client area.
                    self._cached_layout = None
                    self._using_fallback = False
                    if self._last_verified_layout is not None:
                        self._next_auto_locate_at = 0.0
                    else:
                        self._cached_layout = None
                        self._using_fallback = False
                        self._relocation_pending = True
                        self._schedule_auto_locate_backoff_locked()
            else:
                self._cached_layout = self.fallback_layout
                self._using_fallback = True
            self._consecutive_failures = 0

    def _ensure_layout(self) -> SignalLayout:
        calibration = self._read_window_calibration()
        bounds = self._client_bounds(calibration)
        with self._layout_lock.write_lock():
            return self._ensure_layout_locked(calibration, bounds)

    def _ensure_layout_locked(self, calibration, bounds: CaptureBounds | None) -> SignalLayout:
        now = self._clock()
        retry_auto_locate = bool(
            self.auto_locate
            and (self._using_fallback or self._relocation_pending)
            and now >= self._next_auto_locate_at
        )
        if self._cached_layout is not None and not retry_auto_locate:
            return self._project_layout(self._relative_layout, bounds) or self._cached_layout

        if self.auto_locate and now >= self._next_auto_locate_at:
            try:
                layout = self._locate_layout_locked(calibration)
                self._install_located_layout_locked(layout, calibration)
                return layout
            except Exception as error:
                message = f"{type(error).__name__}:{error}"
                self._last_error = message
                self._recent_decode_error = message
                self._schedule_auto_locate_backoff_locked()
                # A prior verified geometry is safer than falling back to the
                # old default strip during a transient fullscreen/DPI/window
                # recreation. Keep predicting from it until the bounded retry.
                if self._last_verified_layout is not None:
                    self._cached_layout = self._last_verified_layout
                    self._relative_layout = self._last_verified_relative_layout
                    self._using_fallback = False
                    self._relocation_pending = True
                    self._last_relocation_reason = self._last_relocation_reason or "client_relocate_backoff"
                    return self._project_layout(self._last_verified_relative_layout, bounds) or self._cached_layout
                self._cached_layout = None
                self._using_fallback = False
                self._relocation_pending = True
                raise OSError("te_signal_layout_not_found") from error

        if not self.auto_locate:
            # Explicit manual/fixed-layout mode is retained for diagnostics and
            # development. It is never selected by the automatic client-anchor
            # path above.
            self._cached_layout = self.fallback_layout
            self._using_fallback = True
            self._relocation_pending = False
            return self.fallback_layout

        # Automatic operation has no absolute-coordinate fallback.  A missing
        # or unverified header is a non-dispatchable SignalSearching state.
        self._using_fallback = False
        self._cached_layout = None
        self._relocation_pending = True
        raise OSError("te_signal_layout_search_backoff")

    def _relocate_after_geometry_change(
        self,
        calibration,
        plan: _LayoutReadPlan,
        read_error: Exception,
    ) -> SignalLayout | None:
        """Perform one immediate current-client scan after a material change.

        A predicted strip has already failed, so this operation is never used on
        the hot success path. Failed re-location is put behind the normal bounded
        auto-locate backoff and leaves TEK in a non-dispatching read-error state.
        """
        if not self.auto_locate:
            return None
        reason = ",".join(plan.geometry_change_reasons) or "geometry_changed"
        if self._background_relocation_enabled:
            self._schedule_background_relocation(calibration, plan, read_error, reason=reason)
            return None
        with self._layout_lock.write_lock():
            # A failed current-client scan has already scheduled an exponential
            # retry. Do not let every 50 ms strip read bypass that bound while a
            # fullscreen/DPI transition is still settling.
            if self._clock() < self._next_auto_locate_at:
                self._relocation_pending = True
                self._last_relocation_reason = self._last_relocation_reason or f"geometry_change_backoff:{reason}"
                return None
            try:
                layout = self._locate_layout_locked(calibration)
                self._install_located_layout_locked(layout, calibration)
                self._last_relocation_reason = f"geometry_change:{reason}"
                return layout
            except Exception as error:
                message = f"{type(error).__name__}:{error}"
                self._last_error = message
                self._recent_decode_error = message
                self._relocation_pending = True
                self._last_relocation_reason = (
                    f"geometry_change_failed:{reason}:"
                    f"after_{type(read_error).__name__}:{read_error}"
                )
                self._schedule_auto_locate_backoff_locked()
                return None

    def _schedule_background_relocation(self, calibration, plan: _LayoutReadPlan, read_error: Exception, *, reason: str) -> bool:
        """Start at most one client-only progressive locator outside the tick loop."""
        bounds = self._client_bounds(calibration)
        with self._window_lock:
            target_hwnd = int(self._target_hwnd or 0)
        if bounds is None or not target_hwnd:
            return False
        with self._layout_lock.write_lock():
            if self._closed:
                return False
            if self._background_relocation_active:
                self._relocation_pending = True
                return True
            if self._clock() < self._next_auto_locate_at:
                self._relocation_pending = True
                self._last_relocation_reason = self._last_relocation_reason or f"geometry_change_backoff:{reason}"
                return True
            self._background_relocation_active = True
            self._relocation_pending = True
            generation = self._relocation_generation
            self._last_relocation_reason = f"background_relocation_started:{reason}:after_{type(read_error).__name__}:{read_error}"

        thread = threading.Thread(
            target=self._run_background_relocation,
            args=(bounds, calibration, target_hwnd, generation, reason),
            name="TEKSignalRelocator",
            daemon=True,
        )
        with self._layout_lock.write_lock():
            self._relocation_thread = thread
        thread.start()
        return True

    def _run_background_relocation(self, bounds: CaptureBounds, calibration, target_hwnd: int, generation: int, reason: str) -> None:
        try:
            layout = self.client_locate_function(bounds)
        except Exception as error:
            with self._layout_lock.write_lock():
                self._background_relocation_active = False
                self._relocation_thread = None
                if not self._closed:
                    self._relocation_pending = True
                    self._last_error = f"{type(error).__name__}:{error}"
                    self._recent_decode_error = self._last_error
                    self._last_relocation_reason = f"background_relocation_failed:{reason}:{self._last_error}"
                    self._schedule_auto_locate_backoff_locked()
            return

        with self._window_lock:
            current_hwnd = int(self._target_hwnd or 0)
        with self._layout_lock.write_lock():
            self._background_relocation_active = False
            self._relocation_thread = None
            if self._closed or generation != self._relocation_generation or current_hwnd != target_hwnd:
                self._relocation_pending = True
                self._last_relocation_reason = f"background_relocation_discarded:{reason}"
                return
            # Header location/one-frame decode is only a candidate.  The next
            # normal read performs the second complete freshness-advancing proof
            # before this geometry becomes dispatch-capable.
            self._install_located_layout_locked(layout, calibration)
            self._last_relocation_reason = f"background_relocation_candidate:{reason}"

    def _locate_layout_locked(self, calibration) -> SignalLayout:
        bounds = self._client_bounds(calibration)
        with self._window_lock:
            target_hwnd = self._target_hwnd

        # UI-linked runtime has a foreground HWND supplied by TEKRunner. In that
        # path P2-A must scan only the WoW client rectangle, even if a caller has
        # retained a legacy locator for diagnostics or test instrumentation.
        if target_hwnd and bounds is not None:
            return self.client_locate_function(bounds)

        # Without a verified UI-linked target, an explicitly supplied locator is
        # the compatibility/CLI contract. This preserves legacy callers and test
        # doubles instead of accidentally scanning an unrelated generic client
        # rectangle and falling through to the fixed fallback layout.
        if callable(self.locate_function):
            return self.locate_function()

        if bounds is not None:
            # Last-resort non-UI caller: keep the P2-A search scope bounded when
            # a concrete client rectangle is available.
            return self.client_locate_function(bounds)
        raise OSError("wow_client_area_unavailable")

    def _install_located_layout_locked(self, layout: SignalLayout, calibration) -> None:
        """Install header-derived geometry; it becomes verified after two frames."""
        self._cached_layout = layout
        bounds = self._client_bounds(calibration)
        self._candidate_geometry = self._geometry_from_calibration(calibration, bounds)
        if bounds is not None:
            relative = RelativeSignalLayout.from_layout(
                layout,
                client_left=bounds.left,
                client_top=bounds.top,
                client_width=bounds.width,
                client_height=bounds.height,
            )
            if relative is not None:
                self._relative_layout = relative
        if calibration is not None:
            self._display_calibration = calibration
        self._using_fallback = False
        self._layout_verification_required = True
        self._last_layout_verification_reason = "candidate_header_located"
        self._relocation_pending = False
        self._consecutive_failures = 0
        self._last_error = None
        self._reset_auto_locate_backoff_locked()

    def _install_verified_layout_locked(self, layout: SignalLayout, calibration) -> None:
        self._install_located_layout_locked(layout, calibration)
        self._layout_verification_required = False
        self._last_verified_layout = layout
        self._last_verified_relative_layout = self._relative_layout
        bounds = self._client_bounds(calibration)
        geometry = self._geometry_from_calibration(calibration, bounds)
        if geometry is not None:
            self._last_geometry_change_reasons = self._geometry_change_reasons(
                self._last_verified_geometry,
                geometry,
            )
            self._last_verified_geometry = geometry
        self._candidate_geometry = None
        self._mark_layout_cache_dirty_locked()

    def _mark_layout_cache_dirty_locked(self) -> None:
        layout = self._last_verified_layout
        relative = self._last_verified_relative_layout
        if layout is None or relative is None:
            return
        signature = (layout, relative)
        if signature != self._layout_cache_signature:
            self._layout_cache_signature = signature
            self._layout_cache_dirty = True

    def _restore_layout_cache(self, cache: dict | None) -> None:
        if not isinstance(cache, dict):
            return
        layout = SignalLayout.from_dict(cache.get("layout"))
        relative = RelativeSignalLayout.from_dict(cache.get("relative_layout") or cache.get("relative"))
        if layout is None or relative is None:
            return
        # A persisted layout is a geometry hint, never an authorization.  It
        # must pass the same two-frame current-session proof as a newly located
        # header before it is marked verified or used for dispatch.
        self._cached_layout = layout
        self._last_verified_layout = None
        self._last_verified_relative_layout = None
        self._relative_layout = relative
        self._using_fallback = False
        self._layout_verification_required = True
        self._last_layout_verification_reason = "cached_layout_pending_proof"
        self._layout_cache_signature = None

    def _schedule_auto_locate_backoff(self) -> None:
        with self._layout_lock.write_lock():
            self._schedule_auto_locate_backoff_locked()

    def _schedule_auto_locate_backoff_locked(self) -> None:
        delay = self._auto_locate_backoff_seconds
        self._next_auto_locate_at = self._clock() + delay
        self._auto_locate_backoff_seconds = min(
            self._auto_locate_max_backoff_seconds,
            max(self._auto_locate_initial_backoff_seconds, delay * 2),
        )

    def _reset_auto_locate_backoff(self) -> None:
        with self._layout_lock.write_lock():
            self._reset_auto_locate_backoff_locked()

    def _reset_auto_locate_backoff_locked(self) -> None:
        self._next_auto_locate_at = 0.0
        self._auto_locate_backoff_seconds = self._auto_locate_initial_backoff_seconds
