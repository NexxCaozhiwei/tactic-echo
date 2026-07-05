# Tactic Echo 1.0.24 基线：直接动作条数值 CD 兼容

## 问题背景

射击猎人规则 `乱射 260243（窗口） → 百发百中 288613（注入）` 的第二轮实测表明：`288613` 已处于自身 CD，TEK 多次收到 `UNIT_SPELLCAST_FAILED`，但 `C_Spell` 临时显示 ready，且该客户端的 `C_ActionBar.GetActionCooldown` 没有给出可用的 `isActive / isOnGCD` 布尔证据。1.0.22 的布尔路径因此无法完成两次 CD 证书，计划持续锁在注入步骤。

## 修复目标

只为**同一直接可信默认动作条按钮**补充一个只读、内部的自身 CD 分类来源：

```text
可信直接按钮
+ 公开 action-bar 冷却数值安全可读
+ remaining > 0
+ duration > 2.25s（严格排除共享 GCD）
→ actionbar_duration own-CD evidence
→ 两次同一 SpellID / 同一 BindingToken 采样
→ simple 注入跳过
→ 继续窗口步骤
```

## 不变项

- 不根据 `UNIT_SPELLCAST_FAILED` 单独跳过：该事件无法区分 CD、资源、距离、目标或其他失败原因。
- 不读取或输出保护数值；若 start/duration 无法安全 materialize，则证据为 UNKNOWN。
- 不使用图标灰度、HUD `DurationObject`、资源、目标、距离、Buff、宏推断或非直接按钮。
- 持续时间 `<= 2.25s` 的动作条读数不构成自身 CD 证据，避免将共享 GCD 误跳过。
- `actionbar_duration` 不改变 TEAP / TEK、BindingToken、派发频率、窗口所有权、起手桥接或 UI 标签。

## 回归要求

1. 已有 `isActive=true + isOnGCD=false` 动作条布尔路径保持有效，且显式 `false` 不得丢失；
2. 无布尔值但有长时真实动作条 CD 时，两次独立样本后 `simple` 注入跳过并推进窗口；
3. 共享 GCD、短 CD、UNKNOWN、非直接或不可信动作条不得形成 `actionbar_duration`；
4. 所有既有窗口接管、四帧 handoff、起手 bridge 和常规战斗内 Burst 回归不得退化。
