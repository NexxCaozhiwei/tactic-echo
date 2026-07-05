# Tactic Echo 1.1.3 基线：HUD 战斗中安全隐藏

## 当前 HUD 显示安全规则

- HUD 卡片在战斗中隐藏时不得直接调用 `Button:Hide()` 或等价受保护隐藏路径。
- 战斗中卡片隐藏必须降级为透明化并禁用卡片鼠标输入；脱战后才允许真实 `Hide()`。
- HUD 手动点击的 `SecureActionButtonTemplate` proxy 在战斗中不得被隐藏、重定向或清理属性。
- 当卡片隐藏或映射失效但仍处于战斗中时，必须用非 secure blocker 覆盖旧 proxy，并将 HUD 手动点击状态设为 fail-closed。
- blocker 只用于阻止旧 secure proxy 被误点，不得创建输入路径、改写宏、调用动作条按钮或请求 TEK 派发。

## 不变边界

- TEK 本地连发介入白名单仍只豁免配置中的主键，默认 `W/A/S/D/SPACE` 不触发手动让步。
- `Ctrl`、`Alt`、`Shift`、`Win` 修饰键仍从按下到抬起持续 `manual_input_held`。
- 自动打断继续生产硬暂停；不生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- AutoBurst 任何 `inCombat=false` 帧仍不得创建或保留 plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。
- 默认 `pause_out_of_combat` 仍对外显示为“自动启停”；未进战斗或脱战导致的底层 `paused` 继续显示为“待命”。

## 验收

- `tests/unit/test_hud_icon_visibility_contract.py`
- `tests/unit/test_p57_hud_manual_click_and_auto_interrupt_suspend.py`
- `tests/unit/test_p57_hud_manual_click_runtime.py`
- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
