from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_burst_queue_has_fixed_window_slot_and_followup_roles() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    model = read("UI/TacticalHudModel.lua")
    board = read("UI/TacticalBoard.lua")
    assert "window = nil" in planner
    assert "followups = {}" in planner
    assert "out.items[#out.items + 1] = out.window" in planner
    assert "markRole(item, role" in planner
    assert '"injection"' in planner and '"trinket"' in planner and '"potion"' in planner and '"racial"' in planner
    assert "MAX_BURST_CARDS = 5" in model
    assert "burst = buildFixedItems" in model
    assert "for index = 1, MAX_BURST_CARDS" in board


def test_always_mode_keeps_window_and_bound_followups() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    assert 'local always = settings.burstDisplayMode == "always"' in planner
    assert "if always then policyAllowsReady = true end" in planner
    assert "if always then" in planner
    assert "for _, group in ipairs(orderedGroups) do addGroup(group.items, group.role) end" in planner
    assert "常驻爆发队列：窗口技能固定首位" in planner


def test_burst_direction_is_independent_from_interrupt_control_direction() -> None:
    layout = read("UI/TacticalHudLayout.lua")
    panel = read("UI/ControlPanel.lua")
    assert 'hud.burstGrowth or "RIGHT"' in layout
    assert 'hud.tacticalGrowth or "RIGHT"' in layout
    assert '"爆发队列方向"' in panel
    assert '"打断控制方向"' in panel


def test_effect_pipeline_caches_state_and_preserves_icon_art() -> None:
    effects = read("UI/TacticalIconEffects.lua")
    icon = read("UI/TacticalIconButton.lua")
    styles = read("UI/TacticalHudStyles.lua")
    assert "tacticEchoEffectSignature" in effects
    assert "rotationhelper_ants_flipbook" in effects
    assert "UI-HUD-ActionBar-Proc-Loop-Flipbook" in effects
    assert "UI-HUD-ActionBar-Channel-Fill" in effects
    assert "maybeFlashHotkey" in effects
    assert "TacticalIconEffects:Refresh" in icon
    assert "itemCount" in icon
    assert "rangeBlocked" in styles
    assert "resourceBlocked" in styles
    assert "castingThisSpell" in styles


def test_profile_enables_trinket_followers_when_global_source_is_enabled() -> None:
    profiles = read("Tactics/BurstProfiles.lua")
    planner = read("Tactics/BurstPlanner.lua")
    assert '{ slot = 13, label = "饰品13", enabled = true }' in profiles
    assert '{ slot = 14, label = "饰品14", enabled = true }' in profiles
    assert "settings.burstShowTrinkets" in planner
