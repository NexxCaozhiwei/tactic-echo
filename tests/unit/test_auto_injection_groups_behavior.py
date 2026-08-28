from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"
LUA = shutil.which("lua")


HARNESS = rf'''
_G.TacticEcho = {{}}
TacticEchoDB = {{
    tactics = {{
        autoBurstEnabled = true,
        autoBurstMode = "focused",
        burstProfiles = {{ MAGE_1 = {{
            autoBurstSequence = {{ schema = 1 }}
        }} }},
    }},
}}
local legacyEntries = {{
    {{ key = "injection:200", role = "injection_1", category = "injection", kind = "spell", spellID = 200, enabled = true }},
    {{ key = "window", role = "window", category = "window", kind = "spell", spellID = 100, enabled = true, fixed = true }},
    {{ key = "injection:201", role = "injection_2", category = "injection", kind = "spell", spellID = 201, enabled = false }},
    {{ key = "trinket:13", role = "trinket_13", category = "trinket", kind = "inventory", inventorySlot = 13, enabled = true, offGCDExplicit = true }},
    {{ key = "trinket:14", role = "trinket_14", category = "trinket", kind = "inventory", inventorySlot = 14, enabled = false }},
}}
TacticEcho.BurstProfiles = {{
    SpecKey = function(_, classFile, specIndex) return tostring(classFile) .. "_" .. tostring(specIndex) end,
    GetAutoBurstSequence = function()
        return {{ schema = 1, windowSpellID = 100, entries = legacyEntries, signature = "legacy-signature" }},
            "MAGE_1", nil, {{ enabled = true, specLabel = "奥术法师" }}
    end,
}}
dofile([[{(ADDON / 'Tactics' / 'AutoInjectionGroups.lua').as_posix()}]])
dofile([[{(ADDON / 'Tactics' / 'AutoInjectionCoordinator.lua').as_posix()}]])
local Groups = TacticEcho.AutoInjectionGroups
local Coordinator = TacticEcho.AutoInjectionCoordinator
local context = {{ classFile = "MAGE", specIndex = 1 }}
local function group(id)
    local container = assert(Groups:Get(context))
    return assert(container.groups[id]), container
end
local function addConfigured(windowSpellID, injectionSpellID)
    local ok, id = Groups:AddGroup(context)
    assert(ok, id)
    assert(Groups:SetGroupWindow(context, id, windowSpellID))
    assert(Groups:AddInjection(context, id, injectionSpellID))
    assert(Groups:SetGroupEnabled(context, id, true))
    return id
end
'''


def run_lua(body: str) -> None:
    if not LUA:
        pytest.skip("lua executable is required")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", encoding="utf-8", delete=False) as handle:
        handle.write(HARNESS + body)
        path = Path(handle.name)
    try:
        result = subprocess.run([LUA, str(path)], cwd=ROOT, text=True, capture_output=True, check=False)
    finally:
        path.unlink(missing_ok=True)
    assert result.returncode == 0, result.stderr + result.stdout


def test_legacy_sequence_migrates_without_behavioral_reordering() -> None:
    run_lua(r'''
local first, container = group("group-1")
assert(container.migrated == true and #container.order == 1)
assert(first.enabled == true and first.mode == "focused" and first.windowSpellID == 100)
assert(first.sequence.entries[1].key == "injection:200")
assert(first.sequence.entries[2].key == "window")
assert(first.sequence.entries[4].key == "trinket:13")
assert(first.sequence.entries[4].enabled == true and first.sequence.entries[4].offGCDExplicit == true)
''')


def test_migration_is_idempotent() -> None:
    run_lua(r'''
local first = assert(Groups:Get(context))
local again = assert(Groups:Get(context))
assert(first == again and #again.order == 1 and again.nextGroupNumber == 2)
''')


def test_legacy_disabled_specialization_profile_migrates_to_disabled_group() -> None:
    run_lua(r'''
TacticEchoDB.tactics.burstProfiles = { MAGE_1 = { autoBurstSequence = { schema = 1 } } }
TacticEcho.BurstProfiles.GetAutoBurstSequence = function()
    return { schema = 1, windowSpellID = 100, entries = legacyEntries, signature = "legacy-signature" },
        "MAGE_1", nil, { enabled = false, specLabel = "奥术法师" }
end
local first = group("group-1")
assert(first.enabled == false, "legacy per-specialization disablement must survive migration")
''')


