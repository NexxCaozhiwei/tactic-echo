import unittest
from pathlib import Path

from tek.src.profile_resolver import ProfileError, ProfileResolver, assert_no_numpad
from tek.src.action_catalog import RETRIBUTION_V2


ROOT = Path(__file__).resolve().parents[2]
LAPTOP = ROOT / "examples" / "profiles" / "laptop.json"
DESKTOP = ROOT / "examples" / "profiles" / "desktop-numpad.json"


class ProfileResolverTests(unittest.TestCase):
    def test_laptop_profile_is_generic_binding_token_profile(self):
        resolver = ProfileResolver.from_file(LAPTOP)
        assert_no_numpad(resolver.profile)

        self.assertEqual(resolver.profile.catalog_version, RETRIBUTION_V2.version)
        self.assertEqual(resolver.profile.catalog_fingerprint, RETRIBUTION_V2.fingerprint)
        self.assertEqual(resolver.profile.bindings, {})
        self.assertTrue(resolver.profile.runnable)

    def test_desktop_profile_no_longer_carries_numpad_action_bindings(self):
        resolver = ProfileResolver.from_file(DESKTOP)

        self.assertEqual(resolver.profile.bindings, {})
        self.assertTrue(resolver.profile.runnable)

    def test_missing_action_reports_unbound(self):
        resolver = ProfileResolver.from_file(LAPTOP)

        with self.assertRaisesRegex(ProfileError, "action_unbound:UNKNOWN_ACTION"):
            resolver.resolve("UNKNOWN_ACTION")

    def test_legacy_action_profile_is_accepted_but_bindings_are_ignored(self):
        from tek.src.profile_resolver import load_profile

        data = {
            "schemaVersion": 1,
            "catalogVersion": 1,
            "catalogFingerprint": "stale-catalog",
            "profileId": "legacy",
            "profileFingerprint": "legacy",
            "bindings": {
                "LEGACY_ACTION_A": "SHIFT+Z",
                "LEGACY_ACTION_B": "SHIFT+X",
            },
        }

        profile = load_profile(data)

        self.assertEqual(profile.catalog_version, RETRIBUTION_V2.version)
        self.assertEqual(profile.catalog_fingerprint, RETRIBUTION_V2.fingerprint)
        self.assertEqual(profile.bindings, {})


if __name__ == "__main__":
    unittest.main()
