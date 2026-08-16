# Tactic Echo 1.2.6 基线：AutoBurst 稳定确认与六注入序列

## 变更范围

- 每专精 AutoBurst 序列允许最多 6 个 `injection:<SpellID>`，继续使用稳定 SpellID 身份保存顺序和启用状态；窗口与饰品 13/14 的身份不变。
- HUD 最多投影 9 张 AutoBurst 卡：1 个窗口、6 个注入、2 个锁定装备槽饰品。HUD 仍为展示/人工点击层，不建立 BindingToken 或派发资格。
- 可选步骤进入 `WAIT_CONFIRM` 后，单帧预测性自身 CD、冷却来源不确定、UNKNOWN 或资源不可用不得推进序列；公开 GCD 可派发时继续同一步候选。
- 资源不足必须由两个不同 RuntimeSnapshot 周期持续确认。普通读条、引导、蓄力、`GCD_LOCKED` 与 `QUEUE_WINDOW` 期间延后资源结论；噬灭虚空变形的特殊兼容同样受此限制。
- 两个精确匹配当前等待 SpellID/等效 SpellID 的失败或中断收据可执行有界活性释放；单个失败、候选帧数、固定睡眠和泛超时均不得跳过或确认步骤。

## 不变边界

- 官方推荐仍是唯一窗口锚点；AutoBurst 只构造下一步候选，SignalFrame 继续独占 BindingToken → TEAP，TEK 继续独占物理输入。
- 成功确认仍只接受当前 `WAIT_CONFIRM` 的精确施法成功事件、稳定自身非 GCD 冷却开始或充能减少。
- 不读取或保存具体资源数值，不使用 Buff、目标状态、图标灰度或泛 GCD 作为成功证据。
- 脱战硬门控、宏身份、手动让权、前台、Hook、新鲜度和全局限频边界不变。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py`
- `python -m pytest -q tek/tests tests/unit`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
