# Tactic Echo 1.1.5 基线：HUD 点击路由战斗保护收口

## 当前 HUD 战斗保护规则

- HUD 卡片 Button 在战斗中不得调用 `SetAlpha`、`EnableMouse`、`Show` 或 `Hide`。
- `HudClickRouter` 的 secure proxy 与 blocker 在战斗中不得调用 `SetAlpha`、`Show` 或 `Hide`。
- 战斗中的点击层可见性变化只能记录 `tacticEchoCombatVisibilityPending` 和 `dirty`；脱战后的正常刷新再真实隐藏、显示或重建 proxy/blocker。
- secure proxy 只能静态复用当前可见、已验证的 Blizzard 默认动作条按钮或已识别宏；不得在战斗中重定向、清空属性或改写动作来源。
- blocker 不得创建输入路径、改写宏、调用动作条按钮或请求 TEK 派发。

## 不变边界

- TEK 本地连发介入白名单仍只豁免配置中的主键，默认 `W/A/S/D/SPACE` 不触发手动让步。
- `Ctrl`、`Alt`、`Shift`、`Win` 修饰键仍从按下到抬起持续 `manual_input_held`。
- 自动打断继续生产硬暂停；不生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- AutoBurst 任何 `inCombat=false` 帧仍不得创建或保留 plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。
- 默认 `pause_out_of_combat` 仍对外显示为“自动启停”；未进战斗或脱战导致的底层 `paused` 继续显示为“待命”。
- AutoBurst、Reaction、控制、防御和生存 HUD 继续共享当前动作栏宏资格规则；宏名、图标、宏列表存在和未知正文不得授权当前动作栏身份。

## 验收

- `tests/unit/test_hud_icon_visibility_contract.py`
- `tests/unit/test_p57_hud_manual_click_and_auto_interrupt_suspend.py`
- `tests/unit/test_p57_hud_manual_click_runtime.py`
- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
