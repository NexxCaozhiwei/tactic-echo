# Tactic Echo 1.4.7 基线：可信动作槽位冷却冲突纠正

## 基线结论

`1.4.7` 修复惩戒骑等天赋或覆盖技能在实际绑定动作已恢复时，声明 SpellID 仍暴露旧基础冷却而导致注入步骤被错误排除的问题。唯一 Coordinator、唯一 OrderedPlan、唯一 capture、唯一候选和既有输入安全链保持不变。

## 冷却纠正边界

- 只有 Resolver 已验证的直接 Blizzard 默认动作槽位，且动作栏状态被标记为可信时，才可参与旧 SpellID 冷却纠正。
- 当前动作槽位必须给出可解释的数值就绪快照（剩余时间为零）并且没有明确处于共享 GCD，才能清除错误的自身冷却分类。
- Retail 若同时返回 `isActive=true` 与数值就绪，数值就绪可在上述严格边界内胜出；该矛盾必须记录为 `trusted_numeric_ready_overrode_active`。
- 宏、间接来源、不可信槽位、非零冷却、共享 GCD、受保护或不可解释数值仍然 fail-closed，不得借此取得 AutoBurst 资格。
- 纠正只影响自身冷却分类；GCD/队列时机继续完全由 `GCDGate` 决定，不构成冷却跳过、成功确认或额外派发权限。

## 诊断与确认

- 步骤观察、预检排除、优先日志和安全映射导出只记录来源、槽位、可信状态、数值就绪证据及冲突原因等普通标量；不得保存原始受保护冷却值。
- 步骤成功仍只由精确 `UNIT_SPELLCAST_SUCCEEDED`，或来自不同业务样本且稳定至少 0.15 秒的自身非 GCD 冷却开始/充能减少确认。
- 图标灰度、Buff、资源、普通 GCD、UNKNOWN 和本次 ready 冲突纠正都不能充当成功确认。

## 架构与协议

- 未修改自动注入组选择与所有权交接、departure lock、capture 终止保护或 persistent recovery 策略。
- 未修改 BindingToken、TEAP v3 20 字节、flags `0x20`、`dispatchOrigin="burst"` 或 TEK。
- 未新增状态机、事件、OnUpdate、轮询器、候选源或输入路径；离线测试仍不能替代 WoW Retail 与 Windows 实机验收。
