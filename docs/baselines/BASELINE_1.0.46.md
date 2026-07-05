# Tactic Echo 1.0.46 P5.2 基线：P4.3 兼容打断派发与宏命中守卫

## 背景

P4.3 已由实机确认下列动作链可用：

```text
真实读条
→ 现有动作条/宏 BindingToken
→ TEAP v3 reaction（0x40）
→ TEK 既有前台、Hook、人工接管、新鲜度、限频门禁
→ 一次玩家已有键位
```

P4.4 的严格证据层在目标 Retail 客户端中经常只得到
`interruptibility_unconfirmed`：读条存在，但 API 的可打断标量、正向
`UNIT_SPELLCAST_INTERRUPTIBLE` 与可验证的原生无盾证据均不可取得。此时
P5.1 的宏身份修复不会被执行，因为 P4 根本不会生成 reaction candidate。

P5.2 恢复 P4.3 已实测的候选交付能力，但不恢复“忽略任何钢条”的探测例外。

## P5.2 打断资格

候选仍必须满足：战斗内、intent/effective state 均为 `armed`、敌对存活、
真实活跃读条（非 `transient_gap_hold`）以及已有 P2 `safeForFutureAuto=true`
真实 BindingToken 路由。

资格分为两层：

1. **严格确认**：直接 API 明确可打断、当前同源正向单位施法事件、或连续
   原生无盾/明确可打断视觉证据，保持 P4.4 行为。
2. **兼容派发**：配置 `compatibilityActiveCast=true`（默认）时，真实活跃读条
   缺少正向证据仍可进入稳定 reaction candidate，但仅限于没有任何硬否决的情况。

以下结论始终硬否决，兼容模式也不得放宽：

- 直接 API 明确不可打断；
- 当前真实原生盾组件可见；
- 同源有效 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE`；
- 当前原生路径明确不可打断。

`showShield`、`barType`、native scalar-only、未知值和短暂读条桥接仍只可诊断，
不是放行或否决依据。

## 宏兼容规则

P5.1 的宏身份确认继续有效：动作条 numeric macro index 可验证时只读同一 index；
代表 SpellID 路径必须以“动作条宏名 + 代表 SpellID + 宏正文语义”唯一匹配。
同名同技能多候选仍 `macro_semantic_identity_ambiguous` fail-closed，宏正文不导出。

P5.2 支持的打断目标路由如下：

- 普通动作条技能：仅当前目标；
- 单路由 `@focus` / `@mouseover` 宏：对应来源；
- 严格 `@mouseover → @focus → target` 单技能整合宏：只有实际宏优先分支会命中
  被观察读条来源时才自动派发；上游活敌会阻断下游候选；
- `@focus → /cleartarget → /targetenemy → 同技能 → /targetlasttarget` 宏：
  仅可对**焦点读条**自动派发。后续 `/targetenemy` 的最终单位要在按键后才由
  Blizzard 选择，无法证明等于 P3 当前目标，因此当前目标候选必须
  `macro_managed_target_fallback_target_unverifiable` fail-closed。

若同时有普通当前目标按钮与目标管理宏，P2 优先普通当前目标按钮。

## 不变项

- AddOn 不改写宏、不创建宏、不切换目标、不移动鼠标、不点击姓名板；
- 不新增 BindingToken、TEAP 格式或 TEK 输入路径；
- 同一读条仍保持稳定 reaction candidate / stable sequence；TEK 成功输入后去重；
- Burst plan 或 pre-window capture 活跃时，reaction 仍仅高亮、不派发；
- 单体控制、群控和 AutoBurst 状态机不在本版修改范围。
