from __future__ import annotations

import unittest

from tek.src.sampler_benchmark import benchmark_sampler
from tek.src.screen_sampler import SignalLayout
from tek.src.teap import encode_fields_v3
from tek.src.visual_decoder import encode_test_blocks


class P4CBenchmarkTests(unittest.TestCase):
    def test_benchmark_collects_only_sampler_timing_and_sends_no_input(self):
        ticks = iter((0.0, 0.0, 0.001, 0.002, 0.004, 0.006, 0.009, 0.012, 0.016, 0.020))

        class Sampler:
            backend = "fake"
            capture_mode = "test"
            def __init__(self):
                self.calls = 0
            def sample(self, layout):
                self.calls += 1
                return encode_test_blocks(encode_fields_v3(action_code=1, sequence=self.calls, frame_freshness_counter=self.calls))

        sampler = Sampler()
        result = benchmark_sampler(
            sampler,
            layout=SignalLayout(),
            iterations=3,
            warmup_iterations=1,
            clock=lambda: next(ticks),
        )
        self.assertEqual(sampler.calls, 4)
        self.assertEqual(result.iterations, 3)
        self.assertEqual(result.backend, "fake")
        self.assertGreaterEqual(result.average_ms, 0.0)
        self.assertGreaterEqual(result.p95_ms, 0.0)


if __name__ == "__main__":
    unittest.main()
