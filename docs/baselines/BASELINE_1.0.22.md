# Tactic Echo 1.0.22 基线：直接动作条自身 CD 证据

## 目标

修复前置简易注入在第二次窗口中已处于真实自身 CD、但 `C_Spell` 对该 SpellID 短暂返回 ready/unknown 时，AutoBurst 仍持续输出注入候选，导致窗口被序列锁住的问题。

## 固定判定链路

```text
声明注入 SpellID
→ 解析当前可见默认动作条的直接可信 BindingToken
→ 实时 C_Spell 冷却采样
→ 实时 C_ActionBar.GetActionCooldown（仅同一直接动作条按钮）
→ 非 GCD 自身 CD 的两次独立、身份一致采样
→ simple 注入跳过
→ 官方窗口步骤
```

## 允许的新增证据

当且仅当下列条件全部成立时，`actionbar_api` 可以作为技能 API 的等价自身 CD 证据：

1. 当前规则步骤是显式 SpellID；
2. BindingResolver 已证明该 SpellID 对应当前可见 Blizzard 默认动作条上的直接、可信按钮；
3. `C_ActionBar.GetActionCooldown(actionSlot)` 明确为 `isActive=true` 且 `isOnGCD=false`；
4. 当前证据保留精确 `spell:<SpellID>` 身份；
5. 第二次独立采样仍使用同一身份和同一 BindingToken。

两次确认前只输出 hold，不得同帧跳过。确认后仅 `simple` 注入可跳过，随后继续同一已锁定窗口。

## 明确禁止

- 共享 GCD（`isOnGCD=true`）；
- 普通灰色图标、HUD 遮罩、DurationObject、Buff 或 UI 颜色；
- `UNKNOWN`、受保护数值、确认延迟；
- `IsSpellUsable` 的资源、目标、距离或其他可用性结果；
- 非直接/不可信动作条、宏猜测、绑定变更或 SpellID 不一致。

以上情形都不得成为跳过、成功确认或窗口推进依据。

## 诊断与回归

`lastStepObservation` 及 `/temapping` 新增/保留：

- `cooldownSource=actionbar_api`；
- `cooldownDirectActionBarEvidence=true`；
- `cooldownActionBarPublicActive*` / `cooldownActionBarPublicOnGCD*`；
- `pre_injection_cooldown_sample`、`pre_injection_cooldown_confirmed` 中的来源字段。

回归要求：

1. 直接动作条非 GCD CD，二次采样后应跳过注入并派发窗口；
2. 动作条仅处于共享 GCD 时，绝不能跳过；
3. 旧的 `spell_api` 两次 CD 证据路径不退化；
4. 不改变 1.0.20 四帧 handoff、1.0.21 起手 bridge、TEAP v3、TEK 门禁或普通脱战边界。
