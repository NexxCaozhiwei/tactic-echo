import json
import os
import tempfile
import threading
import time
import unittest
from dataclasses import replace
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

from tek.app.app_paths import AppPaths, resource_path
from tek.app.single_instance import SingleInstance
from tek.app.tray_controller import menu_labels, state_icon_candidates
from tek.app.worker_controller import AutoLocateFrameSource, WorkerController
from tek.runtime.runtime_status import TEKStatusSnapshot
from tek.runtime.status_mapper import is_snapshot_stale, status_color, trace_record_to_snapshot
from tek.runtime.status_store import StatusStore
from tek.src.engine import TraceRecord
from tek.src.dispatch_failure_tracker import DispatchFailureTracker
from tek.src.dispatch_rate_limiter import DispatchRateLimiter
from tek.src.input_planner import plan_binding
from tek.src.physical_input import PhysicalInputPause
from tek.src.safety_gate import SafetyContext
from tek.src.screen_sampler import SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import encode_test_blocks


def make_record(**overrides):
    values = {
        "accepted": True,
        "reason": "dry_run_planned",
        "sequence": 12,
        "state": "armed",
        "action_code": 1,
        "dispatcher_backend": "dry_run",
        "gatePassed": True,
        "dispatchAttempted": True,
        "inputSent": False,
        "tekState": "Armed",
        "action_id": "PALADIN_RETRIBUTION_JUDGMENT",
        "binding": "SHIFT+Z",
    }
    values.update(overrides)
    return TraceRecord(**values)


class FakeRunner:
    def __init__(self, records):
        self.records = list(records)
        self.index = 0

    def tick(self, config):
        record = self.records[min(self.index, len(self.records) - 1)]
        self.index += 1
        return record


