# Tactic Echo 1.1.2 基线：TEK 修饰键手动接管

## 当前 TEK 白名单与手动让步规则

- TEK 本地连发介入白名单是唯一的物理键盘豁免来源；默认白名单为 `W/A/S/D/SPACE`。
- 白名单内主键按下、重复按下和抬起均不得进入 `manual_input_held`，也不得启动 release delay、freshness 或 replay guard。
- 非白名单真实键盘输入必须从按下到抬起持续让步；只要仍有任何非白名单键持有，TEK 不得派发自动输入。
- `Ctrl`、`Alt`、`Shift`、`Win` 等修饰键不能单独加入白名单，因此属于非白名单真实键盘输入；按下即进入 `manual_input_held`，抬起后才进入既有恢复流程。
- 玩家按住修饰键期间，TEK 不得派发主键，以避免形成 `Alt+E`、`Ctrl+E` 等意外组合键。
- 最后一个非白名单键抬起后，继续使用现有策略：`balanced` 为 30ms release delay、2 帧 freshness、150ms replay guard；`aggressive`、`manual_first` 与 `custom` 仍按既有设置执行。

## 不变边界

- 不通过 `release_modifiers()` 主动松开玩家真实按住的修饰键；正确行为是检测到修饰键持有时让步。
- 不改变 TEAP/TEK 协议，不新增输入通道，不绕过 Hook、前台、新鲜度、CRC、限频或手动让权门禁。
- 自动打断继续生产硬暂停；读条、钢条、事件和冷却证据只服务于只读提示、高亮、诊断与 HUD 人工点击。
- AutoBurst 任何 `inCombat=false` 帧仍不得创建或保留 plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。
- 默认 `pause_out_of_combat` 仍对外显示为“自动启停”；未进战斗或脱战导致的底层 `paused` 继续显示为“待命”。
- HUD 手动点击继续只通过静态 secure proxy 复用当前可靠动作条按钮/已识别宏，且固定输出动作码 0、BindingToken 0。

## 验收

- `tek/tests/test_physical_input.py`
- `tests/unit/test_manual_ownership_gate_contract.py`
- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
