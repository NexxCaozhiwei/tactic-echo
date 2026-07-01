import tempfile
import unittest
from pathlib import Path

from tek.src.engine import TraceRecord
from tek.src.trace import TraceSampler, write_trace


def record(**overrides):
    values = dict(
        accepted=True, reason="waiting_for_signal", sequence=1, state="blocked",
        action_code=0, dispatcher_backend="dry_run", gatePassed=False,
        dispatchAttempted=False, inputSent=False, tekState="Waiting",
        action_id=None, binding=None,
    )
    values.update(overrides)
    return TraceRecord(**values)


class TraceRetentionTests(unittest.TestCase):
    def test_unchanged_idle_state_is_heartbeat_sampled(self):
        now = [0.0]
        sampler = TraceSampler(clock=lambda: now[0], idle_heartbeat_seconds=5, active_heartbeat_seconds=1)
        item = record()
        self.assertTrue(sampler.should_write(item))
        now[0] = 4.9
        self.assertFalse(sampler.should_write(item))
        now[0] = 5.0
        self.assertTrue(sampler.should_write(item))

    def test_state_change_is_written_immediately(self):
        now = [0.0]
        sampler = TraceSampler(clock=lambda: now[0])
        self.assertTrue(sampler.should_write(record()))
        now[0] = 0.1
        self.assertTrue(sampler.should_write(record(reason="physical_input_pause")))

    def test_active_state_is_sampled_once_per_second(self):
        now = [0.0]
        sampler = TraceSampler(clock=lambda: now[0], active_heartbeat_seconds=1)
        item = record(dispatchAttempted=True, inputSent=True, reason="input_sent", tekState="Armed")
        self.assertTrue(sampler.should_write(item))
        now[0] = 0.9
        self.assertFalse(sampler.should_write(item))
        now[0] = 1.0
        self.assertTrue(sampler.should_write(item))

    def test_rotation_keeps_bounded_number_of_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tek-trace.jsonl"
            for sequence in range(20):
                write_trace(record(sequence=sequence, reason=f"state_{sequence}"), path, max_bytes=180, backup_count=3)
            self.assertTrue(path.exists())
            self.assertTrue(path.with_suffix(".jsonl.1").exists())
            self.assertTrue(path.with_suffix(".jsonl.2").exists())
            self.assertTrue(path.with_suffix(".jsonl.3").exists())
            self.assertFalse(path.with_suffix(".jsonl.4").exists())


if __name__ == "__main__":
    unittest.main()
