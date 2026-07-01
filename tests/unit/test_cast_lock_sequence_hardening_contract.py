from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class CastLockSequenceHardeningContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.mapping = (ADDON / "Diagnostics" / "MappingExport.lua").read_text(encoding="utf-8")
        self.encoder = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")

    def test_unit_channel_info_preserves_the_retail_empower_discriminator(self) -> None:
        self.assertIn('spellID, isEmpowered = pcall(UnitChannelInfo, "player")', self.signal)
        self.assertIn('local empowered = plainBoolean(isEmpowered)', self.signal)
        self.assertIn('kind = empowered and "empower" or "channel"', self.signal)
        self.assertIn('if live and live.isEmpowered == true then', self.signal)
        self.assertIn('return false, "ignored_empowered_channel_event"', self.signal)
        self.assertIn('return false, "preserved_empower_lock"', self.signal)

    def test_normal_channels_have_their_own_guid_guard_against_late_events(self) -> None:
        self.assertIn('local function beginPlayerChannelLock(castGUID, spellID)', self.signal)
        self.assertIn('local function updatePlayerChannelLock(castGUID, spellID)', self.signal)
        self.assertIn('local function clearPlayerChannelLock(castGUID)', self.signal)
        self.assertIn('return false, "ignored_stale_channel_update"', self.signal)
        self.assertIn('return false, "channel_terminal_guid_mismatch"', self.signal)
        self.assertIn('changed, outcome = clearPlayerChannelLock(castGUID)', self.signal)
        self.assertIn('changed, outcome = clearPlayerEmpowerLock(castGUID)', self.signal)

    def test_terminal_events_do_not_use_success_or_unrelated_events_to_open_dispatch(self) -> None:
        self.assertIn('outcome = "ignored_success"', self.signal)
        self.assertIn('Success alone is never authoritative for either cast kind.', self.signal)
        self.assertIn('if playerCastLock.active == true and playerCastLock.kind == "channel" then', self.signal)
        self.assertIn('changed, outcome = clearPlayerChannelLock(castGUID)', self.signal)
        self.assertNotIn('updatePlayerChannelLock(false)', self.signal)

    def test_guidless_api_fallback_is_bounded_without_weakening_event_owned_locks(self) -> None:
        self.assertIn('playerCastLock.source = normalizedGUID and "event" or "api"', self.signal)
        self.assertIn('if playerCastLock.source == "api" and playerCastLock.castGUID == nil then', self.signal)
        self.assertIn('clearPlayerCastLock(playerCastLock.kind)', self.signal)
        self.assertIn('Event-owned locks require their', self.signal)

    def test_transition_diagnostics_are_local_plain_data_and_not_teap_fields(self) -> None:
        self.assertIn('TacticEchoDB.signal.castLockTransitions', self.signal)
        self.assertIn('local function rememberCastLockTransition(eventName, outcome, before, eventSpellID)', self.signal)
        self.assertIn('function SignalFrame:GetCastLockDiagnostics()', self.signal)
        self.assertIn('castLockTransitions = copyCastLockTransitions()', self.mapping)
        self.assertIn('beforeHasCastGUID', self.mapping)
        self.assertNotIn('castGUID =', self.mapping)
        state_codes = self.encoder.split('local stateCodes =', 1)[1].split('}', 1)[0]
        self.assertIn('channeling = 5', state_codes)
        self.assertIn('empowering = 6', state_codes)


if __name__ == "__main__":
    unittest.main()
