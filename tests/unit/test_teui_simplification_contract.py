from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(relative: str) -> str:
    return (ADDON / relative).read_text(encoding="utf-8")


def test_settings_center_has_only_current_product_pages() -> None:
    control = read("UI/ControlPanel.lua")
    assert 'local NAV_ORDER = { "general", "hud", "burst", "profiles" }' in control
    assert 'main = "hud"' in control
    assert "general = buildGeneral" in control
    assert "hud = buildHUD" in control
    assert "burst = buildBurst" in control
    assert "profiles = buildProfiles" in control
    for retired in (
        "buildMain",
        "SetBurstSubpage",
        "SetInterruptSubpage",
        "完整调试日志",
        "自动爆发诊断",
        "启用爆发窗口辅助",
        "显示爆发候选栏",
        "爆发候选来源",
        "当前专精覆盖",
    ):
        assert retired not in control


def test_hud_uses_one_authoritative_content_selector() -> None:
    control = read("UI/ControlPanel.lua")
    normalize = read("Config/Normalize.lua")
    board = read("UI/TacticalBoard.lua")
    assert 'label = "主键 + 自动爆发"' in control
    assert 'label = "仅主键"' in control
    assert "hud.compact = false" in control
    assert 'burstStyle.show = hud.queueMode ~= "primary"' in control
    assert "hud.compact = false" in normalize
    assert "hud.showHistory = false" in normalize
    assert "hud.showSourceTags = false" in normalize
    assert 'burst.show = hud.queueMode ~= "primary"' in normalize
    assert 'hud.queueMode == "primary"' in board
    assert 'hud.compact == true or hud.queueMode == "primary"' not in board


def test_hud_burst_lane_projects_saved_sequence_in_order() -> None:
    burst = read("Tactics/AutoBurst.lua")
    assert "HUD_SEQUENCE_MAX_CARDS = 9" in burst
    assert "GetAutoBurstSequence(context)" in burst
    assert "for _, entry in ipairs(sequence.entries or {})" in burst
    assert "entry.enabled == true" in burst
    assert "burstSequenceConfigured = true" in burst
    for legacy in (
        "settings.burstDisplayMode",
        "settings.burstShowCandidates",
        "settings.burstShowTrinkets",
        "settings.burstShowPotions",
        "settings.burstShowRacial",
    ):
        assert legacy not in burst
    assert not (ADDON / "Tactics" / "BurstStateMachine.lua").exists()
    assert "Tactics\\BurstStateMachine.lua" not in read("!TacticEcho.toc")


def test_profile_scope_mapping_is_retained_but_collapsed() -> None:
    control = read("UI/ControlPanel.lua")
    for token in (
        "profilesAdvancedExpanded",
        'advancedFrame:SetShown(profilesAdvancedExpanded == true)',
        '"展开自动切换"',
        '"收起自动切换"',
        "SetScopeProfile(keys.global",
        "SetScopeProfile(keys.character",
        "SetScopeProfile(keys.class",
        "SetScopeProfile(keys.spec",
    ):
        assert token in control
