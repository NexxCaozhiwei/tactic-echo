import unittest
from dataclasses import replace
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.engine import TEKEngine
from tek.src.input_planner import DispatchResult
from tek.src.profile_resolver import ProfileResolver
from tek.src.safety_gate import SafetyContext
from tek.src.teap import TEAPError, decode_fields, encode_fields_v3
from tek.src.binding_tokens import encode_binding_token


ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


class FakeInputDispatcher:
    backend = "fake"

    def dispatch(self, plan):
        return DispatchResult(
            sent=True,
            backend="fake",
            reason="input_sent",
            events_sent=len(plan.events),
        )


def frame_fields(state=1, action_code=1, sequence=1, frame_freshness_counter=None, binding_token=None):
    state_name = {0: "waiting", 1: "armed", 2: "paused", 3: "blocked", 4: "error", 5: "channeling", 6: "empowering", 7: "manual_hold"}[state]
    freshness = sequence + 1 if frame_freshness_counter is None else frame_freshness_counter
    return list(encode_fields_v3(
        state=state_name,
        action_code=action_code,
        sequence=sequence,
        frame_freshness_counter=freshness,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
        binding_token=encode_binding_token("Q") if binding_token is None else binding_token,
        in_combat=True,
    ))


class TEKEngineTests(unittest.TestCase):
    def setUp(self):
        self.engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
        )

    def test_valid_armed_frame_plans_binding_sequence(self):
        frame = decode_fields(frame_fields(action_code=1, sequence=10))
        trace = self.engine.process_frame(frame, SafetyContext(bootstrapped=True))

        self.assertTrue(trace.accepted)
        self.assertEqual(trace.reason, "dry_run_planned")
        self.assertIsNone(trace.action_id)
        self.assertEqual(trace.binding, "Q")
        self.assertEqual(trace.dispatcher_backend, "dry_run")
        self.assertEqual(trace.raw_fields, tuple(frame_fields(action_code=1, sequence=10)))
        self.assertEqual(trace.raw_fields[-1], 165)
        self.assertFalse(trace.dispatch_result.sent)
        self.assertEqual(trace.dispatch_result.backend, "dry_run")
        self.assertEqual(
            [(event.key, event.event) for event in trace.input_plan.events],
            [("Q", "down"), ("Q", "up")],
        )

    def test_injected_dispatcher_can_report_input_sent(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )
        frame = decode_fields(frame_fields(action_code=1, sequence=10))
        trace = engine.process_frame(frame, SafetyContext(bootstrapped=True))

        self.assertTrue(trace.accepted)
        self.assertEqual(trace.reason, "input_sent")
        self.assertEqual(trace.dispatcher_backend, "fake")
        self.assertTrue(trace.dispatch_result.sent)
        self.assertEqual(trace.dispatch_result.backend, "fake")
        self.assertEqual(trace.dispatch_result.events_sent, 2)

    def test_paused_frame_is_blocked(self):
        frame = decode_fields(frame_fields(state=2, action_code=1, sequence=10))
        trace = self.engine.process_frame(frame, SafetyContext(bootstrapped=True))

        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "frame_state_paused")

    def test_channel_and_empower_frames_never_dispatch_and_fresh_armed_resumes(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )
        context = SafetyContext(bootstrapped=True, current_session_epoch=1)
        channeling = decode_fields(frame_fields(state=5, action_code=1, sequence=11, frame_freshness_counter=20))
        empowering = decode_fields(frame_fields(state=6, action_code=1, sequence=12, frame_freshness_counter=21))
        armed = decode_fields(frame_fields(state=1, action_code=1, sequence=13, frame_freshness_counter=22))

        channeling_trace = engine.process_frame(channeling, context)
        empowering_trace = engine.process_frame(empowering, context)
        armed_trace = engine.process_frame(armed, context)

        self.assertFalse(channeling_trace.accepted)
        self.assertEqual(channeling_trace.reason, "frame_state_channeling")
        self.assertEqual(channeling_trace.tekState, "Paused")
        self.assertFalse(channeling_trace.dispatchAttempted)
        self.assertFalse(channeling_trace.inputSent)
        self.assertFalse(empowering_trace.accepted)
        self.assertEqual(empowering_trace.reason, "frame_state_empowering")
        self.assertEqual(empowering_trace.tekState, "Paused")
        self.assertFalse(empowering_trace.dispatchAttempted)
        self.assertFalse(empowering_trace.inputSent)
        self.assertTrue(armed_trace.accepted)
        self.assertEqual(armed_trace.reason, "input_sent")

    def test_repeated_sequence_with_fresh_frame_can_dispatch(self):
        context = SafetyContext(
            bootstrapped=True,
            current_session_epoch=1,
            last_action_sequence=10,
            last_frame_freshness_counter=20,
        )
        frame = decode_fields(frame_fields(action_code=1, sequence=10, frame_freshness_counter=21))
        trace = self.engine.process_frame(frame, context)

        self.assertTrue(trace.accepted)
        self.assertEqual(trace.reason, "dry_run_planned")

    def test_stale_freshness_is_blocked_even_when_sequence_matches(self):
        context = SafetyContext(
            bootstrapped=True,
            current_session_epoch=1,
            last_action_sequence=10,
            last_frame_freshness_counter=21,
        )
        frame = decode_fields(frame_fields(action_code=1, sequence=10, frame_freshness_counter=21))
        trace = self.engine.process_frame(frame, context)

        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "stale_frame_freshness")

    def test_unfocused_wow_is_blocked(self):
        frame = decode_fields(frame_fields(action_code=1, sequence=11))
        trace = self.engine.process_frame(frame, SafetyContext(bootstrapped=True, wow_foreground=False))

        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "foreground_not_game")
        self.assertEqual(trace.dispatcher_backend, "dry_run")

    def test_legacy_protocol_frame_is_rejected_by_decoder(self):
        fields = frame_fields(action_code=1, sequence=12)
        fields[2] = 2
        from tek.src.teap import crc16
        crc = crc16(tuple(fields[:17]))
        fields[17] = crc % 256
        fields[18] = crc // 256
        with self.assertRaisesRegex(TEAPError, "unsupported_protocol_version:2"):
            decode_fields(fields)

    def test_invalid_binding_token_fails_closed(self):
        frame = decode_fields(frame_fields(action_code=1, sequence=12, binding_token=0))
        trace = self.engine.process_frame(frame, SafetyContext(bootstrapped=True))

        self.assertFalse(trace.accepted)
        self.assertIn("binding_token_invalid", trace.reason)

    def test_non_combat_send_input_path_can_dispatch(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )
        fields = frame_fields(action_code=1, sequence=13)
        fields[16] = 0
        from tek.src.teap import crc16
        crc = crc16(tuple(fields[:17]))
        fields[17] = crc % 256
        fields[18] = crc // 256
        frame = decode_fields(fields)
        trace = engine.process_frame(frame, SafetyContext(bootstrapped=True))

        self.assertTrue(trace.gatePassed)
        self.assertTrue(trace.dispatchAttempted)

    def test_ui_startup_allows_current_armed_frame_after_bootstrap(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )
        frame = decode_fields(frame_fields(action_code=1, sequence=13, frame_freshness_counter=20))
        context = SafetyContext(bootstrapped=True, require_start_toggle=False)

        trace = engine.process_frame(frame, context)

        self.assertTrue(trace.accepted)
        self.assertEqual(trace.reason, "input_sent")

    def test_explicit_start_toggle_remains_available_for_cli_safety_mode(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )
        frame = decode_fields(frame_fields(action_code=1, sequence=13))
        context = SafetyContext(bootstrapped=True, require_start_toggle=True)

        trace = engine.process_frame(frame, context)

        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "awaiting_start_toggle")

    def test_v3_valid_token_dispatches_without_registered_action_id(self):
        token = encode_binding_token("ALT+Q")
        fields = encode_fields_v3(
            state="armed", action_code=0, sequence=30, frame_freshness_counter=31,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=token,
        )
        frame = decode_fields(fields)
        trace = self.engine.process_frame(frame, SafetyContext(bootstrapped=True))
        self.assertTrue(trace.accepted)
        self.assertTrue(trace.gatePassed)
        self.assertEqual(trace.binding, "ALT+Q")
        self.assertIsNone(trace.action_id)
        self.assertEqual(trace.binding_token, token)

    def test_v3_channel_and_empower_states_block_binding_token_dispatch_until_fresh_armed(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )
        token = encode_binding_token("ALT+Q")
        context = SafetyContext(bootstrapped=True)
        channeling = decode_fields(encode_fields_v3(
            state="channeling", action_code=0, sequence=40, frame_freshness_counter=41,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=token,
        ))
        empowering = decode_fields(encode_fields_v3(
            state="empowering", action_code=0, sequence=41, frame_freshness_counter=42,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=token,
        ))
        armed = decode_fields(encode_fields_v3(
            state="armed", action_code=0, sequence=42, frame_freshness_counter=43,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=token,
        ))

        channel_trace = engine.process_frame(channeling, context)
        empower_trace = engine.process_frame(empowering, context)
        armed_trace = engine.process_frame(armed, context)

        self.assertFalse(channel_trace.accepted)
        self.assertEqual(channel_trace.reason, "frame_state_channeling")
        self.assertEqual(channel_trace.tekState, "Paused")
        self.assertFalse(channel_trace.dispatchAttempted)
        self.assertFalse(empower_trace.accepted)
        self.assertEqual(empower_trace.reason, "frame_state_empowering")
        self.assertEqual(empower_trace.tekState, "Paused")
        self.assertFalse(empower_trace.dispatchAttempted)
        self.assertTrue(armed_trace.accepted)
        self.assertEqual(armed_trace.reason, "input_sent")
        self.assertTrue(armed_trace.inputSent)

    def test_v3_zero_token_fails_closed(self):
        fields = encode_fields_v3(
            state="armed", action_code=0, sequence=32, frame_freshness_counter=33,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=0,
        )
        trace = self.engine.process_frame(decode_fields(fields), SafetyContext(bootstrapped=True))
        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "binding_token_invalid:invalid_token:0")

    def test_v3_unsupported_token_fails_closed(self):
        fields = encode_fields_v3(
            state="armed", action_code=0, sequence=34, frame_freshness_counter=35,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=63,
        )
        trace = self.engine.process_frame(decode_fields(fields), SafetyContext(bootstrapped=True))
        self.assertFalse(trace.accepted)
        self.assertIn("binding_token_invalid:unsupported_token", trace.reason)


