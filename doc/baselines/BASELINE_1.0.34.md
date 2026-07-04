# Tactic Echo 1.0.34 基线：HUD 受保护冷却转盘恢复

## 保留的稳定链路

以下功能与 1.0.31–1.0.33 保持行为不变：

- AutoBurst 有序多步骤计划、简易/集中预检、运行期漂移处理；
- GCDGate 的共享 GCD 时序判定；
- 四张 observation-only handoff、脱战起手 bridge 与切图安全围栏；
- 官方推荐 → 动作条绑定 → BindingToken → TEAP → TEK 的唯一派发路径；
- HUD 自定义 CD 样式、主键/窗口纯 GCD 隐藏、饰品 13/14 共享 GCD 隔离、CD 数字连续性缓存。

## 1.0.33 回归与修复

1.0.33 将普通技能卡的转盘改为优先调用 Lua `Cooldown:SetCooldown(start, duration)`。部分零售客户端会拒绝插件使用受保护 CD 的标量起止值；同时该客户端没有为这些技能稳定提供 spell-specific `DurationObject`。结果是：

```text
饰品：物品专用 DurationObject 仍正常
普通技能 / 窗口 / 注入 / 打断控制：转盘与自定义 CD 文本同时消失
```

1.0.34 恢复普通技能的受控 `DurationObject` 转盘，但不恢复过去多来源竞争的结构。

## HUD 单对象 / 单文本合同

- `IconState` 继续是唯一 HUD 冷却归并层，输出一份标量 `cooldownPresentation`；`TacticalIconButton` 不得再次调用 Spell / ActionBar / Resolver CD API。
- 标量快照仍是唯一语义来源：它决定自身 CD、纯 GCD、充能、卡片文本与是否允许展示。
- 受保护客户端需要客户端 `DurationObject` 绘制转盘时，`IconState` 为一张卡只选择 **一个** sidecar 对象；渲染层不得再读取或替换该对象。
- 对 `actionbar_numeric` 或已验证直接动作条自身 CD，优先使用同一可信动作条的对象；否则依次尝试技能 ignore-GCD 对象、再尝试已验证 Resolver 动作条对象。
- 上述对象只有在标量快照已确认“自身、非 GCD CD”时才可使用。它不改变 CD 分类、AutoBurst 预检、计划跳过、成功确认、TEAP、TEK 或输入派发。
- 自定义 CD 文本继续只使用归并后的安全标量 / 连续性缓存；每次动态刷新仍强制隐藏 own / GCD / charge 原生数字，杜绝双数字。
- 主键与窗口的纯共享 GCD 继续隐藏；饰品 13/14 继续只使用 ItemID / inventory 自身 CD，绝不接受泛 GCD 对象。

## 必测回归

1. 爆发窗口、注入、打断/控制、防御卡进入自身 CD：恢复一套转盘和一套自定义数字。
2. 上述卡片自定义模式下不显示第二套原生数字；切换“原生（不可调整）”后才显示原生数字。
3. 主键/窗口纯 GCD、饰品泛 GCD 隐藏保持不变；自身 CD + GCD 同时存在时仍显示自身 CD。
4. 真实动作条 60 秒与旧 SpellID 120 秒冲突时，自定义数字继续取真实动作条数值。
5. 简易/集中多步骤计划、前置 handoff、切图围栏与战斗内爆发链保持 1.0.31 行为。
