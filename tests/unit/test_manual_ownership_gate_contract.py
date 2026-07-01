from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHYSICAL = ROOT / "tek" / "src" / "physical_input.py"
WHITELIST = ROOT / "tek" / "src" / "keyboard_whitelist.py"
ENGINE = ROOT / "tek" / "src" / "engine.py"
WINDOW = ROOT / "tek" / "app" / "status_window.py"
SIGNAL_ENCODER = ROOT / "addon" / "!TacticEcho" / "Signal" / "SignalEncoder.lua"
SIGNAL_FRAME = ROOT / "addon" / "!TacticEcho" / "Signal" / "SignalFrame.lua"
EXPORT = ROOT / "addon" / "!TacticEcho" / "Diagnostics" / "MappingExport.lua"


class ManualOwnershipGateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.physical = PHYSICAL.read_text(encoding="utf-8")
        self.whitelist = WHITELIST.read_text(encoding="utf-8")
        self.engine = ENGINE.read_text(encoding="utf-8")
        self.window = WINDOW.read_text(encoding="utf-8")
        self.encoder = SIGNAL_ENCODER.read_text(encoding="utf-8")
        self.signal = SIGNAL_FRAME.read_text(encoding="utf-8")
        self.export = EXPORT.read_text(encoding="utf-8")

    def test_held_keyboard_ownership_and_release_recovery_are_explicit(self) -> None:
        for token in (
            "MANUAL_PRIORITY_POLICIES",
            '"aggressive": {"recovery_seconds": 0.000, "freshness_frames": 1, "replay_guard_seconds": 0.100}',
            '"balanced": {"recovery_seconds": 0.030, "freshness_frames": 2, "replay_guard_seconds": 0.150}',
            '"manual_first": {"recovery_seconds": 0.250, "freshness_frames": 2, "replay_guard_seconds": 0.500}',
            "begin_manual_hold",
            "end_manual_hold",
            "manual_replay_guard",
            "manual_epoch",
            "reset_recovery_gate",
        ):
            self.assertIn(token, self.physical)

    def test_mouse_is_ignored_and_exempt_keys_are_local_configuration_only(self) -> None:
        self.assertIn("def observe_mouse_button", self.physical)
        self.assertIn("def observe_mouse_middle_down", self.physical)
        self.assertIn("def observe_mouse_wheel", self.physical)
        self.assertNotIn("movement_bindings", self.physical)
        self.assertIn("DEFAULT_DISPATCH_EXEMPT_KEYS", self.whitelist)
        self.assertIn("MODIFIER_KEYS", self.whitelist)
        self.assertIn("standalone_modifiers_allowed", self.whitelist)
        self.assertFalse((ROOT / "tek" / "src" / "movement_bindings.py").exists())

    def test_real_sendinput_rechecks_hook_and_epoch_before_dispatch(self) -> None:
        self.assertIn('self.dispatcher_backend != "windows_sendinput"', self.engine)
        self.assertIn("physical_input_hook_unavailable", self.engine)
        self.assertIn("manual_epoch_changed", self.engine)
        self.assertIn("# The second check closes the race", self.engine)

    def test_teap_manual_hold_is_addon_blocking_state_only(self) -> None:
        self.assertIn("manual_hold = 7", self.encoder)
        self.assertIn('return "manual_hold", inputFocusReason', self.signal)
        self.assertIn('manualHoldActive = outputState == "manual_hold"', self.signal)
        self.assertIn("copyMovementBindings", self.export)
        self.assertIn("movementBindings = copyMovementBindings()", self.export)

    def test_window_bounds_manual_settings_and_local_whitelist_editor_are_exposed(self) -> None:
        for token in (
            "root.minsize(450, 900)",
            "root.maxsize(900, 2000)",
            "root.resizable(True, True)",
            'values=("aggressive", "balanced", "manual_first", "custom")',
            "连发介入按键",
            "Ctrl、Alt、Shift、Win 不能单独加入白名单",
            "manual_priority_custom_recovery_ms",
        ):
            self.assertIn(token, self.window)
        self.assertNotIn("wow_bindings_cache_path", self.window)


if __name__ == "__main__":
    unittest.main()
