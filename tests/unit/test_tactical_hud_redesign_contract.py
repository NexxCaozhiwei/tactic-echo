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

    def test_fixed_primary_burst_slots_and_debounce_are_present(self) -> None:
        model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        animator = (ADDON / "UI" / "TacticalHudAnimator.lua").read_text(encoding="utf-8")
        self.assertIn("MAX_BURST_CARDS = 27", model)
        self.assertIn("candidates = {}", model)
        self.assertIn("defense = {}", model)
        self.assertIn("ShouldCommit", board)
        self.assertIn("POSITION_HOLD_TIME", animator)

    def test_burst_cards_explain_missing_binding_without_dispatch_mutation(self) -> None:
        planner = (ADDON / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn("bindingMissing = not (binding and binding.binding)", planner)
        self.assertIn("bindingToken = 0", planner)
        self.assertIn("item.burstDispatchActive = true", advisors)
        self.assertNotIn("SignalEncoder:Encode", planner)
        self.assertNotIn("SignalEncoder:Encode", advisors)


if __name__ == "__main__":
    unittest.main()
