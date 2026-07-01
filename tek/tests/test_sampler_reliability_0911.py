from __future__ import annotations

import unittest

from tek.app.worker_controller import AutoLocateFrameSource
from tek.src.cli import ScreenFrameSource
from tek.src.screen_sampler import SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import encode_test_blocks


class _OneShotSampler:
    backend = "gdi"

    def __init__(self, blocks):
        self.blocks = blocks
        self.calls = 0

    def sample(self, layout):
        self.calls += 1
        return self.blocks


class ScreenFrameProtocolValidationTests(unittest.TestCase):
    def test_single_gdi_read_uses_commit_and_crc_without_double_sample_equality(self):
        blocks = encode_test_blocks(encode_fields_v3(action_code=1, sequence=7, frame_freshness_counter=8))
        sampler = _OneShotSampler(blocks)

        frame = ScreenFrameSource(SignalLayout(), sampler=sampler).read()

        self.assertEqual(frame.sequence, 7)
        self.assertEqual(sampler.calls, 1)


class AutoLocateRecoveryTests(unittest.TestCase):
    def test_gdi_repeated_failures_switch_to_pillow_for_session_and_retry(self):
        blocks = encode_test_blocks(encode_fields_v3(action_code=1, sequence=9, frame_freshness_counter=10))

        class FailingGDI:
            backend = "gdi"

            def sample(self, layout):
                raise ValueError("unstable_frame_sample")

        class StablePillow:
            backend = "pillow"

            def sample(self, layout):
                return blocks

        source = AutoLocateFrameSource(
            auto_locate=False,
            sampler=FailingGDI(),
            sampler_backend="gdi",
            sampler_failure_threshold=2,
            pillow_sampler_factory=StablePillow,
        )

        with self.assertRaises(ValueError):
            source.read()
        frame = source.read()

        self.assertEqual(frame.sequence, 9)
        diagnostics = source.diagnostics()
        self.assertEqual(diagnostics["sampler_backend"], "pillow")
        self.assertTrue(diagnostics["sampler_fallback_locked"])
        self.assertIn("gdi_to_pillow", diagnostics["last_sampler_switch_reason"])
        self.assertEqual(diagnostics["recent_decode_error"], "ValueError:unstable_frame_sample")

    def test_failed_auto_location_uses_bounded_backoff_before_scanning_again(self):
        now = [0.0]
        locate_calls = []

        class BrokenSampler:
            backend = "pillow"

            def sample(self, layout):
                raise ValueError("green_mismatch")

        def locate():
            locate_calls.append(now[0])
            raise OSError("te_signal_layout_not_found")

        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=BrokenSampler(),
            locate_function=locate,
            failure_threshold=1,
            clock=lambda: now[0],
            auto_locate_initial_backoff_seconds=1.0,
            auto_locate_max_backoff_seconds=4.0,
        )

        with self.assertRaisesRegex(OSError, "te_signal_layout_not_found"):
            source.read()
        self.assertEqual(len(locate_calls), 1)
        with self.assertRaisesRegex(OSError, "te_signal_layout_search_backoff"):
            source.read()
        self.assertEqual(len(locate_calls), 1)
        self.assertGreater(source.diagnostics()["auto_locate_backoff_remaining_ms"], 0)

        now[0] = 10.0
        with self.assertRaisesRegex(OSError, "te_signal_layout_not_found"):
            source.read()
        self.assertEqual(len(locate_calls), 2)


if __name__ == "__main__":
    unittest.main()
