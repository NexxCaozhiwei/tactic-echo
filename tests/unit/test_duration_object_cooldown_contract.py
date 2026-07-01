from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class DurationObjectCooldownContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.state = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        self.model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        self.styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")

    def test_protected_cooldown_does_not_call_setcooldown_with_api_secret_fields(self) -> None:
        self.assertIn("SetCooldownFromDurationObject", self.icon)
        self.assertNotIn("SetCooldown(info.startTime", self.icon)
        self.assertNotIn("SetCooldown(startTime, duration, modRate)", self.icon)

    def test_native_duration_objects_show_their_own_countdown_digits_except_gcd(self) -> None:
        self.assertIn("setNativeCountdownNumbers(frame, false)", self.icon)
        self.assertIn("local useNativeNumbers = showNumbers == true", self.icon)
        self.assertIn('duration_object_item', self.icon)
        self.assertIn('duration_object_spell', self.icon)
        self.assertIn("card.nativeCountdownVisible = nativeNumbersVisible == true", self.icon)
        self.assertIn("showDurationObjectCooldown(card.gcdCooldown, { spellID = 61304 }, gcdEnabled, false, false)", self.icon)
        self.assertIn("TacticalIconButton.badge", self.icon)

    def test_model_carries_public_activity_booleans_but_no_raw_secret_fields(self) -> None:
        for marker in ("cooldownActive", "cooldownOnGCD", "gcdActive"):
            self.assertIn(marker, self.state)
            self.assertIn(marker, self.model)
        self.assertNotIn("cooldownDurationObject", self.model)

    def test_actual_spell_cooldown_gets_display_state_not_api_error_text(self) -> None:
        self.assertIn('return "cooldown", "技能冷却中；图标转盘由客户端渲染，CD 标签由 HUD 统一绘制"', self.styles)
        self.assertNotIn("冷却 API 未返回可解释数值", self.icon)

    def test_cooldown_frames_are_explicitly_above_icon_artwork(self) -> None:
        for marker in (
            "card.cooldownContainer:SetFrameLevel(card:GetFrameLevel() + 1)",
            "card.gcdCooldown:SetFrameLevel(card.cooldownContainer:GetFrameLevel() + 1)",
            "card.cooldown:SetFrameLevel(card.cooldownContainer:GetFrameLevel() + 2)",
        ):
            self.assertIn(marker, self.icon)


if __name__ == "__main__":
    unittest.main()
