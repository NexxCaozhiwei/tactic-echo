from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
TRACKER = ADDON / "Tactics" / "CooldownTracker.lua"
RESOLVER = ADDON / "Tactics" / "CooldownResolver.lua"
ICON_STATE = ADDON / "Tactics" / "IconState.lua"
MODEL = ADDON / "UI" / "TacticalHudModel.lua"
ICON = ADDON / "UI" / "TacticalIconButton.lua"


class P52SpellCooldownReliabilityContractTests(unittest.TestCase):
    """P5.4 cooldown reliability guardrails.

    A native DurationObject remains the first renderer authority. The tracker
    supplies event-driven numeric fallback only when protected or delayed API
    values would otherwise leave the HUD without a cooldown time.
    """

    def setUp(self) -> None:
        self.tracker = TRACKER.read_text(encoding="utf-8")
        self.resolver = RESOLVER.read_text(encoding="utf-8")
        self.icon_state = ICON_STATE.read_text(encoding="utf-8")
        self.model = MODEL.read_text(encoding="utf-8")
        self.icon = ICON.read_text(encoding="utf-8")

    def test_cast_uses_event_driven_fallback_then_authoritative_api_reconciliation(self) -> None:
        for marker in (
            "SPELL_CONFIRMATION_DELAYS = { 0.01, 0.05, 0.15, 0.35 }",
            "function Tracker:RecordCast(spellID)",
            "self:ConfirmEntry(entry)",
            "startFallbackCooldown(entry)",
            "function Tracker:ScheduleConfirmation(entry)",
            "C_Timer.After(delay, probe)",
            "spell_api_confirmation",
            "local_tracker_observed",
            "local_tracker_cached",
            "function Tracker:ReconcileSpell(spellID)",
            "SPELL_UPDATE_COOLDOWN",
            "GetSpellBaseCooldown",
            "tooltipCooldownDuration",
        ):
            self.assertIn(marker, self.tracker)

    def test_low_confidence_cast_event_reuses_existing_slot_alias_and_preserves_precache(self) -> None:
        for marker in (
            "local function existingAliasKey(ids)",
            "local key = directKey or aliasKey or",
            "local function migrateEntryToKey(entry, newKey, slot)",
            "without dropping the out-of-combat cached duration",
            "A low-confidence spell-only event must never overwrite",
            'if mapped == nil or entry.key:match("^slot:") then',
        ):
            self.assertIn(marker, self.tracker)

    def test_resolver_retries_spell_snapshot_after_cast_and_cooldown_events(self) -> None:
        for marker in (
            "SPELL_CONFIRMATION_DELAYS = { 0.01, 0.05, 0.15, 0.35 }",
            "function Resolver:ScheduleSpellConfirmation()",
            'current:MarkAllDirty("spell")',
            "UNIT_SPELLCAST_SUCCEEDED",
            "shouldConfirmSpell = true",
            "Resolver:ScheduleSpellConfirmation()",
        ):
            self.assertIn(marker, self.resolver)

    def test_hud_uses_tracker_only_after_resolver_and_the_field_proven_live_renderer(self) -> None:
        for marker in (
            "CooldownTracker.IsConfirmationPending",
            "CooldownTracker.GetCooldown",
            "event-driven (cast → local timer → API reconciliation)",
            "apiExplicitlyReady",
            "cooldownFallback = trackedCooldown.fallback == true",
            "CooldownTracker.GetCharges",
        ):
            self.assertIn(marker, self.icon_state)
        self.assertIn('"cooldownConfirmationPending"', self.model)
        self.assertIn('"cooldownFallback"', self.model)
        self.assertNotIn("function IconState:BuildCooldownPresentation", self.icon_state)
        self.assertNotIn("sanitizeCooldownPresentation", self.model)
        self.assertIn("local function showDurationObjectCooldown", self.icon)
        self.assertIn("C_Spell.GetSpellCooldownDuration", self.icon)
        self.assertIn("C_ActionBar.GetActionCooldownDuration", self.icon)


if __name__ == "__main__":
    unittest.main()
