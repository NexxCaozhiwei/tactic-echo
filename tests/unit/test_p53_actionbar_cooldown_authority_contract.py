from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
RESOLVER = ADDON / "Tactics" / "CooldownResolver.lua"
STATE = ADDON / "Tactics" / "IconState.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"


class P53ActionbarCooldownAuthorityContractTests(unittest.TestCase):
    """1.0.36: restore the known-good 1.0.31 live renderer without planner effects."""

    def setUp(self) -> None:
        self.resolver = RESOLVER.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")

    def test_direct_actionbar_authority_is_collected_before_and_used_by_renderer(self) -> None:
        for marker in (
            "local function actionBarPublicCooldown(actionSlot, trusted)",
            "numericOwnCooldown",
            'state.cooldownSource = "actionbar_numeric"',
        ):
            self.assertIn(marker, self.state)
        self.assertIn("actionSlotTrusted", self.resolver)
        self.assertIn('return duration, "actionbar_duration"', self.resolver)
        for marker in (
            "local function publicCooldownActivity",
            "C_ActionBar.GetActionCooldown",
            "C_ActionBar.GetActionCooldownDuration",
            "local function showDurationObjectCooldown",
        ):
            self.assertIn(marker, self.icon)

    def test_native_duration_never_owns_digits_while_custom_badge_is_universal(self) -> None:
        for marker in (
            'local function cooldownTextMode(_)',
            'return "custom"',
            "pcall(frame.SetHideCountdownNumbers, frame, true)",
            "card.nativeCountdownVisible = false",
            "card.nativeCountdownFallback = false",
            "setNativeCountdownNumbers(card.cooldown, false)",
        ):
            self.assertIn(marker, self.icon)
        self.assertNotIn("nativeNumericFallback", self.icon)

    def test_model_carries_only_scalar_cooldown_state(self) -> None:
        self.assertNotIn("cooldownPresentation", self.model)
        self.assertIn('"cooldownRemaining"', self.model)
        self.assertNotIn("BuildCooldownPresentation", self.state)


if __name__ == "__main__":
    unittest.main()
