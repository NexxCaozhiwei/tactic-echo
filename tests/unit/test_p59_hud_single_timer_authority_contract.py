from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
STATE = ADDON / "Tactics" / "IconState.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class P59HudSingleTimerAuthorityContractTests(unittest.TestCase):
    """1.0.36: one live renderer decision per card, using the 1.0.31 field path."""

    def setUp(self) -> None:
        self.state = STATE.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")

    def test_renderer_resolves_one_client_timer_while_native_digits_remain_hidden(self) -> None:
        start = self.icon.index("local function showDurationObjectCooldown")
        end = self.icon.index("local function cooldownPresentationSignature", start)
        block = self.icon[start:end]
        self.assertIn("local duration, durationSource", block)
        self.assertIn("frame:SetCooldownFromDurationObject(duration, true)", block)
        self.assertIn("setNativeCountdownNumbers(frame, false)", block)
        self.assertIn("return true, renderMode, false", block)
        self.assertNotIn("runtimeDurationObject", block)
        self.assertNotIn("showSnapshotDurationObject", block)

    def test_primary_window_and_item_cards_still_suppress_shared_gcd(self) -> None:
        for marker in (
            "local function suppressSharedGcdPresentation",
            "local function sharedGcdOnlyForPresentation",
            "shared_gcd_suppressed",
            "suppressItemGcdLayer",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("item.cooldownGcdAlias", self.icon)
        self.assertIn("item.cooldownGcdAlias = state.cooldownGcdAlias == true", self.state)

    def test_signature_cache_does_not_reintroduce_the_snapshot_sidecar(self) -> None:
        self.assertIn("if card.cooldownPresentationSignature == signature then", self.icon)
        self.assertIn("card.cooldownPresentationSignature = signature", self.icon)
        for forbidden in ("BuildCooldownPresentation", "HudCooldownDurationObjects", "durationObjectKey"):
            self.assertNotIn(forbidden, self.icon)
            self.assertNotIn(forbidden, self.state)


if __name__ == "__main__":
    unittest.main()
