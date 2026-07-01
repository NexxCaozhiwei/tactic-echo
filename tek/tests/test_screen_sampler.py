import unittest

from PIL import Image

from tek.src.screen_sampler import PillowScreenSampler, SignalLayout, locate_te_signal_layout_from_image
from tek.src.visual_decoder import RGB, decode_rgb_blocks
from tek.src.teap import encode_fields_v3


class ScreenSamplerTests(unittest.TestCase):
    def test_default_layout_matches_te_signal_frame_centers(self):
        layout = SignalLayout()

        self.assertEqual(
            layout.sample_points(),
            (
                (13, 13),
                (25, 13),
                (37, 13),
                (49, 13),
                (61, 13),
                (73, 13),
                (85, 13),
                (97, 13),
                (109, 13),
                (121, 13),
                (133, 13),
                (145, 13),
                (157, 13),
                (169, 13),
                (181, 13),
                (193, 13),
                (205, 13),
                (217, 13),
                (229, 13),
                (241, 13),
            ),
        )

    def test_custom_origin_keeps_spacing(self):
        layout = SignalLayout(x=100, y=200)

        self.assertEqual(layout.sample_points()[0], (105, 205))
        self.assertEqual(layout.sample_points()[1], (117, 205))

    def test_locates_scaled_teap_v3_blocks(self):
        image = Image.new("RGB", (600, 120), (0, 0, 0))
        values = encode_fields_v3(action_code=1, sequence=44, frame_freshness_counter=170)
        x = 22
        y = 22
        block_size = 18
        gap = 4
        for index, value in enumerate(values):
            left = x + index * (block_size + gap)
            for px in range(left, left + block_size):
                for py in range(y, y + block_size):
                    image.putpixel((px, py), (value, 255 - value, 17))

        layout = locate_te_signal_layout_from_image(image)

        self.assertIn(layout.x, (x - 1, x))
        self.assertEqual(layout.block_size, block_size)
        self.assertEqual(layout.block_gap, gap)
        blocks = tuple(RGB(*image.getpixel(point)) for point in layout.sample_points())
        frame = decode_rgb_blocks(blocks)
        self.assertEqual(frame.protocol_version, 3)
        self.assertEqual(frame.action_code, 1)

    def test_locates_v3_header_when_blocks_touch_without_visible_gap(self):
        image = Image.new("RGB", (420, 80), (0, 0, 0))
        values = encode_fields_v3(action_code=1, sequence=44, frame_freshness_counter=170)
        x, y, block_size = 18, 16, 12
        for index, value in enumerate(values):
            left = x + index * block_size
            for px in range(left, left + block_size):
                for py in range(y, y + block_size):
                    image.putpixel((px, py), (value, 255 - value, 17))

        layout = locate_te_signal_layout_from_image(image)

        self.assertEqual(layout.block_gap, 0)
        self.assertEqual(layout.block_size, block_size)
        self.assertEqual(decode_rgb_blocks(tuple(RGB(*image.getpixel(point)) for point in layout.sample_points())).sequence, 44)

    def test_runtime_sampling_uses_median_to_tolerate_one_corrupt_center_pixel(self):
        layout = SignalLayout(x=100, y=200, block_size=10, block_gap=0)
        values = encode_fields_v3(action_code=1, sequence=5, frame_freshness_counter=9)
        image = Image.new("RGB", (layout.strip_width, layout.strip_height), (0, 0, 0))
        for index, value in enumerate(values):
            left = index * layout.block_size
            for px in range(left, left + layout.block_size):
                for py in range(layout.block_size):
                    image.putpixel((px, py), (value, 255 - value, 17))
        # A single center pixel no longer invalidates the T block because the
        # 5×5 center window uses a per-channel median.
        image.putpixel((layout.block_size // 2, layout.block_size // 2), (0, 0, 0))

        sampler = PillowScreenSampler()
        sampler.capture_region = lambda bounds: (image, bounds.left, bounds.top)
        frame = decode_rgb_blocks(sampler.sample(layout))

        self.assertEqual(frame.protocol_version, 3)
        self.assertEqual(frame.sequence, 5)

    def test_header_locator_rejects_wrong_v3_version_cell(self):
        image = Image.new("RGB", (420, 80), (0, 0, 0))
        values = list(encode_fields_v3(action_code=1, sequence=44, frame_freshness_counter=170))
        values[2] = 4
        x, y, block_size = 18, 16, 12
        for index, value in enumerate(values):
            left = x + index * block_size
            for px in range(left, left + block_size):
                for py in range(y, y + block_size):
                    image.putpixel((px, py), (value, 255 - value, 17))

        with self.assertRaises(OSError):
            locate_te_signal_layout_from_image(image)


if __name__ == "__main__":
    unittest.main()

class MultiDisplayScreenSamplerTests(unittest.TestCase):
    def test_locator_translates_virtual_desktop_origin(self):
        image = Image.new("RGB", (700, 160), (0, 0, 0))
        values = encode_fields_v3(action_code=1, sequence=3, frame_freshness_counter=6)
        x, y, block_size, gap = 120, 28, 12, 3
        for index, value in enumerate(values):
            left = x + index * (block_size + gap)
            for px in range(left, left + block_size):
                for py in range(y, y + block_size):
                    image.putpixel((px, py), (value, 255 - value, 17))

        layout = locate_te_signal_layout_from_image(image, search_width=None, search_height=None, origin_x=-1920, origin_y=-120)

        self.assertIn(layout.x, (-1920 + x - 1, -1920 + x))
        self.assertIn(layout.y, (-120 + y - 1, -120 + y))
        self.assertEqual(layout.sample_points()[0][0], layout.x + block_size // 2)

class RuntimeSamplerSelectionTests(unittest.TestCase):
    def test_runtime_sampler_prefers_pillow_on_windows_by_default(self):
        from unittest.mock import patch
        from tek.src import screen_sampler

        with patch.object(screen_sampler.os, "name", "nt"):
            self.assertIsInstance(screen_sampler.runtime_pixel_sampler(), screen_sampler.PillowScreenSampler)
            self.assertIsInstance(screen_sampler.runtime_pixel_sampler("auto"), screen_sampler.PillowScreenSampler)

    def test_runtime_sampler_allows_explicit_gdi_experiment_on_windows(self):
        from unittest.mock import patch
        from tek.src import screen_sampler

        sentinel = object()
        with patch.object(screen_sampler.os, "name", "nt"), patch.object(screen_sampler, "GDIPixelSampler", return_value=sentinel) as factory:
            self.assertIs(screen_sampler.runtime_pixel_sampler("gdi"), sentinel)
            factory.assert_called_once_with()

    def test_runtime_sampler_allows_explicit_gdi_blt_on_windows(self):
        from unittest.mock import patch
        from tek.src import screen_sampler

        sentinel = object()
        with patch.object(screen_sampler.os, "name", "nt"), patch.object(screen_sampler, "GDIBlitStripSampler", return_value=sentinel) as factory:
            self.assertIs(screen_sampler.runtime_pixel_sampler("gdi_blt"), sentinel)
            factory.assert_called_once_with()

    def test_runtime_sampler_uses_pillow_on_non_windows_hosts(self):
        from unittest.mock import patch
        from tek.src import screen_sampler

        with patch.object(screen_sampler.os, "name", "posix"):
            self.assertIsInstance(screen_sampler.runtime_pixel_sampler(), screen_sampler.PillowScreenSampler)
            self.assertIsInstance(screen_sampler.runtime_pixel_sampler("gdi"), screen_sampler.PillowScreenSampler)
