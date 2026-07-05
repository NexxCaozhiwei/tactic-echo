# Tactic Echo 1.0.47 P5.3 基线：钢条稳定证据、打断冷却门控与目标管理宏守卫

## 背景

P4.3 已由实机确认下列动作链可用：

```text
真实读条
→ 现有动作条/宏 BindingToken
→ TEAP v3 reaction（0x40）
→ TEK 既有前台、Hook、人工接管、新鲜度、限频门禁
→ 一次玩家已有键位
```

P5.2 恢复了“真实活跃读条、无明确硬钢条”的兼容 candidate，但现场又发现两项问题：

1. 某些钢条读条在首张 `unit_event_pending` 观察中仍没有暴露可见盾，兼容路径会过早派发；
2. 反制射击等打断处于自身 CD 时，reaction 仍持续占用主键，阻塞正常官方序列。

P5.3 不改变 P4.3 的传输与稳定 candidate 机制，只收紧候选资格、补足冷却否决与目标管理宏守卫。

## P5.3 打断资格

候选仍必须满足：战斗内、intent/effective state 均为 `armed`、敌对存活、真实活跃读条（非 `transient_gap_hold`）以及已有 P2 `safeForFutureAuto=true` 真实 BindingToken 路由。

### 严格确认

以下路径保持 P4.4 行为：

1. `UnitCastingInfo` / `UnitChannelInfo` 可材料化的 `notInterruptible=false`；
2. 同源、未过期 `UNIT_SPELLCAST_INTERRUPTIBLE`；
3. 当前真实原生盾组件连续两次明确隐藏，或原生明确可打断连续两次；
4. 直接 API 与单位事件无需原生视觉稳定等待。

### 兼容候选

`compatibilityActiveCast=true`（默认）时，证据不透明的真实活跃读条仍可走 P4.3 交付链，但必须满足：

```text
同一 castKey
→ 3 次不同 shared-observation 样本
→ 无硬钢条结论
→ 路由存在且打断动作不在已知自身 CD
```

兼容模式的硬阻断为：

- `unit_api_not_interruptible`；
- `native_visible_shield`；
- `unit_event_not_interruptible`；
- `native_not_interruptible`；
- `compat_native_steel_suspected`：native scalar/method-only 不可打断 `true`。

后者不会被 P3 升格成“已验证钢条”，避免跨读条旧 scalar 造成错误提示；但它也不能被兼容自动派发解释成“无钢条”。

`showShield`、`barType`、短暂 bridge、profile fallback 和普通 unknown 均不能单独放行或否决。

## 原生盾组件探测

`ReactionObservation` 只读探测：

- 常见直接 shield 字段；
- Target/Focus/Nameplate castbar 常见全局 shield 子组件；
- 当前 castbar 中名称、atlas 或 texture 明确含 `shield`、`uninterruptible`、`notinterruptible` 的 child/region。

只有这些组件实际 `IsShown()` / `IsVisible()` 才能产出 `native_visible_shield`。普通装饰、`showShield` 模板能力和 `barType` 不被当作视觉证据。

## 打断冷却门控

候选路由准备后，`AutoReaction` 调用已有 `IconState:CollectCooldownOnly()`，针对 TEK 将实际按下的 action slot 读取：

- 技能自身已知、非 GCD CD 且没有可用 charges：返回 `interrupt_action_cooldown`，`bindingToken=0`，不产生 reaction candidate；
- 共享 GCD 不阻断；
- 冷却 unknown、读取失败、sampler 不存在只记录诊断，不伪造 CD；
- 已验证宏按钮仅可提供“自身 CD 中”的**否决**证据，不能用其 ready 状态建立候选资格。

当 reaction 返回 `kind="none"` 时，SignalFrame 回到官方正常推荐，因此主键不应持续显示打断技能。

## 宏路由边界

P5.1 的宏身份规则不变：numeric macro index 优先；代表 SpellID 路径要求“动作条宏名 + 代表 SpellID + 正文语义”唯一一致；不调用 `GetMacroInfo(name)`，同名同技能 fail-closed。

目标管理宏的安全边界为：

- 普通当前目标动作条技能 / 无目标管理的严格 target 宏：可承担 target 候选；
- 单路由 `@focus` / `@mouseover` 宏：仅对应来源；
- mouseover → focus → target 整合宏：仍按上游活敌分支守卫；
- 含 `/cleartarget`、`/targetenemy`、`/targetlasttarget` 的宏：仅可在焦点分支按键前可归属时自动使用；target 或 mouseover 不得自动使用任何后续目标管理分支。精确 fallback 元数据保留历史原因 `macro_managed_target_fallback_target_unverifiable`，其他解析形态使用 `macro_managed_target_target_unverifiable`。

## 不变项

- 不改写、创建、编辑或重排宏；不执行 `/target*` 指令；
- 不新增 BindingToken、TEAP 格式、TEK 输入路径或任何直接输入；
- 同一读条仍保持 stable reaction candidate / stable sequence；TEK 成功输入后去重；
- Burst plan 或 pre-window capture 活跃时，reaction 仍只高亮、不派发；
- AutoBurst、控制/群控和 HUD CD 渲染不在本版修改范围。
