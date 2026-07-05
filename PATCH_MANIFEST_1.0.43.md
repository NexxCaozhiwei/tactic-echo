# Tactic Echo 1.0.43 P4.6 直接覆盖补丁清单

## 本版目标

修复多行“焦点优先 → 选敌回退 → 恢复目标”打断宏的动作条发现与技能关联韧性，覆盖 `反制射击`（147362）在名称 API 临时不可用或宏正文首读缺失时无法被 P2 识别的情形。

## 覆盖文件

- 根目录：`VERSION`、`AGENTS.md`、`docs/baselines/BASELINE_1.0.43.md`、`CHANGELOG.md`、`DECISIONS.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`README.md`、`TASKS.md`、`PATCH_MANIFEST_1.0.43.md`；
- AddOn：`!TacticEcho.toc`、`Core/Bootstrap.lua`、`Actions/MacroSemantics.lua`、`Actions/ActionBarBindingResolver.lua`、`Tactics/ReactionBindings.lua`、`Diagnostics/MappingExport.lua`、`UI/ControlPanel.lua`；
- 文档与测试：`docs/P4.6_COUNTER_SHOT_MACRO_RECOVERY_TEST.md`、`tests/unit/test_counter_shot_macro_recovery_p46.py`。

## 安装

1. 解压并覆盖 Tactic Echo 项目根目录；
2. 将 `addon/!TacticEcho` 覆盖到 WoW 实际加载的 `Interface/AddOns/!TacticEcho`；
3. 重新启动游戏或执行 `/reload`；
4. 本版未修改 TEK 源码；使用已有 P4.3 reaction 去重的 TEK.exe 时，**无需重建 EXE**；
5. 按 `docs/P4.6_COUNTER_SHOT_MACRO_RECOVERY_TEST.md` 验证。

## 不变项

- 不新增输入通道；
- 不修改 AutoBurst、HUD CD、TEAP 结构或 TEK 安全门禁；
- 不创建/改写宏、不写绑定、不自动选目标、不移动鼠标；
- 不保存宏正文。
