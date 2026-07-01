import unittest
from pathlib import Path

from tek.src.profile_resolver import ProfileError, ProfileResolver, assert_no_numpad


ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"
DESKTOP = ROOT / "examples" / "profiles" / "desktop-numpad.json"

RETRIBUTION_ACTIONS = [
    "PALADIN_RETRIBUTION_JUDGMENT",
    "PALADIN_RETRIBUTION_BLADE_OF_JUSTICE",
    "PALADIN_RETRIBUTION_DIVINE_STORM",
    "PALADIN_RETRIBUTION_TEMPLAR_STRIKE",
    "PALADIN_RETRIBUTION_HAMMER_OF_WRATH",
    "PALADIN_RETRIBUTION_WAKE_OF_ASHES",
    "PALADIN_RETRIBUTION_DIVINE_TOLL",
    "PALADIN_RETRIBUTION_HAMMER_OF_LIGHT",
    "PALADIN_RETRIBUTION_FINAL_VERDICT",
    "PALADIN_RETRIBUTION_EXECUTION_SENTENCE",
]


class ProfileResolverTests(unittest.TestCase):
    def test_laptop_profile_resolves_all_retribution_actions_without_numpad(self):
        resolver = ProfileResolver.from_file(LAPTOP)
        assert_no_numpad(resolver.profile)

        for action_id in RETRIBUTION_ACTIONS:
            binding = resolver.resolve(action_id)
            self.assertTrue(binding.startswith("SHIFT+"), action_id)
            self.assertNotIn("NUMPAD", binding)

    def test_desktop_profile_allows_numpad_bindings(self):
        resolver = ProfileResolver.from_file(DESKTOP)

        self.assertFalse(resolver.profile.runnable)
        for action_id in RETRIBUTION_ACTIONS:
            self.assertIn("NUMPAD", resolver.resolve(action_id))

    def test_missing_action_reports_unbound(self):
        resolver = ProfileResolver.from_file(LAPTOP)

        with self.assertRaisesRegex(ProfileError, "action_unbound:UNKNOWN_ACTION"):
            resolver.resolve("UNKNOWN_ACTION")

    def test_rejects_missing_required_action(self):
        resolver = ProfileResolver.from_file(LAPTOP)
        data = {
            "schemaVersion": 1,
            "catalogVersion": resolver.profile.catalog_version,
            "catalogFingerprint": resolver.profile.catalog_fingerprint,
            "profileId": "bad",
            "profileFingerprint": "bad",
            "bindings": dict(resolver.profile.bindings),
        }
        data["bindings"].pop(RETRIBUTION_ACTIONS[0])

        from tek.src.profile_resolver import load_profile

        with self.assertRaisesRegex(ProfileError, "missing_required_actions"):
            load_profile(data)

    def test_rejects_duplicate_physical_binding(self):
        resolver = ProfileResolver.from_file(LAPTOP)
        data = {
            "schemaVersion": 1,
            "catalogVersion": resolver.profile.catalog_version,
            "catalogFingerprint": resolver.profile.catalog_fingerprint,
            "profileId": "bad",
            "profileFingerprint": "bad",
            "bindings": dict(resolver.profile.bindings),
        }
        data["bindings"][RETRIBUTION_ACTIONS[1]] = data["bindings"][RETRIBUTION_ACTIONS[0]]

        from tek.src.profile_resolver import load_profile

        with self.assertRaisesRegex(ProfileError, "duplicate_physical_binding"):
            load_profile(data)


if __name__ == "__main__":
    unittest.main()

