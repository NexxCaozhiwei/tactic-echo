from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / "scripts" / "verify-baseline-contract.py"


class BaselineContractTests(unittest.TestCase):
    def test_static_baseline_contract_passes_for_current_tree(self) -> None:
        result = subprocess.run(
            [sys.executable, str(VERIFY), "--repo-root", str(ROOT)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("Baseline contract passed.", result.stdout)

    def test_single_primary_build_launcher_is_present(self) -> None:
        launcher = ROOT / "TEKEXEBUILD.CMD"
        self.assertTrue(launcher.is_file(), "TEKEXEBUILD.CMD")
        source = launcher.read_text(encoding="ascii")
        self.assertIn("build-tek-exe.ps1", source)
        self.assertIn("-PythonExe", source)



if __name__ == "__main__":
    unittest.main()
