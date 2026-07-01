from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tek.src.input_planner import DispatchResult
from tek.src.sendinput_acceptance import ACCEPTANCE_CONFIRMATION, run_sendinput_acceptance, write_acceptance_evidence
from tek.src.windows_foreground import ForegroundWindow


class _Detector:
    def __init__(self, process_name: str = "notepad.exe"):
        self.window = ForegroundWindow(hwnd=101, title="Untitled - Notepad", process_id=3, process_name=process_name)

    def current(self):
        return self.window


class _Dispatcher:
    def dispatch(self, plan):
        return DispatchResult(sent=True, backend="windows_sendinput", reason="input_sent", events_sent=len(plan.events))


class SendInputAcceptanceTests(unittest.TestCase):
    def test_requires_exact_confirmation_without_target_lookup(self):
        result = run_sendinput_acceptance(confirmation="", foreground_detector=_Detector(), dispatcher=_Dispatcher())
        self.assertFalse(result.ok)
        self.assertEqual(result.reason, "acceptance_confirmation_required")

    def test_refuses_game_target(self):
        result = run_sendinput_acceptance(confirmation=ACCEPTANCE_CONFIRMATION, expected_process="wow.exe")
        self.assertFalse(result.ok)
        self.assertEqual(result.reason, "acceptance_target_game_forbidden")

    @patch("tek.src.sendinput_acceptance.os.name", "nt")
    def test_uses_sendinput_only_for_expected_non_game_foreground(self):
        result = run_sendinput_acceptance(
            confirmation=ACCEPTANCE_CONFIRMATION,
            expected_process="notepad.exe",
            binding="Q",
            foreground_detector=_Detector(),
            dispatcher=_Dispatcher(),
        )
        self.assertTrue(result.ok)
        self.assertEqual(result.reason, "input_sent")
        self.assertEqual(result.binding, "Q")
        self.assertEqual(result.events_sent, 2)

    @patch("tek.src.sendinput_acceptance.os.name", "nt")
    def test_rejects_wrong_foreground_process(self):
        result = run_sendinput_acceptance(
            confirmation=ACCEPTANCE_CONFIRMATION,
            expected_process="notepad.exe",
            foreground_detector=_Detector("calc.exe"),
            dispatcher=_Dispatcher(),
        )
        self.assertFalse(result.ok)
        self.assertEqual(result.reason, "acceptance_foreground_target_mismatch")

    def test_writes_json_evidence(self):
        result = run_sendinput_acceptance(confirmation="")
        with tempfile.TemporaryDirectory() as temporary:
            path = write_acceptance_evidence(result, temporary)
            self.assertTrue(path.exists())
            self.assertIn("acceptance_confirmation_required", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
