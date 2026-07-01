import unittest

from tek.src.input_planner import InputPlanError, plan_binding
import ctypes

from tek.src.windows_sendinput import INPUT, VIRTUAL_KEYS, WindowsSendInputDispatcher


class WindowsSendInputTests(unittest.TestCase):
    def test_required_p0_keys_have_virtual_key_codes(self):
        for key in ["SHIFT", "Z", "X", "C", "G", "H", "N", "R", "T", "Y", "0"]:
            self.assertIn(key, VIRTUAL_KEYS)

    def test_windows_input_structure_has_expected_size(self):
        self.assertIn(ctypes.sizeof(INPUT), (28, 40))

    def test_laptop_binding_can_be_planned_for_sendinput_backend(self):
        plan = plan_binding("SHIFT+Z")

        self.assertEqual(
            [event.key for event in plan.events],
            ["SHIFT", "Z", "Z", "SHIFT"],
        )

    def test_digit_binding_can_be_planned_for_sendinput_backend(self):
        plan = plan_binding("SHIFT+0")

        self.assertEqual(
            [event.key for event in plan.events],
            ["SHIFT", "0", "0", "SHIFT"],
        )

    def test_input_plan_rejects_duplicate_modifier(self):
        with self.assertRaisesRegex(InputPlanError, "duplicate_modifier:SHIFT"):
            plan_binding("SHIFT+SHIFT+Z")

    def test_input_plan_rejects_unknown_key(self):
        with self.assertRaisesRegex(InputPlanError, "unsupported_key:NUMPAD1"):
            plan_binding("CTRL+NUMPAD1")

    def test_input_plan_rejects_multiple_main_keys(self):
        with self.assertRaisesRegex(InputPlanError, "invalid_main_key_count:2"):
            plan_binding("SHIFT+Z+X")

    def test_sendinput_fake_backend_reports_partial_with_last_error(self):
        class FakeKernel32:
            def GetLastError(self):
                return 5

        class FakeSendInput:
            def __call__(self, count, inputs, size):
                return count - 1

        class FakeUser32:
            SendInput = FakeSendInput()

        dispatcher = WindowsSendInputDispatcher(user32=FakeUser32(), kernel32=FakeKernel32())
        result = dispatcher.dispatch(plan_binding("SHIFT+Z"))

        self.assertFalse(result.sent)
        self.assertIn("sendinput_partial:3:4:last_error:5", result.reason)


if __name__ == "__main__":
    unittest.main()
