from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / "addon" / "!TacticEcho" / "Diagnostics" / "MappingExport.lua"
TOC = ROOT / "addon" / "!TacticEcho" / "!TacticEcho.toc"
DIAGNOSTICS = ROOT / "addon" / "!TacticEcho" / "UI" / "Diagnostics.lua"


class MappingExportContractTests(unittest.TestCase):
    def test_mapping_export_is_loaded_and_user_triggerable(self):
        self.assertIn("Diagnostics/MappingExport.lua", TOC.read_text(encoding="utf-8"))
        self.assertIn('SLASH_TACTICECHOMAPPING1 = "/temapping"', DIAGNOSTICS.read_text(encoding="utf-8"))

    def test_export_is_read_only_and_omits_macro_body_field(self):
        source = EXPORT.read_text(encoding="utf-8")
        self.assertIn("TacticEchoDB.diagnostics.mappingExport", source)
        self.assertNotIn("SetBinding(", source)
        self.assertNotIn("SaveBindings(", source)
        self.assertNotIn("macroBody =", source)
        self.assertNotIn("body = entry.macroBody", source)

    def test_export_records_special_actionbar_state(self):
        source = EXPORT.read_text(encoding="utf-8")
        self.assertIn("blockedBySpecialActionBar", source)
        self.assertIn("specialActionBar", source)

    def test_export_includes_diagnostic_only_movement_binding_snapshot(self):
        source = EXPORT.read_text(encoding="utf-8")
        self.assertIn("MOVEMENT_BINDING_COMMANDS", source)
        self.assertIn("copyMovementBindings", source)
        self.assertIn("movementBindings = copyMovementBindings()", source)
        self.assertNotIn("SetBinding(", source)


if __name__ == "__main__":
    unittest.main()
