# Tactic Echo 1.0.50 P5.5 直接覆盖补丁清单

## 版本

- 版本：`1.0.50 P5.5`
- 主题：双 action-info 宏身份兼容，恢复 P4.3 当前动作栏 target transport。
- TEK：未修改；不需要重建 `TEK.exe`。

## 覆盖内容

- AddOn：
  - `addon/!TacticEcho/Tactics/ReactionBindings.lua`
  - `addon/!TacticEcho/Core/Bootstrap.lua`
  - `addon/!TacticEcho/!TacticEcho.toc`
- 根目录：
  - `VERSION`
  - `AGENTS.md`
  - `docs/baselines/BASELINE_1.0.50.md`
  - `CHANGELOG.md`
  - `DECISIONS.md`
  - `HANDOFF.md`
  - `PROJECT_CONTEXT.md`
  - `README.md`
  - `TASKS.md`
  - `PATCH_MANIFEST_1.0.50.md`
- 文档与测试：
  - `docs/P5.5_ACTION_INFO_MACRO_SPELL_TRANSPORT_TEST.md`
  - `tests/unit/test_reaction_p55_action_info_macro_spell_transport.py`

## 安装

1. 覆盖项目根目录。
2. 覆盖 WoW 实际加载目录的 `Interface/AddOns/!TacticEcho`。
3. 重启 TEK，游戏内执行 `/reload` 与 `/tecache refresh`。

## 不包含

`TEK.exe`、构建产物、缓存、诊断日志、SavedVariables、宏正文和历史补丁包。
