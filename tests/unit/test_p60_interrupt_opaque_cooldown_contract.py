from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
STATE = ADDON / "Tactics" / "IconState.lua"
TRACKER = ADDON / "Tactics" / "CooldownTracker.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class P60InterruptOpaqueCooldownContractTests(unittest.TestCase):
    """1.0.36 rolls back the non-working opaque-timer sidecar, not interrupt semantics."""

    def setUp(self) -> None:
        self.state = STATE.read_text(encoding="utf-8")
        self.tracker = TRACKER.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")

    def test_interrupt_cards_use_the_same_live_spell_renderer_as_other_spells(self) -> None:
        self.assertIn("local function showDurationObjectCooldown", self.icon)
        self.assertIn("C_Spell.GetSpellCooldownDuration, durationSpellID, true", self.icon)
        self.assertIn("cooldownHint = item.usableState == \"cooldown\" or item.cooldownActive == true", self.icon)
        self.assertNotIn("BuildCooldownPresentation", self.state)
        self.assertNotIn("HudCooldownDurationObjects", self.state)

    def test_tracker_remains_event_driven_and_never_invents_direct_actionbar_static_seconds(self) -> None:
        for marker in (
            "function Tracker:RecordCast(spellID)",
            "function Tracker:ConfirmEntry(entry)",
            "direct_actionbar_static_forbidden",
            "SPELL_UPDATE_COOLDOWN",
        ):
            self.assertIn(marker, self.tracker)
        self.assertNotIn("entryLiveActionbarCooldown", self.tracker)


if __name__ == "__main__":
    unittest.main()
