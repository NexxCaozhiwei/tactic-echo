# Tactic Echo 1.2.8 基线：AutoBurst 队列窗口派发稳定性

## 变更范围

- 延续 1.2.0 的锁链语义：真实计划创建后只处理 `plan.stepIndex` 指向的当前步骤；官方推荐轮转、GCD 等待和失败隔离均不重选、重排或越过当前步骤。
- 第一个实际派发步骤只在公开 `GCDGate` 为 `READY_NOW` 时创建逻辑尝试。`QUEUE_WINDOW` 与 `GCD_LOCKED` 仍是预检可用时序，不是自身冷却证据，但不会授权首个 BindingToken。
- 已有步骤派发后，后续普通受 GCD 步骤在 `GCD_LOCKED` 保持 observation-only；进入 `QUEUE_WINDOW` 或 `READY_NOW` 后才创建该步骤的首次逻辑尝试。显式脱 GCD 饰品仍沿用已配置的 `READY_NOW` 分类。
- 当前步骤在队列窗口派发后若收到精确匹配失败，先发布两帧 observation-only 隔离帧；隔离完成后继续保持当前步骤，只有 `READY_NOW` 才创建新的逻辑重试，不在同一队列机会内再次尝试。
- `dispatchAttempt` 只在新的 BindingToken-bearing 逻辑尝试建立时增加。GCD/队列等待、`WAIT_CONFIRM`、候选重评和隔离帧均不改变尝试身份。

## 不变边界

- 官方推荐仍是唯一窗口锚点；AutoBurst 只构造当前步骤候选，SignalFrame 继续独占 BindingToken → TEAP，TEK 继续独占物理输入。
- 成功确认仍只接受当前 `WAIT_CONFIRM` 的精确施法成功事件、稳定自身非 GCD 冷却开始或充能减少；GCD、候选帧、失败事件与固定超时均不是成功证据。
- 每个逻辑尝试只接受第一枚精确匹配失败回执。两次来自独立逻辑尝试的精确失败继续执行既有有界释放：`simple` 跳过当前可选步骤，`focused` 按窗口派发边界释放，窗口步骤释放给普通官方路径。
- 不引入固定游戏时间睡眠，不读取或保存具体资源值，不改变宏身份、脱战硬门控、手动让权、前台、Hook、新鲜度或全局限频。
- HUD 展示收口不属于本 P1 基线；运行期详细阶段继续只作为诊断输出，后续 P2 再调整可视状态。

## 奥法验收路径

```text
镜像成功
→ GCD_LOCKED：奥术涌动保持当前步骤，BindingToken=0
→ QUEUE_WINDOW：奥术涌动第一次逻辑派发
→ 精确失败：两帧 observation-only 隔离
→ QUEUE_WINDOW：继续保持，BindingToken=0
→ READY_NOW：奥术涌动第二次逻辑派发
→ 精确成功：推进爆发链下一步
```

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_auto_burst_phase1_contract.py`
- `python -m pytest -q tek/tests tests/unit`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
