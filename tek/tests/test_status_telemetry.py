import unittest

from tek.runtime.status_mapper import trace_record_to_snapshot
from tek.src.engine import TraceRecord


class StatusTelemetryTests(unittest.TestCase):
    def test_monitor_bits_flow_to_status_without_affecting_result(self):
        record = TraceRecord(
            accepted=True, reason="dry_run_planned", sequence=1, state="armed", action_code=1,
            dispatcher_backend="dry_run", target_casting=True, target_interruptible=True,
            player_health_critical=True, monitor_flags=0x1C,
        )
        snapshot = trace_record_to_snapshot(record, mode="dry_run", started_at=None, trace_path=None)
        self.assertTrue(snapshot.last_target_casting)
        self.assertTrue(snapshot.last_target_interruptible)
        self.assertTrue(snapshot.last_player_health_critical)
        self.assertEqual(snapshot.monitor_flags, 0x1C)
        self.assertEqual(snapshot.last_reason, "dry_run_planned")

    def test_non_wow_foreground_maps_to_explicit_waiting_for_foreground(self):
        record = TraceRecord(
            accepted=False,
            reason="window_process_mismatch",
            sequence=-1,
            state="waiting",
            action_code=0,
            dispatcher_backend="windows_sendinput",
            tekState="Waiting",
        )
        snapshot = trace_record_to_snapshot(record, mode="UI 联动", started_at=None, trace_path=None)
        self.assertEqual(snapshot.process_state, "WaitingForForeground")
        self.assertFalse(snapshot.wow_foreground)



if __name__ == "__main__":
    unittest.main()
