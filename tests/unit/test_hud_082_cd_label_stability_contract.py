from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class Hud082CooldownLabelStabilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")
        self.board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.layout = (ADDON / "UI" / "TacticalHudLayout.lua").read_text(encoding="utf-8")
        self.animator = (ADDON / "UI" / "TacticalHudAnimator.lua").read_text(encoding="utf-8")

    def test_hud_never_uses_generic_cd_placeholder_text(self) -> None:
        self.assertNotIn('card.badge:SetText("CD")', self.icon)
        self.assertNotIn('label = "CD"', self.styles)
        self.assertIn('local function cachedCooldownText(card, item, ownCooldown)', self.icon)
        self.assertIn('card.badge:SetText(label)', self.icon)
        self.assertIn('SetCooldownFromDurationObject', self.icon)

    def test_unchanged_urgent_primary_does_not_reapply(self) -> None:
        same = self.animator.index('if slot.fingerprint == fingerprint then')
        urgent = self.animator.index('if urgent == true then')
        self.assertLess(same, urgent)
        self.assertIn('restarts its presentation and caused', self.animator)

    def test_board_uses_snapshot_subscription_without_a_second_poll_loop(self) -> None:
        self.assertIn('TE.TacticalAdvisors:Subscribe(function(snapshot)', self.board)
        self.assertIn('TacticalIconButton.RefreshDynamic', self.board)
        self.assertIn('no second Board OnUpdate polling loop is needed', self.board)
        self.assertNotIn('local DYNAMIC_REFRESH_INTERVAL', self.board)
        self.assertNotIn('function TacticalBoard:RefreshDynamic()', self.board)
        self.assertNotIn('TacticalBoard:Render(TE.TacticalAdvisors:Refresh(false))', self.board)

    def test_layout_does_not_reanchor_identical_snapshots(self) -> None:
        self.assertIn('local function layoutFingerprint(nodes, hud)', self.layout)
        self.assertIn('if board.tacticEchoLayoutFingerprint == fingerprint then return false end', self.layout)
        self.assertIn('board.tacticEchoLayoutFingerprint = fingerprint', self.layout)

    def test_native_cooldown_setup_is_cached_per_presentation_signature(self) -> None:
        self.assertIn('local function cooldownPresentationSignature', self.icon)
        self.assertIn('if card.cooldownPresentationSignature == signature then', self.icon)
        self.assertIn('card.cooldownPresentationSignature = signature', self.icon)


if __name__ == "__main__":
    unittest.main()
