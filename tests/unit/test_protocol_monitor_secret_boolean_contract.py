from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MONITOR = ROOT / "addon" / "!TacticEcho" / "Tactics" / "ProtocolMonitor.lua"


class ProtocolMonitorSecretBooleanContractTests(unittest.TestCase):
    def test_target_interruptibility_is_sanitized_before_any_comparison(self) -> None:
        text = MONITOR.read_text(encoding="utf-8")
        self.assertIn("local function plainBoolean(value)", text)
        self.assertIn("if value == true then return true end", text)
        self.assertIn("if value == false then return false end", text)
        self.assertIn("Preserve false so interruptible casts remain known", text)
        self.assertIn("local safeNotInterruptible = plainBoolean(notInterruptible)", text)
        self.assertIn("state.targetInterruptibleKnown = safeNotInterruptible ~= nil", text)
        self.assertIn("state.targetInterruptible = safeNotInterruptible == false", text)
        self.assertNotIn("state.targetInterruptible = notInterruptible ~= true", text)

    def test_target_cast_scalars_are_secret_safe_and_degrade_to_unknown(self) -> None:
        text = MONITOR.read_text(encoding="utf-8")
        for marker in (
            "local function plainNumber(value)",
            "local function plainText(value)",
            "local safeSpellID = plainNumber(spellID)",
            "local safeName = ok and plainText(name) or nil",
            "secret boolean",
            "fail-unknown",
        ):
            self.assertIn(marker, text)


if __name__ == "__main__":
    unittest.main()
