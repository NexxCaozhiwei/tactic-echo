from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class EmpoweringCastLockContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.encoder = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")
        self.mapping = (ADDON / "Diagnostics" / "MappingExport.lua").read_text(encoding="utf-8")
        self.diagnostics = (ADDON / "UI" / "Diagnostics.lua").read_text(encoding="utf-8")
        self.state = (ADDON / "Tactics" / "TacticalState.lua").read_text(encoding="utf-8")
        self.styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")

    def test_empower_events_form_a_fail_closed_cast_guid_lock(self) -> None:
        for event in (
            '"UNIT_SPELLCAST_EMPOWER_START"',
            '"UNIT_SPELLCAST_EMPOWER_UPDATE"',
            '"UNIT_SPELLCAST_EMPOWER_STOP"',
            '"UNIT_SPELLCAST_FAILED_QUIET"',
        ):
            self.assertIn(event, self.signal)
        self.assertIn('local function plainCastGUID(value)', self.signal)
        self.assertIn('local function matchingCastGUID(left, right)', self.signal)
        self.assertIn('local function beginPlayerEmpowerLock(castGUID, spellID)', self.signal)
        self.assertIn('local function clearPlayerEmpowerLock(castGUID)', self.signal)
        self.assertIn('if matchingCastGUID(playerCastLock.castGUID, castGUID) then', self.signal)
        self.assertIn('return false, "empower_terminal_guid_mismatch"', self.signal)
        self.assertIn('runtimeReason = castLockReason(castLock)', self.signal)
        self.assertIn('return "player_empowering"', self.signal)

    def test_empower_has_a_dedicated_teap_state_code_but_no_new_input_path(self) -> None:
        self.assertIn('empoweringActive = message.empoweringActive or false', self.encoder)
        self.assertIn('empoweringSpellID = message.empoweringSpellID', self.encoder)
        state_codes = self.encoder.split('local stateCodes =', 1)[1].split('}', 1)[0]
        self.assertIn('empowering = 6', state_codes)
        self.assertIn('channeling = 5', state_codes)
        self.assertNotIn('castGUID', self.encoder)
        self.assertIn('empoweringActive = message.empoweringActive == true', self.mapping)
        self.assertIn('empoweringActive = castLock.active == true and castLock.kind == "empower"', self.diagnostics)

    def test_hud_exposes_empower_labels_without_timing_or_automatic_input(self) -> None:
        self.assertIn('empowering = { 0.94, 0.70, 0.30, 1.00 }', self.styles)
        self.assertIn('empowering_lock = { 0.88, 0.56, 0.18, 1.00 }', self.styles)
        self.assertIn('colorKey, alpha, label = "empowering", 1.00, "蓄力"', self.styles)
        self.assertIn('colorKey, alpha, label = "empowering_lock", 0.94, "蓄力锁"', self.styles)
        self.assertIn('No timing fill or queued input', self.styles)
        self.assertNotIn('GetUnitEmpowerStageDuration', self.signal)
        self.assertNotIn('GetUnitEmpowerHoldAtMaxTime', self.signal)
        self.assertNotIn('SendInput', self.signal)
        self.assertNotIn('SetBinding(', self.signal)


if __name__ == "__main__":
    unittest.main()
