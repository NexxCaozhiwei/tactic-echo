from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class SettingsCenterContractTests(unittest.TestCase):
    def test_settings_center_has_expected_navigation(self) -> None:
        text = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        for token in (
            'label = "常规"',
            'label = "HUD"',
            'label = "自动注入"',
            'label = "配置文件"',
            'local NAV_ORDER = { "general", "hud", "burst", "profiles" }',
            'TacticEchoSettingsCenter',
        ):
            self.assertIn(token, text)
        for retired in ('label = "主键"', 'label = "打断与控制"', 'label = "防御与生存"', 'label = "监控与调试"'):
            self.assertNotIn(retired, text)

    def test_tactical_commands_open_real_panels(self) -> None:
        text = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        diagnostics = (ADDON / "UI" / "Diagnostics.lua").read_text(encoding="utf-8")
        self.assertIn('SLASH_TACTICECHOUI1 = "/teui"', text)
        self.assertIn('ControlPanel:Show("hud")', text)
        self.assertIn('SLASH_TACTICECHOTACTICS1 = "/tetactics"', diagnostics)
        self.assertIn('TE.ControlPanel:Show("hud")', diagnostics)

    def test_secret_numeric_helpers_are_not_used_in_tactical_display(self) -> None:
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        monitor = (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8")
        signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        for forbidden in ("UnitHealth(", "UnitHealthMax(", "UnitCastingInfo(", "GetSpellCooldown("):
            self.assertNotIn(forbidden, advisors)
        self.assertNotIn("UnitHealth(", monitor)
        self.assertNotIn("UnitHealthMax(", monitor)
        self.assertIn("packReturns(UnitCastingInfo(\"target\"))", monitor)
        self.assertNotIn("remainingMs = math", signal)
        self.assertNotIn("endTimeMS) -", signal)

    def test_monitor_flags_remain_telemetry_only(self) -> None:
        monitor = (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8")
        encoder = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")
        self.assertIn("flags = flags + 4", monitor)
        self.assertIn("flags = flags + 8", monitor)
        self.assertIn("v3 bit 4", monitor)
        self.assertIn("monitorFlags", encoder)
        self.assertIn("fields = {", encoder)
        self.assertIn("self.commitByte", encoder)

    def test_settings_center_does_not_use_blizzard_settings_panel(self) -> None:
        text = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.assertNotIn("OpenSettingsPanel", text)
        self.assertNotIn("Settings.OpenToCategory", text)

    def test_hud_right_click_routes_to_current_pages_without_burst_subpages(self) -> None:
        panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        button = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        for token in (
            "button.selected = key == activePage",
            "setButtonVisual(button, button.selected)",
            'main = "hud"',
        ):
            self.assertIn(token, panel)
        self.assertNotIn("function ControlPanel:SetBurstSubpage(subpage)", panel)
        self.assertNotIn("burstSubpages = {", panel)
        self.assertIn('if button == "RightButton"', button)
        self.assertIn('TE.ControlPanel:Show(self.settingsPage or "general")', button)
        for token in (
            'nodes.primary.settingsPage = "main"',
            'nodes.tactical.burst) do card.settingsPage = "burst"',
        ):
            self.assertIn(token, board)

    def test_detailed_icon_effect_editor_is_removed(self) -> None:
        panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.assertNotIn("local function buildIconStyleEditor", panel)
        self.assertNotIn('createCheckbox(pane, "启用动态光效"', panel)

if __name__ == "__main__":
    unittest.main()
