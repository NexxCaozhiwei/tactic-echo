from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
CONTROL = ADDON / "UI" / "ControlPanel.lua"
BOARD = ADDON / "UI" / "TacticalBoard.lua"
ADVISOR = ADDON / "Tactics" / "TacticalAdvisors.lua"
PLANNER = ADDON / "Tactics" / "AdvisoryPlanner.lua"
HEALTH = ADDON / "Tactics" / "HealthCompatibility.lua"


class HudUiOptionsContractTests(unittest.TestCase):
    def test_settings_pages_are_scrollable_and_compact_is_minimal(self) -> None:
        text = CONTROL.read_text(encoding="utf-8")
        self.assertIn('CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")', text)
        self.assertIn('pane:SetSize(672, 1320)', text)
        self.assertIn('COMPACT_WIDTH = 280', text)
        self.assertIn('COMPACT_HEIGHT = 38', text)
        self.assertIn('labels.compactRunState', text)
        self.assertNotIn('labels.compactRecommendation', text)
        self.assertNotIn('createActionButton(compactView, "重扫动作条"', text)

    def test_hud_backdrop_key_label_and_queue_layout_are_configurable(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        board = BOARD.read_text(encoding="utf-8")
        for token in (
            'hud.backdropAlpha',
            'hud.keyLabel.fontSize',
            'hud.keyLabel.point',
            'hud.layoutPreset',
            'hud.primaryGrowth',
            'hud.tacticalGrowth',
            'hud.defenseDetached',
        ):
            self.assertIn(token, control)
        for token in ('TacticalHudModel.Build', 'TacticalHudLayout:Apply', 'TacticalIconButton.Apply', 'TacticalHudDragHandle'):
            self.assertIn(token, board)
        self.assertNotIn('board.title:SetText("战术回响")', board)

    def test_interrupt_control_and_defensive_display_modes_are_configured(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        advisor = ADVISOR.read_text(encoding="utf-8")
        planner = PLANNER.read_text(encoding="utf-8")
        self.assertIn('interruptDisplayMode', control)
        self.assertIn('interruptDisplayMode', advisor)
        self.assertIn('defensiveDisplayMode', control)
        self.assertIn('defensiveDisplayMode', advisor)
        self.assertIn('controlDisplayMode', control)
        self.assertIn('controlDisplayMode', planner)
        self.assertIn('defensiveDisplayHealthPercent', planner)
        self.assertIn('defensiveHighlightHealthPercent', planner)
        self.assertIn('always_visible', planner)
        self.assertIn('playerHealthPercent', (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8"))
        self.assertIn('percent = tonumber', HEALTH.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
