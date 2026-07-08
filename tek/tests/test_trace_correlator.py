import unittest

from tek.src.trace_correlator import correlate


TE_SIGNAL = {
    "schemaVersion": 1,
    "component": "TE",
    "eventType": "signal_frame",
    "protocolVersion": 3,
    "sessionEpoch": 7,
    "catalogFingerprint": 53253,
    "sequence": 42,
    "actionCode": 0,
    "actionId": None,
}

TEK_TRACE = {
    "schemaVersion": 1,
    "component": "TEK",
    "eventType": "input_dispatch",
    "protocol_version": 3,
    "session_epoch": 7,
    "catalog_fingerprint": 53253,
    "sequence": 42,
    "action_code": 0,
    "action_id": None,
}


class TraceCorrelatorTests(unittest.TestCase):
    def test_matches_te_and_tek_records(self):
        result = correlate(TE_SIGNAL, TEK_TRACE)

        self.assertTrue(result.matched)
        self.assertEqual(result.reason, "matched")
        self.assertEqual(result.sequence, 42)
        self.assertIsNone(result.action_id)

    def test_reports_sequence_mismatch(self):
        tek = dict(TEK_TRACE)
        tek["sequence"] = 41

        result = correlate(TE_SIGNAL, tek)

        self.assertFalse(result.matched)
        self.assertEqual(result.reason, "sequence_mismatch:42:41")

    def test_reports_action_code_mismatch(self):
        tek = dict(TEK_TRACE)
        tek["action_code"] = 1

        result = correlate(TE_SIGNAL, tek)

        self.assertFalse(result.matched)
        self.assertEqual(result.reason, "action_code_mismatch:0:1")

    def test_reports_action_id_mismatch(self):
        tek = dict(TEK_TRACE)
        tek["action_id"] = "legacy_action"

        result = correlate(TE_SIGNAL, tek)

        self.assertFalse(result.matched)
        self.assertEqual(result.reason, "action_id_mismatch:None:legacy_action")


if __name__ == "__main__":
    unittest.main()
