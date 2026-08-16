# Tactic Echo 1.2.5 基线：AutoBurst 已确认窗口冷却重入隔离

## 变更范围

- AutoBurst 在窗口步骤通过现有可信路径确认时，保存当前战斗内的精确窗口 SpellID、planId、windowGeneration 与 confirmation 摘要。
- 官方推荐短暂离开后重新返回同一窗口，且实时窗口采样仍明确为自身 `COOLDOWN` 时，记录 `confirmed_window_reentry_suppressed`，不创建第二轮计划，也不重放窗口前的可选注入。
- 被抑制的窗口代次进入 observation-only 离开锁；官方推荐真正离开后解除。后续同技能恢复 `READY_NOW`、`QUEUE_WINDOW` 或 `GCD_LOCKED` 时，仍可按正常窗口边沿建立新计划。

## 不变边界

- 首次出现的官方窗口冷却/API 冲突仍沿用既有重校验契约；本次仅隔离同一战斗内已经可信确认过的同 SpellID 窗口重入。
- 窗口收据不使用 Buff、资源数值、目标状态、固定时间等待或失败事件作为成功证据；窗口确认仍只接受原有精确施法事件、自身非 GCD 冷却开始或充能减少。
- 修复不改变用户序列、可选注入资源跳过、BindingToken、TEAP v3、TEK 门禁、共享宏资格、脱战硬门控或 HUD 展示权限。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py`
- `python -m unittest discover -s tek/tests -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
