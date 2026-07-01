from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class SpecDefenseRegistryCooldownContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.profiles = (ADDON / "Tactics" / "AbilityProfiles.lua").read_text(encoding="utf-8")
        self.planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")

    def test_every_supported_class_spec_has_an_explicit_defense_profile(self) -> None:
        expected = {
            "DEATHKNIGHT": 3, "DEMONHUNTER": 2, "DRUID": 4, "EVOKER": 3,
            "HUNTER": 3, "MAGE": 3, "MONK": 3, "PALADIN": 3,
            "PRIEST": 3, "ROGUE": 3, "SHAMAN": 3, "WARLOCK": 3,
            "WARRIOR": 3,
        }
        for class_file, count in expected.items():
            for spec_index in range(1, count + 1):
                self.assertRegex(self.profiles, rf"\b{class_file}_{spec_index}\s*=")
        self.assertNotRegex(self.profiles, r"(?m)^\s{4}[A-Z]+\s*=\s*\{[^\n]*selfheal")

    def test_no_planner_spell_or_class_special_case_remains(self) -> None:
        planner_body = self.planner.split("function Planner:BuildDefense", 1)[1]
        self.assertNotIn("Retribution Paladin", planner_body)
        self.assertNotIn("ALT+Q", planner_body)
        self.assertNotIn("403876", planner_body)
        self.assertIn("current explicit", planner_body)
        self.assertIn("GetDefensiveGroups(classFile, context and context.specIndex)", planner_body)

    def test_profile_override_can_reorder_but_not_inject_cross_spec_spells(self) -> None:
        for marker in (
            "defensiveProfileOverrides",
            "applyDefensiveOrderOverride",
            "local function defenseEntry(spellID, category, priority, conditions)",
            "spellID = tonumber(spellID)",
            "type = category",
            "priority = tonumber(priority) or 1",
            "conditions = copyConditions(selected)",
            "allowed[spellID] = entry",
            "if entry and not used[spellID] then",
            "spell injection is rejected by construction.",
        ):
            self.assertIn(marker, self.profiles)

    def test_protected_cooldowns_use_duration_objects_in_native_ui_layer(self) -> None:
        for marker in (
            "local function showDurationObjectCooldown",
            "C_Spell.GetSpellCooldownDuration",
            "frame:SetCooldownFromDurationObject(duration, true)",
            "ignoreGCD == true",
            "card.cooldownRenderMode",
            "技能 DurationObject 原生 CD",
        ):
            self.assertIn(marker, self.icon)
        self.assertNotIn("frame:SetCooldown(info.startTime, info.duration", self.icon)
        self.assertNotIn("cooldownVisualStart", self.icon)
        self.assertNotIn("cooldownVisualDuration", self.icon)


if __name__ == "__main__":
    unittest.main()
