import unittest

from tek.src.te_savedvariables import latest_signal_from_text, signal_by_sequence_from_text, signal_records_from_text


SAVED_VARIABLES = '''
TacticEchoDB = {
["signal"] = {
["frames"] = {
{
["checksum"] = 20,
["sequence"] = 7,
["actionId"] = "PALADIN_RETRIBUTION_JUDGMENT",
["fields"] = {
84,
69,
1,
1,
1,
7,
0,
20,
},
["actionCode"] = 1,
["spellID"] = 20271,
},
{
["schemaVersion"] = 1,
["component"] = "TE",
["eventType"] = "signal_frame",
["checksum"] = 30,
["sequence"] = 8,
["actionId"] = "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE",
["actionCode"] = 2,
["spellID"] = 184575,
},
},
["bySequence"] = {
["28"] = {
["schemaVersion"] = 1,
["component"] = "TE",
["eventType"] = "signal_frame",
["checksum"] = 186,
["sequence"] = 28,
["actionId"] = "PALADIN_RETRIBUTION_FINAL_VERDICT",
["actionCode"] = 9,
["spellID"] = 383328,
},
},
},
}
'''


class TESavedVariablesTests(unittest.TestCase):
    def test_extracts_signal_records(self):
        records = signal_records_from_text(SAVED_VARIABLES)

        self.assertEqual(len(records), 2)
        self.assertEqual(records[0]["sequence"], 7)
        self.assertEqual(records[0]["schemaVersion"], 1)
        self.assertEqual(records[0]["component"], "TE")

    def test_reads_latest_signal(self):
        record = latest_signal_from_text(SAVED_VARIABLES)

        self.assertEqual(record["sequence"], 8)
        self.assertEqual(record["actionCode"], 2)
        self.assertEqual(record["actionId"], "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE")

    def test_reads_signal_by_sequence_from_bounded_frames(self):
        record = signal_by_sequence_from_text(SAVED_VARIABLES, 8)

        self.assertEqual(record["sequence"], 8)
        self.assertEqual(record["actionCode"], 2)
        self.assertEqual(record["actionId"], "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE")

    def test_missing_sequence_returns_none_without_by_sequence_index(self):
        self.assertIsNone(signal_by_sequence_from_text(SAVED_VARIABLES, 28))


if __name__ == "__main__":
    unittest.main()
