from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class SamplerReliability0911ContractTests(unittest.TestCase):
    def test_runtime_defaults_to_pillow_and_gdi_is_explicit_experiment(self) -> None:
        sampler = (ROOT / "tek" / "src" / "screen_sampler.py").read_text(encoding="utf-8")
        settings = (ROOT / "tek" / "app" / "settings_store.py").read_text(encoding="utf-8")
        self.assertIn('def runtime_pixel_sampler(backend: str = "pillow")', sampler)
        self.assertIn('signal_sampler_backend: str = "pillow"', settings)
        self.assertIn('signal_sampler_backend not in {"pillow", "gdi"}', settings)

    def test_runtime_decode_uses_protocol_validation_not_double_gdi_equality(self) -> None:
        cli = (ROOT / "tek" / "src" / "cli.py").read_text(encoding="utf-8")
        self.assertIn("return decode_rgb_blocks(self.sampler.sample(self.layout))", cli)
        self.assertNotIn("decode_stable_rgb_samples", cli)
        self.assertIn("commit byte and CRC16", cli)

    def test_auto_location_backoff_and_session_gdi_fallback_are_exposed(self) -> None:
        worker = (ROOT / "tek" / "app" / "worker_controller.py").read_text(encoding="utf-8")
        window = (ROOT / "tek" / "app" / "status_window.py").read_text(encoding="utf-8")
        for marker in (
            "sampler_fallback_locked",
            "gdi_to_pillow",
            "auto_locate_backoff_remaining_ms",
            "_schedule_auto_locate_backoff",
        ):
            self.assertIn(marker, worker)
        for marker in ("sampler_backend", "recent_decode_error", "运行期采样后端"):
            self.assertIn(marker, window)


if __name__ == "__main__":
    unittest.main()
