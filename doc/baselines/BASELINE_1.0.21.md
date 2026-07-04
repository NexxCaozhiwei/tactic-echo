# Tactic Echo 1.0.21 基线：受控起手 Burst bridge

## 目标

修复 Boss 开场或首次攻击前，官方推荐已显示前置窗口但角色仍处于脱战帧时，AutoBurst 因 `out_of_combat` 门禁直接放弃 `注入 → 窗口` 序列的问题。

## 固定管线

```text
用户 arm（可见标签不变）
→ 官方精确前置窗口
→ 仅受控 preCombatBridge 取得窗口所有权
→ 4 个 Burst observation-only handoff
→ 前置注入候选
→ 进入战斗时保留计划
→ 注入确认
→ 窗口候选
```

## 窄例外与不变边界

桥接只能在以下条件同时成立时启动：`intentState=armed`、规则方向 `pre`、官方 SpellID 精确等于规则窗口、运行时仅受默认脱战策略影响或用户刚手动 arm、没有文本输入/手动让权/读条或引导/蓄力/死亡/载具等阻断。

- 普通脱战官方推荐不建立 capture 或 plan，不输出普通可派发 Token。
- UI 标签、Session Policy 名称、TEAP v3 20 字节布局、TEK 全局安全门禁与限频不变。
- bridge 帧保留协议真实 `inCombat=false`；只让带 `preCombatBridge=true` 的 Burst hold / 当前步骤临时编码为 `armed`，仍必须通过 BindingToken、CRC、Commit、前台、Hook、手动接管、新鲜度和限频门禁。
- 任何窗口离开、Token/绑定失效、人工暂停、文本输入、读条/引导/蓄力、死亡、载具或计划终止都立即回到既有 fail-closed 行为。

## 四帧 handoff

真实 `paused → armed` 时，状态/事件 Refresh 先输出 hold 但不消耗预算；随后四张 scheduled transport tick 都输出 `dispatch_origin=burst + observation_only=true + BindingToken=0`，第 5 张新鲜 Burst 帧才可能输出前置注入。

## 跨进战

`PLAYER_REGEN_DISABLED` 若命中有效 `preCombatBridge` capture / plan：

```text
保留 capture / plan / window generation / handoff budget
→ 标记 preCombatBridgeEnteredCombat=true
→ 记录 precombat_burst_bridge_combat_entered
```

非 bridge 的战斗边沿继续按历史规则清理状态。

## 诊断与回归

- 生命周期：`precombat_burst_bridge_started`、`precombat_burst_bridge_combat_entered`；
- 映射：`preCombatBurstBridge`、`preCombatBridge`、`preCombatBridgeEnteredCombat`；
- 回归：普通脱战非窗口不启动；脱战前置窗口必须经过四帧 hold 才出现注入；进战边沿不清除 bridge plan；原战斗内 `注入 → 窗口` 不退化。
