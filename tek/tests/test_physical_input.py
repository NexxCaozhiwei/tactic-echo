import threading
import unittest
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.binding_tokens import encode_binding_token
from tek.src.engine import TEKEngine
from tek.src.input_planner import DispatchResult
from tek.src.keyboard_whitelist import KeyboardInterventionWhitelist
from tek.src.physical_input import (
    LLKHF_INJECTED,
    PhysicalInputPause,
    WindowsPhysicalInputMonitor,
    WM_KEYDOWN,
    WM_KEYUP,
    WM_SYSKEYDOWN,
    WM_SYSKEYUP,
)
from tek.src.profile_resolver import ProfileResolver
from tek.src.safety_gate import SafetyContext
from tek.src.teap import decode_fields, encode_fields_v3

ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


class FakeInputDispatcher:
    backend = "fake"

    def __init__(self):
        self.calls = 0

    def dispatch(self, plan):
        self.calls += 1
        return DispatchResult(sent=True, backend=self.backend, reason="input_sent", events_sent=len(plan.events))


class WindowsSendInputLikeDispatcher(FakeInputDispatcher):
    backend = "windows_sendinput"


class FakeHookMonitor:
    def __init__(self, reason=None):
        self.reason = reason

    def health_reason(self):
        return self.reason

    def diagnostics(self):
        return {"hook_healthy": self.reason is None, "hook_health_reason": self.reason}


