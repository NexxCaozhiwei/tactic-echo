from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class Efficiency0910ContractTests(unittest.TestCase):
    def test_signal_history_is_bounded_and_deduplicated_without_by_sequence(self) -> None:
        text = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.assertIn("MAX_SIGNAL_FRAMES = 60", text)
        self.assertIn("TacticEchoDB.signal.bySequence = nil", text)
        self.assertIn("tostring(encoded.sequence or 0)", text)
        self.assertIn("tostring(encoded.state or \"unknown\")", text)
        self.assertIn("tostring(reason or \"tick\")", text)
        self.assertNotIn("store.bySequence[", text)

    def test_player_cast_data_has_one_signalframe_origin(self) -> None:
        signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        icon = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        self.assertIn("function SignalFrame:GetCastDisplayInfo()", signal)
        self.assertIn("GetCastDisplayInfo", icon)
        self.assertNotIn("UnitCastingInfo", icon)
        self.assertNotIn("UnitChannelInfo", icon)
        self.assertNotIn("UnitChannelInfo", effects)

    def test_target_prompt_has_no_independent_update_loop(self) -> None:
        text = (ADDON / "UI" / "TargetCastPrompt.lua").read_text(encoding="utf-8")
        self.assertNotIn('SetScript("OnUpdate"', text)
        self.assertIn("TE.TacticalAdvisors:Subscribe", text)

    def test_telemetry_is_opt_in_and_legacy_macro_layer_is_absent(self) -> None:
        telemetry = (ADDON / "Tactics" / "TacticalTelemetry.lua").read_text(encoding="utf-8")
        toc = (ADDON / "!TacticEcho.toc").read_text(encoding="utf-8")
        self.assertIn("settings.diagnosticsEnabled == true", telemetry)
        self.assertNotIn('center.page == "monitor"', telemetry)
        self.assertNotIn("Actions/MacroRegistry.lua", toc)
        self.assertFalse((ADDON / "Actions" / "MacroRegistry.lua").exists())

    def test_reaction_p3_heavy_paths_are_suspended(self) -> None:
        observation = (ADDON / "Tactics" / "ReactionObservation.lua").read_text(encoding="utf-8")
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn("NAMEPLATE_CONTROL_SCAN_SUSPENDED = true", observation)
        self.assertIn("nameplate_control_scan_suspended", observation)
        self.assertIn("REACTION_READONLY_HIGHLIGHT_SUSPENDED = true", advisors)
        self.assertIn("reaction_p3_suspended", advisors)

    def test_primary_only_hud_uses_lightweight_advisor_path(self) -> None:
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn('hud.queueMode == "primary"', advisors)
        self.assertIn('emptyAdvisory("hud_primary_only")', advisors)
        self.assertIn("hudPrimaryOnly = true", advisors)
        self.assertLess(
            advisors.index("if primaryOnly == true then"),
            advisors.index("monitor = TE.ProtocolMonitor and TE.ProtocolMonitor:Sample()"),
        )
        self.assertLess(
            advisors.index("if primaryOnly == true then"),
            advisors.index("TE.AdvisoryPlanner:Build(primary, context, settings, runtime)"),
        )

    def test_primary_only_disables_unused_observer_scans(self) -> None:
        monitor = (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8")
        planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        events = (ADDON / "Tactics" / "ReactionInterruptEvents.lua").read_text(encoding="utf-8")
        self.assertIn('hud.queueMode == "primary"', monitor)
        self.assertIn("primary_only_lightweight", monitor)
        refresh_start = monitor.index("local function refresh()")
        self.assertLess(
            monitor.index("if hudPrimaryOnly() == true then", refresh_start),
            monitor.index("readTargetCast()", refresh_start),
        )
        self.assertIn("if hudPrimaryOnly() == true then", planner)
        self.assertLess(
            planner.index("if hudPrimaryOnly() == true then"),
            planner.index('pcall(GetUnitSpeed, "player")'),
        )
        self.assertIn("if hudPrimaryOnly() == true then return end", events)
        self.assertLess(
            events.index("if hudPrimaryOnly() == true then return end"),
            events.index("TE.ReactionObservation.Refresh"),
        )

    def test_legacy_resolver_wrapper_and_compact_snapshot_helper_are_removed(self) -> None:
        resolver = (ADDON / "Actions" / "ActionBarBindingResolver.lua").read_text(encoding="utf-8")
        control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.assertNotIn("function Resolver:Resolve(action)", resolver)
        self.assertNotIn("compactSnapshotText", control)


if __name__ == "__main__":
    unittest.main()
