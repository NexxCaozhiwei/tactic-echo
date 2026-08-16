# Tactic Echo 1.2.7 基线：AutoBurst 失败重试队列窗口同步

## 变更范围

- 延续 1.2.0 的爆发链所有权：计划创建后，`plan.stepIndex` 与 `WAIT_CONFIRM` 持续锁定当前步骤；官方推荐离开窗口只记录诊断，不取消、推进或重排当前计划。
- 当前等待步骤只接受每个逻辑 `dispatchAttempt` 的第一枚精确匹配失败回执。同一按键产生的后续失败、静默失败或中断回执不得累计为第二次拒绝。
- 第一枚失败回执后先发布两帧 observation-only 隔离帧。隔离完成后，若公开 GCD 仍为 `GCD_LOCKED`，继续保持 `BindingToken=0`；只有 `GCDGate` 进入 `QUEUE_WINDOW` 或 `READY_NOW` 才创建新的逻辑重试。
- 首次候选仍可沿用普通官方推荐的共享 GCD 连续投递策略；队列窗口等待只收窄已经被客户端精确拒绝后的新逻辑尝试，不改变正常步骤的首次派发时机。
- 两次来自独立逻辑尝试的精确匹配失败仍构成有界活性释放：`simple` 跳过当前可选步骤并继续，`focused` 按窗口是否已派发执行既有释放边界，窗口步骤释放给普通官方路径。

## 不变边界

- 官方推荐仍是唯一窗口锚点；AutoBurst 只构造下一步候选，SignalFrame 继续独占 BindingToken → TEAP，TEK 继续独占物理输入。
- 成功确认仍只接受当前 `WAIT_CONFIRM` 的精确施法成功事件、稳定自身非 GCD 冷却开始或充能减少；失败、GCD 与等待帧均不是成功证据。
- 不引入固定游戏时间睡眠。两帧屏障只隔离传输回执，实际重试时机由公开 `GCDGate` 阶段决定。
- 不读取或保存具体资源数值，不使用 Buff、目标状态、图标灰度或泛 GCD 作为成功、跳过或额外派发资格。
- 脱战硬门控、宏身份、手动让权、前台、Hook、新鲜度和全局限频边界不变。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py`
- `python -m pytest -q tek/tests tests/unit`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
