from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
RESOLVER = ADDON / "Tactics" / "CooldownResolver.lua"
PLANNER = ADDON / "Tactics" / "BurstPlanner.lua"
AUTO = ADDON / "Tactics" / "AutoBurst.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class P51TrinketCooldownContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.resolver = RESOLVER.read_text(encoding="utf-8")
        self.planner = PLANNER.read_text(encoding="utf-8")
        self.auto = AUTO.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")

    def test_inventory_entries_have_bounded_live_reprobe(self) -> None:
        for marker in (
            "INVENTORY_POLL_INTERVAL_SECONDS = 0.10",
            "pollInterval = INVENTORY_POLL_INTERVAL_SECONDS",
            "nextProbeAt",
            "pollingDue",
            "GetInventoryItemCooldown",
        ):
            self.assertIn(marker, self.resolver)

    def test_inventory_slot_is_cross_checked_with_equipped_item_id(self) -> None:
        for marker in (
            "inventoryItemID(slot)",
            "readItemApiSnapshot(currentItemID, \"inventory\")",
            "if activeSnapshot(slotSnapshot) then",
            "if activeSnapshot(itemSnapshot) then",
            '"inventory_item_fallback"',
            "C_Item.GetItemCooldown",
            "C_Container.GetItemCooldown",
        ):
            self.assertIn(marker, self.resolver)

    def test_cooldown_events_refresh_inventory_not_only_spells(self) -> None:
        for marker in (
            '"BAG_UPDATE_COOLDOWN"',
            'Resolver:MarkAllDirty("inventory")',
            "Resolver:ScheduleInventoryConfirmation()",
            "INVENTORY_CONFIRMATION_DELAYS = { 0.01, 0.05, 0.15, 0.35 }",
            "UNIT_SPELLCAST_SUCCEEDED",
            "ACTIONBAR_UPDATE_COOLDOWN",
        ):
            self.assertIn(marker, self.resolver)

    def test_hud_keeps_fallback_state_without_exposing_it_in_native_tooltip(self) -> None:
        self.assertIn("cooldownSlotSource = sample.cooldownSlotSource or sample.slotSource", self.auto)
        self.assertIn("cooldownItemFallbackActive", self.auto)
        self.assertIn("GameTooltip.SetInventoryItem", self.icon)
        self.assertNotIn("当前装备 ItemID 冷却 API（饰品槽位回退）", self.icon)
        self.assertIn("bindingMissing = not (binding and binding.binding)", self.auto)


if __name__ == "__main__":
    unittest.main()
