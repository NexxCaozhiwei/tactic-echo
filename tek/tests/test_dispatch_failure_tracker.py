import unittest

from tek.src.dispatch_failure_tracker import DispatchFailureTracker


class DispatchFailureTrackerTests(unittest.TestCase):
    def test_three_failures_inside_five_seconds_lock(self):
        now = [10.0]
        tracker = DispatchFailureTracker(threshold=3, window_seconds=5, clock=lambda: now[0])
        self.assertFalse(tracker.record_failure()[0])
        now[0] += 1
        self.assertFalse(tracker.record_failure()[0])
        now[0] += 1
        self.assertTrue(tracker.record_failure()[0])

    def test_success_clears_failure_window(self):
        now = [10.0]
        tracker = DispatchFailureTracker(threshold=3, window_seconds=5, clock=lambda: now[0])
        tracker.record_failure()
        tracker.record_failure()
        tracker.record_success()
        self.assertFalse(tracker.record_failure()[0])
        self.assertEqual(tracker.snapshot()["recent_failures"], 1)


    def test_reset_clears_failure_window(self):
        tracker = DispatchFailureTracker()
        tracker.record_failure()
        tracker.record_failure()
        tracker.reset()
        self.assertEqual(tracker.snapshot()["recent_failures"], 0)
