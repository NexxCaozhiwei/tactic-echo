# Tactic Echo 1.4.10 基线

`1.4.10` 在不改变 1.4.9 自动注入运行边界的前提下，为 HUD 多充能技能补齐 12.0+ 秘密值安全的原生充能恢复转盘。

## HUD 充能转盘

- 仅真实 `maxCharges > 1` 的技能进入充能恢复转盘路径；普通技能的 `1/1` 继续隐藏。
- 已验证直接默认动作槽位优先调用 `C_ActionBar.GetActionChargeDuration()`；不可用时按精确等效 SpellID 调用 `C_Spell.GetSpellChargeDuration()`。
- 返回的 `DurationObject` 只可直接传给 `Cooldown:SetCooldownFromDurationObject()`。不得比较、执行算术、调用秘密 `IsZero()`、持久化、导出或传入 HUD 模型。
- DurationObject 不可用时，允许回退到 `IconState` / `CooldownTracker` 已确认的安全充能起止数值；未知状态不伪造转盘。
- 原生 CountdownNumbers 始终隐藏；HUD 徽标仍是唯一数字层，只显示已确认的安全普通标量。

## 不变边界

- 普通技能主冷却仍沿用 1.0.31 实时 DurationObject 转盘与 1.0.38 纯秒数徽标策略。
- 不接入 Blizzard Cooldown Manager，不新增事件、OnUpdate、全局轮询器或输入路径。
- 充能 DurationObject 只负责视觉展示，不影响 AutoBurst 预检、步骤确认、BindingToken、TEAP、TEK 或任何派发资格。
- 1.4.9 的前置注入冷却边沿 observation-only 有界复检与全部多组所有权约束保持不变。
