from __future__ import annotations

import unittest
from dataclasses import dataclass
from unittest.mock import patch

from PIL import Image

from tek.app.worker_controller import AutoLocateFrameSource
from tek.src.engine import TraceRecord
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.safety_gate import ForegroundSnapshot
from tek.src.screen_sampler import PillowScreenSampler, RelativeSignalLayout, SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.trace import TraceSampler
from tek.src.visual_decoder import encode_test_blocks


@dataclass(frozen=True)
class _Calibration:
    client_origin: tuple[int, int] = (100, 200)
    client_rect: tuple[int, int, int, int] = (0, 0, 1200, 800)
    dpi: int = 144

    def to_dict(self):
        return {
            "client_origin": self.client_origin,
            "client_rect": self.client_rect,
            "dpi": self.dpi,
        }


class P2ASamplerTests(unittest.TestCase):
    def test_pillow_runtime_capture_is_limited_to_teap_strip(self):
        layout = SignalLayout(x=120, y=40, block_size=12, block_gap=3)
        expected = layout.strip_bounds()
        values = encode_fields_v3(action_code=1, sequence=9, frame_freshness_counter=12)
        calls = []

        def fake_grab(*, bbox=None, all_screens=True):
            calls.append((bbox, all_screens))
            self.assertEqual((expected.left, expected.top, expected.right, expected.bottom), bbox)
            image = Image.new("RGB", (expected.width, expected.height), (0, 0, 0))
            for point, value in zip(layout.sample_points(), values):
                image.putpixel((point[0] - expected.left, point[1] - expected.top), (value, 255 - value, 17))
            return image

        sampler = PillowScreenSampler()
        with patch("PIL.ImageGrab.grab", side_effect=fake_grab):
            blocks = sampler.sample(layout)

        self.assertEqual(len(blocks), 20)
        self.assertEqual(calls, [((expected.left, expected.top, expected.right, expected.bottom), True)])
        self.assertEqual(sampler.last_capture_bounds, expected)

    def test_relative_layout_projects_after_client_move_and_resize(self):
        original = SignalLayout(x=124, y=222, block_size=20, block_gap=4)
        relative = RelativeSignalLayout.from_layout(
            original,
            client_left=100,
            client_top=200,
            client_width=1200,
            client_height=800,
        )
        self.assertIsNotNone(relative)
        moved = relative.project(client_left=500, client_top=300, client_width=1200, client_height=800)
        self.assertEqual(moved, SignalLayout(x=524, y=322, block_size=20, block_gap=4, block_count=20))
        resized = relative.project(client_left=300, client_top=100, client_width=1800, client_height=1200)
        self.assertEqual(resized.x, 336)
        self.assertEqual(resized.y, 133)
        self.assertEqual(resized.block_size, 30)
        self.assertEqual(resized.block_gap, 6)

    def test_auto_locator_scans_current_client_only_then_reads_strip(self):
        captures = []
        located = SignalLayout(x=124, y=222, block_size=20, block_gap=4)

        class StableSampler:
            backend = "pillow"

            def __init__(self):
                self.layouts = []
                self.freshness = 3

            def sample(self, layout):
                self.layouts.append(layout)
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=self.freshness))

        sampler = StableSampler()

        def client_locator(bounds):
            captures.append(bounds)
            return located

        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=sampler,
            calibration_provider=lambda hwnd=None: _Calibration(),
            locate_function=lambda: self.fail("legacy full-desktop locator must not run"),
            client_locate_function=client_locator,
            layout_verification_interval_seconds=0,
        )
        source.set_foreground_window(ForegroundSnapshot(ok=True, hwnd=77, process_id=88))
        frame = source.read()

        self.assertEqual(frame.sequence, 3)
        self.assertEqual(len(captures), 1)
        self.assertEqual(captures[0].to_dict(), {"left": 100, "top": 200, "right": 1300, "bottom": 1000, "width": 1200, "height": 800})
        self.assertEqual(sampler.layouts, [located, located])
        self.assertEqual(source.diagnostics()["layout_source"], "client_relative")
        self.assertEqual(source.diagnostics()["runtime_capture_bounds"], located.strip_bounds().to_dict())


