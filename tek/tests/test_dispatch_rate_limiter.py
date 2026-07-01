import unittest

from tek.src.dispatch_rate_limiter import DispatchRateLimiter
from tek.src.input_planner import plan_binding


class DispatchRateLimiterTests(unittest.TestCase):
    def test_global_limit_is_shared_across_bindings(self):
        now = [100.0]
        limiter = DispatchRateLimiter(max_per_second=2, max_wheel_per_second=5, clock=lambda: now[0])
        self.assertTrue(limiter.allow(plan_binding("Q"))[0])
        self.assertTrue(limiter.allow(plan_binding("E"))[0])
        allowed, reason = limiter.allow(plan_binding("R"))
        self.assertFalse(allowed)
        self.assertEqual(reason, "dispatch_rate_limited:global:2")
        now[0] += 1.01
        self.assertTrue(limiter.allow(plan_binding("R"))[0])

    def test_wheel_has_stricter_sub_limit(self):
        now = [10.0]
        limiter = DispatchRateLimiter(max_per_second=10, max_wheel_per_second=2, clock=lambda: now[0])
        self.assertTrue(limiter.allow(plan_binding("MOUSEWHEELUP"))[0])
        self.assertTrue(limiter.allow(plan_binding("MOUSEWHEELDOWN"))[0])
        allowed, reason = limiter.allow(plan_binding("MOUSEWHEELUP"))
        self.assertFalse(allowed)
        self.assertEqual(reason, "dispatch_rate_limited:wheel:2")
        self.assertTrue(limiter.allow(plan_binding("Q"))[0])


    def test_reset_clears_temporary_reservations(self):
        limiter = DispatchRateLimiter(max_per_second=2, max_wheel_per_second=2)
        limiter.allow(plan_binding("Q"))
        limiter.allow(plan_binding("MOUSEWHEELUP"))
        limiter.reset()
        self.assertEqual(limiter.snapshot()["used_global"], 0)
        self.assertEqual(limiter.snapshot()["used_wheel"], 0)


class DispatchReservationTests(unittest.TestCase):
    def test_rollback_returns_only_the_provisional_slot(self):
        now = [30.0]
        limiter = DispatchRateLimiter(max_per_second=2, max_wheel_per_second=2, clock=lambda: now[0])
        reservation, reason = limiter.reserve(plan_binding("Q"))
        self.assertEqual(reason, "dispatch_rate_ok")
        self.assertIsNotNone(reservation)
        self.assertEqual(limiter.snapshot()["used_global"], 1)
        self.assertTrue(limiter.rollback(reservation))
        self.assertEqual(limiter.snapshot()["used_global"], 0)
        self.assertFalse(limiter.rollback(reservation))

    def test_allow_claim_exposes_the_same_provisional_slot_for_late_gate_rollback(self):
        limiter = DispatchRateLimiter(max_per_second=2, max_wheel_per_second=2)
        self.assertTrue(limiter.allow(plan_binding("Q"))[0])
        reservation = limiter.claim_last_allow_reservation()
        self.assertIsNotNone(reservation)
        self.assertTrue(limiter.rollback(reservation))
        self.assertEqual(limiter.snapshot()["used_global"], 0)
