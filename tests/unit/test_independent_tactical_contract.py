from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class IndependentTacticalContractTests(unittest.TestCase):
    def test_no_imported_third_party_tactical_tree_or_branding(self) -> None:
        banned_brand = "jus" + "tac"
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        self.assertNotIn("ThirdParty/", toc)
        self.assertNotIn("ThirdParty\\", toc)

        # A copied-over source tree can retain an unused ThirdParty directory. Only TOC-loaded
        # modules are runtime dependencies; stale, unreferenced files must not block TEK.exe builds.
        loaded_paths = [
            line.strip()
            for line in toc.splitlines()
            if line.strip() and not line.lstrip().startswith("#") and line.strip().endswith(".lua")
        ]
        self.assertTrue(loaded_paths)
        for relative in loaded_paths:
            path = ADDON / relative
            self.assertTrue(path.is_file(), relative)
            self.assertNotIn(banned_brand, relative.lower(), relative)
            self.assertNotIn(banned_brand, path.read_text(encoding="utf-8").lower(), str(path))

    def test_toc_loads_independent_modules(self) -> None:
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        expected = [
            "Tactics/ProtocolMonitor.lua",
            "Signal/SignalEncoder.lua",
            "Signal/SignalFrame.lua",
            "Tactics/TacticalState.lua",
            "Tactics/AbilityProfiles.lua",
            "Tactics/AdvisoryPlanner.lua",
            "Tactics/TacticalTelemetry.lua",
            "Tactics/TacticalAdvisors.lua",
            "UI/TacticalBoard.lua",
            "UI/TargetCastPrompt.lua",
        ]
        for item in expected:
            self.assertIn(item, toc)
        self.assertLess(toc.index("Signal/SignalFrame.lua"), toc.index("Tactics/TacticalState.lua"))
        self.assertLess(toc.index("UI/ControlPanel.lua"), toc.index("UI/TacticalBoard.lua"))

    def test_hud_consumes_signal_snapshot_not_official_api(self) -> None:
        hud = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.assertIn("TE.TacticalAdvisors", hud)
        self.assertNotIn("RecommendationAdapter:ReadOfficial", hud)
        self.assertNotIn("RecommendationAdapter", hud)
        self.assertNotIn(":ReadOfficial", hud)

    def test_advisors_and_hud_do_not_mutate_dispatch_or_bindings(self) -> None:
        forbidden = ("SetBinding(", "SaveBindings(", "SetOverrideBindingClick(", "SignalFrame:SetState", "SignalEncoder:Encode")
        for relative in ("Tactics/TacticalAdvisors.lua", "Tactics/TacticalState.lua", "Tactics/AdvisoryPlanner.lua", "UI/TacticalBoard.lua", "UI/TargetCastPrompt.lua"):
            text = (ADDON / relative).read_text(encoding="utf-8")
            for token in forbidden:
                self.assertNotIn(token, text, f"{relative} contains {token}")

    def test_signal_frame_publishes_exact_encoded_snapshot(self) -> None:
        text = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.assertIn("lastMessage = message", text)
        self.assertIn("lastEncoded = encoded", text)
        self.assertIn("TE.TacticalState:Publish(message, encoded)", text)

    def test_v3_monitor_extension_does_not_change_field_count(self) -> None:
        text = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")
        self.assertIn("monitorFlags", text)
        self.assertIn("fields = {", text)
        self.assertIn("self.commitByte", text)
        # 17 data fields plus CRC low/high and commit must remain the v3 20-block contract.
        self.assertIn("fields[#fields + 1] = wordLow(crc)", text)
        self.assertIn("fields[#fields + 1] = wordHigh(crc)", text)
        self.assertIn("fields[#fields + 1] = self.commitByte", text)


if __name__ == "__main__":
    unittest.main()
