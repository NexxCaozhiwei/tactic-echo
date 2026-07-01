# 0.6.6 Core Safe Refactor 审计报告

## 触发原因

WoW 实机反馈：

1. `ADDON_ACTION_FORBIDDEN` 指向 `Core/Bootstrap.lua` / `Tactics/ProtocolMonitor.lua` 的事件注册链，BugGrabber 显示保护调用为 `UNKNOWN()`。
2. `Tactics/IconState.lua` 在比较 `duration` 时触发 `secret number value` 错误，导致 TacticalBoard 刷新链中断，打断、防御、爆发、控制、位移建议不显示。

## 修复策略

- 事件注册从 0.6.5 的“战斗锁定排队 + OnUpdate 重试”改为“加载期一次性注册，无动态重试”。
- `IconState` 对冷却、充能等 WoW API 返回值进行 secret-number 安全隔离；比较/算术失败时返回未知状态与原因，不抛出到 UI 层。
- `TacticalAdvisors` 对图标状态、建议规划、打断构建和推荐队列增加 `pcall` fail-soft 边界。
- 图标施法灰化只作用于正在施放的同一技能；其他图标不再因玩家施法而整体灰化。

## 修改文件

- `addon/!TacticEcho/Core/Bootstrap.lua`
- `addon/!TacticEcho/Tactics/IconState.lua`
- `addon/!TacticEcho/Tactics/TacticalAdvisors.lua`
- `addon/!TacticEcho/!TacticEcho.toc`
- `tests/unit/test_wow_load_hotfix_contract.py`
- `tests/unit/test_tactical_prediction_contract.py`
- 根目录文档：`README.md`、`AGENTS.md`、`HANDOFF.md`、`TASKS.md`、`CHANGELOG.md`、`DECISIONS.md`、`PROJECT_CONTEXT.md`

## 验证结果

- `PYTHONPATH=. pytest -q`：182 项通过。
- `PYTHONPATH=. python3 -m unittest discover tek/tests`：124 项通过。
- `PYTHONPATH=. python3 -m unittest discover tests/unit`：51 项通过。
- `python3 -m compileall -q tek tests`：通过。

`RuntimeError("boom")` 是 TEK Worker 异常恢复测试中的预期模拟输出，测试整体通过。

## 仍需实机验证

- 脱战 `/reload` 后是否不再出现 Bootstrap/ProtocolMonitor `ADDON_ACTION_FORBIDDEN`。
- TacticalBoard 在冷却/充能返回 secret number 时是否显示未知/安全模式，而不是报错。
- 防御、爆发、打断、控制、位移建议在 IconState 某个字段不可用时是否仍继续显示。
