# Tactic Echo 1.0.42 P4.5 基线：受守卫的整合打断宏

## 目标

P4.4 已恢复严格的“可打断证据 + 安全路由”资格。P4.5 不改动该资格、不改动 SignalFrame/TEAP/TEK 输入链，而是解决一类宏解析与路由风险：

```lua
#showtooltip 迎头痛击
/stopcasting
/cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 迎头痛击
```

该宏的三段条件不是三个独立按钮，而是 Blizzard 宏引擎在**同一次按键**中从左到右选择的优先链。

## 固定宏合同

只有同时满足以下条件的既有宏，P2 才可标记为 `macro_priority_chain`：

1. 仅一条 `/cast` 动作行，且全部可执行施法动作均为同一个请求技能；
2. 不含 `/castsequence`、`/target`、`/targetenemy`、`/cleartarget`、`/focus` 等目标管理命令；
3. 条件块严格为 `mouseover → focus → target`，每段仅使用 `@unit`（target 可省略）、可选 `exists`、`harm`、`nodead`；
4. 无修饰键、战斗状态、友方、玩家、宠物、光标、额外条件或未知条件；
5. 宏位于当前可见 Blizzard 默认动作条，且已有安全 BindingToken。

任何部分链、混合条件链、多技能宏、目标切换宏或无法精确建模的分支，均保持手动宏状态。

## P4 路由守卫

宏本身无法判断目标是否读条，只能判断 `harm,nodead`。因此 P4 不能因为 focus 没有读条就假定宏会回退到 target。

- 当 `mouseover` 是候选来源：可使用整合宏；
- 当 `focus` 是候选来源：仅当 mouseover 不存在、非敌对或已死亡时可使用；
- 当 `target` 是候选来源：仅当 mouseover 与 focus 均不存在、非敌对或已死亡时可使用；
- 若任一更高优先级宏分支仍会命中活着的敌对单位，P4 记录 `macro_priority_preempted_by_mouseover` 或 `macro_priority_preempted_by_focus`，不派发、不重建动作条映射。

这是一道来源兼容性预检，**不是**通用宏条件解释器。P4 不判断、重排或执行宏内部条件，仍只按玩家已有的一个按键。

## 不变项

- P4.4 的 API / 事件 / 真实盾组件严格可打断确认完全保留；
- 同一读条的稳定 reaction candidate、SignalFrame stable sequence、TEK 成功后去重完全保留；
- 不新增 BindingToken、TEAP 字段、输入通道、目标切换、鼠标移动、宏创建或宏改写；
- AutoBurst、HUD 冷却、标签与既有 Windows 门禁不变；
- 本版仅改 AddOn 解析/路由/诊断层，已具备 P4.3 reaction 去重的 TEK.exe 无需重新构建。

## 实机验收

见 `docs/P4.5_PRIORITY_INTERRUPT_MACRO_TEST.md`。
