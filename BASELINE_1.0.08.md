# Tactic Echo 1.0.08 基线

## 修订目标

本版本修复前置简易自动爆发在多轮实机循环中偶发只派发 `1`、不进入 `4 -> 1` 计划，以及窗口观察帧 HUD 误报 `1` 未绑定的问题。

目标规则：

```text
窗口：343527（处决宣判，键 1）
注入：31884（复仇之怒，键 4）
方向/模式：pre simple
期望：4 -> 1
```

## 固定规则

1. 计划触发不再只依赖 `non-window -> window` 图标边沿；`paused -> armed` 后首个健康帧若已显示未消费窗口，也可创建计划。
2. `windowGeneration` 标识当前官方窗口；完成、中止或超时后写入 `consumedWindowGeneration` 并保持 `departureLockGeneration`。
3. 同一已消费窗口必须等官方推荐离开再回来，才允许创建新计划。
4. 前置注入未确认时，窗口技能不得回落到 official 派发链。
5. 公共 GCD active、受保护冷却和 `UNKNOWN` 均为等待/重采样，不是注入自身 CD。
6. 只有窗口 generation 创建时明确证明注入自身 `COOLDOWN`，前置简易才可跳过注入。
7. 候选持续发布同一个逻辑 action sequence；TEK 对 Burst sequence 去重，避免重复物理输入。
8. `UNIT_SPELLCAST_SUCCEEDED` 只确认当前 `WAIT_CONFIRM` 步骤，错误 SpellID 不推进计划。
9. Burst 观察帧保持 `BindingToken=0`，HUD 使用独立只读官方绑定显示，不能把观察帧渲染成未绑定。
10. `/temapping` 必须导出 generation、plan、step、candidate、last confirmation、last abort 与 official/dispatch binding 摘要。

## 实机测试重点

- `/teab set 343527 31884`，方向 `pre`，模式 `simple`。
- 启动自动运行后，如果官方推荐首帧已经是 `343527`，仍应先出现 Burst `binding=4`。
- `4` 成功前，不应出现 official 来源 `binding=1`。
- `4` 状态为公共 GCD 或 `UNKNOWN` 时应保持观察/重采样；超时后保持窗口离开锁。
- 完成 `4 -> 1` 后，官方仍显示 `1` 时只观察；推荐离开并再次回到 `1` 后才可下一轮。
- HUD 在 hold、WAIT_CONFIRM、GCD wait、离开锁期间应继续显示官方键位 `1`，但 TEAP `BindingToken` 仍为 `0`。
