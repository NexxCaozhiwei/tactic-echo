# Tactic Echo 1.0.40 P4.3 基线：自动打断动作链探测

## 目标

本版不是最终的钢条判定方案。它的唯一目的，是先验证当前客户端中完整自动打断输入链是否实际工作：

```text
P3 活跃读条 → AutoReaction → P2 安全 BindingToken → SignalFrame → TEAP v3 bit 0x40 → TEK 门禁 → SendInput
```

## 临时探测规则

- 自动打断开关开启后，只要来源按配置启用、单位敌对存活、处于战斗、TE intent/effective state 都是 `armed`，且 P3 仍证实为真实活跃读条、不是 `transient_gap_hold`，便可生成 reaction candidate。
- 当前版本刻意**不以钢条/未确认状态阻断**。`unit_api_not_interruptible`、`unit_event_not_interruptible`、原生可见盾和 `interruptibility_unconfirmed` 都会作为 `probeFallbackReason` 保留给诊断，但不影响此轮实机动作验证。
- P2 真实安全路由仍是硬要求：必须存在 `bindingReady=true`、`safeForFutureAuto=true`、非零 BindingToken 的已有动作条/宏路由。
- 不改变 Burst 冲突策略：AutoBurst active/pre-window capture 仍压制自动打断。

## 稳定交付规则

- 同一 `castKey` 的 reaction candidate 持续到读条消失或身份变化。
- `SignalFrame` 令此候选的 TEAP `sequence` 保持稳定；新鲜度仍按常规刷新推进。
- TEK 成功 SendInput 后记住这个 reaction sequence；同序列后续帧仅作为持续可见候选，不会再次发送按键。
- 只有实际成功 input 才进入 TEK 去重；前台、手动接管、限频、映射等门禁拒绝不会消耗候选，因此候选可在后续新鲜帧继续接受正常门禁检查。

## 验收重点

1. 读条出现时 `TacticEchoDB.autoReactionRuntime.last` 出现 `state="candidate"`、`reason="probe_interrupt_candidate"` 或 `confirmed_interrupt_candidate`。
2. TEK Trace 出现 `dispatch_origin="reaction"`。
3. 第一次允许的 reaction frame 出现 `input_sent`；同一读条后续 trace 如继续出现，理由应为 `reaction_candidate_already_dispatched`，而不是重复 SendInput。
4. 读条退出后恢复官方推荐；下一次新读条因 `castKey` 变化可得到新的 reaction sequence 与一次新的 SendInput。

## 需要回收的临时行为

实机确认动作链后，必须恢复 P4.2 的严格“确认可打断”派发资格，并把稳定候选/TEK sequence 去重保留为永久可靠性交付机制。