def test_group_limit_is_three() -> None:
    run_lua(r'''
assert(Groups:AddGroup(context))
assert(Groups:AddGroup(context))
local ok, reason = Groups:AddGroup(context)
assert(ok == false and reason == "group_limit_reached")
''')


def test_new_group_is_configured_while_disabled_then_enabled_last() -> None:
    run_lua(r'''
local ok, second = Groups:AddGroup(context)
assert(ok)
local secondGroup = group(second)
assert(secondGroup.enabled == false and secondGroup.windowSpellID == nil)
local ready, reason = Groups:GetGroupReadiness(context, second)
assert(ready == false and reason == "group_window_missing")
assert(Groups:SetGroupWindow(context, second, 300))
ready, reason = Groups:GetGroupReadiness(context, second)
assert(ready == false and reason == "group_has_no_optional_steps")
assert(Groups:AddInjection(context, second, 301))
assert(Groups:MoveStep(context, second, "injection:301", -1))
assert(Groups:SetGroupMode(context, second, "focused"))
ready, reason = Groups:GetGroupReadiness(context, second)
assert(ready == true and reason == nil)
assert(group(second).enabled == false, "editing must not implicitly enable the group")
assert(Groups:SetGroupEnabled(context, second, true))
assert(group(second).enabled == true)
''')


def test_enable_rejects_missing_window_and_missing_optional_step() -> None:
    run_lua(r'''
local ok, second = Groups:AddGroup(context)
assert(ok)
local enabled, reason = Groups:SetGroupEnabled(context, second, true)
assert(enabled == false and reason == "group_window_missing")
assert(Groups:SetGroupWindow(context, second, 300))
enabled, reason = Groups:SetGroupEnabled(context, second, true)
assert(enabled == false and reason == "group_has_no_optional_steps")
assert(group(second).enabled == false)
''')


def test_three_distinct_windows_match_their_stable_group_ids() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local third = addConfigured(400, 401)
local firstRule, _, firstId = Coordinator:Observe(context, 100, {{}})
assert(firstRule and firstId == "group-1")
Coordinator:Reset("test")
local secondRule, _, secondId = Coordinator:Observe(context, 300, {{}})
assert(secondRule and secondId == second)
Coordinator:Reset("test")
local thirdRule, _, thirdId = Coordinator:Observe(context, 400, {{}})
assert(thirdRule and thirdId == third)
''')


def test_duplicate_window_save_is_rejected() -> None:
    run_lua(r'''
local ok, second = Groups:AddGroup(context)
assert(ok)
assert(Groups:AddInjection(context, second, 301))
assert(Groups:SetGroupWindow(context, second, 100) == false)
''')


def test_corrupt_duplicate_windows_fail_closed_deterministically_by_order() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local secondGroup = group(second)
secondGroup.windowSpellID = 100
for _, entry in ipairs(secondGroup.sequence.entries) do
    if entry.category == "window" then entry.spellID = 100 end
end
local validation = assert(Groups:Validate(context))
assert(validation.valid["group-1"] == true)
assert(validation.valid[second] ~= true)
assert(validation.byGroup[second] == "duplicate_group_window_spell")
''')


def test_corrupt_duplicate_window_never_promotes_later_group_when_first_has_another_error() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local first = group("group-1")
for _, entry in ipairs(first.sequence.entries) do
    if entry.category ~= "window" then entry.enabled = false end
end
local secondGroup = group(second)
secondGroup.windowSpellID = 100
for _, entry in ipairs(secondGroup.sequence.entries) do
    if entry.category == "window" then entry.spellID = 100 end
end
local validation = assert(Groups:Validate(context))
assert(validation.byGroup["group-1"] == "group_has_no_optional_steps")
assert(validation.byGroup[second] == "duplicate_group_window_spell")
assert(validation.valid[second] ~= true)
''')


def test_window_cannot_be_another_enabled_group_injection() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local ok, reason = Groups:AddInjection(context, second, 100)
assert(ok == false and reason == "window_used_as_other_group_injection")
''')


def test_regular_injection_can_repeat_across_groups() -> None:
    run_lua(r'''
local second = addConfigured(300, 200)
local secondGroup = group(second)
local found = false
for _, entry in ipairs(secondGroup.sequence.entries) do
    if entry.category == "injection" and entry.spellID == 200 then found = true end
end
assert(found)
''')


