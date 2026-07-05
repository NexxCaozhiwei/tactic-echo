from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
CONTROL = ADDON / "UI" / "ControlPanel.lua"
BOARD = ADDON / "UI" / "TacticalBoard.lua"
STYLES = ADDON / "UI" / "TacticalHudStyles.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
ENCODER = ADDON / "Signal" / "SignalEncoder.lua"
GATE = ROOT / "tek" / "src" / "safety_gate.py"


class StateDisplayUnificationContractTests(unittest.TestCase):
    def test_compact_and_general_teui_use_shared_chinese_labels(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        for token in (
            'waiting = "未运行"',
            'armed = "运行中"',
            'paused = "暂停中"',
            'standby = "待命中"',
            'channeling = "引导中"',
            'empowering = "蓄力中"',
            'blocked = "已阻断"',
            'error = "异常"',
            'display_only = "仅显示"',
            'local function userVisibleReason(rawReason, reasonText)',
            'setLabel("generalRuntime", "当前状态：" .. compactStatus.label',
            'runtimeReasonLine = compactStatus.reasonText',
            '“运行中”仅代表用户已启动动态链路',
        ):
            self.assertIn(token, control)
        self.assertNotIn('"运行状态：" .. tostring(runtimeState)', control)

    def test_auto_start_stop_ooc_pause_is_presented_as_standby(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        styles = STYLES.read_text(encoding="utf-8")
        board = BOARD.read_text(encoding="utf-8")
        for token in (
            'out_of_combat_auto_standby") and "standby"',
            '自动启停：未进战斗或脱战时显示待命，进战自动恢复运行。',
            '{ value = "pause_out_of_combat", label = "自动启停（进战运行，脱战待命，默认）" }',
        ):
            self.assertIn(token, control)
        self.assertIn('return "standby", runtimeReason or "未进战斗，自动启停待命"', styles)
        self.assertIn('"standby", 1.00, "none", "待命", false', styles)
        self.assertIn('standby = "待命中"', board)

    def test_channel_and_empower_keep_manual_pause_semantics_in_compact_bar(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        self.assertIn('local function compactToggleGlyph(status)', control)
        self.assertIn('status and status.intentState == "armed" and "Ⅱ" or "▶"', control)
        self.assertIn('compactToggleButton.text:SetText(compactToggleGlyph(compactStatus))', control)
        self.assertIn('function ControlPanel:ToggleRun()', control)
        self.assertIn('if state == "armed" then self:PauseDynamic() else self:StartDynamic() end', control)

    def test_hud_line_uses_human_cast_summary_but_icon_keeps_detailed_label(self) -> None:
        board = BOARD.read_text(encoding="utf-8")
        styles = STYLES.read_text(encoding="utf-8")
        self.assertIn('channeling = "引导中"', board)
        self.assertIn('channeling_lock = "引导中"', board)
        self.assertIn('empowering = "蓄力中"', board)
        self.assertIn('empowering_lock = "蓄力中"', board)
        self.assertIn('return "channeling_lock", "玩家正在引导；当前推荐将在引导结束后恢复"', styles)
        self.assertIn('return "empowering_lock", "玩家正在蓄力；当前推荐将在蓄力结束后恢复"', styles)

    def test_error_is_rendered_as_known_exception_not_unknown_state(self) -> None:
        styles = STYLES.read_text(encoding="utf-8")
        icon = ICON.read_text(encoding="utf-8")
        board = BOARD.read_text(encoding="utf-8")
        self.assertIn('return "error", runtimeReason or "TEAP 状态异常"', styles)
        self.assertIn('colorKey, alpha, overlay, label, desaturate = "error", 0.56, "error", "异常", true', styles)
        self.assertIn('error = "异常"', board)
        self.assertIn('visual.visualState == "error"', icon)

    def test_monitor_page_keeps_raw_protocol_and_lock_diagnostics(self) -> None:
        control = CONTROL.read_text(encoding="utf-8")
        for token in (
            '第4格：',
            '协议状态：',
            '原因码：',
            '锁类型：',
            '施法 SpellID：',
            'castGUID：',
            'local function castGuidMatchDiagnostic()',
        ):
            self.assertIn(token, control)
        self.assertIn('channel_terminal_guid_mismatch', control)
        self.assertIn('empower_terminal_guid_mismatch', control)

    def test_protocol_and_tek_safety_scope_are_unchanged(self) -> None:
        encoder = ENCODER.read_text(encoding="utf-8")
        gate = GATE.read_text(encoding="utf-8")
        self.assertIn('channeling = 5', encoder)
        self.assertIn('empowering = 6', encoder)
        self.assertIn('NON_DISPATCH_PAUSE_STATES = frozenset({"paused", "manual_hold", "channeling", "empowering"})', gate)


if __name__ == "__main__":
    unittest.main()
