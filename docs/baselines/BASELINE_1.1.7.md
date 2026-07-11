# Tactic Echo 1.1.7 基线：HUD 容器可见性战斗保护收口

## AutoBurst 窗口确认防卡死

- 当前等待步骤的成功事件只允许匹配声明 SpellID、冻结绑定身份或 Resolver 对该精确步骤给出的有界基础/覆盖等效 SpellID；不得使用技能名、Buff、资源或无关动作条按钮确认。
- 窗口步骤已经派发、官方窗口已经离开且确认宽限期结束后，若仍没有精确事件、自身非 GCD 冷却开始或充能减少证据，必须记录 `window_confirmation_unobserved_released` 并安全释放计划。
- 安全释放不是成功确认：不得写入 completed、不得推进后续步骤、不得借此授权 BindingToken、TEAP 或 TEK；它只阻止无证据的 `WAIT_CONFIRM` 永久占有普通推荐。

## HUD CD 时间来源一致性

- HUD 徽标只使用 `IconState`/Tracker 已确认的安全数值；存在 `cooldownStart + cooldownDuration` 时以其绝对结束时间为锚，只有 remaining 时同一快照不得在重复绘制中延后结束时间。
- `DurationObject` 只负责客户端原生转盘，CountdownNumbers 始终隐藏，不得成为 HUD 数字来源。
- 主键、Burst-window 和所有物品卡隐藏纯共享 GCD/`61304` 转盘与数字；自身非 GCD 冷却与充能冷却仍优先显示。

## 当前 HUD 战斗保护规则

- HUD 卡片 Button 在战斗中不得调用 `SetAlpha`、`EnableMouse`、`Show` 或 `Hide`。
- `HudClickRouter` 的 secure proxy 与 blocker 在战斗中不得调用 `SetAlpha`、`Show` 或 `Hide`。
- `TacticalBoard` 的主容器与 defense 容器在战斗中不得调用 `SetScale` 或 `SetAlpha`；只允许记录 `tacticEchoCombatPresentationPending`。
- `TacticalBoard` 的主容器、defense 容器与状态文本在战斗中不得调用 `SetShown`、`Show` 或 `Hide`；只允许记录 `tacticEchoCombatShownPending`。
- `TacticalHudLayout` 在战斗中不得执行 `SetScale`、`SetPoint`、`SetSize`、`SetShown` 等布局变更；只允许记录 `tacticEchoLayoutDirty` 与 `tacticEchoPendingLayoutFingerprint`。
- 以上 pending/dirty 状态只能在脱战后的正常 HUD 刷新中真实应用。战斗中显示可能短暂沿用上一份布局或缩放，但不得触发受保护调用。
- secure proxy 只能静态复用当前可见、已验证的 Blizzard 默认动作条按钮或已识别宏；不得在战斗中重定向、清空属性或改写动作来源。

## 不变边界

- TEK 本地连发介入白名单仍只豁免配置中的主键，默认 `W/A/S/D/SPACE` 不触发手动让步。
- `Ctrl`、`Alt`、`Shift`、`Win` 修饰键仍从按下到抬起持续 `manual_input_held`。
- 自动打断继续生产硬暂停；不生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- AutoBurst 任何 `inCombat=false` 帧仍不得创建或保留 plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。
- 默认 `pause_out_of_combat` 仍对外显示为“自动启停”；未进战斗或脱战导致的底层 `paused` 继续显示为“待命”。
- AutoBurst、Reaction、控制、防御和生存 HUD 继续共享当前动作栏宏资格规则；宏名、图标、宏列表存在和未知正文不得授权当前动作栏身份。

## 验收

- `tests/unit/test_hud_board_combat_protection_contract.py`
- `tests/unit/test_hud_icon_visibility_contract.py`
- `tests/unit/test_p57_hud_manual_click_and_auto_interrupt_suspend.py`
- `tests/unit/test_p57_hud_manual_click_runtime.py`
- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
