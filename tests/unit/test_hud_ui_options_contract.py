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
            'hud.scale',
            'hud.alpha',
            'hud.burstGrowth',
            'hud.showKeyLabels',
            'hud.showStatusText',
            'hud.queueMode',
        ):
            self.assertIn(token, control)
        for token in ('TacticalHudModel.Build', 'TacticalHudLayout:Apply', 'TacticalIconButton.Apply', 'TacticalHudDragHandle'):
            self.assertIn(token, board)
        self.assertNotIn('board.title:SetText("战术回响")', board)

    def test_hud_restores_per_module_label_style_editors(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        self.assertIn('local function buildTextStyleSection', control)
        self.assertIn('local function buildHudLabelStyles', control)
        self.assertIn('local function createColorChoice', control)
        self.assertLess(
            control.index('local function createColorChoice'),
            control.index('local function buildTextStyleSection'),
        )
        self.assertIn('mainStyle.keyLabel', control)
        self.assertIn('mainStyle.chargeLabel', control)
        self.assertIn('mainStyle.cooldownText', control)
        self.assertIn('mainStyle.stateText', control)
        self.assertIn('burstStyle.keyLabel', control)
        self.assertIn('burstStyle.chargeLabel', control)
        self.assertIn('burstStyle.cooldownText', control)
        self.assertIn('burstStyle.stateText', control)
        for token in ('颜色', '横向偏移', '纵向偏移'):
            self.assertIn(token, control)

    def test_retired_interrupt_control_and_defense_pages_cannot_be_reenabled(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        advisor = ADVISOR.read_text(encoding="utf-8")
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        for retired in ("打断设置", "控制设置", "防御设置"):
            self.assertNotIn(retired, control)
        refresh = advisor.split("function TacticalAdvisors:Refresh(force)", 1)[1].split("function TacticalAdvisors:GetSnapshot()", 1)[0]
        self.assertIn('emptyAdvisory("scope_primary_burst")', refresh)
        self.assertIn('reaction = emptyReaction("retired_scope")', refresh)
        self.assertNotIn("Tactics/ProtocolMonitor.lua", toc)
        self.assertNotIn("Tactics/AdvisoryPlanner.lua", toc)


if __name__ == "__main__":
    unittest.main()
