# Tactic Echo 1.0.38 基线：HUD 冷却数字统一与首发预注册追踪

## 本版范围

1.0.38 修复 1.0.37 的显示末级回退带来的格式分叉：当客户端只公开“自身非 GCD 冷却进行中”但暂未给出安全数值时，1.0.37 会让同一 `DurationObject` 直接显示 Blizzard 原生倒计时。因此超过一分钟的技能会出现 `MM:SS`，而已有 `actionbar_numeric_observed`、`spell_api_observed` 或本地 Tracker 数字的技能显示纯秒数，造成同一 HUD 内不一致。

本版不改 AutoBurst、有序步骤计划、简易/集中预检、GCDGate、四帧 handoff、起手 bridge、切图围栏、TEAP 或 TEK。

## 冷却展示合同

```text
安全数字可读
→ 单一最终 DurationObject 只画转盘
→ HUD 徽标显示向上取整的纯秒数

安全数字暂不可读，但已确认非 GCD 自身 CD
→ 单一最终 DurationObject 仍只画转盘
→ CooldownTracker 使用已预缓存的当前专精技能时长启动本地 HUD 倒计时
→ 后续安全 API 观察自动校正

无法获得安全数字且没有可用本地追踪
→ 保留原生转盘
→ HUD 不显示任何原生 MM:SS 数字

纯共享 GCD / 61304 别名 / 物品泛 GCD
→ 不显示为技能自身 CD
```

- 所有 `Cooldown` Frame 的 `SetHideCountdownNumbers(true)` 必须在对象附着后再次执行，防止客户端异步恢复 CountdownNumbers。
- HUD 徽标是唯一可见数字层。数字格式为 `math.max(1, math.ceil(remaining))` 的纯秒数；不得按来源切换为原生 `MM:SS` 或小数秒。
- `CooldownTracker:PrimeCurrentSpec()` 在脱战、登录、出战、进图及专精/天赋更新后注册当前专精防御、爆发窗口与注入技能。预注册使用 SpellID 身份缓存时长，随后遇到可信直接动作条槽位时必须迁移到 slot 身份并保留缓存。
- 静态 Tooltip/Base 时长仍不得给任意未知直接动作条伪造即时数值；只允许作为已预注册当前专精技能在已确认 `UNIT_SPELLCAST_SUCCEEDED` 后的本地展示计时后备，且必须接受后续实时 API 校正。

## 验收重点

1. 反魔法护罩、冰封之韧、黑暗突变均显示 HUD 统一整数秒；不得出现 `MM:SS`、原生倒计时或双层数字。
2. 三者 CD 转盘仍由原生 `DurationObject` 驱动；隐藏 HUD 数字时不应重新露出原生数字。
3. `/reload` 后第一次施放冰封之韧或黑暗突变，若即时安全数值不透明，仍应由预注册 Tracker 立刻显示 HUD 纯秒数；待 API 数字恢复后平滑校正。
4. 主键/窗口纯 GCD、13/14 饰品泛 GCD 仍不显示为技能自身 CD。
5. AutoBurst、TEAP、TEK、动作条绑定和输入门禁保持与 1.0.37 一致。
