from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TOC = ADDON / "!TacticEcho.toc"


class HealthCompatibilityContractTests(unittest.TestCase):
    def test_health_defense_runtime_is_retired_from_loaded_addon(self):
        toc = TOC.read_text(encoding="utf-8")
        self.assertNotIn("Tactics/HealthCompatibility.lua", toc)
        self.assertNotIn("Tactics/ProtocolMonitor.lua", toc)
        self.assertNotIn("Tactics/AdvisoryPlanner.lua", toc)

    def test_retired_sources_do_not_reenter_signal_or_hud_scope(self):
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        self.assertIn("scope_primary_burst", advisors)
        self.assertIn("retired_scope", advisors)
        self.assertIn("AutoBurst queue", model)
        self.assertIn("defense = {}", model)


if __name__ == "__main__":
    unittest.main()
