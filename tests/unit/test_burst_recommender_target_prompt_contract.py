from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"

def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")

def test_target_prompt_is_opt_in_and_never_mirrors_always_visible_interrupt_state() -> None:
    defaults = read("Config/Defaults.lua")
    normalizer = read("Config/Normalize.lua")
    prompt = read("UI/TargetCastPrompt.lua")
    panel = read("UI/ControlPanel.lua")
    assert "showTargetPrompt = false" in defaults
    assert "hud.showTargetPrompt = false" in normalizer
    for token in ("interrupt.cast and interrupt.cast.active == true", "interrupt.interruptible ~= true", "item.usableState == \"cooldown\"", "does NOT inherit the interrupt HUD's \"always visible\"", "目标框 / 姓名板打断提示"):
        assert token in (prompt + panel)

def test_burst_recommender_is_independent_but_hud_only() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    state = read("Tactics/BurstStateMachine.lua")
    for token in ("Independent trigger recommendation", "independent_burst_queue", "window_ready", "当前专精爆发窗口技能已就绪", "当前有效动作条真实绑定", "bindingToken = 0", "window = nil", "followups = {}"):
        assert token in planner
    assert "UNIT_SPELLCAST_SUCCEEDED" in state
    assert "function Machine:RecordTriggerCast" in state
    assert "使用定时爆发窗口" in state

def test_burst_policy_has_real_behavior_boundaries() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    for token in ("settings.burstPolicy == \"hold\"", "not inCombat", "WAITING_TARGET", "settings.burstPolicy == \"align\"", "settings.burstShowClassCooldowns ~= false", "settings.burstDisplayMode == \"always\"", "showSequence"):
        assert token in planner
