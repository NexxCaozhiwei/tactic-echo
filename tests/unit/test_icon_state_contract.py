from __future__ import annotations
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"

class IconStateContractTests(unittest.TestCase):
    def test_icon_state_module_is_loaded_before_advisors(self):
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        self.assertIn("Tactics/IconState.lua", toc)
        self.assertLess(toc.index("Tactics/IconState.lua"), toc.index("Tactics/TacticalAdvisors.lua"))

    def test_icon_state_is_read_only_and_uses_display_apis(self):
        text = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        for marker in ("GetSpellCooldown", "GetSpellCharges", "IsSpellUsable", "IsSpellInRange"):
            self.assertIn(marker, text)
        for forbidden in ("SetBinding(", "SaveBindings(", "SignalFrame:SetState", "SignalEncoder:Encode"):
            self.assertNotIn(forbidden, text)

    def test_casting_match_accepts_equivalent_spell_ids_and_preserves_name(self):
        text = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        for marker in (
            "local function spellMatchesCast(spellID, cast, options)",
            "options and options.matchedSpellID",
            "options and options.equivalentSpellIDs",
            "sameBaseSpell(spellID, castSpellID)",
            "name = plainText(source.name, nil)",
            "castingName = cast.name",
            "item.castingName = state.castingName",
        ):
            self.assertIn(marker, text)

    def test_icon_component_renders_all_icon_state_markers(self):
        text = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        for marker in ("frame:SetCooldown", "card.gcdCooldown", "chargeText", "card.chargeEdge", "引导", "unknown", "触发效果：已高亮"):
            self.assertIn(marker, text)
        # Resource/range/target remain HUD states, but no longer have a second
        # icon-component greyscale path that duplicates the cooldown swipe.
        self.assertIn("card.icon:SetDesaturated(visual.desaturate == true)", text)
        self.assertIn("Only explicit hard states chosen by TacticalHudStyles", text)
        self.assertNotIn("card.proc = card:CreateTexture", text)
        effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        self.assertIn("TacticalIconEffects.lua", text)
        self.assertIn("UI-HUD-ActionBar-Proc-Loop-Flipbook", effects)

if __name__ == "__main__":
    unittest.main()
