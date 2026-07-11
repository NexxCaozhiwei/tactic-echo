from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
STATE = ADDON / "Tactics" / "IconState.lua"
TRACKER = ADDON / "Tactics" / "CooldownTracker.lua"


class P58HudCooldownContinuityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.icon = ICON.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.tracker = TRACKER.read_text(encoding="utf-8")

    def test_confirmed_own_cd_survives_shared_gcd_actionbar_overlay(self) -> None:
        for marker in (
            "local knownOwnCooldown = state.cooldownKnown == true",
            "displayActionLongOwn == true",
            "displayActionOnGCD == true and knownOwnCooldown ~= true",
            "generic action-bar `isOnGCD=true` observation must never erase",
        ):
            self.assertIn(marker, self.state)

    def test_hud_custom_label_bridges_one_snapshot_numeric_blackout(self) -> None:
        for marker in (
            "local function cooldownLabelIdentity(item)",
            "local function cachedCooldownText(card, item, ownCooldown)",
            "card.hudCooldownLabelCache",
            '"continuity_cache"',
            '"snapshot_anchor"',
            "never extend an existing remaining-only anchor",
            "never reads a DurationObject",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("local label, labelSource = cachedCooldownText(card, item, true)", self.icon)

    def test_tracker_accepts_only_observed_safe_numeric_snapshots(self) -> None:
        self.assertIn("function Tracker:ObserveCooldown(spellID, meta, snapshot)", self.tracker)
        self.assertIn("already-sanitized numeric cooldown from IconState", self.tracker)
        self.assertIn('source = "actionbar_numeric_observed"', self.state)
        self.assertIn("static tooltip/base durations", self.tracker)


if __name__ == "__main__":
    unittest.main()
