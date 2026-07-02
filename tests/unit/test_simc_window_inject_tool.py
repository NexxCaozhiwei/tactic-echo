from __future__ import annotations

import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from zipfile import ZipFile

from tools.simc_window_inject.core import SimcParserError, build_reports, run_parser
from tools.simc_window_inject.simc_window_inject import _download_simc_archive


ASSISTED = """
# Official Assisted Combat source
actions=auto_attack
actions+=/call_action_list,name=assisted_combat
actions.assisted_combat=major_power
actions.assisted_combat+=/window_strike,if=resource>=2
actions.assisted_combat+=/filler
"""

DEFAULT = """
actions=auto_attack
actions+=/call_action_list,name=cooldowns
actions+=/call_action_list,name=generators
actions.cooldowns=major_power,if=cooldown.window_strike.remains=0
actions.cooldowns+=/use_item,slot=trinket1,if=buff.major_power.up
actions.cooldowns+=/potion,if=buff.major_power.up
actions.cooldowns+=/blood_fury,if=buff.major_power.up
actions.generators=window_strike
actions.generators+=/filler
"""


class SimcWindowInjectToolTests(unittest.TestCase):
    def _tree(self, root: Path) -> Path:
        apl = root / "ActionPriorityLists"
        (apl / "assisted_combat").mkdir(parents=True)
        (apl / "default").mkdir(parents=True)
        (apl / "assisted_combat" / "paladin_retribution.simc").write_text(ASSISTED, encoding="utf-8")
        (apl / "default" / "paladin_retribution.simc").write_text(DEFAULT, encoding="utf-8")
        return root


    @staticmethod
    def _zip_payload(members: dict[str, str]) -> bytes:
        stream = io.BytesIO()
        with ZipFile(stream, "w") as archive:
            for name, value in members.items():
                archive.writestr(name, value)
        return stream.getvalue()

    def test_download_extracts_official_archive_to_cache_when_mocked(self):
        payload = self._zip_payload({
            "simc-midnight/ActionPriorityLists/default/mage_fire.simc": "actions=fireball\n",
            "simc-midnight/ActionPriorityLists/assisted_combat/mage_fire.simc": "actions.assisted_combat=fireball\n",
        })
        response = MagicMock()
        response.read.return_value = payload
        context = MagicMock()
        context.__enter__.return_value = response
        context.__exit__.return_value = False
        with tempfile.TemporaryDirectory() as directory:
            with patch("tools.simc_window_inject.simc_window_inject.urlopen", return_value=context):
                destination = _download_simc_archive(Path(directory), "midnight")
            self.assertTrue((destination / "ActionPriorityLists" / "default" / "mage_fire.simc").is_file())

    def test_download_rejects_archive_path_escape(self):
        payload = self._zip_payload({
            "simc-midnight/../escape.txt": "no",
        })
        response = MagicMock()
        response.read.return_value = payload
        context = MagicMock()
        context.__enter__.return_value = response
        context.__exit__.return_value = False
        with tempfile.TemporaryDirectory() as directory:
            with patch("tools.simc_window_inject.simc_window_inject.urlopen", return_value=context):
                with self.assertRaises(SimcParserError):
                    _download_simc_archive(Path(directory), "midnight")

    def test_build_reports_uses_assisted_for_windows_and_cooldowns_for_injects(self):
        with tempfile.TemporaryDirectory() as directory:
            reports, manifest = build_reports(self._tree(Path(directory)))

        self.assertEqual(1, len(reports))
        report = reports[0]
        self.assertEqual("paladin_retribution", report.spec_key)
        self.assertEqual(["window_strike", "filler"], [item.action for item in report.windows])
        self.assertEqual(
            ["major_power", "use_item", "potion", "blood_fury"],
            [item.action for item in report.injects],
        )
        self.assertEqual(["spell", "trinket1", "potion", "racial"], [item.inject_type for item in report.injects])
        self.assertEqual(["major_power", "trinket1", "potion", "blood_fury"], [item.candidate_key for item in report.injects])
        major_hint = next(item for item in report.pair_hints if item["inject"] == "major_power")
        self.assertEqual(["window_strike"], major_hint["linked_windows"])
        trinket_hint = next(item for item in report.pair_hints if item["inject"] == "trinket1")
        self.assertEqual(["major_power"], trinket_hint["linked_injects"])
        self.assertIn("ActionPriorityLists", manifest["apl_root"])

    def test_run_parser_writes_all_review_products(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._tree(Path(directory) / "simc")
            output = Path(directory) / "out"
            paths = run_parser(root, output)
            for path in paths.values():
                self.assertTrue(path.is_file(), path)
            payload = json.loads(paths["candidates_json"].read_text(encoding="utf-8"))
            self.assertEqual("review_only_window_inject_candidates", payload["purpose"])
            self.assertEqual("PALADIN_3", payload["specs"][0]["te_profile_key"])
            review = paths["review_txt"].read_text(encoding="utf-8")
            self.assertIn("窗口技能候选", review)
            self.assertIn("window_strike", review)
            lua_seed = paths["review_lua_seed"].read_text(encoding="utf-8")
            self.assertIn("REVIEW ONLY", lua_seed)
            self.assertNotIn("spellID =", lua_seed)

    def test_overrides_can_confirm_pair_without_reclassifying_runtime_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._tree(Path(directory) / "simc")
            override = Path(directory) / "overrides.json"
            override.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "spec_overrides": {
                            "paladin_retribution": {
                                "window": {"include": ["manual_window"], "exclude": ["filler"]},
                                "inject": {"include": [], "exclude": []},
                                "pairs": [
                                    {
                                        "window": "window_strike",
                                        "injects": ["major_power", "potion"],
                                        "readiness_mode": "any_ready",
                                        "min_ready_injects": 1,
                                        "order": "pre",
                                    }
                                ],
                                "notes": "test override",
                            }
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            reports, _ = build_reports(root, overrides_path=override)

        report = reports[0]
        self.assertEqual(["window_strike", "manual_window"], [item.action for item in report.windows])
        self.assertEqual("window_strike", report.override_pairs[0]["window"])
        self.assertEqual("pre", report.override_pairs[0]["order"])
        self.assertIn("test override", report.notes)

    def test_unknown_selected_spec_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._tree(Path(directory))
            with self.assertRaises(SimcParserError):
                build_reports(root, selected_specs=["mage_fire"])


    def test_windows_runner_scripts_are_ascii_crlf_and_block_free(self):
        runners = {
            "RUN_SIMC_WINDOW_INJECT.CMD": b"--simc-root",
            "RUN_SIMC_WINDOW_INJECT_DOWNLOAD.CMD": b"--download",
        }
        tool_dir = Path(__file__).resolve().parents[2] / "tools" / "simc_window_inject"
        for name, required_argument in runners.items():
            payload = (tool_dir / name).read_bytes()
            self.assertTrue(payload.isascii(), name)
            self.assertIn(b"\r\n", payload, name)
            self.assertNotIn(b"\n", payload.replace(b"\r\n", b""), name)
            self.assertNotIn(b"(", payload, name)
            self.assertNotIn(b")", payload, name)
            self.assertIn(b"setlocal DisableDelayedExpansion", payload, name)
            self.assertIn(b"where py >nul 2>nul", payload, name)
            self.assertIn(required_argument, payload, name)
            self.assertIn(b"pause\r\nexit /b %EXIT_CODE%\r\n", payload, name)


if __name__ == "__main__":
    unittest.main()
