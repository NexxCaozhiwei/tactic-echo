from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tek.runtime.trace_writer import TraceWriter
from tek.src.engine import TraceRecord


class P4DTraceWriterTests(unittest.TestCase):
    @staticmethod
    def _record(*, sent: bool = True, reason: str = "input_sent") -> TraceRecord:
        return TraceRecord(
            sequence=1,
            dispatcher_backend="dry_run",
            accepted=True,
            reason=reason,
            state="armed",
            action_code=1,
            action_id="ACTION",
            binding="Q",
            gatePassed=sent,
            dispatchAttempted=sent,
            inputSent=sent,
            tekState="Armed",
        )

    def test_writer_flushes_records_without_blocking_submitter(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            writer = TraceWriter()
            writer.start()
            self.assertTrue(writer.submit(self._record(), path, max_bytes=100000, backup_count=1, include_diagnostics=False))
            self.assertTrue(writer.flush(timeout_seconds=1.0))
            writer.stop()
            self.assertIn('"eventType":"input_sent"', path.read_text(encoding="utf-8"))
            self.assertEqual(writer.diagnostics()["written"], 1)

    def test_writer_catches_all_serialization_or_disk_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            writer = TraceWriter()
            writer.start()
            with patch("tek.runtime.trace_writer.write_trace", side_effect=ValueError("bad_trace")):
                self.assertTrue(writer.submit(self._record(), path, max_bytes=100000, backup_count=1, include_diagnostics=False))
                self.assertFalse(writer.flush(timeout_seconds=1.0))
            diagnostics = writer.diagnostics()
            writer.stop()
            self.assertEqual(diagnostics["failed"], 1)
            self.assertIn("ValueError:bad_trace", diagnostics["last_error"])

    def test_queue_drops_low_priority_success_before_blocked_event(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            writer = TraceWriter(max_queue=16)
            # Do not start: fill queue deterministically and then enqueue one
            # blocked high-priority event; low success rows are displaced first.
            for _ in range(16):
                writer.submit(self._record(), path, max_bytes=100000, backup_count=1, include_diagnostics=False)
            self.assertTrue(writer.submit(self._record(sent=False, reason="manual_input_held"), path, max_bytes=100000, backup_count=1, include_diagnostics=False))
            self.assertGreaterEqual(writer.diagnostics()["dropped"], 1)
            writer.stop()


if __name__ == "__main__":
    unittest.main()