def test_window_cannot_repeat_as_an_injection_inside_the_same_group() -> None:
    run_lua(r'''
local ok, reason = Groups:AddInjection(context, "group-1", 100)
assert(ok == false and reason == "window_used_as_same_group_injection")
local first = group("group-1")
first.sequence.entries[#first.sequence.entries + 1] = {
    key = "injection:777", role = "injection", category = "injection",
    kind = "spell", spellID = 777, enabled = true,
}
ok, reason = Groups:SetGroupWindow(context, "group-1", 777)
assert(ok == false and reason == "window_used_as_same_group_injection")
''')


def test_corrupt_same_group_window_injection_is_fail_closed() -> None:
    run_lua(r'''
local first = group("group-1")
first.sequence.entries[#first.sequence.entries + 1] = {
    key = "injection:100", role = "injection", category = "injection",
    kind = "spell", spellID = 100, enabled = true,
}
local validation = assert(Groups:Validate(context))
assert(validation.valid["group-1"] ~= true)
assert(validation.byGroup["group-1"] == "window_used_as_same_group_injection")
''')


def test_active_owner_cannot_be_preempted_by_another_window() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local firstRule = assert(Groups:BuildRule(context, "group-1"))
Coordinator:Claim("group-1")
local selected, reason, owner = Coordinator:Observe(context, 300, { plan = { rule = firstRule } })
assert(selected == firstRule and reason == nil and owner == "group-1")
assert(Coordinator.lastIgnoredGroupId == second)
assert(Coordinator.lastIgnoredEvent == "group_window_ignored_while_owner_active")
''')


def test_matched_group_without_executor_ownership_does_not_claim_or_poison_next_group() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local firstRule, firstReason = Coordinator:Observe(context, 100, {})
assert(firstRule and firstReason == nil)
assert(Coordinator.activeGroupId == nil, "matching alone must not claim ownership")
local secondRule, secondReason, secondId = Coordinator:Observe(context, 300, {})
assert(secondRule and secondReason == nil and secondId == second)
assert(Coordinator.lastIgnoredGroupId ~= second, "an unowned prior match must not poison the next group")
''')


def test_stale_active_identity_is_released_before_another_group_is_matched() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
Coordinator:Claim("group-1")
local selected, reason, matched = Coordinator:Observe(context, 300, {})
assert(selected and reason == nil and matched == second)
assert(Coordinator.activeGroupId == nil, "stale identity without plan/capture/departure lock must be released")
assert(Coordinator.lastIgnoredGroupId ~= second)
''')


def test_departure_lock_is_real_ownership_and_still_marks_other_window_missed() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local firstRule = assert(Groups:BuildRule(context, "group-1"))
local executor = { requireWindowDeparture = true, runtimeGroupId = "group-1" }
local selected, reason, owner = Coordinator:Observe(context, 300, executor)
assert(selected == firstRule and reason == nil and owner == "group-1")
assert(Coordinator.activeGroupId == "group-1")
assert(Coordinator.lastIgnoredGroupId == second)
''')


def test_missed_window_is_not_replayed_after_owner_releases() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local firstRule = assert(Groups:BuildRule(context, "group-1"))
Coordinator:Claim("group-1")
Coordinator:Observe(context, 300, { plan = { rule = firstRule } })
local selected, reason = Coordinator:Observe(context, 300, {{}})
assert(selected == nil and reason == "group_window_missed_while_busy")
''')


def test_new_departure_and_entry_allows_previously_missed_group() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local firstRule = assert(Groups:BuildRule(context, "group-1"))
Coordinator:Claim("group-1")
Coordinator:Observe(context, 300, { plan = { rule = firstRule } })
assert(select(1, Coordinator:Observe(context, 300, {{}})) == nil)
Coordinator:Observe(context, 999, {{}})
local selected, reason, owner = Coordinator:Observe(context, 300, {{}})
assert(selected and reason == nil and owner == second)
''')


def test_inactive_group_change_does_not_change_active_rule() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local firstRule = assert(Groups:BuildRule(context, "group-1"))
Coordinator:Claim("group-1")
assert(Groups:SetGroupMode(context, second, "focused"))
local selected = assert(Coordinator:Observe(context, 100, { plan = { rule = firstRule } }))
assert(selected.id == firstRule.id)
''')


def test_active_group_change_is_detected_safely() -> None:
    run_lua(r'''
