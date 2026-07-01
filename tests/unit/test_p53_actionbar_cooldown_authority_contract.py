from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
RESOLVER = ADDON / "Tactics" / "CooldownResolver.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class P53ActionbarCooldownAuthorityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.resolver = RESOLVER.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")

    def test_actionbar_duration_object_is_first_authority_for_direct_skill_cards(self) -> None:
        for marker in (
            "local preferNativeActionbar = actionSlot ~= nil and item and item.directActionSlot == true",
            "Direct action-bar cards use Blizzard's own DurationObject as the first",
            "showDurationObjectCooldown(",
            "duration_object_actionbar",
            "GetActionCooldownDuration",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("actionSlotTrusted", self.resolver)
        self.assertIn('return duration, "actionbar_duration"', self.resolver)

    def test_native_duration_object_digits_replace_custom_badge_for_all_supported_sources(self) -> None:
        for marker in (
            "local useNativeNumbers = showNumbers == true",
            'durationSource == "actionbar_duration"',
            'durationSource == "item_duration"',
            '"duration_object_spell"',
            "setNativeCountdownNumbers(frame, useNativeNumbers)",
            "card.nativeCountdownVisible = nativeNumbersVisible == true",
            "or card.nativeCountdownVisible == true then",
            "custom badge empty prevents a second, potentially",
        ):
            self.assertIn(marker, self.icon)

    def test_direct_actionbar_numeric_fallback_is_blocked_when_native_state_says_ready(self) -> None:
        for marker in (
            "if nativeSpell ~= true and spellKnown == true and spellMode ~= \"ready\" then",
            "only",
            "explicitly reports ready",
            "last-resort visual fallback",
        ):
            self.assertIn(marker, self.icon)


if __name__ == "__main__":
    unittest.main()
