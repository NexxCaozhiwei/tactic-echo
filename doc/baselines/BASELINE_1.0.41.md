# Tactic Echo 1.0.41 P4.4 基线：严格钢条判定与稳定自动打断

## 目标

1.0.40 P4.3 已在实机确认完整路径可用：

```text
敌方读条 → AutoReaction reaction candidate → BindingToken → TEAP v3 (0x40) → TEK 门禁 → 现有键位
```

P4.4 保留该稳定交付路径，取消 P4.3 的“忽略钢条动作探测”例外，恢复仅对**已确认可打断**读条自动派发。

## 固定证据策略

自动打断候选必须同时满足：战斗内、TE intent/effective 均为 `armed`、敌对存活、真实活跃读条、非 `transient_gap_hold`、已有 P2 `safeForFutureAuto=true` 路由。

可打断判定按下列顺序执行：

1. `UnitCastingInfo` / `UnitChannelInfo` 中可材料化的 `notInterruptible=false`：立即确认。
2. 当前真实原生盾组件可见：硬性否决；不会被缓存的正向事件覆盖。
3. 同源、未过期的 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE`：硬性否决；`UNIT_SPELLCAST_INTERRUPTIBLE`：确认。
4. 直接 API 仍不透明时，真实原生盾组件连续两次 P3 采样均隐藏，或连续两次明确原生 `interruptible/notInterruptible=false`：确认。
5. 其他任何状态均为未确认，只高亮，不派发。

以下字段仅作诊断，不能授权或否决自动输入：

- `showShield`
- `barType`
- 仅原生 `notInterruptible/isUninterruptible=true` 的 scalar
- P3 短暂连续性桥接
- profile fallback 或无法材料化值

## 交付可靠性

- 同一 confirmed cast 仍保持稳定 `reaction` candidate，直到读条结束或身份变化。
- SignalFrame 为它保持稳定 TEAP sequence。
- TEK 仅在该稳定 reaction sequence 首次成功输入后去重。
- P4.4 不改 TEK 可执行逻辑，不新增输入通道，也不要求因本版重新构建 TEK.exe；前提是正在使用已包含 P4.3 reaction 去重逻辑的 TEK.exe。

## 事件缓存修复

`UNIT_SPELLCAST_INTERRUPTIBLE` / `NOT_INTERRUPTIBLE` 在部分客户端可能不携带 spellID / castGUID。P4.4 保留最近一次 START 事件的可读 identity，status 事件携带 nil 时不得覆盖它；TTL、读条终止和目标切换仍会清空缓存。若两端 spellID 都可读且不同，仍 fail-closed。

## 实机验收

见 `docs/P4.4_NATIVE_SHIELD_REVALIDATION_TEST.md`。
