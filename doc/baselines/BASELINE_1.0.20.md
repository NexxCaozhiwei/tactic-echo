# Tactic Echo 1.0.20 基线：持久前置窗口 handoff 屏障

## 目标

修复 1.0.19 中前置窗口 `paused → armed` handoff hold 只持续约 18–32 ms、可能被 TEK 50 ms 采样跨过的问题。

## 固定管线

```text
官方窗口
→ AutoBurst 前置规则仲裁
→ PreWindowCapture / BurstPlan
→ 持久 Burst observation-only handoff hold
→ 前置注入候选
→ 窗口候选
```

前置规则命中窗口后，TEAP 不得回退给官方窗口 BindingToken。计划、绑定、冷却或状态仍在重校验时，输出 `state=armed + observationOnly=true + dispatchOrigin=burst + BindingToken=0`。

## 四帧 transport handoff

真实 `paused → armed` 且首个官方推荐已是前置窗口时：

```text
state/event Refresh      → Burst hold（不计入 transport 帧预算）
transport tick #1        → Burst hold，remaining=3
transport tick #2        → Burst hold，remaining=2
transport tick #3        → Burst hold，remaining=1
transport tick #4        → Burst hold，remaining=0
下一张 fresh transport帧 → 前置注入 BindingToken
```

- 每张 hold 都更新 TEAP freshness，并由 TEK 作为非派发 freshness 围栏。
- 屏障以 `SignalFrame` 的实际 transport tick 计数，不使用固定休眠、GCD 延迟或 Burst 专用输入频率。
- 计划、步骤、确认基线、候选尝试与全局 TEK rate limiter 不因 handoff 帧而重置。
- capture 在绑定/样本未稳定时也沿用同一帧计数；待计划建立后，剩余预算会转移到计划，不能被事件刷新压缩。

## 诊断

`/temapping` 与 `TacticEchoDB.autoBurst` 新增/保留以下字段：

- `handoffBarrierRequiredFrames`
- `handoffBarrierRemainingFrames`
- `handoffBarrierPublishedFrames`
- `handoffBarrierPending`
- `pre_window_capture_handoff_barrier`
- `pre_window_capture_handoff_ready`

实机 Trace 中，四张 hold 均应为 `dispatch_origin=burst + observation_only=true + binding_token=0`。在注入成功或规则允许的自身 CD 跳过前，不得出现可派发官方窗口 Token。

## 不变边界

- TEAP v3 字节布局不变；15/16 格仍只表示当前 BindingToken。
- AutoBurst 不直接输入；普通与 Burst 候选继续共用 BindingToken → TEAP → TEK 与同一全局安全门禁/限频。
- 物品确认仍必须匹配锁定 inventory slot + ItemID 的非 GCD 自身冷却。
