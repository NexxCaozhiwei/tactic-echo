# Tactic Echo 1.2.3 基线：AutoBurst 迟到确认隔离

## 变更范围

- 可选 AutoBurst 步骤在运行期被跳过时，必须同时清除该步骤的 `plan.wait`、冻结绑定与候选计数，并将计划恢复为 `PENDING` 后再进入下一步骤。
- `UNIT_SPELLCAST_SUCCEEDED` 只可用于确认与当前步骤 SpellID 一致的 `plan.wait.expectedSpellID`；旧步骤的迟到事件不得通过旧 `requestedSpellID`、`matchedSpellID` 或等效集合确认新步骤。
- 奥法默认 `奥术涌动（365350）→ 大法师之触（321507）` 序列中，奥术涌动因运行期资源不足被跳过后，只有大法师之触自身或其当前安全等效身份的成功事件可以完成窗口步骤。

## 不变边界

- 当前步骤身份一致后，既有精确、requested、matched 与 Resolver 有界基础/覆盖等效 SpellID 确认继续保留。
- 修复不改变 AutoBurst 排序、资源判定、CD/GCD 规则、BindingToken、TEAP v3、TEK 门禁、脱战硬门控或共享宏资格。
- HUD、Tooltip、冷却转盘与状态文字仍只负责呈现，不参与步骤确认或派发授权。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py`
- `python -m unittest discover -s tek/tests -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
