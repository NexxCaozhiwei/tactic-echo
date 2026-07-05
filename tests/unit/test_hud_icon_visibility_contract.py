from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class HudIconVisibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")

    def test_icon_surface_has_an_explicit_question_mark_fallback(self) -> None:
        self.assertIn('local QUESTION_ICON = "Interface\\\\Icons\\\\INV_Misc_QuestionMark"', self.text)
        self.assertIn("card.icon:SetTexture(QUESTION_ICON)", self.text)
        self.assertIn("pcall(card.icon.SetTexture, card.icon, QUESTION_ICON)", self.text)
        self.assertIn("card.icon:Show()", self.text)

    def test_visibility_uses_bounded_alpha_and_optional_presentation_fade(self) -> None:
        self.assertIn("local function setVisible(card, visible, alpha)", self.text)
        self.assertIn("local targetAlpha = clamp(alpha, 0.05, 1.00)", self.text)
        self.assertIn("card.fadeAlpha:SetDuration(0.10)", self.text)
        self.assertIn("hideFrameSafely(card)", self.text)
        self.assertIn("showFrameSafely(card, targetAlpha)", self.text)

    def test_visibility_avoids_protected_show_hide_during_combat(self) -> None:
        self.assertIn("local function hideFrameSafely(frame)", self.text)
        self.assertIn("if inCombatLockdown() then", self.text)
        self.assertIn("frame.tacticEchoCombatHidden = true", self.text)
        self.assertIn("if inCombatLockdown() and frame.IsShown and not frame:IsShown() then return end", self.text)

    def test_native_mask_is_optional_and_failure_tolerant(self) -> None:
        self.assertIn("local function createRoundedActionIconMask", self.text)
        self.assertIn("CreateMaskTexture", self.text)
        self.assertIn('"UI-HUD-ActionBar-IconFrame-Mask"', self.text)
        self.assertIn("card.roundMaskEnabled = card.roundMask ~= nil", self.text)
        self.assertIn("appearance.roundedIcons", self.text)

    def test_component_remains_display_only(self) -> None:
        for forbidden in (
            "RecommendationAdapter:ReadOfficial",
            "SignalEncoder:Encode",
            "SetBinding(",
            "RegisterEvent(",
        ):
            self.assertNotIn(forbidden, self.text)


if __name__ == "__main__":
    unittest.main()
