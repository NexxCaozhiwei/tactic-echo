from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_burst_queue_has_fixed_window_slot_and_followup_roles() -> None:
    auto = read("Tactics/AutoBurst.lua")
    model = read("UI/TacticalHudModel.lua")
    board = read("UI/TacticalBoard.lua")
    assert "HUD_GROUP_MAX_CARDS = 9" in auto
    assert "HUD_TOTAL_MAX_CARDS = 27" in auto
    assert 'entry.category == "window"' in auto
    assert 'entry.category == "trinket"' in auto
    assert 'role == "window"' in auto
    assert "MAX_BURST_CARDS = 27" in model
    assert "burst = buildFixedItems" in model
    assert "for index = 1, MAX_BURST_CARDS" in board


def test_hud_sequence_uses_the_same_persisted_order_as_autoburst() -> None:
    auto = read("Tactics/AutoBurst.lua")
    assert "hudConfiguredGroups" in auto
    assert "for groupOrder, groupId in ipairs(container.order or {})" in auto
    assert "for _, entry in ipairs(group.sequence and group.sequence.entries or {})" in auto
    assert "entry.enabled == true" in auto
    assert "group.enabled == true" in auto
    assert "item.autoInjectionGroupOrder = groupOrder" in auto
    assert "burstDisplayMode" not in auto


def test_burst_direction_is_independent_from_interrupt_control_direction() -> None:
    layout = read("UI/TacticalHudLayout.lua")
    panel = read("UI/ControlPanel.lua")
    assert 'hud.burstGrowth or "RIGHT"' in layout
    assert 'hud.tacticalGrowth or "RIGHT"' in layout
    assert '"爆发方向"' in panel
    assert '"打断控制方向"' not in panel


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


def test_profile_keeps_trinkets_as_explicit_disabled_sequence_steps() -> None:
    profiles = read("Tactics/BurstProfiles.lua")
    auto = read("Tactics/AutoBurst.lua")
    assert 'key = "trinket:13"' in profiles
    assert 'key = "trinket:14"' in profiles
    assert 'enabled = false' in profiles
    assert "settings.burstShowTrinkets" not in auto
