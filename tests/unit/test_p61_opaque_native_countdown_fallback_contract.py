from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
TRACKER = ADDON / "Tactics" / "CooldownTracker.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"


class P61UnifiedHudCountdownContractTests(unittest.TestCase):
    """1.0.38: DurationObject is swipe-only; HUD owns every visible digit."""

    def setUp(self) -> None:
        self.icon = ICON.read_text(encoding="utf-8")
        self.tracker = TRACKER.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")

    def test_native_duration_countdown_is_strictly_hidden(self) -> None:
        self.assertIn("pcall(frame.SetHideCountdownNumbers, frame, true)", self.icon)
        self.assertIn("card.nativeCountdownVisible = false", self.icon)
        self.assertIn("card.nativeCountdownFallback = false", self.icon)
        self.assertNotIn("local nativeNumericFallback", self.icon)
        self.assertNotIn("已临时使用同一原生 CD 对象倒计时", self.icon)

    def test_hud_digits_use_one_plain_seconds_formatter(self) -> None:
        self.assertIn("return tostring(math.max(1, math.ceil(remaining)))", self.icon)
        self.assertIn("HUD 暂无安全数值；原生 DurationObject 仅用于转盘渲染", self.icon)
        self.assertIn("DurationObject now renders only the swipe, never the digits", self.icon)

    def test_current_spec_defense_and_burst_skills_are_primed(self) -> None:
        for marker in (
            "function Tracker:PrimeCurrentSpec()",
            "TE.AbilityProfiles.GetDefensivePriorityList",
            "TE.BurstProfiles.Get",
            "allowStaticFallback = true",
            "migrateEntryToKey",
            '"PLAYER_LOGIN"',
            "primeAndRefreshOutOfCombat",
        ):
            self.assertIn(marker, self.tracker)
        self.assertIn("direct_actionbar_static_forbidden", self.tracker)

    def test_generic_actionbar_duration_requires_own_cd_certificate(self) -> None:
        for marker in (
            "local genericActionbarNumericCertified = item.cooldownActionBarNumericOwnEvidence == true",
            "local allowGenericActionbarDuration = genericActionbarNumericCertified == true",
            "local canUseActionSlot = actionSlot and genericActionbarNumericCertified == true",
        ):
            self.assertIn(marker, self.icon)

    def test_mapped_override_and_actionbar_evidence_refresh_the_signature(self) -> None:
        self.assertIn('"matchedSpellID"', self.model)
        self.assertIn("styleMarker(item.matchedSpellID)", self.icon)
        self.assertIn("styleMarker(item.cooldownActionBarNumericOwnEvidence)", self.icon)


if __name__ == "__main__":
    unittest.main()
