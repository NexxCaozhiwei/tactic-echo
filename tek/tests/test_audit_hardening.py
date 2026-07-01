from __future__ import annotations

import unittest
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.binding_tokens import encode_binding_token
from tek.src.engine import TEKEngine
from tek.src.input_planner import DispatchResult
from tek.src.profile_resolver import ProfileResolver
from tek.src.runner import RunnerConfig, TEKRunner
from tek.src.safety_gate import SafetyContext
from tek.src.teap import decode_fields, encode_fields_v3

ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


class SentDispatcher:
    backend = "audit_fake"

    def dispatch(self, plan):
        return DispatchResult(sent=True, backend=self.backend, reason="input_sent", events_sent=len(plan.events))


class Frames:
    def __init__(self, frames):
        self.frames = list(frames)
        self.index = 0

    def read(self):
        value = self.frames[min(self.index, len(self.frames) - 1)]
        self.index += 1
        return value


def v3_frame(sequence: int, freshness: int):
    return decode_fields(encode_fields_v3(
        state="armed",
        action_code=1,
        sequence=sequence,
        frame_freshness_counter=freshness,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
        binding_token=encode_binding_token("Q"),
        in_combat=True,
    ))


class ToggleGuard:
    def __init__(self, paused: bool = True):
        self.paused = paused

    def is_paused(self) -> bool:
        return self.paused


class AuditHardeningTests(unittest.TestCase):
    def test_v3_unknown_nonzero_action_code_still_uses_valid_binding_token(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP), input_dispatcher=SentDispatcher())
        frame = decode_fields(encode_fields_v3(
            state="armed",
            action_code=250,
            sequence=10,
            frame_freshness_counter=11,
            catalog_fingerprint=RETRIBUTION_V2.fingerprint16,
            binding_token=encode_binding_token("ALT+Q"),
        ))
        trace = engine.process_frame(frame, SafetyContext(bootstrapped=True))
        self.assertTrue(trace.accepted)
        self.assertEqual(trace.reason, "input_sent")
        self.assertIsNone(trace.action_id)
        self.assertEqual(trace.binding, "ALT+Q")

    def test_old_freshness_counter_fails_closed(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP))
        context = SafetyContext(bootstrapped=True, current_session_epoch=1, last_frame_freshness_counter=50)
        trace = engine.process_frame(v3_frame(20, 49), context)
        self.assertFalse(trace.accepted)
        self.assertEqual(trace.reason, "old_frame_freshness")

    def test_runner_budget_is_not_reset_on_every_tick(self):
        engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(LAPTOP), input_dispatcher=SentDispatcher())
        runner = TEKRunner(engine, Frames([v3_frame(1, 10), v3_frame(2, 11), v3_frame(3, 12)]))
        records = runner.run(RunnerConfig(max_frames=3, interval_seconds=0, assume_wow_foreground=True, dispatch_budget=1))
        self.assertEqual(records[0].reason, "bootstrap_observing_session")
        self.assertEqual(records[1].reason, "input_sent")
        self.assertEqual(records[2].reason, "dispatch_budget_exhausted")
        self.assertEqual(runner.context.dispatch_budget, 0)

    def test_manual_priority_requires_a_fresh_frame_after_recovery(self):
        guard = ToggleGuard(paused=True)
        engine = TEKEngine(
            RETRIBUTION_V2,
            ProfileResolver.from_file(LAPTOP),
            input_dispatcher=SentDispatcher(),
            physical_input_guard=guard,
        )
        context = SafetyContext(bootstrapped=True, current_session_epoch=1)
        paused_frame = v3_frame(40, 100)
        paused = engine.process_frame(paused_frame, context)
        self.assertEqual(paused.reason, "physical_input_pause")
        self.assertEqual(context.last_frame_freshness_counter, 100)

        guard.paused = False
        stale = engine.process_frame(paused_frame, context)
        self.assertEqual(stale.reason, "stale_frame_freshness")

        fresh = engine.process_frame(v3_frame(40, 101), context)
        self.assertEqual(fresh.reason, "input_sent")


if __name__ == "__main__":
    unittest.main()
