import unittest

from tek.app.worker_controller import AutoLocateFrameSource
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.screen_sampler import SignalLayout
from tek.src.safety_gate import ForegroundSnapshot


class _FailingSampler:
    def sample(self, layout):
        raise OSError("sample_failed")


class _Foreground:
    def snapshot(self):
        return ForegroundSnapshot(ok=True, title="魔兽世界", process_id=1, process_name="Wow.exe", executable_path=r"E:\\World of Warcraft\\_retail_\\Wow.exe")


class _Engine:
    dispatcher_backend = "dry_run"


class TekDiagnosticsTests(unittest.TestCase):
    def test_auto_locate_failure_stays_waiting_and_exposes_diagnostics(self):
        source = AutoLocateFrameSource(auto_locate=True, sampler=_FailingSampler(), locate_function=lambda: SignalLayout(), failure_threshold=1)
        runner = TEKRunner(engine=_Engine(), frame_source=source, foreground_source=_Foreground())
        # runner needs no engine because frame reading fails before process_frame
        record = runner.tick(RunnerConfig(interval_seconds=0))
        self.assertEqual("Waiting", record.tekState)
        self.assertTrue(record.reason.startswith("frame_read_error"))
        self.assertEqual("none", record.diagnostics["signal"]["layout_source"])
        self.assertFalse(record.inputSent)

    def test_fallback_failure_never_dispatches(self):
        source = AutoLocateFrameSource(auto_locate=False, sampler=_FailingSampler())
        runner = TEKRunner(engine=_Engine(), frame_source=source, foreground_source=_Foreground())
        record = runner.tick(RunnerConfig(interval_seconds=0))
        self.assertEqual("Waiting", record.tekState)
        self.assertFalse(record.dispatchAttempted)
        self.assertFalse(record.inputSent)

    def test_mismatch_trace_and_status_keep_foreground_diagnostics(self):
        from tek.runtime.status_mapper import trace_record_to_snapshot
        from tek.src.engine import TraceRecord
        from tek.src.trace import trace_to_dict
        foreground = {
            "ok": False, "reason": "window_process_mismatch", "hwnd": 77,
            "title": "Other App", "process_id": 88, "process_name": "other.exe",
            "executable_path": r"C:\\Other\\other.exe",
        }
        record = TraceRecord(
            accepted=False, reason="window_process_mismatch", sequence=-1, state="waiting", action_code=0,
            dispatcher_backend="windows_sendinput", dispatchBlocked=True, tekState="Waiting",
            diagnostics={"foreground": foreground, "signal": None, "reason_counts": {"window_process_mismatch": 2}},
        )
        self.assertEqual(foreground, trace_to_dict(record)["diagnostics"]["foreground"])
        snapshot = trace_record_to_snapshot(record, mode="UI 联动", started_at=None, trace_path=None)
        self.assertEqual(foreground, snapshot.foreground_diagnostics)
        self.assertFalse(snapshot.wow_foreground)
