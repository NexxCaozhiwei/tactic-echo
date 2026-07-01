from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class TacticalPredictionContractTests(unittest.TestCase):
    def test_toc_loads_the_read_only_advisory_planner_before_advisors(self) -> None:
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        self.assertIn("Tactics/AdvisoryPlanner.lua", toc)
        self.assertLess(toc.index("Tactics/AbilityProfiles.lua"), toc.index("Tactics/AdvisoryPlanner.lua"))
        self.assertLess(toc.index("Tactics/AdvisoryPlanner.lua"), toc.index("Tactics/TacticalAdvisors.lua"))

    def test_prediction_is_session_transition_based_not_a_fake_queue(self) -> None:
        state = (ADDON / "Tactics" / "TacticalState.lua").read_text(encoding="utf-8")
        self.assertIn("recordTransition(previous, current)", state)
        self.assertIn("GetTransitionCandidates", state)
        self.assertIn('source = "observed_transition"', state)
        self.assertIn("sessionOnly = true", state)
        self.assertIn("Consecutive refreshes of the same official recommendation", state)

    def test_advisory_conditions_are_explicit_and_read_only(self) -> None:
        planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        for token in (
            "settings.candidatePredictionEnabled",
            "official_burst_anchor",
            "targetInterruptSuppressed",
            "GetUnitSpeed",
            "OnUpdate",
            'item.source = "target_noninterruptible_cast"',
            "environmentSample.highPressure",
            "advisoryOnly = true",
        ):
            self.assertIn(token, planner)
        for forbidden in (
            "SetBinding(",
            "SaveBindings(",
            "SetOverrideBindingClick(",
            "SignalFrame:SetState",
            "SignalEncoder:Encode",
            "UnitHealth(",
            "UnitHealthMax(",
            "GetSpellCooldown(",
        ):
            self.assertNotIn(forbidden, planner)

    def test_advisors_keep_prediction_outside_the_primary_dispatch_data(self) -> None:
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn("TE.AdvisoryPlanner:Build(primary, context, settings)", advisors)
        self.assertIn("history = buildPreview(primary, settings, advisory.candidates)", advisors)
        self.assertIn("advisory = advisory", advisors)
        self.assertNotIn("SignalFrame:SetState", advisors)
        self.assertNotIn("SignalEncoder:Encode", advisors)

    def test_hud_model_and_diagnostics_label_prediction_and_no_dispatch(self) -> None:
        model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        diagnostics = (ADDON / "UI" / "Diagnostics.lua").read_text(encoding="utf-8")
        control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.assertIn("MAX_CANDIDATES = 3", model)
        self.assertIn('buildFixedItems(candidates, MAX_CANDIDATES, "candidate")', model)
        self.assertIn("TacticalHudModel", board)
        self.assertIn("战术预测：状态=", diagnostics)
        self.assertIn("候选预测、爆发、控制、位移", diagnostics)
        self.assertIn("队列模式", control)
        self.assertIn("启用控制提示", control)


if __name__ == "__main__":
    unittest.main()
