from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"

def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")

def test_burst_and_interrupt_control_are_separate_layout_lanes() -> None:
    layout = read("UI/TacticalHudLayout.lua")
    panel = read("UI/ControlPanel.lua")
    assert "Burst and interrupt/control are separate HUD modules" in layout
    assert "local burstLane = {}" in layout
    assert "local interruptControlLane = {" in layout
    assert 'appendLane(burstLane, base.minX, laneY, hud.burstGrowth or "RIGHT")' in layout
    assert 'appendLane(interruptControlLane, base.minX, laneY, hud.tacticalGrowth or "RIGHT")' in layout
    assert '"爆发队列方向"' in panel
    assert '"打断控制方向"' in panel

def test_burst_window_and_followup_cooldowns_remain_renderable() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    panel = read("UI/ControlPanel.lua")
    assert "local function selectWindow" in planner
    assert 'elseif item.usableState == "cooldown" then' in planner
    assert "cooldownAllowed(settings)" in planner
    assert "保留首图标并由游戏原生转盘显示倒计时" in planner
    assert "out.window" in planner and "out.followups" in planner
    assert 'createChoice(pane, "冷却中图标"' in panel

def test_burst_cards_remain_hud_only() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    assert "bindingToken = 0" in planner
    assert "displayOnly = true" in planner
    assert "independent_burst_queue" in planner
