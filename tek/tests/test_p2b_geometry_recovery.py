from __future__ import annotations

import unittest
from dataclasses import dataclass

from tek.app.worker_controller import AutoLocateFrameSource
from tek.src.safety_gate import ForegroundSnapshot
from tek.src.screen_sampler import CaptureBounds, SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import encode_test_blocks


@dataclass(frozen=True)
class _Calibration:
    hwnd: int
    client_origin: tuple[int, int]
    client_rect: tuple[int, int, int, int]
    dpi: int
    window_mode: str
    monitor_rect: tuple[int, int, int, int]


class P2BGeometryRecoveryTests(unittest.TestCase):
    @staticmethod
    def _blocks(freshness: int = 8):
        return encode_test_blocks(encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=freshness))

    @staticmethod
    def _bounds(calibration: _Calibration) -> CaptureBounds:
        left, top = calibration.client_origin
        _, _, right, bottom = calibration.client_rect
        return CaptureBounds(left, top, left + right, top + bottom)

    def test_client_move_reprojects_strip_without_a_new_client_scan(self):
        calibrations = [
            _Calibration(77, (100, 200), (0, 0, 1200, 800), 144, "windowed", (0, 0, 1920, 1080)),
            _Calibration(77, (500, 300), (0, 0, 1200, 800), 144, "windowed", (0, 0, 1920, 1080)),
        ]
        current = [0]
        initial = SignalLayout(x=124, y=222, block_size=20, block_gap=4)
        locator_calls = []
        sampled = []

        class Sampler:
            backend = "pillow"

            def __init__(self):
                self.freshness = 7

            def sample(self, layout):
                sampled.append(layout)
                self.freshness += 1
                return P2BGeometryRecoveryTests._blocks(self.freshness)

        def calibration_provider(hwnd=None):
            return calibrations[current[0]]

        def locate(bounds):
            locator_calls.append(bounds)
            return initial

        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=Sampler(),
            calibration_provider=calibration_provider,
            client_locate_function=locate,
            layout_verification_interval_seconds=0,
        )
        source.set_foreground_window(ForegroundSnapshot(ok=True, hwnd=77, process_id=88))
        source.read()
        current[0] = 1
        source.read()

        self.assertEqual(len(locator_calls), 1)
        self.assertEqual(sampled[0], initial)
        self.assertEqual(sampled[1], initial)  # second complete proof frame
        self.assertEqual(sampled[2], SignalLayout(x=524, y=322, block_size=20, block_gap=4, block_count=20))
        diagnostics = source.diagnostics()
        self.assertEqual(diagnostics["last_geometry_change_reasons"], ["client_moved"])
        self.assertFalse(diagnostics["relocation_pending"])

    def test_resize_dpi_and_mode_change_waits_for_stability_then_relocates(self):
        now = [0.0]
        calibrations = [
            _Calibration(77, (100, 200), (0, 0, 1200, 800), 144, "windowed", (0, 0, 1920, 1080)),
            _Calibration(77, (40, 20), (0, 0, 1600, 1000), 192, "borderless_or_fullscreen", (1920, 0, 4480, 1440)),
        ]
        current = [0]
        initial = SignalLayout(x=124, y=222, block_size=20, block_gap=4)
        relocated = SignalLayout(x=210, y=120, block_size=24, block_gap=5)
        locator_calls = []
        sampled = []

        class Sampler:
            backend = "pillow"

            def __init__(self):
                self.freshness = 7

            def sample(self, layout):
                sampled.append(layout)
                if current[0] == 1 and layout != relocated:
                    raise ValueError("green_mismatch")
                self.freshness += 1
                return P2BGeometryRecoveryTests._blocks(self.freshness)

        def calibration_provider(hwnd=None):
            return calibrations[current[0]]

        def locate(bounds):
            locator_calls.append(bounds)
            return initial if len(locator_calls) == 1 else relocated

        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=Sampler(),
            calibration_provider=calibration_provider,
            client_locate_function=locate,
            clock=lambda: now[0],
            layout_verification_interval_seconds=0,
            geometry_transition_settle_seconds=0.35,
        )
        source.set_foreground_window(ForegroundSnapshot(ok=True, hwnd=77, process_id=88))
        source.read()
        current[0] = 1
        with self.assertRaisesRegex(OSError, "geometry_transition_wait"):
            source.read()
        self.assertEqual(sampled, [initial, initial])

        now[0] = 0.36
        with self.assertRaisesRegex(OSError, "layout_relocating"):
            source.read()
        frame = source.read()

        self.assertEqual(frame.sequence, 3)
        self.assertEqual(locator_calls, [self._bounds(calibrations[0]), P2BGeometryRecoveryTests._bounds(calibrations[1])])
        self.assertEqual(sampled[-1], relocated)
        self.assertEqual(len(sampled), 4)  # two-frame initial proof, no stale projection, two-frame relocated proof
        diagnostics = source.diagnostics()
        self.assertFalse(diagnostics["relocation_pending"])
        self.assertIn("geometry_transition_relocated:client_moved,client_resized,dpi_changed,window_mode_changed,monitor_changed", diagnostics["last_relocation_reason"])
        self.assertEqual(
            diagnostics["last_geometry_change_reasons"],
            ["client_moved", "client_resized", "dpi_changed", "window_mode_changed", "monitor_changed"],
        )


