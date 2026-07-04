import unittest
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.binding_tokens import encode_binding_token
from tek.src.engine import TEKEngine
from tek.src.input_planner import DispatchResult
from tek.src.profile_resolver import ProfileResolver
from tek.src.safety_gate import SafetyContext
from tek.src.teap import decode_fields, encode_fields_v3


ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


class CountingDispatcher:
    backend = "fake"

    def __init__(self) -> None:
        self.calls = 0

    def dispatch(self, plan):
        self.calls += 1
        return DispatchResult(sent=True, backend=self.backend, reason="input_sent", events_sent=len(plan.events))


def burst_frame(*, sequence: int, freshness: int, origin: str = "burst"):
    return decode_fields(encode_fields_v3(
        state="armed",
        action_code=0,
        sequence=sequence,
        frame_freshness_counter=freshness,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
        binding_token=encode_binding_token("Q"),
        dispatch_origin=origin,
    ))


class AutoBurstDispatchOriginTests(unittest.TestCase):
    def test_v3_burst_origin_round_trips_without_changing_monitor_bits(self):
        frame = burst_frame(sequence=12, freshness=20)
        self.assertEqual(frame.dispatch_origin, "burst")
        self.assertTrue(frame.burst_dispatch)
        self.assertEqual(frame.monitor_flags, 0)

    def test_same_burst_candidate_sequence_uses_shared_fresh_frame_rate_policy(self):
        dispatcher = CountingDispatcher()
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
        )
        context = SafetyContext(bootstrapped=True)

        first = engine.process_frame(burst_frame(sequence=25, freshness=40), context)
        repeated = engine.process_frame(burst_frame(sequence=25, freshness=41), context)

        self.assertTrue(first.accepted)
        self.assertTrue(first.inputSent)
        self.assertTrue(repeated.accepted)
        self.assertTrue(repeated.inputSent)
        self.assertEqual(repeated.reason, "input_sent")
        self.assertTrue(repeated.dispatchAttempted)
        self.assertEqual(dispatcher.calls, 2)


    def test_burst_hold_observation_frame_never_dispatches_or_reports_paused(self):
        dispatcher = CountingDispatcher()
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
        )
        context = SafetyContext(bootstrapped=True)
        hold = decode_fields(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=41,
            frame_freshness_counter=70,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=0,
            observation_only=True,
            dispatch_origin="burst",
        ))

        result = engine.process_frame(hold, context)

        self.assertFalse(result.accepted)
        self.assertEqual(result.reason, "observation_frame")
        self.assertEqual(result.state, "armed")
        self.assertEqual(context.state, "Waiting")
        self.assertFalse(result.inputSent)
        self.assertEqual(dispatcher.calls, 0)

    def test_same_sequence_remains_allowed_for_official_recommendations(self):
        dispatcher = CountingDispatcher()
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
        )
        context = SafetyContext(bootstrapped=True)

        first = engine.process_frame(burst_frame(sequence=30, freshness=50, origin="official"), context)
        repeated = engine.process_frame(burst_frame(sequence=30, freshness=51, origin="official"), context)

        self.assertTrue(first.accepted)
        self.assertTrue(repeated.accepted)
        self.assertEqual(dispatcher.calls, 2)


if __name__ == "__main__":
    unittest.main()

class AutoBurstFreshnessBarrierTests(unittest.TestCase):
    def test_observation_frame_advances_freshness_barrier_before_next_armed_dispatch(self):
        dispatcher = CountingDispatcher()
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
        )
        context = SafetyContext(bootstrapped=True)
        handoff = decode_fields(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=50,
            frame_freshness_counter=100,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=0,
            observation_only=True,
            dispatch_origin="burst",
        ))

        held = engine.process_frame(handoff, context)
        self.assertEqual(held.reason, "observation_frame")
        self.assertEqual(context.last_frame_freshness_counter, 100)

        delayed_old = engine.process_frame(burst_frame(sequence=49, freshness=99, origin="official"), context)
        self.assertFalse(delayed_old.accepted)
        self.assertEqual(delayed_old.reason, "old_frame_freshness")

        delayed_same = engine.process_frame(burst_frame(sequence=50, freshness=100, origin="official"), context)
        self.assertFalse(delayed_same.accepted)
        self.assertEqual(delayed_same.reason, "stale_frame_freshness")

        fresh_injection = engine.process_frame(burst_frame(sequence=51, freshness=101), context)
        self.assertTrue(fresh_injection.accepted)
        self.assertTrue(fresh_injection.inputSent)
        self.assertEqual(dispatcher.calls, 1)

class AutoReactionDispatchOriginTests(unittest.TestCase):
    def test_v3_reaction_origin_round_trips_without_reusing_burst_bit(self):
        frame = decode_fields(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=61,
            frame_freshness_counter=91,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=encode_binding_token("Q"),
            dispatch_origin="reaction",
        ))
        self.assertEqual(frame.dispatch_origin, "reaction")
        self.assertTrue(frame.reaction_dispatch)
        self.assertFalse(frame.burst_dispatch)
        self.assertEqual(frame.monitor_flags, 0)

    def test_v3_rejects_conflicting_burst_and_reaction_origin_bits(self):
        from tek.src.teap import TEAPError, crc16

        fields = list(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=62,
            frame_freshness_counter=92,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=encode_binding_token("Q"),
            dispatch_origin="burst",
        ))
        fields[16] |= 0x40
        checksum = crc16(tuple(fields[:17]))
        fields[17] = checksum % 256
        fields[18] = checksum // 256
        with self.assertRaisesRegex(TEAPError, "dispatch_origin_conflict"):
            decode_fields(tuple(fields))

    def test_reaction_candidate_uses_same_binding_token_gate_and_dispatch_path(self):
        dispatcher = CountingDispatcher()
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
        )
        context = SafetyContext(bootstrapped=True)
        frame = decode_fields(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=63,
            frame_freshness_counter=93,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=encode_binding_token("Q"),
            dispatch_origin="reaction",
        ))
        result = engine.process_frame(frame, context)
        self.assertTrue(result.accepted)
        self.assertTrue(result.inputSent)
        self.assertEqual(result.dispatch_result.reason, "input_sent")
        self.assertEqual(dispatcher.calls, 1)

    def test_stable_reaction_candidate_sequence_dispatches_once_across_fresh_samples(self):
        dispatcher = CountingDispatcher()
        engine = TEKEngine(
            catalog=RETRIBUTION_V2,
            profile_resolver=ProfileResolver.from_file(LAPTOP),
            input_dispatcher=dispatcher,
        )
        context = SafetyContext(bootstrapped=True)
        first = decode_fields(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=64,
            frame_freshness_counter=94,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=encode_binding_token("Q"),
            dispatch_origin="reaction",
        ))
        repeated = decode_fields(encode_fields_v3(
            state="armed",
            action_code=0,
            sequence=64,
            frame_freshness_counter=95,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=encode_binding_token("Q"),
            dispatch_origin="reaction",
        ))

        first_result = engine.process_frame(first, context)
        repeated_result = engine.process_frame(repeated, context)

        self.assertTrue(first_result.accepted)
        self.assertTrue(first_result.inputSent)
        self.assertFalse(repeated_result.accepted)
        self.assertEqual(repeated_result.reason, "reaction_candidate_already_dispatched")
        self.assertFalse(repeated_result.inputSent)
        self.assertEqual(dispatcher.calls, 1)
