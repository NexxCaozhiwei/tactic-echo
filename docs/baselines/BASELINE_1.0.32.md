# Tactic Echo 1.0.32 基线：HUD 冷却快照统一与设置页收口

## 保留的稳定链路

以下模块与 1.0.31 保持行为不变：

- `AutoBurst.lua` 有序多步骤计划、简易/集中预检、运行期漂移处理；
- `GCDGate.lua` 的共享 GCD 时序判定；
- 四张 observation-only handoff、脱战起手 bridge 与切图安全围栏；
- 官方推荐 → 动作条绑定 → BindingToken → TEAP → TEK 的唯一派发路径。

## HUD 冷却展示合同

- `IconState` 是 HUD 冷却事实的唯一归并层。每张卡每次刷新生成一份纯标量 `cooldownPresentation`，其中包含自身 CD、纯 GCD、充能、文本模式、来源与短期连续性结果。
- `TacticalIconButton` 不得再调用 `C_Spell`、`C_ActionBar`、`CooldownResolver` 或其他 CD API 重新裁决；它只消费 `cooldownPresentation`。
- DurationObject 仅存于 `TE.HudCooldownDurationObjects` 的短生命周期侧车，供转盘动画使用。模型、SavedVariables、Trace 与 HUD card data 不得保存原始 DurationObject 或受保护值。
- 自定义 HUD CD 文本为默认；原生数字仅在用户显式选择 `duration` 模式时显示。
- 主键、窗口技能的纯 GCD 必须隐藏；饰品 13/14 不显示共享 GCD；自身 CD 与共享 GCD 同时存在时，显示自身 CD。
- 可信直接动作条的真实自身 CD 数值可用于 HUD，但仅为展示数据，不得影响 AutoBurst、TEAP、TEK、BindingToken、步骤跳过或成功确认。

## 设置页合同

- 控制面板周期刷新仅刷新当前可见页面；隐藏页控件、排序列表与文本输入不得在后台反复刷新。
- 运行时 readout 至少预留两行高度；爆发页说明采用“官方窗口候选库”“窗口优先级”“注入优先级”等明确文案。
- 候选栏只影响 HUD 提示，不改变自动爆发顺序、BindingToken 或输入权限。

## 必测回归

1. 自身 CD 与共享 GCD 同时存在时，HUD 显示真实自身 CD；主键/窗口纯 GCD 不显示数字或转盘；饰品不显示共享 GCD。
2. 直接动作条真实 CD 与旧 SpellID 基础 CD 冲突时，HUD 自定义数字跟随实际动作条数值。
3. API 短暂不可读时，已确认的 HUD CD 数字连续，不闪空。
4. 简易/集中多步骤计划、前置 handoff、切图围栏与战斗内爆发链与 1.0.31 一致。
5. 设置页切换、滚动、调整爆发顺序和样式时，无长文本重叠、控件闪动或焦点跳动。