class FailingInputDispatcher:
    backend = "failing"

    def dispatch(self, plan):
        return DispatchResult(
            sent=False,
            backend="failing",
            reason="sendinput_partial:0/2",
            events_sent=0,
        )


class DispatchFailureEscalationTests(unittest.TestCase):
    def test_three_failures_in_window_escalate_but_first_two_are_blocked(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FailingInputDispatcher(),
        )
        context = SafetyContext(bootstrapped=True)
        traces = []
        for sequence in (50, 51, 52):
            frame = decode_fields(frame_fields(action_code=1, sequence=sequence, frame_freshness_counter=sequence + 10))
            traces.append(engine.process_frame(frame, context))
        self.assertEqual(traces[0].tekState, "Blocked")
        self.assertEqual(traces[1].tekState, "Blocked")
        self.assertEqual(traces[2].tekState, "ErrorLocked")
        self.assertTrue(traces[2].reason.endswith(":error_locked"))

class ProtocolVersionTests(unittest.TestCase):
    def test_v2_frame_is_rejected_without_a_legacy_compatibility_path(self):
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
        )
        decoded = decode_fields(frame_fields(action_code=1, sequence=80))
        frame = replace(decoded, protocol_version=2)
        trace = engine.process_frame(frame, SafetyContext(bootstrapped=True, expected_protocol_version=3))
        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "unsupported_protocol_version:2")


