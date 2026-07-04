from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class BurstDefenseRegistryListsContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.burst_profiles = (ADDON / "Tactics" / "BurstProfiles.lua").read_text(encoding="utf-8")
        self.burst_planner = (ADDON / "Tactics" / "BurstPlanner.lua").read_text(encoding="utf-8")
        self.burst_state = (ADDON / "Tactics" / "BurstStateMachine.lua").read_text(encoding="utf-8")
        self.ability_profiles = (ADDON / "Tactics" / "AbilityProfiles.lua").read_text(encoding="utf-8")
        self.defense_planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        self.ui = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")

    def test_every_playable_specialization_has_explicit_burst_profile_metadata(self) -> None:
        expected = {
            "DEATHKNIGHT": 3, "DEMONHUNTER": 2, "DRUID": 4, "EVOKER": 3,
            "HUNTER": 3, "MAGE": 3, "MONK": 3, "PALADIN": 3,
            "PRIEST": 3, "ROGUE": 3, "SHAMAN": 3, "WARLOCK": 3,
            "WARRIOR": 3,
        }
        for class_file, count in expected.items():
            for spec_index in range(1, count + 1):
                self.assertIn(f"{class_file}_{spec_index} = {{ classFile", self.burst_profiles)

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

    def test_burst_planner_has_independent_visible_hotkey_advisory_but_no_input_capability(self) -> None:
        for marker in (
            "Independent trigger recommendation",
            "even when the official primary queue does not itself recommend that spell",
            "hostileTargetState()",
            "collectSpellState(item",
            "TE.IconState:Collect(spellID, { requiresHostileTarget = true })",
            "bindingToken = 0",
            "displayOnly = true",
            "knownState(spellID)",
            "current action-bar key",
            "window = nil",
            "followups = {}",
        ):
            self.assertIn(marker, self.burst_planner)

    def test_empty_justac_seed_is_explicitly_suppressed_not_replaced_with_guesswork(self) -> None:
        self.assertIn("if profile.noSeedNotice then", self.burst_state)
        self.assertIn("intentionally sparse", self.burst_state)
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

    def test_teui_has_justac_style_burst_and_defense_editors_with_safe_boundaries(self) -> None:
        for marker in (
            "createSpellPriorityEditor",
            "官方窗口候选库",
            "注入技能",
            "防御优先列表",
            "添加触发技能",
            "添加注入技能",
            "恢复当前专精全部爆发默认",
            "恢复当前专精防御默认",
            "不能在 TEUI 手工加入其他专精技能",
            "BindingToken 固定为 0",
            '"Interface\\\\Icons\\\\INV_Misc_QuestionMark"',
        ):
            self.assertIn(marker, self.ui)


if __name__ == "__main__":
    unittest.main()
