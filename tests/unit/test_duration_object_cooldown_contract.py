from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
STATE = ADDON / "Tactics" / "IconState.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"
STYLES = ADDON / "UI" / "TacticalHudStyles.lua"


class DurationObjectCooldownContractTests(unittest.TestCase):
    """1.0.36 restores the field-proven 1.0.31 real-time HUD renderer."""

    def setUp(self) -> None:
        self.icon = ICON.read_text(encoding="utf-8")
        self.state = STATE.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")
        self.styles = STYLES.read_text(encoding="utf-8")

    def test_renderer_uses_the_field_proven_live_duration_path(self) -> None:
        for marker in (
            "local function publicCooldownActivity",
            "local function showDurationObjectCooldown",
            "C_ActionBar.GetActionCooldown",
            "C_ActionBar.GetActionCooldownDuration",
            "C_Spell.GetSpellCooldown",
            "C_Spell.GetSpellCooldownDuration",
            "TE.CooldownResolver.GetDurationObject",
            "frame:SetCooldownFromDurationObject(duration, true)",
        ):
            self.assertIn(marker, self.icon)

    def test_removed_snapshot_sidecar_is_not_part_of_hud_data_flow(self) -> None:
        for forbidden in (
            "BuildCooldownPresentation",
            "HudCooldownDurationObjects",
            "durationObjectKey",
            "sanitizeCooldownPresentation",
            "runtimeDurationObject",
            "showSnapshotDurationObject",
        ):
            self.assertNotIn(forbidden, self.state)
            self.assertNotIn(forbidden, self.model)
            self.assertNotIn(forbidden, self.icon)

    def test_hud_digits_are_strictly_badge_owned_while_duration_object_stays_swipe_only(self) -> None:
        for marker in (
            'local function cooldownTextMode(_)',
            'return "custom"',
            "pcall(frame.SetHideCountdownNumbers, frame, true)",
            "card.nativeCountdownVisible = false",
            "card.nativeCountdownFallback = false",
            "return tostring(math.max(1, math.ceil(remaining)))",
            "TacticalIconButton.badge",
        ):
            self.assertIn(marker, self.icon)
        self.assertNotIn("nativeNumericFallback", self.icon)

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
