# Tactic Echo 1.0.42 P4.5 直接覆盖补丁清单

## 本版目标

识别并守卫严格的既有整合打断宏：

```lua
#showtooltip 迎头痛击
/stopcasting
/cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 迎头痛击
```

P4.5 不会假定宏能判断“目标是否正在施法”。当上游分支仍会命中活着的敌对单位时，会 fail-closed，避免将焦点/当前目标的读条错误投向鼠标指向或焦点。

## 覆盖文件

- 根目录：`VERSION`、`AGENTS.md`、`docs/baselines/BASELINE_1.0.42.md`、`CHANGELOG.md`、`DECISIONS.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`README.md`；
- AddOn：`!TacticEcho.toc`、`Core/Bootstrap.lua`、`Actions/MacroSemantics.lua`、`Tactics/ReactionBindings.lua`、`Tactics/AutoReaction.lua`、`Signal/SignalEncoder.lua`、`UI/ControlPanel.lua`；
- 文档与测试：`docs/P4.5_PRIORITY_INTERRUPT_MACRO_TEST.md`、`tests/unit/test_reaction_priority_macro_p45.py`。

## 安装

1. 解压并覆盖 Tactic Echo 项目根目录；
2. 将 `addon/!TacticEcho` 覆盖到 WoW 实际加载的 `Interface/AddOns/!TacticEcho`；
3. 重新启动游戏或执行 `/reload`；
4. 本版未修改 TEK 源码。使用已包含 P4.3 reaction 去重的 TEK.exe 时，**无需重建 EXE**；建议重启 TEK 以开启新会话；
5. 参照 `docs/P4.5_PRIORITY_INTERRUPT_MACRO_TEST.md` 验证。

## 不变项

- 不新增输入通道；
- 不修改 AutoBurst、HUD CD、TEAP 结构或 TEK 安全门禁；
- 不创建/改写宏、不写绑定、不自动选目标、不移动鼠标。
