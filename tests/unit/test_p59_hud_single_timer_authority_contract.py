from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
STATE = ADDON / "Tactics" / "IconState.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
BOARD = ADDON / "UI" / "TacticalBoard.lua"
SIGNAL = ADDON / "Signal" / "SignalFrame.lua"


class P59HudSingleTimerAuthorityContractTests(unittest.TestCase):
    """1.0.36: one live renderer decision per card, using the 1.0.31 field path."""

    def setUp(self) -> None:
        self.state = STATE.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")
        self.board = BOARD.read_text(encoding="utf-8")
        self.signal = SIGNAL.read_text(encoding="utf-8")

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

    def test_primary_window_shared_gcd_is_unlabeled_swipe_not_own_cooldown(self) -> None:
        for marker in (
            "local function suppressSharedGcdPresentation",
            "local function sharedGcdOnlyForPresentation",
            "shared_gcd_suppressed",
            "suppressItemGcdLayer",
            "Pure GCD is intentionally unlabeled; its swipe is still visible.",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("item.cooldownGcdAlias", self.icon)
        self.assertIn("item.cooldownGcdAlias = state.cooldownGcdAlias == true", self.state)

    def test_pressed_feedback_uses_native_down_atlas_and_scale_pop(self) -> None:
        for marker in (
            '"UI-HUD-ActionBar-IconFrame-Down"',
            "card.pressAnim = card:CreateAnimationGroup()",
            'card.pressAnim:CreateAnimation("Scale")',
            "pressDown:SetDuration(0.07)",
            "pressUp:SetDuration(0.12)",
            "pressDown:SetScaleTo(0.85, 0.85)",
            "applyPressedFrame(card, true)",
            "restorePressedFrame(self)",
            "function TacticalIconButton:PlayCastFeedback(card)",
        ):
            self.assertIn(marker, self.icon)
        mouse_down = self.icon[self.icon.index('card:SetScript("OnMouseDown"'):self.icon.index('card:SetScript("OnMouseUp"')]
        self.assertNotIn("pressAnim:Play()", mouse_down)
        for marker in (
            "function TacticalBoard:PlayCastFeedbackForSpell(spellID)",
            "spellMatchesCard(castSpellID, card.item)",
            "TacticalIconButton.PlayCastFeedback",
        ):
            self.assertIn(marker, self.board)
        self.assertIn("UNIT_SPELLCAST_SUCCEEDED", self.signal)
        self.assertIn("TE.TacticalBoard.PlayCastFeedbackForSpell", self.signal)

    def test_signature_cache_does_not_reintroduce_the_snapshot_sidecar(self) -> None:
        self.assertIn("if card.cooldownPresentationSignature == signature then", self.icon)
        self.assertIn("card.cooldownPresentationSignature = signature", self.icon)
        for forbidden in ("BuildCooldownPresentation", "HudCooldownDurationObjects", "durationObjectKey"):
            self.assertNotIn(forbidden, self.icon)
            self.assertNotIn(forbidden, self.state)


if __name__ == "__main__":
    unittest.main()