if __name__ == "__main__":
    unittest.main()

class P2BRelocationBackoffTests(unittest.TestCase):
    def test_failed_geometry_relocation_respects_backoff_before_next_client_scan(self):
        now = [0.0]
        calibrations = [
            _Calibration(77, (100, 200), (0, 0, 1200, 800), 144, "windowed", (0, 0, 1920, 1080)),
            _Calibration(77, (40, 20), (0, 0, 1600, 1000), 192, "borderless_or_fullscreen", (1920, 0, 4480, 1440)),
        ]
        current = [0]
        initial = SignalLayout(x=124, y=222, block_size=20, block_gap=4)
        locator_calls = []
        class Sampler:
            backend = "pillow"

            def __init__(self):
                self.freshness = 7

            def sample(self, layout):
                if current[0] == 1:
                    raise ValueError("green_mismatch")
                self.freshness += 1
                return P2BGeometryRecoveryTests._blocks(self.freshness)

        def calibration_provider(hwnd=None):
            return calibrations[current[0]]

        def locate(bounds):
            locator_calls.append((now[0], bounds))
            if len(locator_calls) == 1:
                return initial
            raise OSError("te_signal_layout_not_found")

        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=Sampler(),
            calibration_provider=calibration_provider,
            client_locate_function=locate,
            clock=lambda: now[0],
            auto_locate_initial_backoff_seconds=1.0,
            auto_locate_max_backoff_seconds=4.0,
            layout_verification_interval_seconds=0,
        )
        source.set_foreground_window(ForegroundSnapshot(ok=True, hwnd=77, process_id=88))
        source.read()
        current[0] = 1
        with self.assertRaisesRegex(OSError, "geometry_transition_wait"):
            source.read()
        self.assertEqual(len(locator_calls), 1)  # no old-layout sample and no scan until stable

        now[0] = 0.1
        with self.assertRaisesRegex(OSError, "geometry_transition_wait"):
            source.read()
        self.assertEqual(len(locator_calls), 1)

        now[0] = 0.36
        with self.assertRaisesRegex(OSError, "layout_relocating|te_signal_layout_not_found"):
            source.read()
        self.assertEqual(len(locator_calls), 2)  # first bounded retry after stable geometry

        now[0] = 0.50
        with self.assertRaisesRegex(OSError, "layout_relocating"):
            source.read()
        self.assertEqual(len(locator_calls), 2)  # relocation failure remains behind backoff

        now[0] = 1.36
        with self.assertRaisesRegex(OSError, "layout_relocating|te_signal_layout_not_found"):
            source.read()
        self.assertEqual(len(locator_calls), 3)

