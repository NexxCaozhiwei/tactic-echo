from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


class Teui079DefenseGcdHotkeyHeaderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.planner = (ADDON / "Tactics" / "AdvisoryPlanner.lua").read_text(encoding="utf-8")
        self.icon_state = (ADDON / "Tactics" / "IconState.lua").read_text(encoding="utf-8")
        self.icon = (ADDON / "UI" / "TacticalIconButton.lua").read_text(encoding="utf-8")
        self.model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
        self.panel = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
        self.advisors = (ADDON / "Tactics" / "TacticalAdvisors.lua").read_text(encoding="utf-8")
        self.resolver = (ADDON / "Actions" / "ActionBarBindingResolver.lua").read_text(encoding="utf-8")
        self.signal = (ADDON / "Signal" / "SignalFrame.lua").read_text(encoding="utf-8")
        self.state = (ADDON / "Tactics" / "TacticalState.lua").read_text(encoding="utf-8")

    def test_out_of_combat_defense_is_spec_bound_display_only_standby(self) -> None:
        for marker in (
            "defensiveOutOfCombatStandby",
            "out_of_combat_standby",
            "GetDefensiveGroups(classFile, context and context.specIndex)",
            'for _, category in ipairs({ "minor", "major", "emergency", "selfheal" }) do',
            "item.bindingToken = 0",
            "requireActualBinding ~= true or (item.binding and item.unbound ~= true)",
            "脱战显示防御待命",
        ):
            self.assertIn(marker, self.planner + self.panel + self.advisors)
        self.assertIn("脱战：当前专精防御待命（只读显示，BindingToken=0）", self.planner)
        self.assertNotIn("TEAP", self.planner[self.planner.index("function Planner:BuildDefense"):self.planner.index("function Planner:BuildBurst")])

    def test_gcd_uses_independent_safe_state_and_native_cooldown_frame(self) -> None:
        for marker in (
            "GLOBAL_COOLDOWN_SPELL_ID = 61304",
            "state.gcdRemaining, state.gcdDuration, state.gcdStart",
            "state.gcdKnown = gcdKnown == true",
            "item.gcdRemaining = state.gcdRemaining",
        ):
            self.assertIn(marker, self.icon_state)
        for marker in ('"gcdRemaining", "gcdDuration", "gcdStart"', '"gcdKnown"'):
            self.assertIn(marker, self.model)
        for marker in (
            'card.gcdCooldown = CreateFrame("Cooldown"',
            '"CooldownFrameTemplate"',
            "sameCooldown",
            "globalOnly",
            "显示共 CD 转盘",
            "公共冷却（GCD）转盘",
        ):
            self.assertIn(marker, self.icon + self.panel)

    def test_hotkey_labels_are_compacted_without_widening_dispatch_policy(self) -> None:
        for marker in (
            "local function formatBinding(binding)",
            'hasShift and "S"',
            'hasCtrl and "C"',
            'hasAlt and "A"',
            "formatBinding(item.binding)",
        ):
            self.assertIn(marker, self.icon)
        self.assertIn('local MODIFIERS = { [""]=0, ALT=1, CTRL=2, SHIFT=3 }', self.resolver)
        self.assertIn('["0"]=28,["-"]=29,["="]=30', self.resolver)
        self.assertIn('binding = bindingInfo and (bindingInfo.binding or bindingInfo.rawBinding) or nil', self.signal)
        self.assertIn('binding = message.binding or binding.binding or binding.rawBinding', self.state)
        self.assertIn('binding = primary.binding or primary.rawBinding', self.advisors)

    def test_header_state_is_anchored_before_window_actions(self) -> None:
        for marker in (
            'labels.headerState = normalHeader:CreateFontString',
            'labels.headerState:SetPoint("RIGHT", normalHeader, "RIGHT", -116, 0)',
            'labels.headerState:SetJustifyV("MIDDLE")',
        ):
            self.assertIn(marker, self.panel)

    def test_static_border_and_opt_in_blizzard_atlas_effects_are_separate(self) -> None:
        effects = (ADDON / "UI" / "TacticalIconEffects.lua").read_text(encoding="utf-8")
        for marker in (
            "card.highlight = CreateFrame",
            "card.highlight:SetBackdropBorderColor",
            "updateHighlight(card, item, card.resolvedHighlightStyle)",
            "启用静态边框高亮",
            "紧急防御状态边框",
            "光效与动画",
        ):
            self.assertIn(marker, self.icon + self.panel)
        self.assertNotIn("ActionButton_ShowOverlayGlow", self.icon)
        self.assertIn("rotationhelper_ants_flipbook", effects)
        self.assertIn("UI-HUD-ActionBar-Proc-Loop-Flipbook", effects)


if __name__ == "__main__":
    unittest.main()
