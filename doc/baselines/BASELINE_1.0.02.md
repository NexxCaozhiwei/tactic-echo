# Tactic Echo 1.0.02 基线

`1.0.02` 以 `1.0.01` 为代码基线，实装自动爆发 Phase 1 的最小双技能注入状态机。

- 仅一条人工声明的 `windowSpell + injectionSpell` 规则；
- 支持前置/后置与简易/集中；
- 新增 `AutoBurst.lua`、`GCDGate.lua` 与 `IconState:CollectCooldownOnly()`；
- TEAP v3 保持 20 字节，flags bit 5 标识 `dispatchOrigin=burst`；
- TEK 对同一 burst action sequence 的短暂重复候选去重；
- 成功确认仅使用技能自身 CD/充能，不使用 Buff 或泛 GCD；
- 默认关闭，尚未完成 Windows/WoW 实机验收。
