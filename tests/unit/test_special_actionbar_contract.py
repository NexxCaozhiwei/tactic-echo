from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
RESOLVER = ROOT / "addon" / "!TacticEcho" / "Actions" / "ActionBarBindingResolver.lua"
STATE = ROOT / "addon" / "!TacticEcho" / "Tactics" / "TacticalState.lua"
EXPORT = ROOT / "addon" / "!TacticEcho" / "Diagnostics" / "MappingExport.lua"


class SpecialActionBarContractTests(unittest.TestCase):
    def test_replacing_contexts_are_explicitly_fail_closed(self) -> None:
        text = RESOLVER.read_text(encoding="utf-8")
        self.assertIn("readSpecialActionBarState", text)
        for api, reason in (
            ("UnitHasVehicleUI", "special_actionbar_vehicle"),
            ("HasOverrideActionBar", "special_actionbar_override"),
            ("GetPossessBarIndex", "special_actionbar_possess"),
            ("C_PetBattles.IsInBattle", "special_actionbar_pet_battle"),
        ):
            self.assertIn(api, text)
            self.assertIn(reason, text)

    def test_extra_action_is_observed_but_does_not_fail_close_resolution(self) -> None:
        text = RESOLVER.read_text(encoding="utf-8")
        function_start = text.index("local function readSpecialActionBarState()")
        function_end = text.index("local function trim(value)", function_start)
        state_reader = text[function_start:function_end]
        self.assertIn("HasExtraActionBar", state_reader)
        self.assertIn("observeExtraAction", state_reader)
        self.assertIn("extraActionVisible", state_reader)
        self.assertNotIn('return mark("special_actionbar_extra"', state_reader)
        self.assertNotIn('return mark("special_actionbar_extra"', text)

    def test_resolution_checks_only_replacing_special_bars_before_cached_candidates(self) -> None:
        text = RESOLVER.read_text(encoding="utf-8")
        start = text.index("function Resolver:ResolveSpell")
        cached = text.index("local cached = self.cache[spellID]", start)
        guard = text.index("local specialActionBar = self:GetSpecialActionBarState()", start)
        self.assertLess(guard, cached)
        self.assertIn('bindingToken = 0', text[start:cached])
        self.assertIn('status = "NoBinding"', text[start:cached])

    def test_extra_action_state_is_exported_for_diagnosis(self) -> None:
        text = EXPORT.read_text(encoding="utf-8")
        self.assertIn("extraActionVisible", text)
        self.assertIn("extraActionSources", text)

    def test_reason_text_remains_visible_for_blocked_contexts(self) -> None:
        text = STATE.read_text(encoding="utf-8")
        self.assertIn('special_actionbar_vehicle = "载具动作条已阻断"', text)
        self.assertIn('special_actionbar_override = "覆盖动作条已阻断"', text)
        self.assertNotIn('special_actionbar_extra = "额外动作条已阻断"', text)


if __name__ == "__main__":
    unittest.main()
