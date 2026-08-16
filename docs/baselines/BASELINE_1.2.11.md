# Tactic Echo 1.2.11 基线：P3 当前链路结构收口

## 变更范围

- `TacticalAdvisors.lua` 删除无运行消费者的旧打断、控制、Reaction P3、候选预测和旧动作条展示分支；当前刷新只构建主推荐与 AutoBurst。
- `ControlPanel.lua` 删除四页设置中心无法进入的 ReactionBindings、自动打断与 P3 观察诊断格式化代码。
- `AutoBurst:BuildHudSnapshot()` 只保留唯一的有序 `items` 输出，删除无人读取的 `window/followups` 重复投影。
- 清除当前 AutoBurst/HUD 主路径中的孤儿局部 helper，并增加自动结构回归测试。

## 不变边界

- P1 已验收的计划锁定、GCD/队列窗口派发、精确确认、失败隔离与有界释放规则不变。
- P2 已验收的 HUD 只显示真实“派发”与硬“阻止”规则不变。
- 官方推荐、动作条解析、BindingToken、TEAP v3、TEK、宏身份、脱战硬门控、手动让权、前台、Hook、新鲜度与限频边界不变。
- 退役模块的历史源码可继续留作归档，但不加载、不轮询，也不从当前已加载文件建立运行分支。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
