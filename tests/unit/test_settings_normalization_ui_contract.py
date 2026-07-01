from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_toc_loads_normalizer_before_ui_and_tactics_consumers() -> None:
    toc = read("!TacticEcho.toc")
    assert toc.index("Config/Defaults.lua") < toc.index("Tactics/TacticalAdvisors.lua")
    assert toc.index("Config/Normalize.lua") < toc.index("UI/ControlPanel.lua")


def test_defaults_use_full_size_and_opacity_for_missing_profiles() -> None:
    defaults = read("Config/Defaults.lua")
    for token in [
        "scale = 1.00",
        "alpha = 1.00",
        'outOfCombatMode = "show"',
        "defensiveDisplayHealthPercent = 45",
        "displayHealthPercent = 35",
    ]:
        assert token in defaults


def test_normalizer_owns_legacy_repair_and_visual_reset() -> None:
    normalizer = read("Config/Normalize.lua")
    for token in [
        "knownClampBug",
        "hud.scale, hud.alpha = defaults.scale, defaults.alpha",
        "allLegacyThresholdsAtMinimum",
        "function Normalize:ResetVisuals()",
        "hud.modules = {}",
    ]:
        assert token in normalizer


def test_hud_page_exposes_previously_unreachable_presentation_controls() -> None:
    panel = read("UI/ControlPanel.lua")
    for label in [
        "HUD 全局缩放",
        "HUD 全局透明度",
        "HUD 底纹透明度",
        "脱战透明度",
        "脱战缩放",
        "简洁 HUD 模式",
        "独立防御缩放",
        "独立防御透明度",
        "锁定独立防御队列",
        "启用候选预测",
        "候选来源",
        "战术队列优先级",
        "目标框打断提示",
        "启用位移脱险提示",
    ]:
        assert label in panel


def test_board_uses_config_normalizer_and_adjustable_ooc_multipliers() -> None:
    board = read("UI/TacticalBoard.lua")
    for token in [
        "TE.Config.Normalize:All()",
        "hud.outOfCombatAlpha",
        "hud.outOfCombatScale",
        "defenseAlpha = defenseAlpha * hud.outOfCombatAlpha",
    ]:
        assert token in board
