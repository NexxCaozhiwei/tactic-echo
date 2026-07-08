import unittest
from pathlib import Path

from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.profile_resolver import ProfileResolver


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"


def read(path):
    return path.read_text(encoding="utf-8-sig")


class AddonTekContractTests(unittest.TestCase):
    def test_toc_loads_generic_registry_without_retired_macro_registry(self):
        toc = [line.strip() for line in read(ADDON / "!TacticEcho.toc").splitlines() if line.strip() and not line.startswith("##")]

        self.assertIn("Profiles/BindingProfile.lua", toc)
        self.assertIn("Actions/ActionRegistry.lua", toc)
        self.assertNotIn("Actions/MacroRegistry.lua", toc)
        self.assertFalse((ADDON / "Actions" / "MacroRegistry.lua").exists())

    def test_lua_action_registry_is_generic_empty_catalog(self):
        text = read(ADDON / "Actions" / "ActionRegistry.lua")

        self.assertIn("ActionRegistry.catalogVersion = 3", text)
        self.assertIn('ActionRegistry.catalogFingerprint = "d005247012f71db9"', text)
        self.assertIn("ActionRegistry.catalogFingerprint16 = 53253", text)
        self.assertNotIn("register({", text)
        self.assertNotIn("PALADIN_RETRIBUTION", text)
        self.assertEqual(RETRIBUTION_V2.version, 3)
        self.assertEqual(RETRIBUTION_V2.fingerprint, "d005247012f71db9")
        self.assertEqual(RETRIBUTION_V2.action_ids, set())

    def test_default_profile_has_no_class_specific_bindings(self):
        text = read(ADDON / "Profiles" / "BindingProfile.lua")
        tek_profile = ProfileResolver.from_file(LAPTOP).profile

        self.assertIn("BindingProfile.catalogVersion = 3", text)
        self.assertIn('BindingProfile.catalogFingerprint = "d005247012f71db9"', text)
        self.assertNotIn("PALADIN_RETRIBUTION", text)
        self.assertEqual(tek_profile.bindings, {})


if __name__ == "__main__":
    unittest.main()
