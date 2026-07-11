from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
TRACKER = ADDON / "Tactics" / "CooldownTracker.lua"
STATE = ADDON / "Tactics" / "IconState.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"


class P57MainWindowGcdAndDirectCooldownContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.icon = ICON.read_text(encoding="utf-8")
        self.tracker = TRACKER.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")

    def test_main_window_hides_pure_shared_gcd_swipe(self) -> None:
        for marker in (
            "local function suppressSharedGcdPresentation",
            'item.kind == "primary"',
            'item.burstRole == "window"',
            "local function sharedGcdOnlyForPresentation",
            "shared_gcd_suppressed",
            "Hide that pure shared-GCD swipe completely",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("presentation-only", self.icon)
        self.assertIn("must never affect AutoBurst, bindings", self.icon)

    def test_renderer_suppresses_item_and_main_window_gcd_layers(self) -> None:
        self.assertIn("local suppressItemGcdLayer = isItemBackedCard(item) or suppressSharedGcd == true", self.icon)
        self.assertIn("local gcdCanRender = gcdEnabled", self.icon)
        self.assertIn("and suppressItemGcdLayer ~= true", self.icon)
        self.assertNotIn("and not globalOnly", self.icon[self.icon.index("local gcdCanRender = gcdEnabled"):self.icon.index("local gcdShown", self.icon.index("local gcdCanRender = gcdEnabled"))])
        self.assertIn("C_Spell.GetSpellCooldownDuration", self.icon)

    def test_direct_actionbar_keeps_hud_badge_digits_with_exact_numeric_truth(self) -> None:
        for marker in (
            "applyDirectActionbarNumericCooldown",
            "numericOwnCooldown",
            'state.cooldownSource = "actionbar_numeric"',
        ):
            self.assertIn(marker, self.state)
        for marker in (
            "local function showDurationObjectCooldown",
            "pcall(frame.SetHideCountdownNumbers, frame, true)",
            "card.nativeCountdownVisible = false",
            "return tostring(math.max(1, math.ceil(remaining)))",
        ):
            self.assertIn(marker, self.icon)

    def test_tracker_does_not_seed_direct_actionbar_timer_from_static_tooltip_or_base_cd(self) -> None:
        start = self.tracker.index("local function cacheFallbackDuration(entry)")
        end = self.tracker.index("for _, spellID in ipairs(entry.ids or {}) do", start)
        block = self.tracker[start:end]
        self.assertIn("if entry.slot and entry.allowStaticFallback ~= true then", block)
        self.assertIn('entry.durationSource = "direct_actionbar_static_forbidden"', block)
        self.assertIn("current-spec tactical", block)
        self.assertIn("talents, hero nodes and override spells", block)

    def test_fallback_provenance_is_sanitized_as_display_only_diagnostic(self) -> None:
        self.assertIn("fallbackOrigin = isFallback == true and entry.durationSource", self.tracker)
        self.assertIn("fallbackOrigin = data.fallbackOrigin", self.tracker)
        self.assertIn("state.cooldownFallbackOrigin = trackedCooldown.fallbackOrigin", self.state)
        self.assertIn("item.cooldownFallbackOrigin = state.cooldownFallbackOrigin", self.state)
        self.assertIn("item.cooldownFallbackOrigin = plainText", self.model)


if __name__ == "__main__":
    unittest.main()
