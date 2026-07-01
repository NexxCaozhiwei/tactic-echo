from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class ChannelingHudDisplayContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.encoder = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")
        self.state = (ADDON / "Tactics" / "TacticalState.lua").read_text(encoding="utf-8")
        self.advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        self.styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.gate = (ROOT / "tek" / "src" / "safety_gate.py").read_text(encoding="utf-8")
        self.teap = (ROOT / "tek" / "src" / "teap.py").read_text(encoding="utf-8")

    def test_field_four_has_dedicated_channel_and_empower_codes(self) -> None:
        self.assertIn('channeling = 5', self.encoder)
        self.assertIn('empowering = 6', self.encoder)
        self.assertIn('5: "channeling"', self.teap)
        self.assertIn('6: "empowering"', self.teap)
        self.assertIn('local function castLockState(castLock)', self.signal)
        self.assertIn('return "channeling"', self.signal)
        self.assertIn('return "empowering"', self.signal)
        self.assertIn('outputState = castLockState(castLock)', self.signal)
        self.assertIn('if castLock.active then return castLockState(castLock), castLockReason(castLock) end', self.signal)

    def test_tactical_snapshot_projects_the_actual_dedicated_state_for_hud_only(self) -> None:
        self.assertIn('state == "channeling" and reason == "player_channeling" and channelingActive', self.state)
        self.assertIn('state == "empowering" and reason == "player_empowering" and empoweringActive', self.state)
        self.assertIn('displayState = "channeling_lock"', self.state)
        self.assertIn('displayState = "empowering_lock"', self.state)
        self.assertIn('displayState = primary.displayState', self.advisors)
        self.assertIn('empowering = type(primary.empowering) == "table"', self.advisors)

    def test_primary_hud_preserves_block_error_priority_and_cast_lock_labels(self) -> None:
        self.assertIn('local function matchesActiveCastLock(item, castLock)', self.model)
        spell_id_match = self.model.index('if recommendationSpellID and lockSpellID then return recommendationSpellID == lockSpellID end')
        name_fallback = self.model.index('local recommendationName = plainText(item and item.spellName, nil)')
        self.assertLess(spell_id_match, name_fallback)
        blocked = self.styles.index('if runtimeState == "blocked" or item.blocked == true then')
        channeling = self.styles.index('if item.displayState == "channeling_lock" or runtimeState == "channeling" then')
        empowering = self.styles.index('if item.displayState == "empowering_lock" or runtimeState == "empowering" then')
        paused = self.styles.index('if runtimeState == "paused" or item.paused == true then')
        self.assertLess(blocked, channeling)
        self.assertLess(channeling, empowering)
        self.assertLess(empowering, paused)
        self.assertIn('return "channeling_lock", "玩家正在引导；当前推荐将在引导结束后恢复"', self.styles)
        self.assertIn('return "empowering_lock", "玩家正在蓄力；当前推荐将在蓄力结束后恢复"', self.styles)
        self.assertIn('visual.visualState == "empowering" or visual.visualState == "empowering_lock"', self.icon)

    def test_control_panel_uses_human_cast_labels_while_tek_gate_rejects_both_states(self) -> None:
        self.assertIn('channeling = "引导中"', self.control)
        self.assertIn('empowering = "蓄力中"', self.control)
        self.assertNotIn('channeling_lock', self.control)
        self.assertNotIn('empowering_lock', self.control)
        self.assertIn('NON_DISPATCH_PAUSE_STATES = frozenset({"paused", "manual_hold", "channeling", "empowering"})', self.gate)
        self.assertIn('frame.state in NON_DISPATCH_PAUSE_STATES', self.gate)
        self.assertIn('return False, f"frame_state_{frame.state}"', self.gate)


if __name__ == "__main__":
    unittest.main()
