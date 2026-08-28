# Tactic Echo 1.4.6 基线：自动注入所有权交接边沿

## 基线结论

`1.4.6` 修复 1.4.5 再审计发现的 departure-lock 同帧交接、capture 配置失效放行、重复 runtime 快照确认及手工所有权写入不一致。唯一 Coordinator、唯一 OrderedPlan、唯一 capture 和唯一候选架构不变。

## 所有权交接

- departure lock 从组 1 窗口直接观察到组 2 窗口时，Coordinator 必须先以组 1 仍拥有执行器的事实标记组 2 为 `group_window_ignored_while_owner_active`，随后才释放组 1；组 2 必须离开并重新进入才能建立计划。
- `activeGroupId` 仅表示 plan、pre-window capture 或 departure lock。所有手工建锁路径必须同步 Claim，所有无锁终止路径必须同步 Release。
- `recordDecision.activeGroupId`、HUD 和 Coordinator snapshot 均不得把仅用于 `<profileKey>:<groupId>` 状态命名空间的 `runtimeGroupId` 当作活动所有权。

## Capture 与确认

- 已拥有的 pre-window capture 遇到任意 Abort 原因时，必须先建立 departure lock 再释放 capture。活动组关闭、模式/签名变化、配置非法、脱战或 evaluator fault 都不能让仍可见窗口在同帧 fail-open。
- 冷却开始或充能减少的 fallback confirmation 继续要求至少两个样本并稳定 0.15 秒；runtime cycleId 可用时，两个样本必须来自不同 cycle。重复事件刷新读取同一缓存快照不得推进。
- 精确成功事件仍可立即确认；精确失败、装备变化、冷却回滚、普通 GCD、图标灰度与 UNKNOWN 仍不能推进。

## 诊断与安全边界

- `lastIgnoredEvent` 只描述忽略事件；普通所有权释放原因写入独立 `lastReleaseReason`，协调器重置原因写入 `lastResetReason`。
- 未修改 persistent recovery 产品策略、BindingToken、TEAP v3 20 字节、flags `0x20`、`dispatchOrigin="burst"` 或 TEK。
- 未新增并行状态机、事件、OnUpdate、轮询器、候选源或输入路径；离线测试仍不能替代 WoW Retail 与 Windows 实机验收。
