"""P5.8 contract: HUD physical clicks and OOC AutoBurst hard gate."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def source(rel: str) -> str:
    return (ADDON / rel).read_text(encoding="utf-8")


def test_auto_interrupt_is_forced_suspended_in_defaults_normalizer_and_runtime() -> None:
    defaults = source("Config/Defaults.lua")
    normalize = source("Config/Normalize.lua")
    auto = source("Tactics/AutoReaction.lua")
    panel = source("UI/ControlPanel.lua")
    assert "suspended = true" in defaults
    assert 'suspensionReason = "auto_interrupt_suspended"' in defaults
    assert "interrupt.enabled = false" in normalize
    assert "interrupt.suspended = true" in normalize
    assert 'state = "suspended"' in auto
    assert "if config.suspended == true then" in auto
    assert "自动打断（当前不可用）" in panel
    assert "pausedToggle:Disable()" in panel


def test_hud_manual_click_is_a_secure_proxy_not_an_input_or_macro_writer() -> None:
    router = source("UI/HudClickRouter.lua")
    resolver = source("Actions/ActionBarBindingResolver.lua")
    assert '"SecureActionButtonTemplate"' in router
    assert 'SetAttribute("clickbutton", target.button)' in router
    assert 'SetAttribute("type", "click")' in router
    assert 'proxy:RegisterForClicks("LeftButtonDown", "LeftButtonUp")' in router
    assert 'blocker:RegisterForClicks("AnyDown", "AnyUp")' in router
    assert 'proxy:SetFrameStrata("HIGH")' in router
    assert 'blocker:SetFrameStrata("HIGH")' in router
    assert "proxy:Hide()" in router
    assert "blocker:Hide()" in router
    assert "programmatically" in router  # explanatory prohibition comment
    assert ":Click(" not in router
    assert "SetOverrideBinding" not in router
    assert "EditMacro" not in router
    assert "CreateMacro" not in router
    for token in ("ResolveManualSpell", "ResolveManualItem", "ResolveManualInventorySlot", "ResolveManualHudAction"):
        assert token in resolver


def test_hud_click_router_defers_proxy_and_blocker_visibility_in_combat() -> None:
    router = source("UI/HudClickRouter.lua")
    assert "local function hideInputLayer(layer)" in router
    assert "SecureActionButtonTemplate and sibling button visibility can both be" in router
    assert "hideLayerFrame(layer.proxy, true)" in router
    assert "hideLayerFrame(layer.blocker, false)" in router
    assert 'frame.tacticEchoCombatVisibilityPending = "show"' in router
    assert 'frame.tacticEchoCombatVisibilityPending = "hide"' in router


def test_manual_click_preempts_dispatch_through_existing_manual_hold() -> None:
    priority = source("Tactics/ManualActionPriority.lua")
    signal = source("Signal/SignalFrame.lua")
    assert "native_actionbar" in priority
    assert "manual_click_priority" in priority
    assert "manualPriorityObservation" in signal
    assert 'outputState = "manual_hold"' in signal
    assert 'dispatchActionKind = "manual_hold"' in signal
    assert "bindingInfo = nil" in signal
    assert "manualPriorityActive = manualPriorityObservation == true" in signal


def test_toc_load_order_places_priority_before_signal_and_router_before_icons() -> None:
    toc = source("!TacticEcho.toc")
    assert toc.index("Tactics/ManualActionPriority.lua") < toc.index("Signal/SignalFrame.lua")
    assert toc.index("UI/HudClickRouter.lua") < toc.index("UI/TacticalIconButton.lua")


def test_out_of_combat_autoburst_cannot_use_legacy_bridge_or_signal_envelope_override() -> None:
    auto = source("Tactics/AutoBurst.lua")
    signal = source("Signal/SignalFrame.lua")
    assert 'Hard encounter boundary. This runs before the enable check' in auto
    assert 'if not inCombat then' in auto
    assert 'self:Abort("out_of_combat", true)' in auto
    assert 'local paused, pauseReason = isRuntimePaused(self, runtime)' in auto
    assert 'SetState("armed") does not authorize any out-of-combat Burst' in signal
    assert 'local preCombatBurstBridgeFrame = false' in signal


def test_manual_hud_inventory_cards_resolve_exact_slot_before_spell_or_item() -> None:
    resolver = source("Actions/ActionBarBindingResolver.lua")
    function_start = resolver.index("function Resolver:ResolveManualHudAction")
    function_end = resolver.index("\nend", function_start)
    body = resolver[function_start:function_end]
    assert body.index("if inventorySlot == 13 or inventorySlot == 14") < body.index("local spellID = tonumber(item.spellID)")


def test_baselines_are_canonical_under_docs_baselines() -> None:
    root = ROOT
    baseline_dir = root / "docs" / "baselines"
    assert baseline_dir.is_dir()
    assert (baseline_dir / "BASELINE_1.0.53.md").is_file()
    assert not list(root.glob("BASELINE_*.md"))
