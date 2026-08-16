# Tactic Echo 1.2.9 基线：AutoBurst Retail upvalue 热修

## 变更范围

- 修复 `1.2.8` 在 Retail 客户端加载时报告的 `function at line ... has more than 60 upvalues`。
- P1 新增的逻辑派发阶段判断与等待原因判断改为 `AutoBurst:CanStartLogicalDispatch()`、`AutoBurst:PendingDispatchHoldReason()` 方法，不再成为大型 `Evaluate()` 的局部 upvalue。
- 首步骤 `READY_NOW`、后续步骤 `QUEUE_WINDOW`、`GCD_LOCKED` 无 Token 保持，以及失败后等待 `READY_NOW` 重试的 P1 行为不变。

## 不变边界

- 锁链顺序、精确成功确认、每次逻辑尝试失败回执去重、两帧 observation-only 隔离和两次独立精确失败的有界释放均不改变。
- BindingToken、TEAP、TEK、宏身份、脱战硬门控、手动让权、前台、Hook、新鲜度与限频边界不变。
- 本热修不实施 P2 HUD 展示调整或 P3 结构重构。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py tests/unit/test_current_scope_efficiency_contract.py`
- `python -m pytest -q tek/tests tests/unit`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
- Retail `FrameXML.log` 在重新加载后不得出现新的 `more than 60 upvalues`。
