# Tactic Echo 1.0.33 基线：HUD 单计时源稳定化

## 保留的稳定链路

以下功能与 1.0.32 / 1.0.31 保持行为不变：

- AutoBurst 有序多步骤计划、简易/集中预检、运行期漂移处理；
- GCDGate 的共享 GCD 时序判定；
- 四张 observation-only handoff、脱战起手 bridge 与切图安全围栏；
- 官方推荐 → 动作条绑定 → BindingToken → TEAP → TEK 的唯一派发路径；
- HUD 自定义 CD 样式、主键/窗口纯 GCD 隐藏、饰品 13/14 共享 GCD 隔离、CD 数字连续性缓存。

## HUD 单计时源合同

- `IconState` 继续是每张 HUD 卡片的唯一冷却归并层，输出一份标量 `cooldownPresentation`。
- 当该快照拥有安全的自身 `start/duration` 时，`TacticalIconButton` 必须优先使用该同一标量驱动冷却转盘与 HUD 自定义数字；不得让另一份 ActionBar/宏/覆盖状态 `DurationObject` 同时主导转盘。
- `DurationObject` 只保留为标量 `SetCooldown()` 无法挂载时的后备转盘；普通技能卡仅可使用 spell-specific ignore-GCD 对象，不能借用通用动作条对象。
- 自定义 CD 文本模式下，每次动态 HUD 刷新均要重新隐藏 own / GCD / charge 原生倒计时数字，防止客户端异步恢复原生数字后与 HUD 自定义数字重叠。
- 原生数字仍仅对应显式 `duration` 文本模式。
- 此展示修复不得改变 AutoBurst 预检、计划跳过、成功确认、BindingToken、TEAP、TEK 或输入派发。

## 必测回归

1. 窗口技能、注入技能、打断/控制技能在自身 CD 时：同一张卡只出现一组 CD 数字；数字和转盘同步，且字体仍受 HUD 样式控制。
2. 直接动作条真实 CD 与旧 SpellID 基础 CD 冲突时：HUD 仍显示真实动作条数值。
3. 宏/覆盖技能、共享 GCD 与自身 CD 短暂并存时：不出现第二份原生数字、不把 GCD 显示为自身 CD。
4. 饰品 13/14、主键/窗口纯 GCD、充能卡和 API 瞬时不可读的连续性行为与 1.0.32 保持一致。
5. 简易/集中多步骤计划、前置 handoff、切图围栏与战斗内爆发链与 1.0.31 一致。
