from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
STYLES = ADDON / "UI" / "TacticalHudStyles.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class PrimaryRuntimeStatePresentationContractTests(unittest.TestCase):
    def test_primary_pause_remains_colored_and_unmasked(self) -> None:
        styles = STYLES.read_text(encoding="utf-8")
        icon = ICON.read_text(encoding="utf-8")
        self.assertIn('if kind == "primary" then', styles)
        self.assertIn('"paused", 1.00, "none", "暂停", false', styles)
        self.assertIn('"standby", 1.00, "none", "待命", false', styles)
        self.assertIn('card.icon:SetDesaturated(visual.desaturate == true)', icon)
        self.assertIn('Only explicit hard states chosen by TacticalHudStyles', icon)
        self.assertNotIn('availabilityDesaturate', icon)

    def test_primary_cast_and_channel_labels_are_concise(self) -> None:
        styles = STYLES.read_text(encoding="utf-8")
        casting = styles.index('if item.castingThisSpell == true then')
        pause = styles.index('if runtimeState == "paused" or item.paused == true then')
        self.assertLess(casting, pause)
        self.assertIn('return "casting", "正在施放该技能"', styles)
        self.assertIn('"casting", 1.00, "施法"', styles)
        self.assertIn('"channeling_lock", 0.94, "引导"', styles)
        self.assertNotIn('"channeling_lock", 0.94, "引导锁"', styles)

    def test_change_remains_hud_only(self) -> None:
        styles = STYLES.read_text(encoding="utf-8")
        self.assertIn('without changing any TEAP or dispatch state', styles)
        self.assertNotIn('SetBinding(', styles)
        self.assertNotIn('SendInput', styles)


if __name__ == "__main__":
    unittest.main()