local firstRule = assert(Groups:BuildRule(context, "group-1"))
Coordinator:Claim("group-1")
assert(Groups:SetGroupMode(context, "group-1", "simple"))
local selected, reason = Coordinator:Observe(context, 100, { plan = { rule = firstRule } })
assert(selected == nil and reason == "active_group_changed")
''')


def test_active_group_disable_is_detected_safely() -> None:
    run_lua(r'''
local firstRule = assert(Groups:BuildRule(context, "group-1"))
Coordinator:Claim("group-1")
assert(Groups:SetGroupEnabled(context, "group-1", false))
local selected, reason = Coordinator:Observe(context, 100, { plan = { rule = firstRule } })
assert(selected == nil and reason == "group_disabled")
''')


def test_group_signatures_are_isolated() -> None:
    run_lua(r'''
local second = addConfigured(300, 301)
local before = assert(Groups:BuildRule(context, "group-1")).groupSequenceSignature
assert(Groups:SetGroupMode(context, second, "focused"))
local after = assert(Groups:BuildRule(context, "group-1")).groupSequenceSignature
assert(before == after)
''')


def test_group_without_enabled_optional_step_cannot_take_ownership() -> None:
    run_lua(r'''
local first = group("group-1")
for _, entry in ipairs(first.sequence.entries) do
    if entry.category ~= "window" then entry.enabled = false end
end
local rule, reason = Groups:BuildRule(context, "group-1")
assert(rule == nil and reason == "group_has_no_optional_steps")
''')


def test_window_plus_six_injections_and_two_trinkets_is_nine_steps() -> None:
    run_lua(r'''
