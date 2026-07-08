from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class PerformanceCleanup088ContractTests(unittest.TestCase):
    """Structural checks for the 0.8.8 no-visible-change cleanup."""

    def setUp(self) -> None:
        self.monitor = (ADDON / "Tactics" / "ProtocolMonitor.lua").read_text(encoding="utf-8")
        self.icon_state = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        self.advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.burst = (ADDON / "Tactics" / "BurstPlanner.lua").read_text(encoding="utf-8")
        self.board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
        self.model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        self.layout = (ADDON / "UI" / "TacticalHudLayout.lua").read_text(encoding="utf-8")
        self.effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        self.panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.animator = (ADDON / "UI" / "TacticalHudAnimator.lua").read_text(encoding="utf-8")
        self.agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")

    def test_monitor_returns_cached_snapshot_between_polls(self) -> None:
        self.assertIn("if state.initialized ~= true then refresh() end", self.monitor)
        self.assertIn("return state.snapshot or {}", self.monitor)
        self.assertIn("POLL_INTERVAL = 0.12", self.monitor)

    def test_refresh_context_shares_gcd_and_monitor_samples(self) -> None:
        self.assertIn("function IconState:CreateRefreshContext(primary)", self.icon_state)
        self.assertIn("gcdSnapshot = collectGcdSnapshot()", self.icon_state)
        self.assertIn("primaryIconContext = TE.IconState", self.advisors)
        self.assertNotIn("monitor = TE.ProtocolMonitor and TE.ProtocolMonitor:Sample()", self.advisors)
        self.assertIn("iconContext = primaryIconContext", self.advisors)
        self.assertIn("gcdSnapshot = iconContext.gcdSnapshot", self.advisors)
        self.assertIn("gcdSnapshot = runtime.iconContext", self.burst)

    def test_burst_state_is_not_decorated_twice(self) -> None:
        self.assertIn("item.iconState.schema >= 5", self.advisors)
        self.assertIn('item.iconStateCollectedBy = "BurstPlanner"', self.burst)

    def test_board_has_no_independent_dynamic_poll(self) -> None:
        self.assertNotIn("DYNAMIC_REFRESH_INTERVAL", self.board)
        self.assertNotIn("function TacticalBoard:RefreshDynamic", self.board)
        self.assertIn("TE.TacticalAdvisors:Subscribe", self.board)
        self.assertIn("TacticalIconButton.RefreshDynamic", self.board)

    def test_model_skips_empty_card_classification(self) -> None:
        self.assertNotIn("classify({ empty = true", self.model)
        self.assertIn("if raw then items[index] = classify(raw, kind, nil, preparedMeta) end", self.model)
        self.assertIn("signature(model.candidates[index])", self.model)

    def test_layout_returns_before_reapplying_identical_visual_geometry(self) -> None:
        early = self.layout.index("if board.tacticEchoLayoutFingerprint == fingerprint then return false end")
        backdrop = self.layout.index("setContainerBackdrop(board, hud.backdropAlpha)")
        self.assertLess(early, backdrop)

    def test_removed_dead_animation_and_board_helpers(self) -> None:
        for token in ("function Animator:FadeTo", "GLOW_HOLD_TIME", "FADE_IN_SECONDS", "FADE_OUT_SECONDS"):
            self.assertNotIn(token, self.animator)
        self.assertNotIn("safeShowTooltip", self.board)
        self.assertNotIn("lastModelFingerprint", self.board)

    def test_effect_resizing_is_cached_and_documented(self) -> None:
        self.assertIn("tacticEchoMarchingExtent", self.effects)
        self.assertIn("性能与刷新约束", self.agents)
        self.assertIn("视觉层仅用于呈现", self.agents)

    def test_settings_panel_no_longer_drives_advisory_refresh(self) -> None:
        self.assertNotIn("TE.TacticalAdvisors:Refresh(false)", self.panel)
        self.assertIn("Config.Normalize", self.panel)


if __name__ == "__main__":
    unittest.main()
