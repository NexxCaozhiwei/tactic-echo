from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"

def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")

def test_burst_and_interrupt_control_are_separate_layout_lanes() -> None:
    layout = read("UI/TacticalHudLayout.lua")
    panel = read("UI/ControlPanel.lua")
    assert "Burst and interrupt/control are separate HUD modules" in layout
    assert "local burstGroups, burstGroupById = {}, {}" in layout
    assert "local interruptControlLane = {" in layout
    assert "for _, burstLane in ipairs(burstGroups) do" in layout
    assert "appendLane(burstLane, base.minX, groupY, burstDirection)" in layout
    assert 'appendLane(interruptControlLane, base.minX, laneY, hud.tacticalGrowth or "RIGHT")' in layout
    assert '"爆发方向"' in panel
    assert '"打断控制方向"' not in panel

def test_burst_window_and_followup_cooldowns_remain_renderable() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    auto = read("Tactics/AutoBurst.lua")
    assert "TE.AutoBurst.BuildHudSnapshot" in planner
    assert "hudApplySpellState" in auto
    assert "hudApplyItemCooldown" in auto
    assert "cooldownRemaining" in auto
    assert "cooldownDuration" in auto

def test_burst_cards_remain_hud_only() -> None:
    auto = read("Tactics/AutoBurst.lua")
    advisors = read("Tactics/TacticalAdvisors.lua")
    assert "bindingToken = 0" in auto
    assert "displayOnly = true" in auto
    assert "advisoryOnly = true" in auto
    assert "item.burstDispatchActive = true" in advisors