local first = group("group-1")
first.sequence.entries = {{ {{ key = "window", category = "window", spellID = 100, enabled = true }} }}
for spellID = 201, 206 do assert(Groups:AddInjection(context, "group-1", spellID)) end
local first = group("group-1")
assert(#first.sequence.entries == 9)
local ok, reason = Groups:AddInjection(context, "group-1", 207)
assert(ok == false and reason == "injection_limit_reached")
''')


def test_ordinary_spell_window_is_not_restricted_to_burst_registry() -> None:
    run_lua(r'''
local second = addConfigured(987654, 301)
local rule, reason, owner = Coordinator:Observe(context, 987654, {{}})
assert(rule and reason == nil and owner == second and rule.windowSpellID == 987654)
''')


def test_new_modules_register_no_events_or_onupdate_loops() -> None:
    groups = (ADDON / "Tactics" / "AutoInjectionGroups.lua").read_text(encoding="utf-8")
    coordinator = (ADDON / "Tactics" / "AutoInjectionCoordinator.lua").read_text(encoding="utf-8")
    combined = groups + coordinator
    assert "RegisterEvent" not in combined
    assert 'SetScript("OnUpdate"' not in combined
    assert "BindingToken" not in coordinator


def test_runtime_namespace_and_hud_validation_contracts_are_explicit() -> None:
    auto = (ADDON / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    assert 'tostring(profileKey or "unknown")' not in auto
    assert 'return false, "group_runtime_identity_incomplete"' in auto
    assert "AutoInjectionGroups:Validate(context)" in auto
    assert 'or "INVALID"' in auto
    assert "item.bindingToken = 0" in auto


def test_ui_and_hud_capacity_share_the_nine_step_contract() -> None:
    control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
    auto = (ADDON / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    groups = (ADDON / "Tactics" / "AutoInjectionGroups.lua").read_text(encoding="utf-8")
    assert "for rowIndex = 1, 9 do" in control
    assert "local HUD_GROUP_MAX_CARDS = 9" in auto
    assert "local HUD_TOTAL_MAX_CARDS = 27" in auto
    assert "MAX_SEQUENCE_STEPS = 9" in groups
    assert "for rowIndex = 1, 6 do" not in control


def test_ui_guides_disabled_group_configuration_before_enablement() -> None:
    control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
    for marker in (
        "当前组保持关闭，可继续编辑",
        "请先填写并应用窗口 SpellID",
        "当前组配置完整；可在这里启用，或继续调整下方设置",
        "窗口技能不能再次作为本组注入技能",
        "GetGroupReadiness",
    ):
        assert marker in control


def test_window_spellid_editor_is_explicit_and_not_overwritten_by_periodic_refresh() -> None:
    control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
    for marker in (
        "第一步：设置窗口技能（必填）",
        "窗口技能 SpellID",
        "只填数字，不填技能名称或按键",
        "保存窗口技能",
        "第二步：添加注入技能",
        "第三步：调整当前组顺序（最多九步）",
        "当前组启用状态",
        "local identityContainer, identityGroupId",
        "if value == identityContainer and currentGroupId == identityGroupId then return end",
        'windowBox:SetScript("OnEnterPressed"',
    ):
        assert marker in control
    identity_refresh = control.split("local function refreshIdentityBoxes()", 1)[1].split("registerControl(refreshIdentityBoxes)", 1)[0]
    assert identity_refresh.index("if value == identityContainer and currentGroupId == identityGroupId then return end") < identity_refresh.index("windowBox:SetText")


def test_hud_projects_all_enabled_groups_in_persisted_order() -> None:
    auto = (ADDON / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    model = (ADDON / "UI" / "TacticalHudModel.lua").read_text(encoding="utf-8")
    board = (ADDON / "UI" / "TacticalBoard.lua").read_text(encoding="utf-8")
    layout = (ADDON / "UI" / "TacticalHudLayout.lua").read_text(encoding="utf-8")
    for marker in (
        "for groupOrder, groupId in ipairs(container.order or {})",
        'group.enabled == true',
        "item.autoInjectionGroupOrder = groupOrder",
        'out.recommendationState = out.active and "auto_injection_group_sequences"',
    ):
        assert marker in auto
    assert "MAX_BURST_CARDS = 27" in model
    assert "MAX_BURST_CARDS = 27" in board
    assert "local burstGroups, burstGroupById = {}, {}" in layout
    assert "card.item.autoInjectionGroupId" in layout


def test_auto_injection_enablement_precedes_basic_settings_and_scroll_height_follows_rows() -> None:
    control = (ADDON / "UI" / "ControlPanel.lua").read_text(encoding="utf-8")
    assert control.index('createSection(pane, "当前组启用状态"') < control.index('createSection(pane, "当前组基本设置"')
    assert "local visibleRows = math.max(1, math.min(#entries, 9))" in control
    assert "sequenceFooter:SetPoint" in control
    assert "pane:SetHeight(math.max(620, -footerY + 64))" in control


def test_hud_first_materialized_card_commits_immediately() -> None:
    animator = (ADDON / "UI" / "TacticalHudAnimator.lua").read_text(encoding="utf-8")
    assert "if slot.fingerprint == nil then" in animator
    assert "slot.fingerprint, slot.pendingFingerprint" in animator


def test_teap_protocol_and_burst_flag_remain_unchanged() -> None:
    encoder = (ADDON / "Signal" / "SignalEncoder.lua").read_text(encoding="utf-8")
    assert "local fields = {" in encoder
    assert encoder.count("fields[#fields + 1]") == 3  # 17 payload fields + CRC16 + commit = 20 bytes.
    assert "flags = flags + 32" in encoder
    assert 'dispatchOrigin == "burst"' in encoder


def test_new_configuration_modules_stay_below_retail_upvalue_limit() -> None:
    luac = shutil.which("luac")
    if not luac:
        pytest.skip("luac executable is required")
    for path in (
        ADDON / "Tactics" / "AutoInjectionGroups.lua",
        ADDON / "Tactics" / "AutoInjectionCoordinator.lua",
        ADDON / "Tactics" / "AutoBurst.lua",
    ):
        result = subprocess.run([luac, "-p", str(path)], text=True, capture_output=True, check=False)
        assert result.returncode == 0, result.stderr


def test_existing_lifecycle_watcher_clears_group_ownership_without_new_loops() -> None:
    auto = (ADDON / "Tactics" / "AutoBurst.lua").read_text(encoding="utf-8")
    for event in (
        '"PLAYER_REGEN_ENABLED"',
        '"PLAYER_DEAD"',
        '"UNIT_ENTERED_VEHICLE"',
        '"PLAYER_SPECIALIZATION_CHANGED"',
        '"PLAYER_LEAVING_WORLD"',
    ):
        assert event in auto
    spec_branch = auto.split('event == "PLAYER_SPECIALIZATION_CHANGED"', 1)[1]
    assert 'AutoBurst.groupRuntime = {}' in spec_branch
    assert 'TE.AutoInjectionCoordinator:Reset("specialization_changed")' in spec_branch