class ManualOwnershipTests(unittest.TestCase):
    def make_monitor(self, guard, keys=None):
        whitelist = KeyboardInterventionWhitelist.from_keys(keys or ("W", "A", "S", "D", "SPACE"))
        return WindowsPhysicalInputMonitor(guard, intervention_whitelist=whitelist, platform_name="test")

    def test_non_exempt_key_owns_input_until_all_keys_are_released(self):
        now = [10.0]
        guard = PhysicalInputPause(profile="balanced", clock=lambda: now[0])
        monitor = self.make_monitor(guard)

        self.assertTrue(monitor.observe_keyboard_event(vk_code=ord("Q"), message=WM_KEYDOWN))
        epoch = guard.manual_epoch
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")
        self.assertTrue(monitor.observe_keyboard_event(vk_code=ord("R"), message=WM_KEYDOWN))
        self.assertEqual(guard.snapshot().held_inputs, ("Q", "R"))
        self.assertTrue(monitor.observe_keyboard_event(vk_code=ord("Q"), message=WM_KEYUP))
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")
        self.assertTrue(monitor.observe_keyboard_event(vk_code=ord("R"), message=WM_KEYUP))
        self.assertEqual(guard.manual_epoch, epoch + 1)
        self.assertEqual(guard.dispatch_block_reason(), "manual_release_delay")
        self.assertEqual(guard.snapshot().remaining_ms, 30)

    def test_keyup_releases_only_and_never_extends_manual_window(self):
        now = [20.0]
        guard = PhysicalInputPause(profile="aggressive", clock=lambda: now[0])
        monitor = self.make_monitor(guard)
        monitor.observe_keyboard_event(vk_code=ord("Q"), message=WM_KEYDOWN)
        epoch_after_down = guard.manual_epoch
        now[0] += 0.020
        monitor.observe_keyboard_event(vk_code=ord("Q"), message=WM_KEYUP)
        self.assertEqual(guard.manual_epoch, epoch_after_down)
        # Aggressive mode has no release timer; it enters freshness recovery
        # immediately and still never lets KEYUP create another manual epoch.
        self.assertEqual(guard.snapshot().remaining_ms, 0)
        now[0] += 0.051
        self.assertEqual(guard.dispatch_block_reason(), "manual_wait_freshness")

    def test_local_whitelist_exempts_wasd_space_main_keys(self):
        now = [30.0]
        guard = PhysicalInputPause(clock=lambda: now[0])
        monitor = self.make_monitor(guard)

        self.assertFalse(monitor.observe_keyboard_event(vk_code=ord("W"), message=WM_KEYDOWN))
        self.assertFalse(guard.snapshot().active)
        monitor.observe_keyboard_event(vk_code=ord("W"), message=WM_KEYUP)
        self.assertFalse(monitor.observe_keyboard_event(vk_code=0x20, message=WM_KEYDOWN))
        self.assertFalse(guard.snapshot().active)

    def test_modifier_keys_take_manual_ownership_until_release(self):
        now = [30.0]
        guard = PhysicalInputPause(profile="balanced", clock=lambda: now[0])
        monitor = self.make_monitor(guard)

        self.assertTrue(monitor.observe_keyboard_event(vk_code=0x10, message=WM_KEYDOWN))
        self.assertEqual(guard.snapshot().held_inputs, ("SHIFT",))
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")
        # A whitelisted movement key still does not create a new hold, but the
        # active modifier continues to own manual input until it is released.
        self.assertFalse(monitor.observe_keyboard_event(vk_code=ord("W"), message=WM_KEYDOWN))
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")
        monitor.observe_keyboard_event(vk_code=ord("W"), message=WM_KEYUP)
        self.assertTrue(monitor.observe_keyboard_event(vk_code=0x10, message=WM_KEYUP))
        self.assertEqual(guard.dispatch_block_reason(), "manual_release_delay")

    def test_alt_syskey_takes_manual_ownership_until_release(self):
        now = [35.0]
        guard = PhysicalInputPause(profile="balanced", clock=lambda: now[0])
        monitor = self.make_monitor(guard)

        self.assertTrue(monitor.observe_keyboard_event(vk_code=0x12, message=WM_SYSKEYDOWN))
        self.assertEqual(guard.snapshot().held_inputs, ("ALT",))
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")
        self.assertTrue(monitor.observe_keyboard_event(vk_code=0x12, message=WM_SYSKEYUP))
        self.assertEqual(guard.dispatch_block_reason(), "manual_release_delay")

    def test_default_local_whitelist_exempts_wasd(self):
        now = [40.0]
        guard = PhysicalInputPause(clock=lambda: now[0])
        monitor = WindowsPhysicalInputMonitor(guard, intervention_whitelist=KeyboardInterventionWhitelist(), platform_name="test")
        self.assertFalse(monitor.observe_keyboard_event(vk_code=ord("W"), message=WM_KEYDOWN))
        self.assertFalse(guard.snapshot().active)
        self.assertEqual(monitor.diagnostics()["last_physical_key_classification"], "dispatch_exempt")

    def test_non_whitelist_key_starts_manual_takeover(self):
        guard = PhysicalInputPause()
        monitor = WindowsPhysicalInputMonitor(guard, intervention_whitelist=KeyboardInterventionWhitelist(), platform_name="test")
        self.assertTrue(monitor.observe_keyboard_event(vk_code=ord("Q"), message=WM_KEYDOWN))
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")

    def test_escape_enter_tab_and_chat_shortcut_keys_are_manual(self):
        for key in (0x1B, 0x0D, 0x09):
            now = [50.0]
            guard = PhysicalInputPause(clock=lambda: now[0])
            monitor = self.make_monitor(guard)
            self.assertTrue(monitor.observe_keyboard_event(vk_code=key, message=WM_KEYDOWN))
            self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")

    def test_all_mouse_events_are_ignored_by_manual_takeover_policy(self):
        guard = PhysicalInputPause()
        monitor = self.make_monitor(guard)
        self.assertFalse(monitor.observe_mouse_button())
        self.assertFalse(monitor.observe_mouse_middle_down())
        self.assertFalse(monitor.observe_mouse_middle_up())
        self.assertFalse(monitor.observe_mouse_wheel())
        self.assertFalse(guard.snapshot().active)

    def test_keyboard_hook_health_does_not_require_a_mouse_hook_when_mouse_is_ignored(self):
        guard = PhysicalInputPause()
        monitor = self.make_monitor(guard)
        # The production policy intentionally does not observe any mouse input.
        # Health must therefore depend only on the keyboard hook.
        monitor.platform_name = "nt"
        monitor._ready_event.set()
        monitor._started = True
        monitor._keyboard_hook_handle = object()
        monitor._thread = threading.current_thread()
        self.assertTrue(monitor.is_healthy())
        diagnostics = monitor.diagnostics()
        self.assertFalse(diagnostics["mouse_hook_required"])
        self.assertEqual(diagnostics["mouse_hook_status"], "disabled_by_input_policy")

    def test_keyboard_hook_install_retries_null_module_and_preserves_native_error(self):
        class FakeUser32:
            def __init__(self):
                self.modules = []

            def SetWindowsHookExW(self, _kind, _proc, module, _thread_id):
                self.modules.append(module)
                return object() if module is None else None

        class FakeKernel32:
            def GetModuleHandleW(self, _name):
                # A value above 32 bits catches accidental c_int truncation in
                # the installation path.
                return 0x123456789ABC

        class FakeApi:
            def __init__(self):
                self.user32 = FakeUser32()
                self.kernel32 = FakeKernel32()

            def last_error(self):
                return 5

        guard = PhysicalInputPause()
        monitor = self.make_monitor(guard)
        monitor._keyboard_proc = object()
        api = FakeApi()
        handle, mode, error = monitor._install_keyboard_hook(api)
        self.assertIsNotNone(handle)
        self.assertEqual(mode, "null_module")
        self.assertEqual(error, 0)
        self.assertEqual(api.user32.modules, [0x123456789ABC, None])

    def test_injected_keyboard_event_never_takes_ownership(self):
        guard = PhysicalInputPause()
        monitor = self.make_monitor(guard)
        self.assertFalse(monitor.observe_keyboard_event(vk_code=ord("Q"), message=WM_KEYDOWN, flags=LLKHF_INJECTED))
        self.assertFalse(guard.snapshot().active)
        self.assertEqual(guard.snapshot().ignored_injected_events, 1)

    def test_balanced_recovery_requires_two_new_freshness_frames(self):
        now = [60.0]
        guard = PhysicalInputPause(profile="balanced", clock=lambda: now[0])
        guard.observe_freshness(100)
        guard.begin_manual_hold("Q")
        guard.end_manual_hold("Q")
        now[0] += 0.031
        self.assertEqual(guard.dispatch_block_reason(), "manual_wait_freshness")
        guard.observe_freshness(101)
        self.assertEqual(guard.dispatch_block_reason(), "manual_wait_freshness")
        guard.observe_freshness(102)
        self.assertIsNone(guard.dispatch_block_reason())

    def test_replay_guard_suppresses_same_token_until_sequence_changes_or_deadline(self):
        now = [70.0]
        guard = PhysicalInputPause(profile="manual_first", clock=lambda: now[0])
        token = encode_binding_token("Q")
        guard.note_auto_dispatch(token, 10)
        guard.observe_freshness(200)
        guard.begin_manual_hold("Q")
        guard.end_manual_hold("Q")
        now[0] += 0.251
        guard.dispatch_block_reason()
        guard.observe_freshness(201)
        guard.observe_freshness(202)
        self.assertEqual(guard.dispatch_block_reason(binding_token=token, action_sequence=10), "manual_replay_guard")
        self.assertIsNone(guard.dispatch_block_reason(binding_token=token, action_sequence=11))

    def test_teap_manual_hold_is_an_independent_hard_owner(self):
        guard = PhysicalInputPause(profile="aggressive")
        guard.observe_teap_state("manual_hold")
        self.assertEqual(guard.dispatch_block_reason(), "teap_manual_hold")
        guard.observe_teap_state("armed")
        # Aggressive mode has no release timer, so TEAP manual-hold release
        # proceeds straight to the freshness requirement.
        self.assertEqual(guard.dispatch_block_reason(), "manual_wait_freshness")

    def test_explicit_recovery_clears_only_post_release_gate_and_preserves_held_keys(self):
        guard = PhysicalInputPause(profile="balanced")
        guard.observe_freshness(10)
        guard.begin_manual_hold("Q")
        guard.end_manual_hold("Q")
        self.assertEqual(guard.dispatch_block_reason(), "manual_release_delay")
        epoch = guard.manual_epoch
        guard.reset_recovery_gate()
        self.assertIsNone(guard.dispatch_block_reason())
        self.assertGreater(guard.manual_epoch, epoch)
        guard.begin_manual_hold("R")
        guard.reset_recovery_gate()
        self.assertEqual(guard.dispatch_block_reason(), "manual_input_held")

    def test_hook_stop_timeout_keeps_monitor_in_stopping_state_and_blocks_restart(self):
        class StubbornThread:
            def is_alive(self):
                return True

            def join(self, _timeout):
                return None

        guard = PhysicalInputPause()
        monitor = WindowsPhysicalInputMonitor(guard, platform_name="nt")
        thread = StubbornThread()
        monitor._thread = thread
        monitor._started = True
        monitor._keyboard_hook_handle = object()
        self.assertFalse(monitor.stop(timeout_seconds=0.0))
        self.assertTrue(monitor.is_stopping())
        self.assertEqual(monitor.health_reason(), "physical_input_hook_stopping")
        self.assertFalse(monitor.start())
        self.assertIs(monitor._thread, thread)


