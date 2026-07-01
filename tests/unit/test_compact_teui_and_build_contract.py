from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
CONTROL = ADDON / "UI" / "ControlPanel.lua"
RESOLVER = ADDON / "Actions" / "ActionBarBindingResolver.lua"
TACTICAL_STATE = ADDON / "Tactics" / "TacticalState.lua"
BUILD_SCRIPT = ROOT / "scripts" / "build-tek-exe.ps1"
ONE_CLICK = ROOT / "TEKEXEBUILD.CMD"


class CompactTeuiAndBuildContractTests(unittest.TestCase):
    def test_extra_action_observation_reaches_same_source_ui_snapshot(self) -> None:
        resolver = RESOLVER.read_text(encoding="utf-8")
        tactical = TACTICAL_STATE.read_text(encoding="utf-8")
        control = CONTROL.read_text(encoding="utf-8")

        self.assertIn("cached.specialActionBar = specialActionBar", resolver)
        self.assertIn("specialActionBar=specialActionBar", resolver)
        self.assertIn("specialActionBar = binding.specialActionBar", tactical)
        self.assertIn("额外动作条：已显示（仅观察，不阻断）", control)
        self.assertNotIn("compactSnapshotText", control)

    def test_settings_center_has_persistent_minimized_presentation(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        for token in (
            "COMPACT_WIDTH = 280",
            "COMPACT_HEIGHT = 38",
            "TacticEchoDB.ui.settingsCenter.minimized",
            "function ControlPanel:SetMinimized(minimized)",
            "function ControlPanel:Minimize()",
            "function ControlPanel:Restore()",
            "applyPanelPresentation(store.minimized == true)",
            'createActionButton(normalHeader, "-", 962, -10, 40, function() ControlPanel:Minimize() end)',
            'createActionButton(compactView, "□", 248, -5, 24, function() ControlPanel:Restore() end)',
            'compactToggleButton = createActionButton(compactView, "▶", 220, -5, 24, function() ControlPanel:ToggleRun() end)',
            'function ControlPanel:GetCompactStatus()',
            'function ControlPanel:ResetCompactPosition()',
        ):
            self.assertIn(token, control)

    def test_compact_commands_are_distinct_from_tactical_hud_compact(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        self.assertIn('elseif command == "compact" then\n        ControlPanel:SetCompact(true)', control)
        self.assertIn('elseif command == "min" or command == "minimize" then\n        ControlPanel:Minimize()', control)
        self.assertIn('elseif command == "restore" or command == "expand" then\n        ControlPanel:Restore()', control)

    def test_single_one_click_builder_discovers_python_and_passes_exact_executable(self) -> None:
        self.assertTrue(ONE_CLICK.exists())
        cmd = ONE_CLICK.read_text(encoding="ascii")
        ps1 = BUILD_SCRIPT.read_text(encoding="utf-8")

        for token in (
            "py -3 -c",
            "python -c",
            "64-bit Python 3.11 or newer",
            'build-tek-exe.ps1" -InstallDependencies -PythonExe "%PYTHON_EXE%"',
            "dist\\TEK.exe",
            "setlocal EnableExtensions DisableDelayedExpansion",
            "pause",
        ):
            self.assertIn(token, cmd)
        self.assertIn('[string]$PythonExe = "python"', ps1)
        self.assertIn("Get-Command $PythonExe", ps1)
        self.assertIn("& $PythonExe -m unittest discover -s tek/tests -v", ps1)
        self.assertIn("& $PythonExe @PyInstallerArgs", ps1)
        self.assertIn("isolated staging output", ps1)
        self.assertIn("TEK.new.exe", ps1)

    def test_single_builder_does_not_depend_on_legacy_aliases(self) -> None:
        self.assertFalse((ROOT / "BTE.CMD").exists())
        self.assertFalse((ROOT / "BUILD_TEK_EXE.cmd").exists())
        cmd = ONE_CLICK.read_text(encoding="ascii")
        self.assertNotIn("call \"%~dp0BTE.CMD\"", cmd)
        self.assertNotIn("call \"%~dp0BUILD_TEK_EXE.cmd\"", cmd)


if __name__ == "__main__":
    unittest.main()

class CompactStatusBar091ContractTests(unittest.TestCase):
    def test_compact_status_bar_is_small_chinese_and_snapshot_only(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        for token in (
            'COMPACT_WIDTH = 280',
            'COMPACT_HEIGHT = 38',
            'function ControlPanel:GetCompactStatus()',
            'waiting = "未运行"',
            'armed = "运行中"',
            'paused = "暂停中"',
            'channeling = "引导中"',
            'empowering = "蓄力中"',
            'blocked = "已阻断"',
            'error = "异常"',
            'display_only = "仅显示"',
            '"状态未知"',
            'local primary = type(snapshot.primary) == "table" and snapshot.primary or {}',
            'primary.state or display.state or (TE.SignalFrame and TE.SignalFrame:GetEffectiveState())',
            'compactToggleButton = createActionButton(compactView, "▶", 220, -5, 24, function() ControlPanel:ToggleRun() end)',
            'createActionButton(compactView, "□", 248, -5, 24, function() ControlPanel:Restore() end)',
            'createActionButton(pane, "重置紧凑条位置"',
        ):
            self.assertIn(token, control)
        for forbidden in (
            'createActionButton(compactView, "×"',
            'createActionButton(compactView, "展开"',
            'createActionButton(compactView, "重扫动作条"',
            'RecommendationAdapter:ReadOfficial',
            'ActionBarBindingResolver:ResolveSpell',
        ):
            self.assertNotIn(forbidden, control)

    def test_compact_position_is_isolated_from_normal_window_position(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        for token in (
            'store.compact = type(store.compact) == "table" and store.compact or {}',
            'savePanelPosition("normal")',
            'savePanelPosition("compact")',
            'restorePanelPosition("compact")',
            'function ControlPanel:ResetCompactPosition()',
            'pendingCompactPositionSave = true',
        ):
            self.assertIn(token, control)
        self.assertNotIn('hud.defensePoint', control)
        self.assertNotIn('hud.compact.point', control)
