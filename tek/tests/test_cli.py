import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

from tek.src.cli import main, parse_fields
from tek.src.visual_decoder import encode_test_blocks
from tek.src.teap import encode_fields_v3
from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.binding_tokens import encode_binding_token


def fields(action_code=1, sequence=42, state=1):
    state_name = {0: "waiting", 1: "armed", 2: "paused", 3: "blocked", 4: "error", 5: "channeling", 6: "empowering"}[state]
    values = encode_fields_v3(
        state=state_name,
        action_code=action_code,
        sequence=sequence,
        frame_freshness_counter=sequence + 1,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
        binding_token=encode_binding_token("Q"),
        in_combat=True,
    )
    return ",".join(str(value) for value in values)


def run_cli(args):
    with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
        return main(args)


class CLITests(unittest.TestCase):
    def test_parse_fields_accepts_decimal_and_hex(self):
        self.assertEqual(parse_fields(fields().replace("69", "0x45", 1))[:2], [84, 69])

    def test_cli_writes_dry_run_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek.jsonl"
            code = run_cli([
                "--fields",
                fields(),
                "--assume-wow-foreground",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 0)
            lines = trace_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            trace = json.loads(lines[0])
            self.assertEqual(trace["schemaVersion"], 1)
            self.assertEqual(trace["component"], "TEK")
            self.assertEqual(trace["eventType"], "input_dispatch")
            self.assertEqual(trace["dispatcher_backend"], "dry_run")
            self.assertEqual(trace["protocol_version"], 3)
            self.assertTrue(trace["accepted"])
            self.assertTrue(trace["gatePassed"])
            self.assertFalse(trace["inputSent"])
            self.assertEqual(trace["reason"], "dry_run_planned")
            self.assertEqual(trace["action_id"], "PALADIN_RETRIBUTION_JUDGMENT")

    def test_cli_blocks_by_default_without_foreground_assumption(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek.jsonl"
            code = run_cli(["--fields", fields(), "--trace", str(trace_path)])

            self.assertEqual(code, 0)
            trace = json.loads(trace_path.read_text(encoding="utf-8").splitlines()[0])
            self.assertEqual(trace["eventType"], "input_blocked")
            self.assertEqual(trace["dispatcher_backend"], "dry_run")
            self.assertFalse(trace["accepted"])
            self.assertEqual(trace["reason"], "foreground_not_game")

    def test_cli_accepts_rgb_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek.jsonl"
            rgb = ",".join(f"{block.red}:{block.green}:{block.blue}" for block in encode_test_blocks([int(value) for value in fields().split(",")]))
            code = run_cli([
                "--rgb",
                rgb,
                "--assume-wow-foreground",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 0)
            trace = json.loads(trace_path.read_text(encoding="utf-8").splitlines()[0])
            self.assertTrue(trace["accepted"])
            self.assertEqual(trace["action_id"], "PALADIN_RETRIBUTION_JUDGMENT")

    def test_cli_loop_preserves_sequence_state(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek.jsonl"
            code = run_cli([
                "--fields",
                fields(),
                "--assume-wow-foreground",
                "--loop",
                "--max-frames",
                "2",
                "--interval",
                "0",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 0)
            traces = [json.loads(line) for line in trace_path.read_text(encoding="utf-8").splitlines()]
            self.assertFalse(traces[0]["accepted"])
            self.assertEqual(traces[0]["reason"], "bootstrap_observing_session")
            self.assertFalse(traces[1]["accepted"])
            self.assertEqual(traces[1]["reason"], "stale_frame_freshness")

    def test_send_input_requires_explicit_confirmation(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek.jsonl"
            code = run_cli([
                "--fields",
                fields(),
                "--send-input",
                "--check-foreground",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 2)

    def test_send_input_rejects_foreground_assumption(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek.jsonl"
            code = run_cli([
                "--fields",
                fields(),
                "--send-input",
                "--confirm-send-input",
                "I_UNDERSTAND_TEK_SENDS_KEYS",
                "--assume-wow-foreground",
                "--check-foreground",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 2)

    def test_send_input_requires_trace_file(self):
        code = run_cli([
            "--fields",
            fields(),
            "--send-input",
            "--confirm-send-input",
            "I_UNDERSTAND_TEK_SENDS_KEYS",
            "--check-foreground",
        ])

        self.assertEqual(code, 2)

    def test_live_requires_trace_file(self):
        code = run_cli(["--live"])

        self.assertEqual(code, 2)

    def test_live_rejects_foreground_assumption(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek-live.jsonl"
            code = run_cli([
                "--live",
                "--assume-wow-foreground",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 2)

    def test_live_rejects_non_runnable_desktop_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            trace_path = Path(directory) / "tek-live.jsonl"
            code = run_cli([
                "--live",
                "--profile",
                "examples/profiles/desktop-numpad.json",
                "--trace",
                str(trace_path),
            ])

            self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
