# Tactic Echo 1.0.44 P5 当前开发基线

`1.0.44 P5` 是当前唯一开发基线。早期版本仅保留历史记录，不得从旧版本恢复已废弃入口、字段或运行时规则。

## 基线继承

- AutoBurst 与常规输入路径继续以 `1.0.35` 的冻结输入链为底线。
- HUD 冷却渲染继续以 `1.0.31` 已实测稳定的实时转盘路径为基础。
- `1.0.38` 收口为：`DurationObject` 只画转盘，HUD 徽标统一纯秒数。
- `1.0.39 P1-P3` 提供设置、动作条/宏映射、只读读条候选与 HUD 高亮。
- `1.0.40 P4.3` 证明 reaction 的 `BindingToken -> TEAP -> TEK` 动作链可用。
- `1.0.41 P4.4` 恢复严格钢条/可打断证据。
- `1.0.42 P4.5` 守卫 `@mouseover -> @focus -> target` 单技能整合打断宏。
- `1.0.43 P4.6` 修复多行打断宏正文回收与 SpellID 关联韧性。
- `1.0.44 P5` 将宏身份收紧为动作条 `actionInfoID` 的 numeric macro index，彻底移除按宏名回收正文路径。

## 唯一常规输入链

```text
官方推荐（只读）
-> 当前可见 Blizzard 默认动作条绑定
-> BindingToken
-> TEAP v3
-> TEK 协议 / 前台 / Hook / 手动让权 / 限频门禁
-> 单次 SendInput
```

禁止新增绕过链路。AddOn 不得创建隐藏按钮、写按键、保存按键、编辑宏、合成宏、直接调用 Windows 输入或写虚拟键值。

## AutoBurst 边界

AutoBurst 是官方推荐之上的受控候选层，不是第二条输入通道：

```text
OfficialRecommendation（不可变）
-> AutoBurst OrderedPlan（候选）
-> 已解析 BindingToken
-> TEAP v3（dispatchOrigin=burst）
-> TEK 全部门禁
-> 单次 SendInput
```

每专精保存独立 `autoBurstSequence`，步骤身份只允许：

- `window`：固定存在，不可停用。
- `injection:<SpellID>`：最多 3 个，来自当前专精已启用注入技能列表。
- `trinket:13` / `trinket:14`：固定装备槽身份，计划创建时锁定实际 ItemID。

不得按注入槽位、动作条键位、瞬时 ItemID 或跨专精全局变量保存顺序。旧 Phase 1.5 的手填窗口/注入 SpellID、方向、单饰品入口和 fallback 字段不得恢复。

预检只允许使用 `IconState:CollectCooldownOnly()`、`CollectInventoryCooldownOnly()`、`GCDGate`、已验证动作条绑定和当前官方推荐。Buff、Debuff、资源、目标生命、敌人数量、首领机制、距离、范围或读条对象不得成为爆发时机输入。

## AutoReaction 与宏身份

P4 只允许 `AutoReaction` 生成自动打断候选，不得实现单体控制、群控、HUD 点击、自动选目标或宏改写。

P4/P5 自动打断必须同时满足：

- 战斗内，intent/effective state 均为 `armed`。
- 敌对且存活。
- P3 证明为真实活跃读条，且不是 `transient_gap_hold`。
- 已有 P2 `safeForFutureAuto=true` 的真实 BindingToken 路由。
- 可打断证据满足 P4.4 严格优先级，未知、桥接、profile fallback、native scalar-only true 均不得授权。

P5 宏身份锚定规则：

- 当前可见动作条上宏的唯一正文身份是 `GetActionInfo(actionSlot)` 返回的 numeric `actionInfoID`。
- 首读仅有名称或无正文时，只能对同一 numeric index 有界重读。
- 禁止 `GetMacroInfo(name)`，禁止按账号/角色宏名枚举，禁止借用另一枚同名宏正文。
- 当前 index 无正文必须 fail-closed，即使另一同名宏包含请求技能也不得授权。
- 宏正文不得持久化，不得进入 SavedVariables、TEAP、TEK trace 或映射导出。

## HUD 冷却展示

- `IconState`、`CooldownResolver`、`CooldownTracker` 负责 CD/GCD/充能安全语义和标量状态。
- `TacticalHudModel` 只传递普通标量，不保存 `DurationObject`、受保护值、宏正文或派发权限。
- `TacticalIconButton` 可为视觉展示实时查询客户端 `DurationObject` 绘制转盘，但不得回写推荐、AutoBurst、BindingToken、TEAP、TEK 或输入条件。
- `DurationObject` 的 CountdownNumbers 必须隐藏。HUD 徽标是唯一数字层，只使用安全数值并统一向上取整显示纯秒数。
- 主键与 Burst-window 的纯共享 GCD 必须隐藏。物品卡不得显示泛 GCD。自身 CD 与共享 GCD 同时存在时展示自身 CD。
- `BuildCooldownPresentation`、`TE.HudCooldownDurationObjects`、`cooldownPresentation` 侧车、`runtimeDurationObject`、`showSnapshotDurationObject` 不得恢复。

## 协议和审计

- TEAP v3 保持 20 字节长度。
- flags bit `0x20` 固定表示 `dispatchOrigin=burst`。
- SignalEncoder 使用 bit `0x40` 标记 `reaction`。
- TEK 在 `0x20 | 0x40` 同时存在时拒绝帧。
- Trace 与状态快照必须暴露 `dispatch_origin` / `last_dispatch_origin`。
- 诊断只导出纯标量摘要，不导出宏正文、原始受保护 cooldown 数值或用户敏感数据。

## 绝对禁止

- HUD、Tooltip、视觉层、防御、打断、控制、位移或普通 Burst 展示层建立 Token、改写官方推荐、写 TEAP 或请求 TEK 输入。
- AutoBurst 绕过 BindingToken、TEAP、TEK、前台、Hook、手动让权、新鲜度、CRC、会话、限频或动作条解析。
- 用固定睡眠毫秒代替 `GCDGate` 与确认状态机。
- 将原始 GCD 剩余数值泄漏给 AutoBurst 状态机；原始数值只能存在于 `GCDGate` 时序适配层。
- Bootstrap 之外直接 `:RegisterEvent()`；AddOn 仅可经 `TE:RegisterEventSafe` / `TE:RegisterEventsSafe` 注册一次性事件。
