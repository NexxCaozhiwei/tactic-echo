# Tactic Echo 1.0.19 基线：前置窗口接管屏障与跨端新鲜度围栏

## 目标

修复 `paused → armed` 时，旧的官方窗口帧可能先被 TEK 消费，导致前置规则出现“窗口先按、注入后按”的跨端竞态。

## 先仲裁、后编码

```text
官方推荐窗口
→ AutoBurst 前置规则仲裁
→ PreWindowCapture / BurstPlan
→ 当前唯一动作（注入候选或 Burst Hold）
→ 解析该动作 BindingToken
→ TEAP v3
→ TEK 新鲜度/频率门禁
```

`BindingToken` 仍只代表当前真实动作条绑定；TEAP 第 15/16 格不得复用为 Burst 步骤或计划标识。Burst 计划保持在 AddOn 内部状态与映射诊断中。

## 前置窗口所有权

当官方推荐精确命中 `pre` 规则窗口时，AutoBurst 必须先建立 `PreWindowCapture`：

- 计划与绑定可立即确定：输出前置注入候选；
- 计划构建、绑定、冷却快照或重校验暂未稳定：输出 `armed + observationOnly + dispatchOrigin=burst + BindingToken=0`；
- 在注入确认或规则允许的自身 CD 跳过前，绝不回退输出官方窗口 BindingToken。

真实 `paused → armed` 重启会先产生一张 Burst handoff hold，再输出注入候选。启动时的首次观察（没有既存非 armed epoch）不额外强加此帧。

## TEK 新鲜度围栏

TEK 对任何 `observationOnly`、暂停、等待、引导、蓄力或其他不可派发帧都记录最新 `frameFreshnessCounter`。之后只有严格更新的新鲜 `armed` 帧可进入派发。

因此：

```text
Burst handoff hold freshness=N
→ 延迟到达的官方窗口 armed freshness≤N：拒绝
→ 新 Burst 注入 armed freshness>N：按现有全局频率门禁派发
```

不增加 Burst 专用输入通道、固定重试上限或 TEAP 字节。

## 故障关闭

若 Evaluate 在前置窗口 capture 期间异常：

- AutoBurst 对 capture 建立窗口离开锁；
- SignalFrame 以 observation-only Burst hold 输出当前帧；
- 官方窗口必须离开后才可再次正常获取。

## 不变边界

- AutoBurst 不直接输入；
- 普通官方推荐、Burst 候选仍共同走 BindingToken → TEAP → TEK；
- 同一逻辑步骤可按全局频率持续派发，但只由精确 CD/充能/施法成功事件推进；
- 物品仍必须按锁定 slot + ItemID 的非 GCD 自身 CD 确认。
