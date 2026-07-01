from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from tek.app.app_paths import AppPaths
from tek.app.settings_store import AppSettings, SettingsStore
from tek.runtime.runtime_status import TEKStatusSnapshot
from tek.src.diagnostic_bundle import create_diagnostic_bundle
from tek.src.te_savedvariables import mapping_export_from_text


_MAPPING_SAMPLE = r'''
TacticEchoDB = {
  ["diagnostics"] = {
    ["mappingExport"] = {
      ["schemaVersion"] = 1,
      ["component"] = "TE",
      ["eventType"] = "mapping_export",
      ["exportedAt"] = "2026-06-28 10:00:00",
      ["reason"] = "slash_mapping",
      ["cache"] = {
        ["generation"] = 8,
        ["blockedBySpecialActionBar"] = false,
        ["entries"] = 1,
      },
      ["movementBindings"] = {
        { ["command"] = "MOVEFORWARD", ["primary"] = "W", ["secondary"] = "UP" },
      },
      ["entries"] = {
        {
          ["buttonName"] = "ActionButton1",
          ["spellID"] = 20271,
          ["binding"] = "1",
          ["macroName"] = "Safe Macro",
          ["macroBody"] = "/cast forbidden",
        },
      },
    },
  },
}
'''


class DiagnosticBundleTests(unittest.TestCase):
    def test_mapping_export_parser_excludes_macro_bodies(self):
        parsed = mapping_export_from_text(_MAPPING_SAMPLE)
        self.assertEqual(parsed["eventType"], "mapping_export")
        self.assertEqual(parsed["cache"]["generation"], 8)
        self.assertEqual(parsed["entries"][0]["binding"], "1")
        self.assertNotIn("macroBody", parsed["entries"][0])
        self.assertEqual(parsed["movementBindings"][0]["command"], "MOVEFORWARD")
        self.assertEqual(parsed["movementBindings"][0]["primary"], "W")

    def test_bundle_includes_sanitized_runtime_files_and_mapping(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = AppPaths.from_root(Path(temporary) / "state")
            paths.ensure()
            store = SettingsStore(paths.settings_json)
            saved_variables = Path(temporary) / "TacticEcho.lua"
            saved_variables.write_text(_MAPPING_SAMPLE, encoding="utf-8")
            store.save(AppSettings(wow_savedvariables_path=str(saved_variables)))
            paths.tray_log.write_text("tray sample\n", encoding="utf-8")
            paths.trace_path_for_today().write_text('{"trace":true}\n', encoding="utf-8")
            profile = paths.profiles / "laptop.json"
            profile.write_text(json.dumps({"profileId": "laptop"}), encoding="utf-8")
            snapshot = TEKStatusSnapshot.stopped(log_dir=str(paths.logs))

            bundle_path, manifest = create_diagnostic_bundle(
                paths=paths,
                settings_store=store,
                status_snapshot=snapshot,
                saved_variables_path=saved_variables,
            )
            self.assertTrue(bundle_path.exists())
            self.assertTrue(manifest["mappingExportIncluded"])
            with zipfile.ZipFile(bundle_path) as archive:
                names = set(archive.namelist())
                self.assertIn("manifest.json", names)
                self.assertIn("settings.json", names)
                self.assertIn("status.json", names)
                self.assertIn("te-mapping-export.json", names)
                parsed = json.loads(archive.read("te-mapping-export.json"))
                self.assertNotIn("macroBody", parsed["entries"][0])
                self.assertNotIn("TacticEcho.lua", names)

    def test_bundle_is_created_without_mapping_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = AppPaths.from_root(Path(temporary) / "state")
            paths.ensure()
            store = SettingsStore(paths.settings_json)
            bundle_path, manifest = create_diagnostic_bundle(paths=paths, settings_store=store)
            self.assertTrue(bundle_path.exists())
            self.assertFalse(manifest["mappingExportIncluded"])
            self.assertEqual(manifest["mappingExportError"], "mapping_export_path_not_configured")


if __name__ == "__main__":
    unittest.main()
