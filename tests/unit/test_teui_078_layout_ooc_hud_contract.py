from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class Teui078LayoutOocHudContractTests(unittest.TestCase):
    def test_control_panel_uses_bounded_two_column_grid(self) -> None:
        text = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        for token in (
            "local CONTENT_PANE_WIDTH = 720",
            "local RIGHT_X = 376",
            "local function columnEnd(x)",
            "local function controlWidth(x, desired)",
            "pane:SetSize(CONTENT_PANE_WIDTH, CONTENT_PANE_HEIGHT)",
            "pane:SetVerticalScroll(0)",
        ):
            self.assertIn(token, text)

    def test_hud_exposes_module_visibility_and_size_controls(self) -> None:
        text = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        for token in (
            '"显示主键"', '"显示爆发"', '"显示打断与控制"', '"显示防御与生存"',
            '"主键图标"', '"爆发图标"', '"打断控制图标"', '"防御生存图标"',
            "setModuleIconSize",
        ):
            self.assertIn(token, text)
        board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.assertIn("moduleShown(hud, \"main\")", board)
        self.assertIn("moduleShown(hud, \"defense\")", board)

    def test_out_of_combat_primary_is_display_only(self) -> None:
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")
        for token in (
            "buildOutOfCombatPrimary",
            "out_of_combat_display_observer",
            "bindingToken = 0",
            "displayOnly = true",
        ):
            self.assertIn(token, advisors)
        self.assertIn("local displayOnly = item.displayOnly == true", model)
        self.assertIn("if item.displayOnly == true", styles)

    def test_layout_uses_bounded_common_placement_pass(self) -> None:
        text = (ADDON / "UI" / "TacticalHudLayout.lua").read_text(encoding="utf-8")
        for token in (
            "appendPlacement", "boundsFor", "applyPlacements", "layoutDefenseDetached", "defenseDetached",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
