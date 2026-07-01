from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class HudSecretValueContractTests(unittest.TestCase):
    def test_board_fingerprint_does_not_concatenate_raw_charges(self) -> None:
        text = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.assertIn("safeFingerprintText", text)
        self.assertIn("Cooldown/charge values intentionally do not participate", text)
        self.assertNotIn('tostring(item.charges or "")', text)
        self.assertNotIn('tostring(item.maxCharges or "")', text)

    def test_hud_model_scrubs_dynamic_api_fields_before_fingerprints(self) -> None:
        text = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        for marker in ("NUMERIC_FIELDS", "plainNumber", "sanitize", "signature(model.primary)"):
            self.assertIn(marker, text)
        self.assertNotIn('tostring(item.spellID or 0)', text)

    def test_icon_state_rejects_secret_numbers_instead_of_forwarding_them(self) -> None:
        text = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        self.assertIn("local probe = number + 0", text)
        self.assertIn("probe < -math.huge", text)
        self.assertIn("冷却数值受保护，已跳过比较", text)
        self.assertNotIn('current = numeric(current) or 0', text)

    def test_icon_component_does_not_use_format_as_a_secret_number_converter(self) -> None:
        text = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.assertIn("local function safeText", text)
        self.assertNotIn('string.format("%.6f", value)', text)
        self.assertIn("Force a plain arithmetic/comparison probe", text)

    def test_board_has_top_level_render_fail_soft(self) -> None:
        text = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.assertIn("local function renderSafeFallback", text)
        self.assertIn("pcall(renderInternal, self, snapshot)", text)
        self.assertIn("HUD 安全模式", text)


if __name__ == "__main__":
    unittest.main()
