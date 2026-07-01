from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "scripts" / "build-tek-exe.ps1"
VERIFY = ROOT / "scripts" / "verify-tek-sendinput.ps1"
PACKAGE = ROOT / "scripts" / "package-tek-release.ps1"
APP_MAIN = ROOT / "tek" / "app" / "main.py"
BASELINE_VERIFY = ROOT / "scripts" / "verify-baseline-contract.py"


class WindowsPackagingContractTests(unittest.TestCase):
    def test_build_includes_assets_tests_and_manifest(self):
        source = BUILD.read_text(encoding="utf-8")
        self.assertIn("tek\\assets", source)
        self.assertIn("examples\\profiles", source)
        self.assertIn("unittest discover -s tek/tests", source)
        self.assertIn("TEK-build-manifest.json", source)
        self.assertIn("Get-FileHash", source)

    def test_build_stages_output_and_preserves_a_locked_primary_target(self):
        source = BUILD.read_text(encoding="utf-8")
        for token in (
            "Test-FileExclusiveAccess",
            "Stop-ExactTargetTekProcess",
            "build\\tek-stage-",
            "Publish-OneFileArtifact",
            "TEK.new.exe",
            "fallback_locked_target",
            "standardOutput",
            "publishState",
        ):
            self.assertIn(token, source)

    def test_build_script_uses_braced_variables_before_literal_colons(self):
        source = BUILD.read_text(encoding="utf-8")
        self.assertNotIn("$BackupPath:", source)
        self.assertIn("${BackupPath}:", source)

    def test_real_sendinput_gate_targets_notepad_and_requires_visual_confirmation(self):
        source = VERIFY.read_text(encoding="utf-8")
        self.assertIn("notepad.exe", source)
        self.assertIn("I_UNDERSTAND_TEK_SENDS_A_TEST_KEY", source)
        self.assertIn("Type YES", source)
        self.assertIn("must never be a WoW process", source)
        self.assertIn("--sendinput-acceptance", source)

    def test_exe_entry_exposes_explicit_acceptance_mode(self):
        source = APP_MAIN.read_text(encoding="utf-8")
        self.assertIn("--sendinput-acceptance", source)
        self.assertIn("write_acceptance_evidence", source)
        self.assertIn("run_sendinput_acceptance", source)

    def test_release_script_packages_only_target_addon_and_exe(self):
        source = PACKAGE.read_text(encoding="utf-8")
        self.assertIn("addon\\!TacticEcho", source)
        self.assertIn("TEK.exe", source)
        self.assertNotIn("TBSeek", source)

    def test_build_runs_baseline_contract_and_pytest(self):
        source = BUILD.read_text(encoding="utf-8")
        self.assertIn("verify-baseline-contract.py --repo-root", source)
        self.assertIn("-m pytest -q tek/tests tests/unit", source)

    def test_release_package_selects_matching_fallback_manifest_and_checks_archive(self):
        source = PACKAGE.read_text(encoding="utf-8")
        self.assertIn("GetFileNameWithoutExtension($TekExe)", source)
        self.assertIn("--archive $OutputPath --expect-root \"TacticEcho\" --release-package", source)
        self.assertTrue(BASELINE_VERIFY.is_file())


if __name__ == "__main__":
    unittest.main()
