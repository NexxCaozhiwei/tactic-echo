from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TOC = ADDON / "!TacticEcho.toc"


class MappingExportContractTests(unittest.TestCase):
    def test_mapping_export_and_debug_ui_are_not_loaded(self):
        toc = TOC.read_text(encoding="utf-8")
        self.assertNotIn("Diagnostics/MappingExport.lua", toc)
        self.assertNotIn("UI/Diagnostics.lua", toc)
        self.assertNotIn("Recommendation/OfficialApiProbe.lua", toc)

    def test_historical_export_source_remains_read_only_if_inspected(self):
        source = (ADDON / "Diagnostics" / "MappingExport.lua").read_text(encoding="utf-8")
        self.assertNotIn("SetBinding(", source)
        self.assertNotIn("SaveBindings(", source)
        self.assertNotIn("macroBody =", source)
        self.assertNotIn("body = entry.macroBody", source)


if __name__ == "__main__":
    unittest.main()