class P4BProgressiveRecoveryTests(unittest.TestCase):
    def test_progressive_client_regions_are_bounded_to_the_fixed_top_left_anchor(self):
        from tek.src.screen_sampler import progressive_client_search_bounds

        bounds = CaptureBounds(100, 200, 4100, 2400)
        regions = progressive_client_search_bounds(bounds)
        self.assertEqual(
            [region.to_dict() for region in regions],
            [
                {"left": 100, "top": 200, "right": 460, "bottom": 296, "width": 360, "height": 96},
                {"left": 100, "top": 200, "right": 740, "bottom": 360, "width": 640, "height": 160},
                {"left": 100, "top": 200, "right": 1060, "bottom": 440, "width": 960, "height": 240},
            ],
        )

    def test_background_relocation_does_not_block_failed_sampling_tick(self):
        import threading
        import time
        now = [0.0]

        calibrations = [
            _Calibration(77, (100, 200), (0, 0, 1200, 800), 144, "windowed", (0, 0, 1920, 1080)),
            _Calibration(77, (40, 20), (0, 0, 1600, 1000), 192, "borderless_or_fullscreen", (1920, 0, 4480, 1440)),
        ]
        current = [0]
        initial = SignalLayout(x=124, y=222, block_size=20, block_gap=4)
        relocated = SignalLayout(x=210, y=120, block_size=24, block_gap=5)
        locator_started = threading.Event()
        locator_release = threading.Event()
        locator_calls = []

        class Sampler:
            backend = "pillow"

            def __init__(self):
                self.freshness = 7

            def sample(self, layout):
                if current[0] == 1 and layout != relocated:
                    raise ValueError("green_mismatch")
                self.freshness += 1
                return P2BGeometryRecoveryTests._blocks(self.freshness)

        def calibration_provider(hwnd=None):
            return calibrations[current[0]]

        def locate(bounds):
            locator_calls.append(bounds)
            if len(locator_calls) == 1:
                return initial
            locator_started.set()
            self.assertTrue(locator_release.wait(1.0))
            return relocated

        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=Sampler(),
            calibration_provider=calibration_provider,
            client_locate_function=locate,
            background_relocation=True,
            clock=lambda: now[0],
            layout_verification_interval_seconds=0,
            geometry_transition_settle_seconds=0.35,
        )
        source.set_foreground_window(ForegroundSnapshot(ok=True, hwnd=77, process_id=88))
        source.read()
        current[0] = 1
        with self.assertRaisesRegex(OSError, "geometry_transition_wait"):
            source.read()
        self.assertFalse(locator_started.is_set())
        now[0] = 0.36
        locator_release.set()
        with self.assertRaisesRegex(OSError, "layout_relocating"):
            source.read()
        self.assertEqual(source.read().sequence, 3)
        self.assertEqual(locator_calls[-1], P2BGeometryRecoveryTests._bounds(calibrations[1]))
        source.close()

    def test_cross_start_layout_cache_is_only_a_hint_but_avoids_initial_scan_after_live_decode(self):
        calibration = _Calibration(77, (500, 300), (0, 0, 1200, 800), 144, "windowed", (0, 0, 1920, 1080))
        original = SignalLayout(x=124, y=222, block_size=20, block_gap=4)
        from tek.src.screen_sampler import RelativeSignalLayout

        relative = RelativeSignalLayout.from_layout(
            original,
            client_left=100,
            client_top=200,
            client_width=1200,
            client_height=800,
        )
        cache = {
            "schema_version": 1,
            "layout": original.to_dict(),
            "relative_layout": relative.to_dict(),
        }
        expected = SignalLayout(x=524, y=322, block_size=20, block_gap=4)

        class Sampler:
            backend = "pillow"
            def __init__(self):
                self.layouts = []
                self.freshness = 7
            def sample(self, layout):
                self.layouts.append(layout)
                self.freshness += 1
                return P2BGeometryRecoveryTests._blocks(self.freshness)

        sampler = Sampler()
        source = AutoLocateFrameSource(
            auto_locate=True,
            sampler=sampler,
            calibration_provider=lambda hwnd=None: calibration,
            client_locate_function=lambda bounds: self.fail("cache hint should be validated before scanning"),
            layout_cache=cache,
            layout_verification_interval_seconds=0,
        )
        source.set_foreground_window(ForegroundSnapshot(ok=True, hwnd=77, process_id=88))
        self.assertEqual(source.read().sequence, 3)
        self.assertEqual(sampler.layouts, [expected, expected])
        persisted = source.take_layout_cache_update()
        self.assertIsNotNone(persisted)
        self.assertEqual(persisted["layout"], expected.to_dict())
