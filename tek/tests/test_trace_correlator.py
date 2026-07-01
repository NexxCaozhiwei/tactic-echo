import unittest

from tek.src.trace_correlator import correlate


TE_SIGNAL = {
    "schemaVersion": 1,
    "component": "TE",
    "eventType": "signal_frame",
    "protocolVersion": 3,
    "sessionEpoch": 7,
    "catalogFingerprint": 21881,
    "sequence": 42,
    "actionCode": 1,
    "actionId": "PALADIN_RETRIBUTION_JUDGMENT",
}

TEK_TRACE = {
    "schemaVersion": 1,
    "component": "TEK",
    "eventType": "input_dispatch",
    "protocol_version": 3,
    "session_epoch": 7,
    "catalog_fingerprint": 21881,
    "sequence": 42,
    "action_code": 1,
    "action_id": "PALADIN_RETRIBUTION_JUDGMENT",
}


class TraceCorrelatorTests(unittest.TestCase):
    def test_matches_te_and_tek_records(self):
        result = correlate(TE_SIGNAL, TEK_TRACE)

        self.assertTrue(result.matched)
        self.assertEqual(result.reason, "matched")
        self.assertEqual(result.sequence, 42)
        self.assertEqual(result.action_id, "PALADIN_RETRIBUTION_JUDGMENT")

    def test_reports_sequence_mismatch(self):
        tek = dict(TEK_TRACE)
        tek["sequence"] = 41

        result = correlate(TE_SIGNAL, tek)

        self.assertFalse(result.matched)
        self.assertEqual(result.reason, "sequence_mismatch:42:41")

    def test_reports_action_code_mismatch(self):
        tek = dict(TEK_TRACE)
        tek["action_code"] = 2

        result = correlate(TE_SIGNAL, tek)

        self.assertFalse(result.matched)
        self.assertEqual(result.reason, "action_code_mismatch:1:2")

    def test_reports_action_id_mismatch(self):
        tek = dict(TEK_TRACE)
        tek["action_id"] = "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE"

        result = correlate(TE_SIGNAL, tek)

        self.assertFalse(result.matched)
        self.assertEqual(result.reason, "action_id_mismatch:PALADIN_RETRIBUTION_JUDGMENT:PALADIN_RETRIBUTION_BLADE_OF_JUSTICE")


if __name__ == "__main__":
    unittest.main()