class AppRuntimeTests(unittest.TestCase):
    def test_trace_record_maps_to_snapshot_and_green_color(self):
        snapshot = trace_record_to_snapshot(
            make_record(inputSent=True, reason="input_sent", dispatcher_backend="windows_sendinput"),
            mode="UI linked",
            started_at="2026-06-27T00:00:00+00:00",
            trace_path="trace.jsonl",
        )

        self.assertEqual(snapshot.process_state, "Armed")
        self.assertEqual(snapshot.last_action_id, "PALADIN_RETRIBUTION_JUDGMENT")
        self.assertTrue(snapshot.last_input_sent)
        self.assertEqual(status_color(snapshot), "green")

    def test_error_locked_maps_to_red(self):
        snapshot = trace_record_to_snapshot(
            make_record(tekState="ErrorLocked", dispatchError="sendinput_partial:1:4"),
            mode="UI linked",
            started_at=None,
            trace_path=None,
        )

        self.assertEqual(snapshot.process_state, "ErrorLocked")
        self.assertEqual(status_color(snapshot), "red")

    def test_frame_read_error_maps_to_waiting_not_error_locked(self):
        snapshot = trace_record_to_snapshot(
            make_record(
                accepted=False,
                reason="frame_read_error:OSError:te_signal_layout_not_found",
                sequence=-1,
                tekState="Blocked",
                dispatchError="OSError:te_signal_layout_not_found",
            ),
            mode="UI linked",
            started_at=None,
            trace_path=None,
        )

        self.assertEqual(snapshot.process_state, "Waiting")
        self.assertEqual(status_color(snapshot), "blue")

    def test_status_store_atomic_write_and_tolerant_read(self):
        with tempfile.TemporaryDirectory() as directory:
            store = StatusStore(Path(directory) / "logs" / "tek-status.json")
            snapshot = TEKStatusSnapshot.stopped(log_dir=str(Path(directory) / "logs"))

            store.write(snapshot)
            self.assertEqual(store.read().process_state, "Stopped")

            store.path.write_text("{bad json", encoding="utf-8")
            self.assertIsNone(store.read())

    def test_stale_snapshot_detection(self):
        snapshot = TEKStatusSnapshot.stopped(log_dir=None)

        self.assertTrue(is_snapshot_stale(snapshot, max_age_seconds=-1))

    def test_auto_locate_source_caches_discovered_layout(self):
        class StableSampler:
            backend = "pillow"
            def __init__(self):
                self.freshness = 0
            def sample(self, layout):
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=1, frame_freshness_counter=self.freshness))

        calls = []
        located = SignalLayout(x=222, y=18, block_size=10, block_gap=2)

        def locate():
            calls.append(True)
            return located

        source = AutoLocateFrameSource(
            auto_locate=True,
            fallback_layout=SignalLayout(x=12, y=12),
            sampler=StableSampler(),
            locate_function=locate,
            layout_verification_interval_seconds=0,
        )
        source.read()
        source.read()

        self.assertEqual(len(calls), 1)
        self.assertEqual(source.cached_layout, located)
        self.assertFalse(source.using_fallback)

    def test_auto_locate_source_relocates_after_repeated_failures_without_default_fallback(self):
        class FlakySampler:
            backend = "pillow"
            def __init__(self):
                self.fail = False
                self.freshness = 0
            def sample(self, layout):
                if self.fail:
                    raise ValueError("bad_pixels")
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=1, frame_freshness_counter=self.freshness))

        located = SignalLayout(x=222, y=18)
        sampler = FlakySampler()
        source = AutoLocateFrameSource(
            auto_locate=True,
            fallback_layout=SignalLayout(x=91, y=92),
            sampler=sampler,
            locate_function=lambda: located,
            failure_threshold=2,
            layout_verification_interval_seconds=0,
        )
        source.read()  # establish a decoded, verified layout
        sampler.fail = True
        with self.assertRaises(ValueError):
            source.read()
        with self.assertRaises(ValueError):
            source.read()

        self.assertFalse(source.using_fallback)
        self.assertIsNone(source.cached_layout)
        # The next read locates again rather than sampling the default fallback.
        with self.assertRaises(ValueError):
            source.read()
        self.assertEqual(source.cached_layout, located)

    def test_status_store_serializes_same_process_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            store = StatusStore(Path(directory) / "logs" / "tek-status.json")
            self.assertTrue(hasattr(store, "_write_lock"))
            store.write(TEKStatusSnapshot.stopped(log_dir=directory))
            self.assertIsNotNone(store.read())

    def test_worker_start_stop_duplicate_and_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            store = StatusStore(paths.status_json)
            released = []
            worker = WorkerController(
                paths=paths,
                status_store=store,
                runner_factory=lambda _: FakeRunner([make_record()]),
                modifier_releaser=lambda: released.append(True),
            )

            self.assertTrue(worker.start_dry_run())
            self.assertFalse(worker.start_dry_run())
            time.sleep(0.05)
            self.assertTrue(worker.stop())

            self.assertTrue(released)
            self.assertEqual(worker.snapshot.process_state, "Stopped")
            self.assertTrue(paths.trace_path_for_today().exists())

    def test_error_locked_recovery_resets_failure_limiter_and_recovery_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            worker = WorkerController(paths=paths, status_store=StatusStore(paths.status_json))
            guard = PhysicalInputPause(profile="balanced")
            guard.observe_freshness(10)
            guard.begin_manual_hold("Q")
            guard.end_manual_hold("Q")
            limiter = DispatchRateLimiter(max_per_second=2)
            limiter.allow(plan_binding("Q"))
            failures = DispatchFailureTracker()
            failures.record_failure()
            failures.record_failure()
            runner = SimpleNamespace(
                context=SafetyContext(),
                engine=SimpleNamespace(
                    failure_tracker=failures,
                    rate_limiter=limiter,
                    physical_input_guard=guard,
                ),
            )
            worker._runner = runner
            worker._thread = threading.current_thread()
            worker._set_snapshot(replace(worker.snapshot, process_state="ErrorLocked", safety_state="ErrorLocked"))

            self.assertTrue(worker.recover_error())
            self.assertEqual(worker.snapshot.process_state, "Waiting")
            self.assertEqual(failures.snapshot()["recent_failures"], 0)
            self.assertEqual(limiter.snapshot()["used_global"], 0)
            self.assertIsNone(guard.dispatch_block_reason())
            self.assertTrue(runner.context.allow_initial_armed_dispatch)

    def test_pending_hook_shutdown_blocks_new_worker_start(self):
        class PendingHook:
            def is_stopping(self):
                return True

        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            worker = WorkerController(paths=paths, status_store=StatusStore(paths.status_json))
            worker._physical_input_monitor = PendingHook()
            self.assertFalse(worker.start_dry_run())
            self.assertEqual(worker.snapshot.process_state, "Stopping")
            self.assertEqual(worker.snapshot.last_reason, "physical_input_hook_stopping")

    def test_worker_exception_becomes_worker_exited_snapshot(self):
        class BrokenRunner:
            def tick(self, config):
                raise RuntimeError("boom")

        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            worker = WorkerController(
                paths=paths,
                status_store=StatusStore(paths.status_json),
                runner_factory=lambda _: BrokenRunner(),
            )

            self.assertTrue(worker.start_dry_run())
            time.sleep(0.05)

            self.assertEqual(worker.snapshot.process_state, "WorkerExited")
            self.assertEqual(status_color(worker.snapshot), "red")

    def test_app_paths_use_local_app_data(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {"LOCALAPPDATA": directory}):
                paths = AppPaths.from_environment()

            self.assertEqual(paths.root, Path(directory) / "TacticEcho")
            self.assertEqual(paths.status_json.name, "tek-status.json")

    def test_app_paths_seed_default_profile_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            profile = paths.default_profile_path()
            self.assertTrue(profile.exists())

            profile.write_text('{"custom":true}', encoding="utf-8")
            paths.ensure()
            self.assertEqual(profile.read_text(encoding="utf-8"), '{"custom":true}')

    def test_app_paths_refreshes_stale_default_profile_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            profile = paths.default_profile_path()
            data = json.loads(profile.read_text(encoding="utf-8-sig"))
            data["catalogFingerprint"] = "old-catalog"
            profile.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

            paths.ensure()

            refreshed = json.loads(profile.read_text(encoding="utf-8-sig"))
            bundled = json.loads(resource_path("examples/profiles/laptop.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(refreshed["catalogFingerprint"], bundled["catalogFingerprint"])

    def test_app_paths_preserves_custom_default_profile_on_catalog_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(directory)
            paths.ensure()
            profile = paths.default_profile_path()
            data = json.loads(profile.read_text(encoding="utf-8-sig"))
            data["catalogFingerprint"] = "old-catalog"
            data["profileFingerprint"] = "custom-fingerprint"
            profile.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

            paths.ensure()

            preserved = json.loads(profile.read_text(encoding="utf-8-sig"))
            self.assertEqual(preserved["catalogFingerprint"], "old-catalog")
            self.assertEqual(preserved["profileFingerprint"], "custom-fingerprint")

    def test_single_instance_blocks_second_instance(self):
        with tempfile.TemporaryDirectory() as directory:
            first = SingleInstance(Path(directory) / "tek.lock")
            second = SingleInstance(Path(directory) / "tek.lock")
            try:
                self.assertTrue(first.acquire())
                self.assertFalse(second.acquire())
            finally:
                first.release()
                second.release()

    def test_single_instance_recovers_stale_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            lock_path = Path(directory) / "tek.lock"
            lock_path.write_text("999999", encoding="ascii")
            instance = SingleInstance(lock_path)
            try:
                self.assertTrue(instance.acquire())
                self.assertEqual(lock_path.read_text(encoding="ascii"), str(os.getpid()))
            finally:
                instance.release()

    def test_menu_labels_reflect_snapshot(self):
        labels = menu_labels(TEKStatusSnapshot.stopped(log_dir="logs"))

        self.assertIn("状态：Stopped", labels)
        self.assertIn("启动 UI 联动", labels)

    def test_tray_state_icon_candidates_map_available_assets(self):
        expected = {
            "gray": "TEK_GREY.png",
            "blue": "TEK_BLUE.png",
            "green": "TEK_GREEN.png",
            "yellow": "TEK_YELLOW.png",
            "red": "TEK_RED.png",
        }

        for color, filename in expected.items():
            candidates = state_icon_candidates(color)
            self.assertEqual(candidates[0].name, filename)
            self.assertTrue(candidates[0].exists())

    def test_packaging_entry_imports_without_real_tray(self):
        import tek.app.main as main_module

        self.assertTrue(callable(main_module.main))

    def test_snapshot_includes_v3_binding_telemetry(self):
        from tek.src.binding_tokens import encode_binding_token
        from tek.src.teap import decode_fields, encode_fields_v3
        from tek.src.engine import TEKEngine
        from tek.src.profile_resolver import ProfileResolver
        from tek.src.safety_gate import SafetyContext
        from tek.runtime.status_mapper import trace_record_to_snapshot
        from tek.src.action_catalog import RETRIBUTION_V2
        root = Path(__file__).resolve().parents[2]
        token = encode_binding_token("Q")
        frame = decode_fields(encode_fields_v3(action_code=0, catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=token, frame_freshness_counter=2))
        record = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(root / "examples" / "profiles" / "laptop.json")).process_frame(frame, SafetyContext(bootstrapped=True, last_frame_freshness_counter=1))
        snapshot = trace_record_to_snapshot(record, mode="Dry-run", started_at=None, trace_path=None)
        self.assertEqual(snapshot.last_protocol_version, 3)
        self.assertEqual(snapshot.last_binding_token, token)
        self.assertEqual(snapshot.last_binding, "Q")


class CalibrationSourceTests(unittest.TestCase):
    def test_explicit_calibration_caches_locator_result_and_display_metadata(self):
        located = SignalLayout(x=-1260, y=42, block_size=12, block_gap=3)

        class Calibration:
            def to_dict(self):
                return {"dpi": 144, "window_mode": "borderless_or_fullscreen"}

        class FreshSampler:
            backend = "pillow"
            def __init__(self):
                self.freshness = 0
            def sample(self, layout):
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=1, frame_freshness_counter=self.freshness))

        source = AutoLocateFrameSource(
            auto_locate=True,
            fallback_layout=SignalLayout(),
            sampler=FreshSampler(),
            locate_function=lambda: located,
            calibration_provider=lambda: Calibration(),
            layout_verification_interval_seconds=0,
        )
        self.assertEqual(source.calibrate(), located)
        self.assertEqual(source.cached_layout, located)
        self.assertFalse(source.using_fallback)
        self.assertEqual(source.diagnostics()["display"]["dpi"], 144)


