# Tactic Echo 1.0.15 基线

基于 1.0.14。

## 修复

1. 所有新鲜、可派发的 `armed` TEAP 帧（官方推荐与 Burst）均分配新的 transport `sequence`。逻辑步骤、确认基线、计划 ID 与步骤/总时限保持不变；TEK 全局限频仍是唯一真实输入频率门槛。
2. 官方推荐精确命中窗口 SpellID，但窗口冷却采样返回 `COOLDOWN/UNKNOWN` 时，创建有界 AutoBurst 计划，不在计划创建前拒绝。窗口动作在注入完成后持续重校验，仅回到 `READY_NOW/QUEUE_WINDOW/GCD_LOCKED` 时才可派发；超时保持窗口离开锁。
3. 前置饰品恢复期、精确 `slot + locked ItemID` 自身非 GCD CD 确认、手动补按恢复和 fail-closed 规则沿用 1.0.14。

## 验收重点

- GCD 中的前置饰品：TEK trace 应出现连续递增 sequence 的 Burst 候选；真实发送次数受当前全局派发上限控制。
- 官方窗口/CD 读数冲突：应出现 `plan_gate_window_official_cooldown_conflict`，而不是 `plan_rejected:spell_cooldown_active`；窗口未就绪时不派发窗口键，恢复后才派发。
- 未获得精确技能或饰品成功证据时，不得自动越过前置步骤派发窗口。
