from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class SpecAwareDefenseBindingContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.profiles = (ADDON / "Tactics" / "AbilityProfiles.lua").read_text(encoding="utf-8")
        self.planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        self.resolver = (ADDON / "Actions" / "ActionBarBindingResolver.lua").read_text(encoding="utf-8")
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.styles = (ADDON / "UI" / "TacticalHudStyles.lua").read_text(encoding="utf-8")

    def test_retribution_profile_stays_separate_from_protection_only_tools(self) -> None:
        self.assertIn("PALADIN_3", self.profiles)
        ret_body = self.profiles.split("PALADIN_3", 1)[1].split("PRIEST_1", 1)[0]
        self.assertIn("184662", ret_body)
        self.assertNotIn("31850", ret_body)
        self.assertNotIn("86659", ret_body)
        self.assertIn("PALADIN_2", self.profiles)
        self.assertIn("31850", self.profiles)
        self.assertIn("86659", self.profiles)

    def test_defensive_profile_resolution_is_explicit_spec_only(self) -> None:
        self.assertIn("one explicit profile for every playable specialization", self.profiles)
        self.assertIn("function AbilityProfiles:GetDefensiveGroups(classFile, specIndex)", self.profiles)
        self.assertIn('source = overridden and "spec_registry_profile_order" or "spec_registry"', self.profiles)
        self.assertIn('source = "missing_spec_registry"', self.profiles)
        self.assertNotIn('source = "class_fallback"', self.profiles)
        self.assertIn("GetDefensiveGroups(classFile, context and context.specIndex)", self.planner)

    def test_advisory_prefers_real_binding_over_unbound_fallback(self) -> None:
        self.assertIn("local firstUnbound = nil", self.planner)
        self.assertIn("if binding then return item end", self.planner)
        self.assertIn("if not firstUnbound then firstUnbound = item end", self.planner)
        self.assertIn("known ~= false", self.planner)
        self.assertIn("defensiveProfileKey", self.planner)

    def test_secondary_binding_is_explicitly_scanned(self) -> None:
        self.assertIn("local function resolveBindingPair(primaryBinding, secondaryBinding)", self.resolver)
        self.assertIn("for bindingIndex = 1, 2 do", self.resolver)
        self.assertIn("if bindingIndex == 1 then", self.resolver)
        self.assertIn("candidateBinding = secondaryBinding", self.resolver)
        self.assertNotIn("local bindingKeys = { primaryBinding, secondaryBinding }", self.resolver)
        self.assertIn("bindingSourceIndex", self.resolver)
        self.assertIn("valid ALT+Q/CTRL+Q mapping", self.resolver)

    def test_valid_mapping_outranks_unbound_duplicate(self) -> None:
        self.assertIn("if (left.parsed ~= nil) ~= (right.parsed ~= nil) then", self.resolver)
        self.assertIn("return left.parsed ~= nil", self.resolver)

    def test_icon_effects_are_external_atlas_frames_not_icon_tints(self) -> None:
        effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        self.assertIn("rotationhelper_ants_flipbook", effects)
        self.assertIn("UI-HUD-ActionBar-Proc-Loop-Flipbook", effects)
        self.assertIn("UI-HUD-ActionBar-Channel-Fill", effects)
        self.assertIn("TacticalIconEffects.lua", self.icon)
        self.assertNotIn("card.glow = card:CreateTexture", self.icon)
        self.assertNotIn("card.proc = card:CreateTexture", self.icon)
        self.assertIn("setIcon(card, texture)", self.icon)
        self.assertIn("card.icon.SetVertexColor", self.icon)


if __name__ == "__main__":
    unittest.main()
