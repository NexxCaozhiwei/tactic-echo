from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TRACKER = ADDON / "Tactics" / "CooldownTracker.lua"
STATE = ADDON / "Tactics" / "IconState.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class P54LayeredCooldownFallbackContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tracker = TRACKER.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")

    def test_tracker_precaches_duration_and_charge_state_out_of_combat(self) -> None:
        for marker in (
            "tooltipCooldownDuration",
            "baseCooldownDuration",
            "cacheFallbackDuration",
            "cacheFromApi(entry)",
            "C_Spell.GetSpellCharges",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_TALENT_UPDATE",
            "TRAIT_CONFIG_UPDATED",
        ):
            self.assertIn(marker, self.tracker)

    def test_cast_starts_local_timer_only_after_authoritative_snapshot_is_unavailable(self) -> None:
        self.assertIn("if not self:ConfirmEntry(entry) then", self.tracker)
        self.assertIn("startFallbackCooldown(entry)", self.tracker)
        self.assertIn("fallback = isFallback == true", self.tracker)
        self.assertIn("API confirmation always replaces the local timer", self.tracker)

    def test_icon_state_projects_tracker_data_only_after_shared_resolver(self) -> None:
        self.assertLess(
            self.state.index("local remaining, duration, start"),
            self.state.index("local trackedCooldown"),
        )
        self.assertIn("state.cooldownFallback = trackedCooldown.fallback == true", self.state)
        self.assertIn("state.chargeCooldownKnown = charges.cooldownKnown == true", self.state)

    def test_renderer_keeps_the_legacy_native_timer_then_numeric_fallback_order(self) -> None:
        native_index = self.icon.index("nativeSpell, spellMode, nativeNumbersVisible = showDurationObjectCooldown(")
        numeric_index = self.icon.index("spellShown = showCooldown(card.cooldown, spellStart, spellDuration")
        self.assertLess(native_index, numeric_index)
        self.assertIn("Direct action-bar DurationObjects remain the authoritative swipe source", self.icon)
        self.assertIn("cooldownPresentationSignature", self.icon)
        self.assertIn("C_Spell.GetSpellCooldownDuration", self.icon)
        self.assertIn("C_ActionBar.GetActionCooldownDuration", self.icon)
        self.assertNotIn("BuildCooldownPresentation", self.state)


if __name__ == "__main__":
    unittest.main()
