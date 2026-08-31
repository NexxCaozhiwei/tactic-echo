from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
ICON = ROOT / "addon" / "!TacticEcho" / "UI" / "TacticalIconButton.lua"


class HudNativeTooltipContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ICON.read_text(encoding="utf-8")
        cls.show_tooltip = cls.source.split("local function showTooltip(card)", 1)[1].split(
            "function TacticalIconButton:Create", 1
        )[0]

    def test_hover_uses_blizzard_spell_and_item_tooltip_providers(self):
        for token in (
            "GameTooltip.SetInventoryItem",
            "GameTooltip.SetItemByID",
            "GameTooltip.SetHyperlink",
            "GameTooltip.SetSpellByID",
        ):
            self.assertIn(token, self.show_tooltip)

    def test_hover_does_not_append_tactic_echo_diagnostics(self):
        self.assertNotIn("tooltipLines(", self.show_tooltip)
        self.assertNotIn("GameTooltip:AddLine", self.show_tooltip)
        self.assertNotIn("自动注入组", self.show_tooltip)


if __name__ == "__main__":
    unittest.main()
