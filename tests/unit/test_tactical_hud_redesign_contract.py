from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TOC = ADDON / "!TacticEcho.toc"


class TacticalHudRedesignContractTests(unittest.TestCase):
    def test_queue_hud_modules_are_loaded_before_board(self) -> None:
        toc = TOC.read_text(encoding="utf-8")
        expected = [
            "UI/TacticalHudStyles.lua",
            "UI/TacticalHudAnimator.lua",
            "UI/TacticalHudModel.lua",
            "UI/TacticalIconButton.lua",
            "UI/TacticalHudDragHandle.lua",
            "UI/TacticalHudLayout.lua",
            "UI/TacticalBoard.lua",
        ]
        for path in expected:
            self.assertIn(path, toc)
            self.assertTrue((ADDON / path).is_file(), path)
        for earlier in expected[:-1]:
            self.assertLess(toc.index(earlier), toc.index("UI/TacticalBoard.lua"))

    def test_visual_semantics_are_explicit(self) -> None:
        styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")
        for token in (
            "dispatchable",
            "preview",
            "blocked",
            "unknown",
            "unbound",
            "paused",
            "interrupt",
            "defense",
            "burst",
        ):
            self.assertIn(token, styles)

    def test_hud_is_display_only_and_avoids_dynamic_event_registration(self) -> None:
        forbidden = (
            "RecommendationAdapter:ReadOfficial",
            "SignalEncoder:Encode",
            "SetBinding(",
            "SaveBindings(",
            "SetOverrideBindingClick(",
            "RegisterEvent(",
        )
        for relative in (
            "UI/TacticalHudModel.lua",
            "UI/TacticalIconButton.lua",
            "UI/TacticalHudDragHandle.lua",
            "UI/TacticalHudLayout.lua",
            "UI/TacticalBoard.lua",
        ):
            text = (ADDON / relative).read_text(encoding="utf-8")
            for token in forbidden:
                self.assertNotIn(token, text, f"{relative} contains {token}")

    def test_fixed_slots_debounce_and_detached_defense_are_present(self) -> None:
        model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        layout = (ADDON / "UI" / "TacticalHudLayout.lua").read_text(encoding="utf-8")
        animator = (ADDON / "UI" / "TacticalHudAnimator.lua").read_text(encoding="utf-8")
        self.assertIn("MAX_CANDIDATES = 3", model)
        self.assertIn("MAX_DEFENSIVES = 4", model)
        self.assertIn("ShouldCommit", board)
        self.assertIn("POSITION_HOLD_TIME", animator)
        self.assertIn("defenseDetached", layout)
        self.assertIn("layoutDefenseDetached", layout)

    def test_advisory_items_can_explain_missing_binding_without_dispatch_mutation(self) -> None:
        planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn("动作条未找到现实绑定", planner)
        self.assertIn("unbound = binding == nil", planner)
        self.assertIn("unbound = binding == nil", advisors)
        self.assertNotIn("SignalEncoder:Encode", planner)
        self.assertNotIn("SignalEncoder:Encode", advisors)


if __name__ == "__main__":
    unittest.main()
