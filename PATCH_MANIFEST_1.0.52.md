# Tactic Echo 1.0.52 P5.7 直接覆盖补丁清单

## 版本

- 版本：`1.0.52 P5.7`
- 主题：HUD 主键启动/暂停；爆发、打断、控制、防御/生存 HUD 卡片安全复用现有动作条按钮；自动打断设计暂停。
- TEK：未修改；不需要重建 `TEK.exe`。

## 覆盖内容

- AddOn：
  - `addon/!TacticEcho/Tactics/ManualActionPriority.lua`
  - `addon/!TacticEcho/UI/HudClickRouter.lua`
  - `addon/!TacticEcho/Actions/ActionBarBindingResolver.lua`
  - `addon/!TacticEcho/Signal/SignalFrame.lua`
  - `addon/!TacticEcho/Tactics/AutoReaction.lua`
  - `addon/!TacticEcho/Config/Defaults.lua`
  - `addon/!TacticEcho/Config/Normalize.lua`
  - `addon/!TacticEcho/UI/ControlPanel.lua`
  - `addon/!TacticEcho/UI/TacticalIconButton.lua`
  - `addon/!TacticEcho/UI/TacticalBoard.lua`
  - `addon/!TacticEcho/Core/Bootstrap.lua`
  - `addon/!TacticEcho/!TacticEcho.toc`
- 根目录与文档：
  - `VERSION`、`docs/baselines/BASELINE_1.0.52.md`、`PATCH_MANIFEST_1.0.52.md`、`CHANGELOG.md`
  - `AGENTS.md`、`README.md`、`PROJECT_CONTEXT.md`、`HANDOFF.md`、`TASKS.md`、`DECISIONS.md`
- 测试：
  - `tests/unit/test_p57_hud_manual_click_and_auto_interrupt_suspend.py`
  - `tests/unit/test_p57_hud_manual_click_runtime.py`
  - `docs/P5.7_HUD_MANUAL_CLICK_TEST.md`

## 安装

1. 覆盖项目根目录。
2. 覆盖 WoW 实际加载目录的 `Interface/AddOns/!TacticEcho`。
3. 游戏内执行 `/reload`；首次建立 HUD 点击映射请在脱战状态下完成。

## 不包含

`TEK.exe`、构建产物、缓存、诊断日志、SavedVariables、宏正文和历史补丁包。
