import unittest

from tek.src.teap import decode_fields, encode_fields_v3


class TelemetryFlagTests(unittest.TestCase):
    def test_v3_reserved_monitor_bits_decode_without_changing_dispatch_fields(self):
        fields = encode_fields_v3(
            state="armed", action_code=7, binding_token=42,
            target_casting=True, target_interruptible=True, player_health_critical=True,
        )
        frame = decode_fields(fields)
        self.assertEqual(frame.state, "armed")
        self.assertEqual(frame.action_code, 7)
        self.assertEqual(frame.binding_token, 42)
        self.assertTrue(frame.target_casting)
        self.assertTrue(frame.target_interruptible)
        self.assertTrue(frame.player_health_critical)
        self.assertEqual(frame.monitor_flags, 0x1C)

    def test_v3_default_monitor_bits_remain_clear(self):
        frame = decode_fields(encode_fields_v3())
        self.assertFalse(frame.target_casting)
        self.assertFalse(frame.target_interruptible)
        self.assertFalse(frame.player_health_critical)
        self.assertEqual(frame.monitor_flags, 0)


if __name__ == "__main__":
    unittest.main()
