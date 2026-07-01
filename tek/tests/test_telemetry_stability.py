from __future__ import annotations

import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from tek.runtime.runtime_status import TEKStatusSnapshot
from tek.runtime.status_publisher import StatusPublisher
from tek.runtime.status_store import StatusStore
from tek.src.diagnostic_bundle import _tail_bytes
from tek.src.engine import TraceRecord
from tek.src.trace import trace_to_dict, write_trace


def snapshot() -> TEKStatusSnapshot:
    return TEKStatusSnapshot.stopped(log_dir=None)


def record(**overrides) -> TraceRecord:
    values = dict(
        accepted=False,
        reason="frame_state_empowering",
        sequence=42,
        state="empowering",
        action_code=0,
        dispatcher_backend="windows_sendinput",
        gatePassed=False,
        dispatchAttempted=False,
        inputSent=False,
        tekState="Paused",
        diagnostics={
            "foreground": {"title": "World of Warcraft", "process_id": 1234},
            "signal": {"layout": {"x": 12, "y": 12}},
            "rate_limiter": {"used_global": 1},
            "physical_input_pause": False,
        },
    )
    values.update(overrides)
    return TraceRecord(**values)


class _MemoryStatusStore:
    def __init__(self, *, fail: bool = False) -> None:
        self.writes: list[dict] = []
        self.fail = fail
        self.last_error = None

    def write(self, value) -> bool:
        if self.fail:
            self.last_error = "PermissionError:locked"
            return False
        self.writes.append(value.to_runtime_dict())
        return True


class TelemetryStabilityTests(unittest.TestCase):
    def test_status_store_permission_error_is_best_effort_not_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            store = StatusStore(Path(directory) / "logs" / "tek-status.json")
            with patch("tek.runtime.status_store.os.replace", side_effect=PermissionError(5, "denied")):
                self.assertFalse(store.write(snapshot()))
            details = store.diagnostics()
            self.assertEqual(details["failed_writes"], 1)
            self.assertIn("PermissionError", details["last_error"])

    def test_status_publisher_coalesces_hot_updates(self):
        store = _MemoryStatusStore()
        publisher = StatusPublisher(store, stable_interval_seconds=0.05)
        publisher.start()
        try:
            for _ in range(50):
                publisher.submit(snapshot())
            time.sleep(0.12)
            self.assertTrue(publisher.flush(timeout_seconds=0.5))
            details = publisher.diagnostics()
            self.assertLessEqual(len(store.writes), 3)
            self.assertGreater(details["coalesced"], 0)
            self.assertEqual(details["failed"], 0)
        finally:
            publisher.stop(timeout_seconds=0.5)

    def test_status_publisher_failure_is_contained(self):
        store = _MemoryStatusStore(fail=True)
        publisher = StatusPublisher(store, stable_interval_seconds=0.05, retry_interval_seconds=0.05)
        publisher.start()
        try:
            publisher.submit(snapshot(), urgent=True)
            time.sleep(0.08)
            details = publisher.diagnostics()
            self.assertGreaterEqual(details["failed"], 1)
            self.assertTrue(details["worker_alive"])
            self.assertFalse(publisher.flush(timeout_seconds=0.02))
        finally:
            publisher.stop(timeout_seconds=0.5)

    def test_status_publisher_unexpected_store_exception_is_contained(self):
        class RaisingStore:
            last_error = None

            def write(self, value):
                raise PermissionError(5, "locked")

        publisher = StatusPublisher(RaisingStore(), stable_interval_seconds=0.05, retry_interval_seconds=0.05)
        publisher.start()
        try:
            publisher.submit(snapshot(), urgent=True)
            time.sleep(0.08)
            details = publisher.diagnostics()
            self.assertGreaterEqual(details["failed"], 1)
            self.assertTrue(details["worker_alive"])
            self.assertIn("PermissionError", details["last_error"])
        finally:
            publisher.stop(timeout_seconds=0.5)

    def test_runtime_status_disk_payload_excludes_nested_diagnostics(self):
        payload = snapshot().to_runtime_dict()
        for field in (
            "foreground_diagnostics",
            "signal_diagnostics",
            "reason_counts",
            "rate_limiter",
            "dispatch_failures",
            "physical_input_diagnostics",
        ):
            self.assertNotIn(field, payload)

    def test_normal_trace_omits_expensive_nested_diagnostics(self):
        payload = trace_to_dict(record(), include_diagnostics=False)
        self.assertEqual(payload["diagnostics"], {"physical_input_pause": False})
        encoded = json.dumps(payload, ensure_ascii=False)
        self.assertNotIn("World of Warcraft", encoded)
        self.assertNotIn("rate_limiter", encoded)

    def test_diagnostic_tail_starts_at_complete_jsonl_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            first = json.dumps({"seq": 1, "data": "x" * 200}) + "\n"
            second = json.dumps({"seq": 2, "data": "y" * 200}) + "\n"
            path.write_text(first + second, encoding="utf-8")
            data = _tail_bytes(path, max_bytes=250)
            rows = [json.loads(line) for line in data.decode("utf-8").splitlines()]
            self.assertEqual(rows[0]["seq"], 2)

    def test_normal_trace_file_can_be_written_without_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            write_trace(record(), path, include_diagnostics=False)
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(payload["state"], "empowering")
            self.assertEqual(payload["diagnostics"], {"physical_input_pause": False})


if __name__ == "__main__":
    unittest.main()

class WorkerTelemetryContainmentTests(unittest.TestCase):
    def test_status_mirror_failure_does_not_stop_worker(self):
        from tek.app.app_paths import AppPaths
        from tek.app.worker_controller import WorkerController

        class AlwaysFailStatusStore:
            last_error = "PermissionError:locked"

            def write(self, value):
                return False

        class StableRunner:
            def tick(self, config):
                return record(reason="dry_run_planned", state="armed", tekState="Armed")

        with tempfile.TemporaryDirectory() as directory:
            paths = AppPaths.from_root(Path(directory) / "state")
            paths.ensure()
            worker = WorkerController(
                paths=paths,
                status_store=AlwaysFailStatusStore(),
                runner_factory=lambda _: StableRunner(),
            )
            self.assertTrue(worker.start_dry_run())
            time.sleep(0.08)
            self.assertTrue(worker.is_running())
            self.assertNotEqual(worker.snapshot.process_state, "WorkerExited")
            self.assertTrue(worker.stop(timeout_seconds=1.5))

class StatusPublisherPriorityTests(unittest.TestCase):
    def test_action_churn_is_batched_without_immediate_disk_publish(self):
        store = _MemoryStatusStore()
        publisher = StatusPublisher(store, stable_interval_seconds=0.20)
        publisher.start()
        try:
            first = snapshot()
            publisher.submit(first, urgent=True)
            time.sleep(0.04)
            for action in range(1, 20):
                publisher.submit(TEKStatusSnapshot(
                    **{**first.__dict__, "last_action_code": action, "last_binding": "Q", "last_input_sent": bool(action % 2)}
                ))
            time.sleep(0.06)
            # Safety/lifecycle signature did not change, so action churn cannot
            # force a write per tick.
            self.assertLessEqual(len(store.writes), 1)
        finally:
            publisher.stop(timeout_seconds=0.5)
