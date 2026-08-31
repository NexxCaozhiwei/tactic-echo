from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class AutoBurstHotkeyStatusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.defaults = (ADDON / "Config" / "Defaults.lua").read_text(encoding="utf-8")
        self.normalize = (ADDON / "Config" / "Normalize.lua").read_text(encoding="utf-8")
        self.panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")

    def test_auto_burst_hotkey_is_persisted_and_normalized_independently(self) -> None:
        self.assertIn('autoBurstToggleHotkey = ""', self.defaults)
        self.assertIn("settings.autoBurstToggleHotkey = type(settings.autoBurstToggleHotkey) == \"string\"", self.normalize)
        self.assertIn("and settings.autoBurstToggleHotkey or defaults.autoBurstToggleHotkey", self.normalize)

    def test_general_page_places_auto_burst_hotkey_below_main_toggle_hotkey(self) -> None:
        main = self.panel.index('createReadout(pane, "generalHotkey"')
        burst = self.panel.index('createReadout(pane, "generalAutoBurstHotkey"')
        self.assertLess(main, burst)
        for marker in (
            '"TacticEchoAutoBurstToggleHotkeyButton"',
            "ControlPanel:BeginAutoBurstHotkeyCapture()",
            "ControlPanel:SetAutoBurstHotkey(pendingAutoBurstHotkey or autoBurstHotkeyBox:GetText())",
            "ControlPanel:ApplyStoredAutoBurstHotkey()",
            "pendingAutoBurstApplyAfterCombat",
        ):
            self.assertIn(marker, self.panel)

    def test_hotkey_only_toggles_auto_burst_setting(self) -> None:
        start = self.panel.index("function ControlPanel:ToggleAutoBurst(source)")
        end = self.panel.index("function ControlPanel:SetToggleHotkey", start)
        narrowed = self.panel[start:end]
        self.assertIn("tactics.autoInjectionEnabled = tactics.autoInjectionEnabled ~= true", narrowed)
        self.assertIn("tactics.autoBurstEnabled = tactics.autoInjectionEnabled", narrowed)
        for forbidden in (
            "SignalFrame:SetState",
            "SignalEncoder",
            "bindingToken",
            "SetBinding(",
            "SaveBindings(",
        ):
            self.assertNotIn(forbidden, narrowed)
        self.assertIn('if state == "armed" then self:PauseDynamic() else self:StartDynamic() end', self.panel)

    def test_dispatchable_hud_line_uses_lcc_or_had_without_changing_icon_label(self) -> None:
        self.assertIn("tactics.autoInjectionEnabled", self.board)
        self.assertIn('dispatchable = autoInjectionEnabled == true and "HAD" or "LCC"', self.board)
        self.assertIn('if visual == "dispatchable" then', self.styles)
        self.assertNotIn('label = "HAD"', self.styles)


if __name__ == "__main__":
    unittest.main()
