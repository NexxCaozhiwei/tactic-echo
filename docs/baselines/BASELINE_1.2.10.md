# Tactic Echo 1.2.10 基线：AutoBurst HUD 派发态与测试契约收口

## 变更范围

- AutoBurst HUD 不再显示内部校验、等待、确认或重试过程；只有当前 TEAP Burst 帧实际可派发且具有有效 BindingToken 时，对应卡显示“派发”。
- `TacticalState` 向只读 HUD 投影补充 `dispatchActionKind`、`dispatchInventorySlot` 与 `dispatchItemID`，用于精确匹配当前技能或饰品步骤。
- HUD 卡继续固定为 `bindingToken=0`、`displayOnly=true`，该视觉标记不授权 SignalFrame、TEAP、TEK 或 secure click。
- AutoBurst HUD 序列容量统一为九张：一个窗口、最多六个注入和两个饰品。
- 全套测试契约改为当前主键与 AutoBurst 产品范围；已退役打断、控制、防御、生存、候选历史和独立爆发推荐不再作为当前行为断言。

## 不变边界

- P1 的锁链、GCD/队列窗口派发、精确确认、失败回执隔离和有界释放规则不变。
- 官方推荐、动作条解析、BindingToken、TEAP v3、TEK、宏身份、脱战硬门控、手动让权、前台、Hook、新鲜度与限频边界不变。
- HUD 仍可显示真实硬阻止；普通校验与等待过程不再占用用户可见状态。
- `AGENTS.md` 未修改；测试契约按现行产品范围修正，而不是放宽运行安全规则。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
- 完整测试结果：`652 passed, 7 skipped, 17 subtests passed`；七项跳过均为明确退役的自动打断候选派发历史契约。
