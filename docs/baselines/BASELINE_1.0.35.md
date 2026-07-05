# Tactic Echo 1.0.35 基线：打断卡不透明冷却展示修复

## 本版范围

本版以 1.0.34 为基线，**只修打断/控制 HUD 卡在“公开状态确认正在自身 CD、但当前数值不可物化”时不显示转盘/数字的问题**。爆发窗口、注入和防御卡在 1.0.34 已能正常展示，本版不回退、不重写这些路径。

## 保持不变

- AutoBurst 有序多步骤计划、简易/集中预检、运行期漂移处理；
- GCDGate、四帧 handoff、起手 bridge、切图安全围栏；
- 官方推荐 → 当前动作条绑定 → BindingToken → TEAP → TEK 的唯一派发路径；
- HUD 自定义 CD 样式、主键/窗口纯 GCD 隐藏、饰品 13/14 共享 GCD 隔离、CD 数字连续性缓存；
- 1.0.34 已恢复正常的爆发窗口、注入和防御 CD 展示。

## 问题与修复

打断卡常通过“目标读条建议 / 常驻打断提示”在独立 tactical lane 中临时创建。部分零售客户端在该时刻只返回：

```text
isActive=true
isOnGCD=false
start/duration=opaque
```

旧逻辑将 `cooldownKnown=false` 等同于“没有自身 CD”，不为卡片请求 spell-specific ignore-GCD `DurationObject`，因此转盘消失；随后也没有可供 HUD 文本恢复的动态动作条确认。

1.0.35 规则：

1. 公开 `isActive=true` 且已确认非 GCD，即使标量数值暂不可读，也认定为“自身 CD 正在进行”；
2. 此时只尝试 **spell-specific ignore-GCD DurationObject**，不得借用通用动作条对象，避免把共享 GCD 画成打断 CD；
3. `CooldownTracker` 在事件确认和脱战同步时新增可信直接动作条的**实际动态数值**采样，作为 HUD 文本恢复来源；
4. 不使用 Tooltip、`GetSpellBaseCooldown` 或静态值为直接动作条打断技能伪造时间；没有安全数值时仍只显示转盘，直到客户端/动作条给出真实数值。

## 验收重点

- 打断技能进入自身 CD：应至少稳定显示一套非 GCD 转盘；数值 API 可读时显示同一套可配置 HUD 数字。
- 主键/窗口纯 GCD、饰品纯 GCD 仍隐藏；打断的通用共享 GCD不应冒充自身 CD。
- 爆发窗口、注入、防御与饰品的已正常 CD 展示不退化。
- AutoBurst 计划、预检、派发与切图围栏保持 1.0.34 行为。
