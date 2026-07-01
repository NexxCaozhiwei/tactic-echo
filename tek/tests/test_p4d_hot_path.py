from __future__ import annotations

import unittest

from tek.app.worker_controller import AutoLocateFrameSource
from tek.src.screen_sampler import SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import encode_test_blocks


class P4DHotPathTests(unittest.TestCase):
    def test_layout_uses_cached_sampling_geometry(self):
        layout = SignalLayout(x=100, y=200, block_size=14, block_gap=3)
        self.assertIs(layout.sample_points(), layout.sample_points())
        self.assertIs(layout.strip_bounds(), layout.strip_bounds())

    def test_source_reuses_reader_for_same_sampler_and_layout(self):
        layout = SignalLayout(x=124, y=222, block_size=20, block_gap=4)

        class Sampler:
            backend = "pillow"
            def __init__(self):
                self.calls = 0
            def sample(self, requested):
                self.calls += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=self.calls, frame_freshness_counter=self.calls))

        sampler = Sampler()
        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=sampler,
            locate_function=lambda: layout,
            layout_verification_interval_seconds=0,
        )
        source.read()
        source.read()
        self.assertEqual(len(source._reader_cache), 1)
        # First read takes two complete freshness-advancing frames to prove
        # a header-derived layout; the second read reuses the same reader.
        self.assertEqual(sampler.calls, 3)


if __name__ == "__main__":
    unittest.main()
