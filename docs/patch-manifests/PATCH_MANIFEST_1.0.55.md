# Tactic Echo 1.0.55 P5.10 完整源码包清单

## 核心变更

- `addon/!TacticEcho/Actions/ActionBarBindingResolver.lua`：落实 P5.5/P5.6 当前动作栏宏身份规则；有效 numeric index 失败不再扫描其它宏；代表 SpellID 恢复采用 `GetActionText`/action-info handle 只读名称 + 代表 SpellID + 唯一正文语义；代表 SpellID 或 `GetMacroSpell` 不再单独授权正文恢复、HUD 或 AutoBurst。
- `addon/!TacticEcho/Tactics/ReactionBindings.lua`：P4 opaque action-info route 强制要求真实 nonzero BindingToken；未验证正文身份不能成为控制 HUD 手动来源。
- `addon/!TacticEcho/Tactics/AdvisoryPlanner.lua`、`Tactics/TacticalAdvisors.lua`、`UI/HudClickRouter.lua`：HUD 只接受正文已验证的宏来源，并复核来源类型、macroID 与语义身份；同技能其他槽位或原槽位替换不再静默接管。
- `tests/unit/test_p510_current_actionbar_macro_identity.py`：覆盖 `CTRL+1` `[@cursor] 冰冻陷阱`、action-info handle 标签、正文失配、双标签歧义、有效 index 不跨宏扫描与 P4 opaque token 边界。
- `docs/P5.10_CURRENT_ACTIONBAR_MACRO_IDENTITY_TEST.md`、`docs/baselines/BASELINE_1.0.55.md`、`CHANGELOG.md`、`AGENTS.md`、`README.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`TASKS.md`、`DECISIONS.md`：同步 P5.10 规则与验收。

## 交付边界

- 单一源码根目录；不包含 SavedVariables、日志、缓存、构建输出、历史 ZIP 或 EXE。
- 不改动 TEK/Windows 输入实现；不恢复自动打断、自动控制、防御/生存派发或脱战 Burst。
- 不创建快捷键、宏、spell/item secure action，不调用程序化点击，也不改变玩家宏的目标/分支语义。