class EngineManualGateTests(unittest.TestCase):
    def frame(self, *, state="armed", sequence=12, freshness=20, token=None):
        return decode_fields(encode_fields_v3(
            state=state,
            action_code=0,
            sequence=sequence,
            frame_freshness_counter=freshness,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=token or encode_binding_token("Q"),
        ))

    def test_engine_blocks_windows_sendinput_when_hook_is_not_ready(self):
        dispatcher = WindowsSendInputLikeDispatcher()
        engine = TEKEngine(
            RETRIBUTION_V2,
            ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
            physical_input_monitor=FakeHookMonitor("physical_input_hook_not_ready"),
        )
        trace = engine.process_frame(self.frame(), SafetyContext(bootstrapped=True))
        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "physical_input_hook_not_ready")
        self.assertEqual(dispatcher.calls, 0)

    def test_manual_epoch_change_before_dispatch_blocks_the_frame(self):
        guard = PhysicalInputPause(profile="aggressive")
        dispatcher = FakeInputDispatcher()
        engine = TEKEngine(
            RETRIBUTION_V2,
            ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
            physical_input_guard=guard,
        )
        original_allow = engine.rate_limiter.allow

        def race_allow(plan):
            guard.begin_manual_hold("Q")
            return original_allow(plan)

        engine.rate_limiter.allow = race_allow
        trace = engine.process_frame(self.frame(), SafetyContext(bootstrapped=True))
        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "manual_epoch_changed")
        self.assertEqual(dispatcher.calls, 0)
        self.assertEqual(engine.rate_limiter.snapshot()["used_global"], 0)

    def test_engine_observes_teap_manual_hold_before_safety_dispatch(self):
        guard = PhysicalInputPause(profile="aggressive")
        dispatcher = FakeInputDispatcher()
        engine = TEKEngine(
            RETRIBUTION_V2,
            ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
            physical_input_guard=guard,
        )
        trace = engine.process_frame(self.frame(state="manual_hold"), SafetyContext(bootstrapped=True))
        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "teap_manual_hold")
        self.assertEqual(dispatcher.calls, 0)



class P1PhysicalInputQueryTests(unittest.TestCase):
    def test_is_paused_is_read_only_and_does_not_clear_an_elapsed_replay_guard(self):
        now = [100.0]
        guard = PhysicalInputPause(profile="aggressive", clock=lambda: now[0])
        token = encode_binding_token("Q")
        guard.note_auto_dispatch(token, 44)
        guard.observe_freshness(500)
        guard.begin_manual_hold("Q")
        guard.end_manual_hold("Q")
        guard.dispatch_block_reason()
        guard.observe_freshness(501)
        self.assertEqual(guard._phase, guard.REPLAY_GUARD)

        now[0] += 0.200
        self.assertFalse(guard.is_paused())
        # Querying merely reports the elapsed state; dispatch_block_reason owns
        # the state-machine transition that clears the guard.
        self.assertEqual(guard._phase, guard.REPLAY_GUARD)
        self.assertIsNone(guard.dispatch_block_reason(binding_token=token, action_sequence=44))
        self.assertEqual(guard._phase, guard.DISPATCHABLE)

if __name__ == "__main__":
    unittest.main()
