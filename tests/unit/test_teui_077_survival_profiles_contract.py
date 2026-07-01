from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class Teui077SurvivalProfilesContractTests(unittest.TestCase):
    def test_profile_manager_is_loaded_and_scopes_are_ordered(self) -> None:
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        profiles = (ADDON / "Profiles" / "ProfileManager.lua").read_text(encoding="utf-8")
        self.assertIn("Profiles/ProfileManager.lua", toc)
        for token in (
            "Scope precedence: spec -> class -> character -> global -> Default.",
            "function ProfileManager:ApplyBestScope",
            "function ProfileManager:SetScopeProfile",
            "function ProfileManager:SaveActive",
        ):
            self.assertIn(token, profiles)

    def test_survival_items_are_observed_only_after_bag_bar_and_binding_checks(self) -> None:
        planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        resolver = (ADDON / "Actions" / "ActionBarBindingResolver.lua").read_text(encoding="utf-8")
        for token in (
            "plainItemCount",
            "itemBinding",
            "survivalItem",
            "buildSurvivalItems",
            "healthstoneItemID",
            "potionItemID",
            "bindingToken = 0",  # no item dispatch token
            "only after three independent observations agree",
        ):
            self.assertIn(token, planner)
        self.assertIn("function Resolver:ResolveItem(itemID)", resolver)
        self.assertIn("read-only mapping for survival/consumable display", resolver)
        for forbidden in ("SetBinding(", "SaveBindings(", "SetOverrideBindingClick(", "SignalEncoder:Encode"):
            self.assertNotIn(forbidden, planner)

    def test_icon_style_is_module_scoped_and_effects_are_external(self) -> None:
        panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        for key in ('"main"', '"burst"', '"interrupt"', '"defense"'):
            self.assertIn(f"ensureModuleStyle(hud, {key})", panel)
        effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        self.assertIn("TacticalIconEffects.lua", icon)
        self.assertIn("rotationhelper_ants_flipbook", effects)
        self.assertIn("cooldownSwipe", icon)


if __name__ == "__main__":
    unittest.main()
