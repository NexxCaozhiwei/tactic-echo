# Tactic Echo 1.1.4 基线：HUD Button 战斗保护收口

## 当前 HUD 战斗保护规则

- HUD 卡片 Button 在战斗中不得调用 `SetAlpha`、`EnableMouse`、`Show` 或 `Hide`。
- 战斗中卡片可见性变化只记录 `tacticEchoCombatHidden` 等待处理状态；脱战后的正常刷新再真实更新显示。
- HUD 手动点击的 `SecureActionButtonTemplate` proxy 在战斗中不得隐藏、重定向或清理属性。
- 战斗中卡片隐藏或映射失效时，非 secure blocker 必须覆盖旧 proxy 并 fail-closed，防止旧动作条映射被误点。
- blocker 不得创建输入路径、改写宏、调用动作条按钮或请求 TEK 派发。

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
