from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TOC = ADDON / "!TacticEcho.toc"
RESOLVER = ADDON / "Tactics" / "CooldownResolver.lua"
PLANNER = ADDON / "Tactics" / "BurstPlanner.lua"
ICON_STATE = ADDON / "Tactics" / "IconState.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"
STYLES = ADDON / "UI" / "TacticalHudStyles.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"
DEFAULTS = ADDON / "Config" / "Defaults.lua"
NORMALIZE = ADDON / "Config" / "Normalize.lua"
CONTROL = ADDON / "UI" / "ControlPanel.lua"


class P5UnifiedCooldownContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.toc = TOC.read_text(encoding="utf-8")
        self.resolver = RESOLVER.read_text(encoding="utf-8")
        self.planner = PLANNER.read_text(encoding="utf-8")
        self.icon_state = ICON_STATE.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")
        self.styles = STYLES.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")
        self.defaults = DEFAULTS.read_text(encoding="utf-8")
        self.normalize = NORMALIZE.read_text(encoding="utf-8")
        self.control = CONTROL.read_text(encoding="utf-8")

    def test_shared_resolver_is_loaded_before_spell_state_collection(self) -> None:
        self.assertIn("Tactics/CooldownResolver.lua", self.toc)
        self.assertLess(
            self.toc.index("Tactics/CooldownResolver.lua"),
            self.toc.index("Tactics/IconState.lua"),
        )
        self.assertTrue(RESOLVER.is_file())
        for marker in (
            'C_Spell.GetSpellCooldown',
            'GetInventoryItemCooldown, "player", slot',
            'C_Item.GetItemCooldown',
            'readItemApiSnapshot',
            'C_Container.GetItemCooldown',
            'C_Timer.After(delay',
            'UNIT_SPELLCAST_SUCCEEDED',
            'BAG_UPDATE_COOLDOWN',
            'PLAYER_EQUIPMENT_CHANGED',
            'SPELL_UPDATE_COOLDOWN',
        ):
            self.assertIn(marker, self.resolver)
        # ITEM_COOLDOWN_CHANGED is not a valid WoW event. Registration must use
        # the supported bag/action-bar/cast signals above instead.
        self.assertNotIn('"ITEM_COOLDOWN_CHANGED"', self.resolver)

    def test_cooldown_identity_is_source_specific_but_snapshot_shape_is_shared(self) -> None:
        for marker in (
            '"spell:" .. tostring(spellID)',
            '"inventory:" .. tostring(slot)',
            '"item:" .. tostring(itemID)',
            'identity = identity',
            'remaining = nil',
            'source = source',
            'known = false',
        ):
            self.assertIn(marker, self.resolver)
        self.assertIn('TE.CooldownResolver.GetSpell', self.icon_state)
        for marker in (
            'resolver:GetInventory(item.inventorySlot, item.itemID)',
            'resolver:GetPotion(item.itemID)',
            'resolver:GetItem(item.itemID',
            'cooldownIdentityKey = snapshot.identity',
            'cooldownSource = snapshot.source',
        ):
            self.assertIn(marker, self.planner)

    def test_trinket_and_potion_cards_do_not_require_actionbar_binding_for_cd_visibility(self) -> None:
        self.assertIn('bindingMissing = not (binding and binding.binding)', self.planner)
        self.assertIn('Binding is optional for display-only item cards', self.planner)
        self.assertIn('当前未绑定现实按键', self.planner)
        self.assertIn('itemCandidate(itemID, "trinket"', self.planner)
        self.assertIn('inventorySlot = slot', self.planner)
        self.assertIn('itemCandidate(itemID, "potion"', self.planner)
        self.assertIn('return "unbound", "未在现实动作条白名单中找到绑定"', self.styles)
        self.assertIn("card.badge = card.cooldownText", self.icon)
        self.assertIn("pcall(frame.SetHideCountdownNumbers, frame, true)", self.icon)

    def test_hud_has_independent_source_cooldown_and_state_text_layers(self) -> None:
        for marker in (
            'card.sourceText',
            'card.cooldownText',
            'card.stateText',
            'card.badge = card.cooldownText',
            'card.label = card.sourceText',
            'visual.sourceLabel',
            'visual.stateLabel',
            'card.stateText:SetText',
        ):
            self.assertIn(marker, self.icon)
        self.assertIn('stateText = { enabled = true', self.defaults)
        self.assertIn('style.stateText = normalizeTextStyle', self.normalize)
        self.assertIn('状态标签（施法 / 暂停等）', self.control)
        self.assertIn('stateLabel = ""', self.styles)
        self.assertIn('sourceLabel = sourceLabel', self.styles)
        self.assertIn('stateLabel = stateLabel', self.styles)

    def test_cooldown_model_keeps_scalar_state_while_renderer_restores_live_duration_objects(self) -> None:
        self.assertIn('function Resolver:GetDurationObject(item)', self.resolver)
        self.assertNotIn('function IconState:BuildCooldownPresentation', self.icon_state)
        self.assertNotIn('sanitizeCooldownPresentation', self.model)
        self.assertNotIn('durationObjectKey', self.model)
        self.assertIn('local function showDurationObjectCooldown', self.icon)
        self.assertIn('SetCooldownFromDurationObject', self.icon)
        self.assertIn('C_Spell.GetSpellCooldownDuration', self.icon)
        self.assertIn('C_ActionBar.GetActionCooldownDuration', self.icon)
        self.assertIn('cooldownUnknownReason', self.model)
        self.assertIn('cooldownIdentityKey', self.model)


if __name__ == "__main__":
    unittest.main()
