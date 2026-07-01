from __future__ import annotations

import unittest
from unittest.mock import patch

from tek.app.worker_controller import AutoLocateFrameSource
from tek.src.screen_sampler import SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import encode_test_blocks


class P4CSamplerBackendTests(unittest.TestCase):
    @staticmethod
    def _blocks():
        return encode_test_blocks(encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=8))

    def test_auto_backend_promotes_only_after_three_valid_pillow_reads(self):
        layout = SignalLayout(x=124, y=222, block_size=20, block_gap=4)

        outer = self

        class PillowSampler:
            backend = "pillow"
            def __init__(self):
                self.freshness = 0
            def sample(self, requested):
                outer.assertEqual(requested, layout)
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=self.freshness))

        class GdiBltSampler:
            backend = "gdi_blt"
            def __init__(self):
                self.freshness = 0
            def sample(self, requested):
                self.freshness += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=self.freshness))

        with patch("tek.app.worker_controller.GDIBlitStripSampler", return_value=GdiBltSampler()) as factory:
            source = AutoLocateFrameSource(
                auto_locate=True,
                sampler=PillowSampler(),
                sampler_backend="auto",
                locate_function=lambda: layout,
                layout_verification_interval_seconds=0,
            )
            source.read()
            self.assertEqual(source.sampler_backend, "pillow")
            source.read()
            self.assertEqual(source.sampler_backend, "pillow")
            source.read()
            self.assertEqual(source.sampler_backend, "gdi_blt")
            self.assertEqual(source.diagnostics()["last_sampler_switch_reason"], "auto_promoted_pillow_to_gdi_blt")
            factory.assert_called_once()

    def test_gdi_blt_fallback_diagnostic_keeps_original_backend_name(self):
        class GdiBltSampler:
            backend = "gdi_blt"
            def sample(self, layout):
                raise OSError("bitblt_failed")

        class PillowSampler:
            backend = "pillow"
            def sample(self, layout):
                return P4CSamplerBackendTests._blocks()

        source = AutoLocateFrameSource(
            auto_locate=False,
            sampler=GdiBltSampler(),
            sampler_backend="gdi_blt",
            pillow_sampler_factory=PillowSampler,
            sampler_failure_threshold=1,
        )
        # The first read observes the explicit GDI failure, falls back, then
        # retries once through the Pillow sampler.
        self.assertEqual(source.read().sequence, 3)
        self.assertEqual(source.sampler_backend, "pillow")
        self.assertTrue(source.diagnostics()["last_sampler_switch_reason"].startswith("gdi_blt_to_pillow:"))


if __name__ == "__main__":
    unittest.main()