class P1LayoutLockTests(unittest.TestCase):
    def test_calibration_writer_blocks_layout_readers_until_atomic_swap(self):
        old_layout = SignalLayout(x=10, y=10, block_size=10, block_gap=2)
        new_layout = SignalLayout(x=210, y=30, block_size=12, block_gap=3)
        locate_started = threading.Event()
        allow_swap = threading.Event()
        reader_done = threading.Event()
        observed = {}

        def locate():
            locate_started.set()
            self.assertTrue(allow_swap.wait(1.0))
            return new_layout

        class FreshSampler:
            backend = "pillow"
            def __init__(self):
                self.freshness = 0
            def sample(self, layout):
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=1, frame_freshness_counter=self.freshness))

        source = AutoLocateFrameSource(
            auto_locate=True,
            fallback_layout=old_layout,
            sampler=FreshSampler(),
            locate_function=locate,
            calibration_provider=lambda: None,
            layout_verification_interval_seconds=0,
        )
        source._cached_layout = old_layout
        source._last_verified_layout = old_layout

        calibrator = threading.Thread(target=source.calibrate)
        calibrator.start()
        self.assertTrue(locate_started.wait(1.0))

        def read_layout():
            observed["layout"] = source.cached_layout
            reader_done.set()

        reader = threading.Thread(target=read_layout)
        reader.start()
        self.assertFalse(reader_done.wait(0.050))
        allow_swap.set()
        calibrator.join(1.0)
        reader.join(1.0)
        self.assertFalse(calibrator.is_alive())
        self.assertFalse(reader.is_alive())
        self.assertTrue(reader_done.is_set())
        self.assertEqual(observed["layout"], new_layout)

if __name__ == "__main__":
    unittest.main()
