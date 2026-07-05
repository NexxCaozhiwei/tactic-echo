# Tactic Echo 1.0.48 P5.3.1 基线：目标管理宏兼容恢复与代表 SpellID 宏名恢复

## 现场问题

P5.3 的钢条稳定与打断冷却门控均已进入实机状态，但最新日志显示自动打断在第三次兼容观察后被：

```text
macro_managed_target_target_unverifiable
```

阻断。当前玩家的反制射击宏为严格的焦点优先、选敌回退、恢复目标形态；P5.3 将所有含目标管理命令的 target 路由一律封死，造成 P4.3 已验证动作链无法使用。

同时，Retail 可在动作条返回代表 SpellID `147362`，`GetActionText(actionSlot)` 为空，`GetMacroInfo(147362)` 只能提供宏名“反射”而不给正文。P5.1 的唯一语义匹配没有继续使用该名称，导致后续缓存重建可能丢失宏正文关联。

## P5.3.1 规则

### 1. 严格 legacy 宏 target 兼容

仅恢复以下已解析形态的 current-target 兼容路由：

```lua
/cast [@focus,nodead] 反制射击
/cleartarget
/targetenemy
/cast 反制射击
/targetlasttarget
```

必须同时满足：

- `macroManagedTargetFallback=true`；
- `managedTargetRouteOrder = { "focus", "target" }`；
- 当前来源是 `target`；
- 没有存活、敌对的 `focus` 会先命中第一条宏分支。

此时记录 `macro_managed_target_target_compat`，允许沿 P4.3 的既有 BindingToken → TEAP reaction → TEK 路径派发。普通当前目标按钮仍在 P2 优先级中高于该兼容宏。

以下仍拒绝：

- 任意不具有上述精确 metadata 的目标管理宏：`macro_managed_target_target_unverifiable`；
- 有存活敌对焦点时 target 来源：`macro_managed_target_target_preempted_by_focus`；
- mouseover 来源的任何目标管理宏。

AddOn 不执行、改写或模拟 `/cleartarget`、`/targetenemy`、`/targetlasttarget`；这些仍完全由玩家已有宏的原生执行语义决定。

### 2. 代表 SpellID 的宏名语义恢复

当 `GetActionInfo(actionSlot).id` 不属于当前宏索引范围时，它只可作为代表 SpellID，不能作为 macro index。若 `GetActionText` 为空，解析器可从该 action-info handle 只读取得宏名；这个名称只作为语义 join key：

```text
宏名
+ 代表 SpellID
+ 当前真实宏 index 的已解析正文
→ 唯一候选才恢复
```

若同名同技能候选多于一枚，继续 `macro_semantic_identity_ambiguous` fail-closed。不会以宏名直接读取或盲选正文。

## 延续 P5.3 的不变项

- 兼容读条仍须同一 `castKey` 连续 3 个 shared-observation 样本；
- API 明确不可打断、真实可见盾、`NOT_INTERRUPTIBLE`、native scalar/method 钢条嫌疑仍阻断；
- 打断动作的已知、非 GCD 自身冷却仍返回 `interrupt_action_cooldown`，不占主键；
- TEK、TEAP、BindingToken、Burst 与 HUD CD 逻辑均未修改；无需重建 `TEK.exe`。
