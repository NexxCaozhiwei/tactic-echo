# Tactic Echo 1.0.17 基线：装备饰品 HUD 通用 GCD 覆盖层隔离

## 目标

修复 1.0.16 后仍可在 13/14 槽饰品卡上看到公共 GCD 转盘/倒数的问题。该问题属于 HUD 的第二条独立绘制路径，不影响 AutoBurst 计划、饰品确认或 TEK 输入。

## 根因

`UI/TacticalIconButton.lua:updateCooldown()` 同时维护：

1. 主 CD 框 `card.cooldown`：用于技能或物品自身 CD；
2. 独立 GCD 框 `card.gcdCooldown`：用于普通技能的公共 GCD 提示，并在数值路径或 `61304` DurationObject 路径渲染。

1.0.16 已阻止饰品主 CD 框把动作条共享 GCD 误画成饰品 CD，但没有关闭第二个 `card.gcdCooldown` 层。饰品自身 ready、普通公共 GCD 活跃时，该层仍会在饰品卡上显示约 1～1.5 秒转盘。

## 固定合同

1. 对 `inventorySlot=13|14` 的装备饰品卡，`card.gcdCooldown` 必须始终隐藏；不得绘制数值 GCD，也不得调用通用 `61304` DurationObject 覆盖。
2. 饰品自身已确认的非 GCD CD 仍只使用主 CD 框显示，取源权威保持：装备 ItemID → 动作条回退 → 常规 ItemID 回退。
3. 非装备饰品卡的普通技能继续保持既有 GCD 显示策略。
4. 仅限 HUD 呈现：不得改变冷却采样、AutoBurst 逻辑、BindingToken、TEAP、TEK、输入频率或安全门禁。

## 实机复测

1. 13 槽与 14 槽饰品均未使用时，施放任意普通 GCD 技能：两张饰品卡均不得显示 GCD 转盘或倒数。
2. 饰品自身进入真实 CD：显示该物品 CD；若此时触发普通 GCD，不能再叠加第二层短转盘。
3. 普通主技能、Burst 技能、打断与防御卡的 GCD 提示应保持原有行为。
4. 前置/后置饰品注入、AutoBurst 持续候选、精确 ItemID 确认和人工恢复均按 1.0.15/1.0.16 原合同回归。
