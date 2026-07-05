# Tactic Echo 1.0.45 P5.1 直接覆盖补丁清单

## 版本

- 版本：`1.0.45 P5.1`
- 主题：修复 Retail 宏动作 `GetActionInfo(...).id` 返回代表 SpellID 时的正文回收与同名宏唯一语义匹配。
- TEK：未修改；不需要重建 `TEK.exe`。

## 覆盖内容

- AddOn：`addon/!TacticEcho/Actions/ActionBarBindingResolver.lua`、`addon/!TacticEcho/Core/Bootstrap.lua`、`addon/!TacticEcho/Diagnostics/MappingExport.lua`、`addon/!TacticEcho/UI/ControlPanel.lua`、`addon/!TacticEcho/UI/Diagnostics.lua`、`addon/!TacticEcho/!TacticEcho.toc`
- 根目录：`VERSION`、`AGENTS.md`、`docs/baselines/BASELINE_1.0.45.md`、`CHANGELOG.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`README.md`、`PATCH_MANIFEST_1.0.45.md`
- 文档与测试：`docs/P5.1_MACRO_ACTION_IDENTITY_TEST.md`、`tests/unit/test_macro_identity_p5.py`、`tests/unit/test_counter_shot_macro_recovery_p46.py`

## 安装

1. 覆盖项目根目录文件。
2. 覆盖 WoW 实际加载目录的 `Interface/AddOns/!TacticEcho`。
3. 重启 TEK，游戏内执行 `/reload`。
4. 执行 `/tecache refresh` 和 `/temapping p51_macro_action_identity`，按 P5.1 文档验证。

## 不包含

- `TEK.exe`、构建产物、缓存、诊断日志、SavedVariables。
