# Patch Manifest — 1.0.56 P5.11

## 修改文件

- `addon/!TacticEcho/Actions/ActionBarBindingResolver.lua`
  - 集中提供当前宏身份与 AutoBurst 宏资格判定；`ResolveSpell` 诊断改为请求作用域化，并保留同一有效 index 的可读失败证据。
- `addon/!TacticEcho/Tactics/AutoBurst.lua`
  - 仅调用 Resolver 的 AutoBurst 宏资格判定。
- `addon/!TacticEcho/Tactics/ReactionBindings.lua`
  - 常规宏路由与手动宏来源使用 Resolver 的当前宏身份判定；P4 opaque 仍单独 target-only。
- `addon/!TacticEcho/Tactics/TacticalAdvisors.lua`
- `addon/!TacticEcho/Tactics/AdvisoryPlanner.lua`
  - 控制、防御、生存 HUD 手动展示均调用同一 Resolver 判定。
- `addon/!TacticEcho/Tactics/AbilityProfiles.lua`
  - 保持猎人控制使用当前动作条实际 SpellID `19577`（胁迫）与 `187650`（冰冻陷阱）。
- `tests/unit/test_p511_shared_macro_policy.py`
- `tests/unit/test_p511_hunter_control_macro_identity.py`
- `tests/unit/test_p510_current_actionbar_macro_identity.py`
- `docs/baselines/BASELINE_1.0.56.md`
- `docs/P5.11_SHARED_MACRO_POLICY_TEST.md`
- `AGENTS.md`、`CHANGELOG.md`、`PROJECT_CONTEXT.md`、`HANDOFF.md`、`DECISIONS.md`、`TASKS.md`、`README.md`

## 不修改

- 宏正文、宏绑定、宏目标与宏分支。
- TEAP/TEK 格式、输入门禁与自动打断硬暂停。
- AutoBurst 战斗内硬门控、HUD CD/DurationObject、标签和排序。
