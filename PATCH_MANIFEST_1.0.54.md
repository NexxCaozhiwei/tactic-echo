# Tactic Echo 1.0.54 P5.9 完整源码包清单

## 核心变更

- `addon/!TacticEcho/Actions/MacroSemantics.lua`：新增 `/use` 物品语义匹配，支持 ItemID、`item:ID`、本地化物品名、条件/分支和 `/castsequence` 的只读关联。
- `addon/!TacticEcho/Actions/ActionBarBindingResolver.lua`：`ResolveItem()` 复用当前可见默认动作条中的已识别 `/use` 宏；无合法快捷键宏仍只供 HUD 实体点击，不生成新输入路径。
- `addon/!TacticEcho/Tactics/TacticalAdvisors.lua`、`Tactics/AdvisoryPlanner.lua`、`Tactics/TacticalState.lua`：控制、防御与生存保留宏的可靠动作条呈现身份，避免把已识别宏误降级；无 BindingToken 的来源固定为人工 HUD 用途。
- `docs/P5.9_CONTROL_DEFENSE_SURVIVAL_MACRO_TEST.md`、`docs/baselines/BASELINE_1.0.54.md`、`CHANGELOG.md`、`AGENTS.md`、`README.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`TASKS.md`、`DECISIONS.md`：同步 P5.9 规则与验收。

## 交付边界

- 只包含单一源码根目录；不包含 SavedVariables、日志、缓存、构建输出、历史 ZIP 或 EXE。
- 不改动 TEK/Windows 输入实现；不恢复自动打断、自动控制、防御/生存派发或脱战 Burst。
- 不创建快捷键、宏、spell/item secure action，不调用程序化点击，也不改变玩家宏的目标/分支语义。