class P2ARunnerTests(unittest.TestCase):
    @staticmethod
    def _record(**overrides):
        values = dict(
            accepted=True,
            reason="input_sent",
            sequence=1,
            state="armed",
            action_code=1,
            dispatcher_backend="windows_sendinput",
            gatePassed=True,
            dispatchAttempted=True,
            inputSent=True,
            tekState="Armed",
            action_id="ACTION",
            binding="Q",
        )
        values.update(overrides)
        return TraceRecord(**values)

    def test_idle_sampling_uses_200ms_but_armed_stays_50ms(self):
        runner = TEKRunner(engine=type("Engine", (), {"dispatcher_backend": "dry_run"})(), frame_source=object())
        config = RunnerConfig(interval_seconds=0.05, idle_interval_seconds=0.20)
        runner.context.wow_foreground = True
        self.assertEqual(runner.next_interval_seconds(config, self._record()), 0.05)
        self.assertEqual(runner.next_interval_seconds(config, self._record(state="paused", tekState="Paused")), 0.20)
        runner.context.wow_foreground = False
        self.assertEqual(runner.next_interval_seconds(config, self._record()), 0.20)

    def test_runner_uses_light_foreground_recheck_before_engine(self):
        blocks = encode_test_blocks(encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=4))
        frame = __import__("tek.src.visual_decoder", fromlist=["decode_rgb_blocks"]).decode_rgb_blocks(blocks)
        calls = {"full": 0, "light": 0}

        class Foreground:
            def snapshot(self):
                calls["full"] += 1
                return ForegroundSnapshot(ok=True, hwnd=21, process_id=22, title="World of Warcraft", process_name="wow.exe")

            def light_snapshot(self, expected):
                calls["light"] += 1
                self_expected = expected
                return ForegroundSnapshot(ok=True, hwnd=self_expected.hwnd, process_id=self_expected.process_id)

        class Source:
            def __init__(self):
                self.target = None

            def set_foreground_window(self, snapshot):
                self.target = snapshot

            def read(self):
                return frame

        class Engine:
            dispatcher_backend = "dry_run"

            def process_frame(self, incoming, context):
                self.context = context
                return P2ARunnerTests._record()

        source = Source()
        engine = Engine()
        runner = TEKRunner(engine=engine, frame_source=source, foreground_source=Foreground())
        runner.tick(RunnerConfig(interval_seconds=0))
        self.assertEqual(calls, {"full": 1, "light": 1})
        self.assertEqual(source.target.hwnd, 21)
        self.assertEqual(engine.context.foreground_before_dispatch.hwnd, 21)


class P2ATraceTests(unittest.TestCase):
    @staticmethod
    def _sent(sequence: int, action: int) -> TraceRecord:
        return TraceRecord(
            accepted=True,
            reason="input_sent",
            sequence=sequence,
            state="armed",
            action_code=action,
            dispatcher_backend="windows_sendinput",
            gatePassed=True,
            dispatchAttempted=True,
            inputSent=True,
            tekState="Armed",
            action_id=f"A{action}",
            binding="Q",
        )

    def test_default_trace_aggregates_successful_dispatches(self):
        now = [0.0]
        sampler = TraceSampler(clock=lambda: now[0], active_heartbeat_seconds=0.5)
        first = sampler.records_to_write(self._sent(1, 1))
        self.assertEqual(len(first), 1)
        now[0] = 0.1
        self.assertEqual(sampler.records_to_write(self._sent(2, 2)), ())
        now[0] = 0.5
        rows = sampler.records_to_write(self._sent(3, 3))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].diagnostics["input_sent_summary"]["count"], 2)
        self.assertEqual(rows[0].diagnostics["input_sent_summary"]["last_action_code"], 3)

    def test_full_debug_trace_keeps_each_successful_dispatch(self):
        now = [0.0]
        sampler = TraceSampler(clock=lambda: now[0], full_debug=True, active_heartbeat_seconds=60)
        self.assertEqual(len(sampler.records_to_write(self._sent(1, 1))), 1)
        now[0] = 0.01
        self.assertEqual(len(sampler.records_to_write(self._sent(2, 2))), 1)


if __name__ == "__main__":
    unittest.main()
