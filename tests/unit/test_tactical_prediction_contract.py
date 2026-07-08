from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class TacticalPredictionContractTests(unittest.TestCase):
    def test_advisory_planner_and_prediction_queue_are_not_loaded(self) -> None:
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        self.assertNotIn("Tactics/AdvisoryPlanner.lua", toc)
        self.assertNotIn("Tactics/RecommendationQueue.lua", toc)
        self.assertIn("Tactics/BurstPlanner.lua", toc)
        self.assertLess(toc.index("Tactics/BurstPlanner.lua"), toc.index("Tactics/TacticalAdvisors.lua"))

    def test_tactical_state_still_records_primary_transitions(self) -> None:
        state = (ADDON / "Tactics" / "TacticalState.lua").read_text(encoding="utf-8")
        self.assertIn("recordTransition(previous, current)", state)
        self.assertIn("GetTransitionCandidates", state)
        self.assertIn('source = "observed_transition"', state)
        self.assertIn("sessionOnly = true", state)

    def test_advisors_call_burst_planner_directly_and_publish_no_prediction_history(self) -> None:
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        narrowed = advisors[advisors.index("Product scope is intentionally narrowed"):]
        self.assertIn("TE.BurstPlanner:Build(primary, context, settings, runtime)", narrowed)
        self.assertIn('history = { active = false, items = {}, source = "retired_scope"', narrowed)
        self.assertIn("advisory = advisory", narrowed)
        self.assertNotIn("SignalFrame:SetState", narrowed)
        self.assertNotIn("SignalEncoder:Encode", narrowed)

    def test_hud_model_and_control_panel_expose_primary_and_burst_only(self) -> None:
        model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.assertIn("schema = 4", model)
        self.assertIn("candidates = {}", model)
        self.assertIn("defense = {}", model)
        self.assertIn("主键 + 爆发", control)
        self.assertIn("BUILDERS.interrupt = nil", control)
        self.assertIn("BUILDERS.defense = nil", control)
        self.assertIn("BUILDERS.monitor = nil", control)


if __name__ == "__main__":
    unittest.main()
