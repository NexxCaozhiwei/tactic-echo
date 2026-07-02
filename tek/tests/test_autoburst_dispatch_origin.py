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

    def test_same_burst_candidate_sequence_is_dispatched_once(self):
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
        self.assertFalse(repeated.accepted)
        self.assertEqual(repeated.reason, "burst_sequence_already_dispatched")
        self.assertFalse(repeated.dispatchAttempted)
        self.assertEqual(dispatcher.calls, 1)


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
