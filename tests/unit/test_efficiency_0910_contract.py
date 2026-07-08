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
        self.assertNotIn('source = "reaction_p3_suspended"', advisors)

    def test_primary_only_hud_uses_lightweight_advisor_path(self) -> None:
        advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.assertIn('hud.queueMode == "primary"', advisors)
        self.assertIn("local function shouldBuildBurstHud(hud)", advisors)
        self.assertIn("local ADVISOR_REFRESH_INTERVAL = 0.35", advisors)
        self.assertIn("if refreshElapsed < ADVISOR_REFRESH_INTERVAL then return end", advisors)
        self.assertIn('if hud.compact == true or hud.queueMode == "primary" then return false end', advisors)
        self.assertIn('local advisory = emptyAdvisory(primaryOnly and "hud_primary_only" or "hud_burst_hidden")', advisors)
        self.assertIn("hudPrimaryOnly = primaryOnly == true", advisors)
        self.assertLess(
            advisors.index("if buildBurstHud ~= true then"),
            advisors.index("TE.BurstPlanner:Build(primary, context, settings, runtime)"),
        )
        self.assertNotIn("TE.AdvisoryPlanner:Build(primary, context, settings, runtime)", advisors)
        self.assertNotIn("monitor = TE.ProtocolMonitor and TE.ProtocolMonitor:Sample()", advisors)

    def test_signalframe_only_builds_autoburst_snapshot_for_reaction_consumer(self) -> None:
        signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.assertIn('if inCombat and TE.AutoBurst and type(TE.AutoBurst.Evaluate) == "function" then', signal)
        reaction_gate = signal.index('if TE.AutoReaction and type(TE.AutoReaction.Evaluate) == "function" then')
        snapshot_call = signal.index('pcall(TE.AutoBurst.GetSnapshot, TE.AutoBurst)', reaction_gate)
        self.assertLess(reaction_gate, snapshot_call)

    def test_signalframe_reuses_only_official_tick_messages_at_wr_cadence(self) -> None:
        signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.assertIn("local OFFICIAL_RECOMMENDATION_REBUILD_INTERVAL = 0.10", signal)
        self.assertIn("local REUSABLE_OFFICIAL_TICK_STATES = {", signal)
        self.assertIn("waiting = true", signal)
        self.assertIn("armed = true", signal)
        self.assertIn("paused = true", signal)
        self.assertIn("blocked = true", signal)
        self.assertIn('if message.dispatchOrigin == "burst" or message.dispatchOrigin == "reaction" then return false end', signal)
        self.assertIn('local canReuse = reason == "tick"', signal)
        self.assertIn('and reusableOfficialTickMessage(lastMessage)', signal)
        self.assertIn('OFFICIAL_RECOMMENDATION_REBUILD_INTERVAL', signal)
        self.assertIn('local message = canReuse and cloneMessageForFreshness(lastMessage) or self:BuildMessage(reason)', signal)

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
