# Tactic Echo 1.2.4 基线：AutoBurst 预测性充能回滚隔离

## 变更范围

- AutoBurst spell 步骤的充能下降或自身非 GCD 冷却开始仅作为暂定确认；相同证据必须至少再次出现，并持续跨过 0.15 秒稳定窗口，才能作为缺少成功事件时的后备确认。
- 当前 `WAIT_CONFIRM` spell 步骤收到匹配的 `UNIT_SPELLCAST_FAILED` 或 `UNIT_SPELLCAST_FAILED_QUIET` 时，清除暂定确认并立即请求 SignalFrame 重评；失败事件不完成、不跳过也不中止该步骤。
- `UNIT_SPELLCAST_SUCCEEDED` 的精确、requested、matched 与 Resolver 有界等效身份继续立即确认当前步骤，不受稳定窗口延迟。

## 不变边界

- GCD 锁定期间继续按普通官方推荐调度语义发布新鲜候选，由 TEK 的共享限频与客户端队列窗口决定实际按键时点。
- 饰品仍仅由锁定 slot + ItemID 的可信自身 CD 证据确认，不应用 spell 预测回滚稳定窗口。
- 修复不改变序列排序、资源判定、BindingToken、TEAP v3、TEK 门禁、脱战硬门控、共享宏资格或 HUD 展示。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py`
- `python -m unittest discover -s tek/tests -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
