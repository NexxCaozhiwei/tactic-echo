from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
RESOLVER = ADDON / "Tactics" / "CooldownResolver.lua"
BURST = ADDON / "Tactics" / "BurstPlanner.lua"
AUTO_BURST = ADDON / "Tactics" / "AutoBurst.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"
ICON_STATE = ADDON / "Tactics" / "IconState.lua"


class InventoryGcdPresentationContractTests(unittest.TestCase):
    """Item cards retain the field-proven 1.0.31 GCD isolation path."""

    def setUp(self) -> None:
        self.icon = ICON.read_text(encoding="utf-8")
        self.resolver = RESOLVER.read_text(encoding="utf-8")
        self.burst = BURST.read_text(encoding="utf-8")
        self.auto_burst = AUTO_BURST.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")
        self.icon_state = ICON_STATE.read_text(encoding="utf-8")

    def test_item_cards_are_classified_in_the_live_renderer(self) -> None:
        for marker in (
            "local function isEquippedTrinketCard",
            "local function isItemBackedCard",
            "local function suppressSharedGcdPresentation",
            "local function showDurationObjectCooldown",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("CooldownResolver", self.icon)
        self.assertNotIn("BuildCooldownPresentation", self.icon_state)

    def test_item_gcd_suppression_survives_transient_missing_itemid(self) -> None:
        for marker in (
            "if isEquippedTrinketCard(item) then return true end",
            'local category = safeText(item.category, ""):lower()',
            'category == "trinket" or category == "potion" or category == "item" or category == "consumable"',
            "during exactly the refresh interval in which a trinket's ItemID is being",
        ):
            self.assertIn(marker, self.icon)

    def test_shared_item_gcd_is_normalized_at_resolver_boundary(self) -> None:
        for marker in (
            "local function normalizeItemSnapshotAgainstGcd(snapshot)",
            "GLOBAL_COOLDOWN_SPELL_ID = 61304",
            '"gcd_snapshot_aligned"',
            "out.gcdAlias = true",
            "out.active = false",
            "slotSnapshot = normalizeItemSnapshotAgainstGcd",
            "snapshot = normalizeItemSnapshotAgainstGcd(snapshot)",
        ):
            self.assertIn(marker, self.resolver)

    def test_equipped_trinket_never_borrows_generic_actionbar_gcd(self) -> None:
        inventory = self.resolver.index("local inventoryCard = inventorySlot == 13 or inventorySlot == 14")
        strict_certificate = self.resolver.index("item.cooldownGcdAlias ~= true", inventory)
        disabled = self.resolver.index('return nil, "inventory_own_cooldown_unconfirmed"', inventory)
        actionbar = self.resolver.index('if actionSlotTrusted and C_ActionBar and type(C_ActionBar.GetActionCooldownDuration) == "function" then')
        self.assertLess(inventory, strict_certificate)
        self.assertLess(strict_certificate, disabled)
        self.assertLess(disabled, actionbar)
        self.assertIn("shared spell GCD", self.resolver)

    def test_all_item_backed_cards_suppress_generic_gcd_overlay_layer(self) -> None:
        for marker in (
            "local suppressItemGcdLayer = isItemBackedCard(item)",
            "local gcdCanRender = gcdEnabled",
            "and suppressItemGcdLayer ~= true",
            "hideCooldown(card.gcdCooldown)",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn("local suppressItemGcdLayer = isItemBackedCard(item) or suppressSharedGcd == true", self.icon)

    def test_gcd_alias_reaches_hud_model_and_burst_item_collector(self) -> None:
        self.assertIn('"cooldownGcdAlias"', self.model)
        self.assertIn("item.cooldownGcdAlias", self.auto_burst)
        self.assertIn("item.cooldownGcdAlias ~= true", self.auto_burst)

    def test_non_item_skill_uses_live_duration_renderer_not_sidecar(self) -> None:
        self.assertIn('return duration, "actionbar_duration"', self.resolver)
        self.assertIn("C_Spell.GetSpellCooldownDuration", self.icon)
        self.assertIn("C_ActionBar.GetActionCooldownDuration", self.icon)
        self.assertNotIn("HudCooldownDurationObjects", self.icon)
        self.assertNotIn("HudCooldownDurationObjects", self.icon_state)

    def test_actionbar_public_gcd_overrides_stale_spell_api_for_burst_and_hud(self) -> None:
        for marker in (
            "local function actionBarPublicCooldown(actionSlot, trusted)",
            "C_ActionBar.GetActionCooldown",
            "state.cooldownActionBarPublicOnGCD",
            "state.cooldownGcdAlias = true",
            'state.cooldownGcdAliasReason = "actionbar_public_on_gcd"',
        ):
            self.assertIn(marker, self.icon_state)

    def test_all_hud_cooldown_widgets_are_centralized_in_tactical_icon_button(self) -> None:
        hits = []
        for path in (ADDON / "UI").glob("*.lua"):
            text = path.read_text(encoding="utf-8")
            if 'CreateFrame("Cooldown"' in text:
                hits.append(path.name)
        self.assertEqual(hits, ["TacticalIconButton.lua"])


if __name__ == "__main__":
    unittest.main()
