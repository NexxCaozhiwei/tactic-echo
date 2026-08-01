# Tactic Echo 1.1.7 基线：HUD 容器可见性战斗保护收口

## 噬灭 DH 与空种子专精

- 噬灭默认后置 `injection:1217605` 的资源判定必须以已确认 `window:1225826` 之后的新鲜共享快照为准。根除前若绑定、真实 BindingToken 与自身 CD 合格，但仅公开可用性布尔值显示资源不足，预检必须保留该步骤并导出 `resourceCheckDeferred=true`、`deferredResourceOrder`；不得让根除前的资源状态取消整轮爆发。
- 根除得到当前步骤的精确事件、自身非 GCD CD 或充能变化确认后，后置虚空变形必须进入 `POST_WINDOW_RESOURCE_SETTLING`。`GCD_LOCKED` 期间不得派发、跳过或累计不可用证据；`READY_NOW` / `QUEUE_WINDOW` 中精确可用性明确为 true 时可立即派发；持续资源不足，或在绑定/自身 CD 仍可派发时资源布尔持续 UNKNOWN，只有在两个不同 `RuntimeSnapshot.cycleId` 的新鲜样本上仍成立时才可释放可选注入，同一快照重复评估不得重复计数或永久卡住。绑定、自身 CD 等其他门禁的 UNKNOWN 继续使用既有 fail-safe 规则。
- 上述延迟复核只适用于 `DEMONHUNTER_3` 中位于窗口之后的 `1217605`。位于窗口之前的虚空变形、其他噬灭自定义注入、其他专精和其他技能继续使用既有预检/运行期资源规则；不得扩展到原始资源数值、Buff、Debuff、目标状态、BindingToken、TEAP 或 TEK。
- `DEMONHUNTER_3` 必须作为噬灭恶魔猎手显式注册，`specIndex=3`、`specID=1480`；默认窗口技能固定为 `1225826`（根除），默认第一注入技能固定为 `1217605`（虚空变形），不得回退到浩劫/复仇或跨专精共用配置。
- 噬灭默认序列必须保持 `window:1225826 → injection:1217605`（根除 → 虚空变形），已有用户自定义排序不得被迁移或覆盖，并继续允许当前专精已学会的额外自定义触发/注入技能。其他没有内置参考触发/注入种子的显式专精保持空列表，但必须允许 `C_Spell.IsSpellKnown` / `IsPlayerSpell` / `IsSpellKnown` 已确认的当前专精技能作为用户自定义条目加入。
- 用户已明确授权资源不足例外：仅对可选 spell 注入、仅在绑定来源为当前已验证动作栏且存在真实 BindingToken 时，可从共享 `RuntimeSnapshot:GetSpellUsability()` 按精确 SpellID 读取 `usable` / `insufficientPower` 两个公开布尔值，并以 `GetActionUsability()` 作为动作槽兼容回退。该判定必须位于冷却 UNKNOWN 继续派发分支之前；普通注入明确 `false/true` 时 `simple` 排除或跳过该注入并继续，`focused` 不建计划或按窗口是否已派发执行既有释放/离开锁规则。Retail 对噬灭光环型特殊资源可能只返回 `usable=false` 而不设置通用 `insufficientPower`；因此仅允许 `DEMONHUNTER_3` 的 `1217605`（虚空变形）在已验证动作栏/真实 BindingToken 前提下，于计划运行期、首次派发前或等待确认时，把任一精确可用性探针的 `usable=false` 解释为特殊资源不足，并导出 `specialResourceUnusableCompat=true` 诊断；初始预检不得用该兼容形态提前丢弃位于根除之后的虚空变形步骤。窗口步骤、其他专精/技能及 UNKNOWN 不得据此跳过，且不得读取、保存或导出具体资源数值。
- 资源例外不得读取、保存或导出具体资源数值，不得扩展到窗口、饰品、普通官方推荐、Buff、Debuff、目标状态、BindingToken、TEAP 或 TEK。
- `noSeedNotice` 只在合并默认与用户配置后的触发、注入列表都为空时成立。用户加入有效自定义条目后必须解除该阻断，并由自定义触发形成固定窗口、由最多前三项已启用自定义注入形成稳定 `injection:<SpellID>` 步骤。
- 显式注册表必须覆盖 13 个职业共 40 个现行战斗专精；契约测试需逐项校验 class、specIndex 与 specID，防止新专精再次出现 UI 可见但无法保存自定义技能的问题。

## 稳定性与热路径收口

- 主卡拖动与 HUD 抓手只能通过 `beginContainerMove()` / `finishContainerMove()` 改变容器移动状态；`InCombatLockdown()` 为真时不得直接调用 `StartMoving()` 或 `StopMovingOrSizing()`。
- HUD 运行时只创建主键卡与最多 5 个 AutoBurst 卡。候选历史、打断、控制、位移、防御卡保持空节点，不创建 `TacticalIconButton`，也不进入布局指纹。
- TEAP v3 的 20 字节协议、50ms transport freshness、可派发 sequence 更新和像素绘制节奏不变。`TacticEchoDB.signal.frames` 只在语义状态变化时立即追加，稳定状态按 0.5 秒心跳追加；逐帧 dispatch attempt 只更新到下一份心跳记录。
- AutoBurst 的持续 `window_queue_delivery_continues` / `gcd_locked_delivery_continues` 诊断按 plan、step 与 wait phase 合并为 0.5 秒心跳，且不占用 priority lifecycle ring；计划创建、预检、派发、确认、中止、释放与完成记录不合并。
- `TacticalAdvisors:Refresh()` 每轮只执行一次 `Config.Normalize:All()` 并同时取得 tactical/HUD 配置；不改变 BurstPlanner、BindingToken、TEAP 或 TEK 行为。

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

- `tests/unit/test_auto_burst_phase1_behavior.py::test_sparse_registered_specs_accept_custom_trigger_and_injection_sequences`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_defaults_build_sequence_and_accept_additional_custom_skills`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_simple_preflight_skips_resource_blocked_void_metamorphosis`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_simple_runtime_resource_drift_skips_injection_and_continues_window`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_window_first_plan_finishes_when_post_injection_loses_special_resource`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_post_window_resource_preflight_is_deferred_and_ready_after_eradicate_dispatches_immediately`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_post_window_resource_settlement_waits_for_gcd_and_two_distinct_unavailable_cycles`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_post_window_resource_unknown_is_bounded_and_released`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_post_window_resource_deferral_does_not_apply_to_other_specializations`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_devourer_focused_resource_block_refuses_plan_without_claiming_window`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_action_slot_resource_boolean_remains_compatibility_fallback`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_runtime_snapshot_preserves_false_action_usability_for_resource_gate`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_runtime_snapshot_preserves_special_spell_resource_boolean`
- `tests/unit/test_auto_burst_phase1_behavior.py::test_resource_exception_does_not_apply_to_window_or_non_resource_unusable_result`
- `tests/unit/test_burst_profile_configuration_table_contract.py`
- `tests/unit/test_burst_defense_registry_lists_contract.py::BurstDefenseRegistryListsContractTests::test_every_playable_specialization_has_explicit_burst_profile_metadata`
- `tests/unit/test_current_scope_efficiency_contract.py`
- `tests/unit/test_hud_board_combat_protection_contract.py`
- `tests/unit/test_hud_icon_visibility_contract.py`
- `tests/unit/test_p57_hud_manual_click_and_auto_interrupt_suspend.py`
- `tests/unit/test_p57_hud_manual_click_runtime.py`
- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
