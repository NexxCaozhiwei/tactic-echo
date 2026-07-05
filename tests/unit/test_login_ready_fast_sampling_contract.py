from __future__ import annotations

import unittest
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class LoginReadyFastSamplingContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.settings = (ROOT / "tek" / "app" / "settings_store.py").read_text(encoding="utf-8")
        self.worker = (ROOT / "tek" / "app" / "worker_controller.py").read_text(encoding="utf-8")
        self.window = (ROOT / "tek" / "app" / "status_window.py").read_text(encoding="utf-8")

    def test_player_login_shows_a_live_paused_teap_signal_without_arming_dispatch_intent(self) -> None:
        self.assertIn('local UPDATE_INTERVAL = 0.05', self.signal)
        self.assertIn('function SignalFrame:ShowPausedOnLogin()', self.signal)
        self.assertIn('createFrame():Show()', self.signal)
        self.assertIn('return self:Refresh("player_login_paused")', self.signal)
        self.assertIn('TE:RegisterEventSafe(loginWatcher, "PLAYER_LOGIN")', self.signal)
        self.assertIn('SignalFrame:ShowPausedOnLogin()', self.signal)
        self.assertIn('state = nextState or "waiting"', self.signal)
        self.assertNotIn('self:Refresh("disarmed")', self.signal)
        set_state_start = self.signal.index('function SignalFrame:SetState(nextState)')
        set_state_end = self.signal.index('function SignalFrame:GetState()', set_state_start)
        self.assertNotIn('createFrame():Hide()', self.signal[set_state_start:set_state_end])

        start = self.signal.index('function SignalFrame:ShowPausedOnLogin()')
        end = self.signal.index('local loginWatcher = CreateFrame("Frame")', start)
        login_function = self.signal[start:end]
        self.assertIn('state = "paused"', login_function)
        self.assertNotIn('state = "armed"', login_function)
        self.assertNotIn('ArmOnLogin', self.signal)

    def test_out_of_combat_policies_keep_teap_visible_and_use_paused_not_waiting(self) -> None:
        self.assertIn('manual_keep = true', self.signal)
        self.assertIn('pause_out_of_combat = true', self.signal)
        self.assertIn('close_out_of_combat = true', self.signal)
        self.assertIn('if not inCombat and policy == "pause_out_of_combat" then return "paused", "out_of_combat_auto_standby" end', self.signal)
        self.assertIn('if event == "PLAYER_REGEN_ENABLED" and state == "armed" and getSessionPolicy() == "close_out_of_combat" then', self.signal)
        self.assertIn('SignalFrame:SetState("paused")', self.signal)
        self.assertIn('if policy == "close_out_of_combat" and state == "armed" and not inCombat then', self.signal)
        self.assertIn('pause_out_of_combat = "自动启停（进战运行，脱战待命，默认）"', self.signal)

        set_state_start = self.signal.index('function SignalFrame:SetState(nextState)')
        set_state_end = self.signal.index('function SignalFrame:GetState()', set_state_start)
        set_state = self.signal[set_state_start:set_state_end]
        self.assertIn('createFrame():Show()', set_state)
        self.assertNotIn('createFrame():Hide()', set_state)
        self.assertNotIn('Refresh("disarmed")', set_state)

    def test_manual_armed_and_paused_state_changes_have_short_audio_cues(self) -> None:
        armed_sound = ADDON / "Media" / "te-armed-123.wav"
        paused_sound = ADDON / "Media" / "te-paused-321.wav"
        self.assertTrue(armed_sound.exists())
        self.assertTrue(paused_sound.exists())
        self.assertLess(armed_sound.stat().st_size, 30000)
        self.assertLess(paused_sound.stat().st_size, 30000)
        for sound in (armed_sound, paused_sound):
            with wave.open(str(sound), "rb") as audio:
                duration = audio.getnframes() / audio.getframerate()
            self.assertGreaterEqual(duration, 0.23)
            self.assertLessEqual(duration, 0.27)
        self.assertIn('armed = "Interface\\\\AddOns\\\\!TacticEcho\\\\Media\\\\te-armed-123.wav"', self.signal)
        self.assertIn('paused = "Interface\\\\AddOns\\\\!TacticEcho\\\\Media\\\\te-paused-321.wav"', self.signal)

        set_state_start = self.signal.index('function SignalFrame:SetState(nextState)')
        set_state_end = self.signal.index('function SignalFrame:GetState()', set_state_start)
        set_state = self.signal[set_state_start:set_state_end]
        self.assertIn('state ~= previousState', set_state)
        self.assertIn('PlaySoundFile', set_state)
        self.assertIn('"SFX"', set_state)

    def test_tek_defaults_to_50ms_sampling_and_keeps_20ms_floor(self) -> None:
        self.assertIn('sampling_interval_ms: int = 50', self.settings)
        self.assertIn('interval = max(20, min(500, int(self.sampling_interval_ms)))', self.settings)
        self.assertIn('interval_seconds: float = 0.05', self.worker)
        self.assertIn('默认 50；建议 50–100', self.window)
        self.assertIn('采样 50ms 时可更快识别暂停帧', self.window)


if __name__ == "__main__":
    unittest.main()
