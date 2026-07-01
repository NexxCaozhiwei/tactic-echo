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

    def test_icon_component_renders_all_icon_state_markers(self):
        text = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        for marker in ("frame:SetCooldown", "card.gcdCooldown", "chargeText", "card.chargeEdge", 'item.usableState == "resource"', 'item.usableState == "range"', 'item.usableState == "target"', "引导", "unknown", "触发效果：已高亮"):
            self.assertIn(marker, text)
        self.assertNotIn("card.proc = card:CreateTexture", text)
        effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        self.assertIn("TacticalIconEffects.lua", text)
        self.assertIn("UI-HUD-ActionBar-Proc-Loop-Flipbook", effects)

if __name__ == "__main__":
    unittest.main()
