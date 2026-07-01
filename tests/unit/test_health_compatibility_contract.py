from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HEALTH = ROOT / "addon" / "!TacticEcho" / "Tactics" / "HealthCompatibility.lua"
MONITOR = ROOT / "addon" / "!TacticEcho" / "Tactics" / "ProtocolMonitor.lua"
PLANNER = ROOT / "addon" / "!TacticEcho" / "Tactics" / "AdvisoryPlanner.lua"
ENCODER = ROOT / "addon" / "!TacticEcho" / "Signal" / "SignalEncoder.lua"
TOC = ROOT / "addon" / "!TacticEcho" / "!TacticEcho.toc"


class HealthCompatibilityContractTests(unittest.TestCase):
    def test_boolean_bridge_never_reads_or_calculates_numeric_health(self):
        source = HEALTH.read_text(encoding="utf-8")
        self.assertIn("RegisterBooleanProvider", source)
        self.assertIn("PublishBoolean", source)
        self.assertIn("boolean_required", source)
        self.assertNotIn("UnitHealth(", source)
        self.assertNotIn("UnitHealthMax(", source)
        self.assertNotIn("healthPct", source)

    def test_bit4_is_emitted_only_from_boolean_critical_state(self):
        source = MONITOR.read_text(encoding="utf-8")
        self.assertIn("HealthCompatibility", source)
        self.assertIn("if sample.playerHealthCritical == true then flags = flags + 16", source)
        self.assertNotIn("UnitHealth(", source)
        self.assertNotIn("UnitHealthMax(", source)
        self.assertIn("Tactics/HealthCompatibility.lua", TOC.read_text(encoding="utf-8"))
        self.assertIn("monitorFlags", ENCODER.read_text(encoding="utf-8"))

    def test_defensive_advice_remains_read_only_and_requires_critical_monitor(self):
        source = PLANNER.read_text(encoding="utf-8")
        self.assertIn("monitorSample.playerHealthCritical", source)
        self.assertIn("monitorSample.playerRecentDamage", source)
        self.assertIn("environmentSample.highPressure", source)
        self.assertIn("advisoryOnly = true", source)
        self.assertNotIn("SignalFrame:SetState", source)
        self.assertNotIn("SignalEncoder:Encode", source)


if __name__ == "__main__":
    unittest.main()
