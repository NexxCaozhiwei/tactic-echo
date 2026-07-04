from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


class AutoBurstOrderedTrinketContractTests(unittest.TestCase):
    def test_trinkets_are_stable_optional_steps_not_global_manual_rule_fields(self) -> None:
        defaults = read("Config/Defaults.lua")
        normalize = read("Config/Normalize.lua")
        profiles = read("Tactics/BurstProfiles.lua")
        auto = read("Tactics/AutoBurst.lua")
        self.assertNotIn("autoBurstInjectionKind", defaults)
        self.assertNotIn("autoBurstInjectionTrinketSlot", defaults)
        self.assertIn("tactics.autoBurstInjectionKind = nil", normalize)
        self.assertIn('"trinket:13"', profiles)
        self.assertIn('"trinket:14"', profiles)
        self.assertIn("SetAutoBurstTrinketOffGCD", profiles)
        self.assertIn("inventorySlot = slot", auto)
        self.assertIn("windowSpellID", auto)

    def test_inventory_step_reuses_existing_binding_token_and_exact_slot_item_confirmation(self) -> None:
        resolver = read("Actions/ActionBarBindingResolver.lua")
        icon = read("Tactics/IconState.lua")
        cooldown = read("Tactics/CooldownResolver.lua")
        auto = read("Tactics/AutoBurst.lua")
        signal = read("Signal/SignalFrame.lua")
        self.assertIn("function Resolver:ResolveInventorySlot(slot, expectedItemID)", resolver)
        self.assertIn("currentInventoryItemID(slot)", resolver)
        self.assertIn('reason = "inventory_equipment_changed"', resolver)
        self.assertIn("function IconState:CollectInventoryCooldownOnly", icon)
        self.assertIn("function Resolver:GetInventoryLive(slot, expectedItemID)", cooldown)
        self.assertIn("ResolveInventorySlot", auto)
        self.assertIn("CollectInventoryCooldownOnly", auto)
        self.assertIn("inventoryEquipmentChanged", auto)
        self.assertIn("expectedItemID = itemID", auto)
        self.assertIn("dispatchInventorySlot", signal)
        self.assertIn("dispatchItemID", signal)
        self.assertNotIn("SendInput(", auto)

    def test_preflight_and_runtime_revalidation_keep_cd_and_gcd_semantics_strict(self) -> None:
        auto = read("Tactics/AutoBurst.lua")
        self.assertIn("preflightSequence", auto)
        self.assertIn("isDispatchablePhase", auto)
        self.assertIn("GCD_LOCKED", auto)
        self.assertIn("QUEUE_WINDOW", auto)
        self.assertIn("cooldownUncertain", auto)
        self.assertIn("sequence_optional_step_skipped", auto)
        self.assertIn("focused_optional_step_unavailable", auto)
        self.assertIn("offGCDExplicit == true", auto)
        self.assertIn("It is never inferred", auto)

    def test_inventory_macro_rejects_dual_trinket_slots_but_allows_one_explicit_slot(self) -> None:
        macro = read("Actions/MacroSemantics.lua")
        resolver = read("Actions/ActionBarBindingResolver.lua")
        self.assertIn("function MacroSemantics:MatchInventorySlot", macro)
        self.assertIn('"macro_multiple_trinket_slots"', macro)
        self.assertIn("inventoryMacroMatches", resolver)
        self.assertIn("macroByInventorySlot", resolver)
        self.assertIn("item_slot", macro)
        self.assertIn("slot ~= 13 and slot ~= 14", resolver)

    def test_teab_exposes_only_runtime_toggle_not_hand_entered_spellid_rules(self) -> None:
        diagnostics = read("UI/Diagnostics.lua")
        self.assertIn("/teab status|on|off", diagnostics)
        self.assertNotIn("trinket <官方窗口SpellID>", diagnostics)
        self.assertNotIn("autoBurstInjectionKind", diagnostics)
        self.assertIn("爆发窗口、注入技能、饰品和顺序", diagnostics)


if __name__ == "__main__":
    unittest.main()
