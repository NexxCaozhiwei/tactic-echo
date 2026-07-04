# Tactic Echo 1.0.28 基线：简易序列直接动作条就绪校正

## 范围

本版修复多步骤 `simple` 爆发序列在“饰品自身 CD、后续注入实际已就绪”时，因覆盖/天赋变体导致 Spell API 残留旧基础冷却而错误放弃整个窗口的问题。

不修改爆发顺序 UI、窗口识别、四帧 handoff、TEAP、TEK、BindingToken、输入限频或普通官方推荐派发。

## 直接动作条就绪权威

- 对 resolver 已验证的**直接、可信、默认动作条按钮**，当前按钮明确返回 `isActive=false` 且非 GCD 时，`IconState:CollectCooldownOnly()` 将其视为该按键已就绪。
- 若客户端隐藏动作条布尔值，但该同一按钮返回可解释的 `0/0` CD 数值，同样可形成窄范围的动作条就绪证据。
- 该就绪证据只用于清除该绑定动作的**错误自身 CD 分类**；共享 GCD、队列窗口仍由 `GCDGate` 正常处理。
- 只有同一可信动作条的 `active=true + 非 GCD` 或长时非 GCD数值，才是自身 CD 证据；“就绪证据”绝不用于 CD 跳过或成功确认。
- 非直接绑定、非可信动作条、宏猜测、灰色图标、未知/短时数值均不能形成就绪覆盖。

## 简易多步骤预检

对于如：

```text
饰品13 → 窗口 → 注入技能
```

- 饰品 13 在真实自身 CD：只排除饰品步骤。
- 注入技能的可信动作条已就绪：保留注入步骤。
- 本轮计划实际为：`窗口 → 注入技能`；不会因为饰品 CD 放弃整个窗口。
- 集中模式语义不变：任一已启用可选步骤不可用，仍不建立计划。

## 诊断

- `lastStepObservation` 与 `/temapping autoburst_105` 新增：
  - `cooldownDirectActionBarReadyEvidence`
  - `cooldownActionBarNumericReady`
- `sequence_preflight_selected` / `sequence_preflight_no_eligible` 现在记录：
  - `selectedOrder`
  - `excludedOrder`
  - 首个排除步骤的 key、role、reason、SpellID 或装备栏位

## 验证

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 所有 TOC Lua 文件经 `texluac -p`。