class P1DispatchStateTests(unittest.TestCase):
    def setUp(self):
        self.engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=FakeInputDispatcher(),
        )

    def _frame(self, state: str, *, catalog_version: int = 255, catalog_fingerprint: int = 1, binding_token: int = 0):
        return decode_fields(encode_fields_v3(
            state=state,
            action_code=0,
            sequence=90,
            frame_freshness_counter=91,
            catalog_version=catalog_version,
            catalog_fingerprint=catalog_fingerprint,
            binding_token=binding_token,
            in_combat=False,
        ))

    def test_non_dispatch_states_keep_their_own_semantics_before_catalog_or_binding_checks(self):
        expected = {
            "paused": ("frame_state_paused", "Paused"),
            "waiting": ("frame_state_waiting", "Waiting"),
            "manual_hold": ("frame_state_manual_hold", "Paused"),
        }
        for state, (reason, tek_state) in expected.items():
            with self.subTest(state=state):
                trace = self.engine.process_frame(self._frame(state), SafetyContext(bootstrapped=True))
                self.assertFalse(trace.accepted)
                self.assertEqual(trace.reason, reason)
                self.assertEqual(trace.tekState, tek_state)
                self.assertNotIn("catalog_", trace.reason)
                self.assertNotIn("binding_token_invalid", trace.reason)

    def test_mapping_result_is_blocked_without_failure_escalation_or_rate_charge(self):
        class UnsupportedDispatcher:
            backend = "mapping_test"

            def dispatch(self, _plan):
                return DispatchResult(
                    sent=False,
                    backend=self.backend,
                    reason="unsupported_key:OEM_102",
                    events_sent=0,
                )

        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=UnsupportedDispatcher(),
        )
        frame = decode_fields(frame_fields(action_code=1, sequence=94, frame_freshness_counter=95))
        trace = engine.process_frame(frame, SafetyContext(bootstrapped=True))

        self.assertFalse(trace.accepted)
        self.assertTrue(trace.gatePassed)
        self.assertTrue(trace.dispatchAttempted)
        self.assertTrue(trace.dispatchBlocked)
        self.assertEqual(trace.reason, "unsupported_key:OEM_102")
        self.assertEqual(trace.tekState, "Blocked")
        self.assertEqual(engine.failure_tracker.snapshot()["recent_failures"], 0)
        self.assertEqual(engine.rate_limiter.snapshot()["used_global"], 0)

if __name__ == "__main__":
    unittest.main()
