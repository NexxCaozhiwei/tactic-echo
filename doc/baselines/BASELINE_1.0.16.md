# Tactic Echo 1.0.16 基线：装备饰品 HUD 共享 GCD 显示修复

## 目标

修复 13/14 槽饰品卡在公共 GCD 期间错误显示约 1～1.5 秒饰品倒计时的问题。该问题仅发生在 HUD 的原生 `DurationObject` 展示层，不影响 AutoBurst 的饰品确认或 TEK 输入。

## 根因

`UI/TacticalIconButton.lua` 读取已绑定动作条饰品按钮的 `C_ActionBar.GetActionCooldownDuration(actionSlot)`。该对象会反映当前公共 GCD；旧代码没有保留 `C_ActionBar.GetActionCooldown(...).isOnGCD` 作为饰品展示排除条件，于是把共享 GCD 直接附着到了饰品卡的主 CD 框。

同时，`Tactics/CooldownResolver.lua:GetDurationObject()` 对所有卡片优先读取动作条 DurationObject。该顺序适用于直接技能，但不适用于装备饰品：饰品应先取当前装备 ItemID 的自身冷却对象。

## 固定合同

1. 仅针对 `inventorySlot=13|14` 的装备饰品卡，若动作条表明 `isOnGCD=true`，且 HUD 没有已确认的 `cooldownKnown=true + cooldownActive=true + cooldownOnGCD~=true` 槽位自身 CD，则必须隐藏饰品主 CD 转盘与数字。
2. 饰品卡的原生 DurationObject 取源顺序为：当前装备 ItemID → 动作条回退 → 常规 ItemID 回退。
3. 直接动作条技能继续保留动作条 DurationObject 的原有优先权威。
4. 不读取 HUD 图标、灰度、动画或文案作为 AutoBurst 输入；此版本不改变 CD 确认、前后置注入、TEAP 帧、TEK 全局限频或 Windows 输入行为。

## 实机复测

1. 13 槽和 14 槽饰品分别放在可见默认动作条，任意施放一个普通 GCD 技能。
2. 饰品未使用且自身 ready 时：饰品图标不得出现公共 GCD 转盘或倒数。
3. 使用一个具有真实自身 CD 的饰品：应显示其自身 CD；在该饰品触发同一公共 GCD 时，显示不得退化为约 1～1.5 秒的公共 GCD。
4. 复测前置/后置饰品注入：计划建立、精确 slot + ItemID 自身 CD 确认、恢复期和窗口推进行为应与 1.0.15 一致。
