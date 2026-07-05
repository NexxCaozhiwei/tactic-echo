# Tactic Echo 1.0.51 P5.6 直接覆盖补丁清单

## 版本

- 版本：`1.0.51 P5.6`
- 主题：以 `UnitCastingInfo` / `UnitChannelInfo` 的 `notInterruptible` 与单位施法事件作为自动打断资格；修复 `false` 被 Lua `and/or` 折为 `nil` 的问题。
- TEK：未修改；不需要重建 `TEK.exe`。

## 覆盖内容

- AddOn：
  - `addon/!TacticEcho/Tactics/ReactionObservation.lua`
  - `addon/!TacticEcho/Tactics/AutoReaction.lua`
  - `addon/!TacticEcho/Config/Defaults.lua`
  - `addon/!TacticEcho/Config/Normalize.lua`
  - `addon/!TacticEcho/UI/ControlPanel.lua`
  - `addon/!TacticEcho/Core/Bootstrap.lua`
  - `addon/!TacticEcho/!TacticEcho.toc`
- 根目录：
  - `VERSION`
  - `AGENTS.md`
  - `docs/baselines/BASELINE_1.0.51.md`
  - `CHANGELOG.md`
  - `DECISIONS.md`
  - `HANDOFF.md`
  - `PROJECT_CONTEXT.md`
  - `README.md`
  - `TASKS.md`
  - `PATCH_MANIFEST_1.0.51.md`
- 文档与测试：
  - `docs/P5.6_API_EVENT_INTERRUPTIBILITY_TEST.md`
  - `tests/unit/test_reaction_api_interruptibility_p56.py`
  - `tests/unit/test_reaction_compat_p52.py`
  - `tests/unit/test_reaction_safety_p53.py`
  - `tests/unit/test_reaction_p54_p43_route_reanchor.py`
  - `tests/unit/test_reaction_p55_action_info_macro_spell_transport.py`
  - `tests/unit/test_reaction_control_p4_contract.py`

## 安装

1. 覆盖项目根目录。
2. 覆盖 WoW 实际加载目录的 `Interface/AddOns/!TacticEcho`。
3. 重启 TEK，游戏内执行 `/reload` 与 `/tecache refresh`。

## 不包含

`TEK.exe`、构建产物、缓存、诊断日志、SavedVariables、宏正文和历史补丁包。
