# Tactic Echo 1.4.1 基线：自动注入组先配置后启用

## 基线结论

`1.4.1` 修正多技能组设置流程。新组默认关闭，但窗口 SpellID、注入/饰品、模式和九步顺序均可先编辑；只有配置完整且无冲突时才允许启用。

## 冻结行为

- 设置顺序为：窗口 SpellID → 注入/饰品 → 排序 → 启用。
- 缺少窗口返回 `group_window_missing`；缺少已启用可选步骤返回 `group_has_no_optional_steps`，设置页显示对应中文操作提示。
- 本组窗口不得再次作为本组注入，保存与损坏 SavedVariables 校验均以 `window_used_as_same_group_injection` fail-closed。
- 不同启用组的窗口保持唯一，且不得进入对方注入链；普通注入技能可以跨组复用。
- 各组平级。一个组拥有计划时，其他窗口只记录 `group_window_ignored_while_owner_active`，不抢占、不排队、不触发嵌套链。
- 所有组继续共享唯一 `AutoInjectionCoordinator`、唯一 AutoBurst OrderedPlan、唯一 capture 和唯一候选。

## 安全与协议

- TEAP v3 仍为 20 字节；`dispatchOrigin="burst"`、flags `0x20` 与 TEK 门禁不变。
- 未新增输入路径、事件循环、固定延时、Buff/资源驱动或跨组自动级联。
- HUD 与设置页仍不得建立 BindingToken 或派发权限。

## 必需验证

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。

实机需验证新组从创建到启用的完整交互、任意普通技能窗口、活动链期间其他窗口不触发嵌套链，以及原爆发链顺序与确认语义不回归。
