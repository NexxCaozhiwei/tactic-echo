from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"

def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")

def test_target_prompt_is_retired_and_not_loaded() -> None:
    toc = read("!TacticEcho.toc")
    panel = read("UI/ControlPanel.lua")
    assert "UI/TargetCastPrompt.lua" not in toc
    assert "目标框 / 姓名板打断提示" not in panel

def test_burst_hud_is_projected_from_the_autoburst_runtime_snapshot() -> None:
    planner = read("Tactics/BurstPlanner.lua")
    auto = read("Tactics/AutoBurst.lua")
    for token in ("Pure HUD projection adapter", "TE.AutoBurst.BuildHudSnapshot", "autoburst_snapshot_adapter"):
        assert token in planner
    for token in ("function AutoBurst:BuildHudSnapshot", "bindingToken = 0", "displayOnly = true"):
        assert token in auto

def test_autoburst_policy_has_current_preflight_and_runtime_boundaries() -> None:
    auto = read("Tactics/AutoBurst.lua")
    for token in ("preflightSequence", "focused_optional_step_unavailable", "sequence_optional_step_skipped", "GCD_LOCKED", "QUEUE_WINDOW", "if not inCombat then"):
        assert token in auto
    for retired in ("burstPolicy", "burstDisplayMode", "burstShowClassCooldowns"):
        assert retired not in auto
