import unittest

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.profile_resolver import ProfileResolver
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import RGB, VisualDecodeError, decode_rgb_blocks, decode_stable_rgb_samples, encode_test_blocks


def fields(action_code=1, sequence=42, state=1):
    profile = ProfileResolver.from_file("examples/profiles/laptop.json").profile
    state_name = {0: "waiting", 1: "armed", 2: "paused", 3: "blocked", 4: "error", 5: "channeling", 6: "empowering"}[state]
    return encode_fields_v3(
        state=state_name,
        action_code=action_code,
        sequence=sequence,
        frame_freshness_counter=sequence + 1,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
                in_combat=True,
    )


class VisualDecoderTests(unittest.TestCase):
    def test_decodes_te_signal_rgb_blocks_to_frame(self):
        frame = decode_rgb_blocks(encode_test_blocks(fields(action_code=9, sequence=513)))

        self.assertEqual(frame.state, "armed")
        self.assertEqual(frame.action_code, 9)
        self.assertEqual(frame.sequence, 513)

    def test_decodes_dedicated_channel_and_empower_states(self):
        channeling = decode_rgb_blocks(encode_test_blocks(fields(action_code=1, sequence=514, state=5)))
        empowering = decode_rgb_blocks(encode_test_blocks(fields(action_code=1, sequence=515, state=6)))

        self.assertEqual(channeling.state, "channeling")
        self.assertEqual(empowering.state, "empowering")

    def test_rejects_wrong_block_count(self):
        with self.assertRaisesRegex(VisualDecodeError, "invalid_block_count:19"):
            decode_rgb_blocks(encode_test_blocks(fields()[:19]))

    def test_rejects_color_integrity_mismatch(self):
        blocks = list(encode_test_blocks(fields()))
        blocks[0] = RGB(red=84, green=84, blue=17)

        with self.assertRaisesRegex(VisualDecodeError, "green_mismatch"):
            decode_rgb_blocks(blocks)

    def test_allows_small_sampling_tolerance(self):
        blocks = list(encode_test_blocks(fields()))
        blocks[0] = RGB(red=84, green=172, blue=18)

        frame = decode_rgb_blocks(blocks, tolerance=2)
        self.assertEqual(frame.action_code, 1)

    def test_rejects_unstable_double_sample(self):
        first = list(encode_test_blocks(fields()))
        second = list(first)
        second[10] = RGB(red=2, green=253, blue=17)

        with self.assertRaisesRegex(VisualDecodeError, "unstable_frame_sample"):
            decode_stable_rgb_samples(first, second)


if __name__ == "__main__":
    unittest.main()
