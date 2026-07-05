# Tactic Echo 1.0.46 P5.2 直接覆盖补丁清单

## 版本

- 版本：`1.0.46 P5.2`
- 主题：恢复 P4.3 已实测的未确认真实读条兼容派发，并以可验证宏分支守卫收紧多行打断宏。
- TEK：未修改；不需要重建 `TEK.exe`。

## 覆盖内容

- AddOn：
  - `addon/!TacticEcho/Tactics/AutoReaction.lua`
  - `addon/!TacticEcho/Tactics/ReactionBindings.lua`
  - `addon/!TacticEcho/Actions/MacroSemantics.lua`
  - `addon/!TacticEcho/Config/Defaults.lua`
  - `addon/!TacticEcho/Config/Normalize.lua`
  - `addon/!TacticEcho/UI/ControlPanel.lua`
  - `addon/!TacticEcho/Core/Bootstrap.lua`
  - `addon/!TacticEcho/!TacticEcho.toc`
- 根目录：`VERSION`、`AGENTS.md`、`docs/baselines/BASELINE_1.0.46.md`、`CHANGELOG.md`、`DECISIONS.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`README.md`、`TASKS.md`、`PATCH_MANIFEST_1.0.46.md`
- 文档与测试：`docs/P5.2_REACTION_COMPAT_AND_MACRO_TEST.md`、`tests/unit/test_reaction_compat_p52.py`、`tests/unit/test_reaction_managed_target_macro_p52.py`、`tests/unit/test_reaction_control_p4_contract.py`

## 安装

1. 覆盖项目根目录文件。
2. 覆盖 WoW 实际加载目录的 `Interface/AddOns/!TacticEcho`。
3. 重启 TEK，游戏内执行 `/reload`。
4. 执行 `/tecache refresh` 和 `/temapping p52_reaction_compat`，按 P5.2 文档验证。

## 不包含

- `TEK.exe`、构建产物、缓存、诊断日志、SavedVariables、宏正文。
