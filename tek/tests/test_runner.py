import json
import tempfile
import unittest
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.binding_tokens import encode_binding_token
from tek.src.engine import TEKEngine
from tek.src.profile_resolver import ProfileResolver
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.teap import decode_fields, encode_fields_v3


ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


def make_frame(sequence, frame_freshness_counter=None):
    freshness = sequence + 1 if frame_freshness_counter is None else frame_freshness_counter
    return decode_fields(encode_fields_v3(
        action_code=1,
        sequence=sequence,
        frame_freshness_counter=freshness,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
        binding_token=encode_binding_token("Q"),
        in_combat=True,
    ))


class ListFrameSource:
    def __init__(self, frames):
        self.frames = list(frames)
        self.index = 0

    def read(self):
        frame = self.frames[min(self.index, len(self.frames) - 1)]
        self.index += 1
        return frame


class ErrorFrameSource:
    def read(self):
        raise ValueError("bad_colors")


class ListForegroundSource:
    def __init__(self, values):
        self.values = list(values)
        self.index = 0

    def is_wow_foreground(self):
        value = self.values[min(self.index, len(self.values) - 1)]
        self.index += 1
        return value


class RunnerTests(unittest.TestCase):
    def test_runner_preserves_last_sequence_between_ticks(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ListFrameSource([make_frame(10), make_frame(10)]))

        records = runner.run(RunnerConfig(max_frames=2, interval_seconds=0, assume_wow_foreground=True))

        self.assertFalse(records[0].accepted)
        self.assertEqual(records[0].reason, "bootstrap_observing_session")
        self.assertFalse(records[1].accepted)
        self.assertEqual(records[1].reason, "stale_frame_freshness")

    def test_runner_allows_repeated_sequence_when_freshness_advances(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ListFrameSource([
            make_frame(10, frame_freshness_counter=20),
            make_frame(10, frame_freshness_counter=21),
            make_frame(10, frame_freshness_counter=22),
        ]))

        records = runner.run(RunnerConfig(max_frames=3, interval_seconds=0, assume_wow_foreground=True))

        self.assertFalse(records[0].accepted)
        self.assertEqual(records[0].reason, "bootstrap_observing_session")
        self.assertTrue(records[1].accepted)
        self.assertEqual(records[1].reason, "dry_run_planned")
        self.assertTrue(records[2].accepted)
        self.assertEqual(records[2].reason, "dry_run_planned")

    def test_ui_linked_runner_dispatches_first_valid_armed_frame_without_bootstrap_delay(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ListFrameSource([make_frame(10)]))

        records = runner.run(
            RunnerConfig(
                max_frames=1,
                interval_seconds=0,
                assume_wow_foreground=True,
                allow_initial_armed_dispatch=True,
            )
        )

        self.assertTrue(records[0].accepted)
        self.assertEqual(records[0].reason, "dry_run_planned")
        self.assertTrue(runner.context.bootstrapped)

    def test_visible_waiting_frame_is_clean_non_dispatchable_state(self):
        waiting = decode_fields(encode_fields_v3(
            state="waiting",
            action_code=0,
            sequence=10,
            frame_freshness_counter=20,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=0,
            in_combat=False,
        ))
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ListFrameSource([waiting]))

        records = runner.run(RunnerConfig(max_frames=1, interval_seconds=0, assume_wow_foreground=True))

        self.assertFalse(records[0].accepted)
        self.assertEqual(records[0].reason, "frame_state_waiting")
        self.assertEqual(records[0].tekState, "Waiting")
        self.assertNotIn("binding_token_invalid", records[0].reason)

    def test_runner_writes_jsonl_trace(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ListFrameSource([make_frame(10), make_frame(11)]))

        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "trace.jsonl"
            runner.run(RunnerConfig(max_frames=2, interval_seconds=0, trace_path=trace_path, assume_wow_foreground=True))

            lines = trace_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 2)
            self.assertEqual(json.loads(lines[0])["sequence"], 10)
            self.assertEqual(json.loads(lines[1])["sequence"], 11)

    def test_runner_records_frame_read_errors(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ErrorFrameSource())

        records = runner.run(RunnerConfig(max_frames=1, interval_seconds=0, assume_wow_foreground=True))

        self.assertFalse(records[0].accepted)
        self.assertEqual(records[0].state, "error")
        self.assertEqual(records[0].dispatcher_backend, "dry_run")
        self.assertIn("frame_read_error:ValueError:bad_colors", records[0].reason)


    def test_tick_applies_ui_linked_safety_options_without_run_wrapper(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        runner = TEKRunner(engine, ListFrameSource([make_frame(10)]))

        runner.tick(
            RunnerConfig(
                interval_seconds=0,
                assume_wow_foreground=True,
                dispatch_budget=None,
                require_start_toggle=True,
            )
        )

        self.assertTrue(runner.context.require_start_toggle)
        self.assertIsNone(runner.context.dispatch_budget)

    def test_runner_checks_foreground_each_tick(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        foreground = ListForegroundSource([True, True, False, False])
        runner = TEKRunner(
            engine,
            ListFrameSource([make_frame(10), make_frame(11)]),
            foreground_source=foreground,
        )

        records = runner.run(RunnerConfig(max_frames=2, interval_seconds=0))

        self.assertFalse(records[0].accepted)
        self.assertEqual(records[0].reason, "bootstrap_observing_session")
        self.assertFalse(records[1].accepted)
        self.assertEqual(records[1].reason, "foreground_not_game")

if __name__ == "__main__":
    unittest.main()
