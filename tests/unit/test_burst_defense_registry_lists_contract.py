from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class BurstDefenseRegistryListsContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.burst_profiles = (ADDON / "Tactics" / "BurstProfiles.lua").read_text(encoding="utf-8")
        self.burst_planner = (ADDON / "Tactics" / "BurstPlanner.lua").read_text(encoding="utf-8")
        state_path = ADDON / "Tactics" / "BurstStateMachine.lua"
        self.burst_state = state_path.read_text(encoding="utf-8") if state_path.exists() else ""
        self.ability_profiles = (ADDON / "Tactics" / "AbilityProfiles.lua").read_text(encoding="utf-8")
        self.defense_planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        self.ui = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")

    def test_every_playable_specialization_has_explicit_burst_profile_metadata(self) -> None:
        expected = {
            "DEATHKNIGHT": [250, 251, 252],
            "DEMONHUNTER": [577, 581, 1480],
            "DRUID": [102, 103, 104, 105],
            "EVOKER": [1467, 1468, 1473],
            "HUNTER": [253, 254, 255],
            "MAGE": [62, 63, 64],
            "MONK": [268, 270, 269],
            "PALADIN": [65, 66, 70],
            "PRIEST": [256, 257, 258],
            "ROGUE": [259, 260, 261],
            "SHAMAN": [262, 263, 264],
            "WARLOCK": [265, 266, 267],
            "WARRIOR": [71, 72, 73],
        }
        for class_file, spec_ids in expected.items():
            for spec_index, spec_id in enumerate(spec_ids, start=1):
                marker = (
                    f'{class_file}_{spec_index} = {{ classFile = "{class_file}", '
                    f"specIndex = {spec_index}, specID = {spec_id},"
                )
                self.assertIn(marker, self.burst_profiles)
        self.assertEqual(sum(map(len, expected.values())), 40)

    def test_justac_seeds_are_normalized_and_eye_of_tyr_is_corrected_before_registry_use(self) -> None:
        for marker in (
            "REFERENCE_TRIGGER_SEEDS",
            "REFERENCE_INJECTION_SEEDS",
            "REFERENCE_DURATION_SEEDS",
            "TRIGGER_AURA_OVERRIDES",
            "reference_spell_seed_explicit_spec",
            "PALADIN_2 = { 387174 }",
            "The reference seed placed Eye of Tyr (387174) under the wrong specialization",
        ):
            self.assertIn(marker, self.burst_profiles)
        injection_section = self.burst_profiles.split("local REFERENCE_INJECTION_SEEDS", 1)[1].split("local REFERENCE_DURATION_SEEDS", 1)[0]
        self.assertNotIn("PALADIN_1 = { 387174 }", injection_section)

    def test_burst_lists_support_current_spec_reorder_enable_custom_add_and_reset(self) -> None:
        for marker in (
            "function BurstProfiles:GetEditableList(context, kind)",
            "function BurstProfiles:Move(context, kind, spellID, delta)",
            "function BurstProfiles:SetEnabled(context, kind, spellID, enabled)",
            "function BurstProfiles:RemoveCustom(context, kind, spellID)",
            "function BurstProfiles:AddCustom(context, kind, spellID)",
            "function BurstProfiles:RestoreDefaults(context)",
            "currentSpecKnown(spellID)",
            "当前专精未确认该技能已学会",
        ):
            self.assertIn(marker, self.burst_profiles)

    def test_burst_planner_is_a_pure_autoburst_hud_adapter_without_input_capability(self) -> None:
        for marker in (
            "Pure HUD projection adapter",
            "AutoBurst owns burst sequence, binding, cooldown and confirmation snapshots",
            "TE.AutoBurst.BuildHudSnapshot",
            "autoburst_snapshot_adapter",
            "advisoryOnly = true",
            "displayOnly = true",
        ):
            self.assertIn(marker, self.burst_planner)
        for forbidden in ("ResolveSpell", "CollectCooldownOnly", "BindingToken", "SendInput"):
            self.assertNotIn(forbidden, self.burst_planner)

    def test_empty_justac_seed_is_explicitly_suppressed_not_replaced_with_guesswork(self) -> None:
        self.assertIn("if profile.noSeedNotice then", self.burst_profiles)
        self.assertIn("#triggerEntries == 0 and #injectionEntries == 0", self.burst_profiles)
        self.assertIn("列表保持为空", self.burst_profiles)

    def test_defense_uses_single_current_spec_priority_list_without_special_case(self) -> None:
        for marker in (
            "defensivePriorityOverrides",
            "GetDefensivePriorityList(classFile, specIndex)",
            "GetEditableDefensivePriority(context)",
            "MoveDefensivePriority(context, spellID, delta)",
            "SetDefensivePriorityEnabled(context, spellID, enabled)",
            "RestoreDefensivePriority(context)",
            "spell_not_in_current_spec_defense_registry",
        ):
            self.assertIn(marker, self.ability_profiles)
        defense_body = self.defense_planner.split("function Planner:BuildDefense", 1)[1].split("function Planner:BuildBurst", 1)[0]
        self.assertIn("GetDefensivePriorityList(classFile, context and context.specIndex)", defense_body)
        self.assertIn("bindingToken = 0", defense_body)
        self.assertNotIn("ALT+Q", defense_body)
        self.assertNotIn("403876", defense_body)

    def test_teui_has_current_spec_autoburst_editor_without_retired_defense_editor(self) -> None:
        for marker in (
            "自动爆发",
            "注入技能",
            "爆发顺序",
        ):
            self.assertIn(marker, self.ui)
        for retired in ("防御优先列表", "恢复当前专精防御默认"):
            self.assertNotIn(retired, self.ui)


if __name__ == "__main__":
    unittest.main()
