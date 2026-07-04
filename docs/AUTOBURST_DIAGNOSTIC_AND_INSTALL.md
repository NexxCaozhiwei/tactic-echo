# 自动爆发 1.0.22：安装与诊断

## 本次故障的直接证据

当前上传的 `TacticEcho.lua` 已记录到一个完整的前置饰品计划：规则 `manual:pre:simple:343527:trinket:13:false` 创建后，13 槽物品 `193701` 先进入恢复，再以 `inventory_recovery_action_cooldown_started` 精确确认。随后窗口 `343527` 仍被采样为 `spell_cooldown_active`，官方推荐也已旋转到 `184575`，旧版本最终以 `step_revalidate_timeout:official_window_cooldown_conflict` 中止。该链路证明“饰品未绑定/计划没进入”不是根因；根因是已创建计划受旧的窗口重校验终止逻辑影响。1.0.18 将此类等待改为持久锁定与持续候选。

## 正确覆盖位置

完整源码包用于项目根目录；WoW 实机安装必须把包内：

```text
addon/!TacticEcho/
```

整个目录覆盖到：

```text
World of Warcraft/_retail_/Interface/AddOns/!TacticEcho/
```

不要把 `tactic-echo-1.0.20` 根目录、`addon` 父目录或旧 `!WR` 目录直接当作插件目录。确认游戏角色选择界面的插件列表中显示：

```text
Tactic Echo 1.0.21
```

游戏完全退出或执行 `/reload` 后，应出现：

```text
World of Warcraft/_retail_/WTF/Account/<账号>/SavedVariables/TacticEcho.lua
```

## Phase 1 测试规则

1. 技能注入使用 `/teab set <官方窗口SpellID> <注入SpellID>`；饰品注入使用 `/teab trinket <官方窗口SpellID> <13|14> [offgcd]`，或在“爆发 → 爆发设置”页面选择注入动作。
2. `官方窗口SpellID` 是暴雪官方推荐实际会出现的锚点，不一定是 HUD 爆发列表中的第一个大技能。
3. `注入SpellID` 是 Tactic Echo 要在锚点之前或之后插入的技能。
4. 执行 `/teab status`，必须看到 `构建=1.0.21`；技能规则显示两项 SpellID，饰品规则显示窗口 SpellID 与饰品槽位。
5. 执行 `/tesignal armed`，勾选“启用自动爆发”。常规战斗内测试仍等待官方推荐**先离开再边沿进入**窗口技能；起手测试则在脱战状态让官方推荐已显示窗口后 arm，验证受控 `注入 → 窗口` bridge。
6. 测试后执行 `/temapping autoburst_105`，再 `/reload` 或完全退出游戏。
7. 在 TEK 设置中选择上述 `TacticEcho.lua` 作为 SavedVariables 路径，再生成诊断包。

诊断包的摘要将显示自动爆发的启用状态、实际规则、最近拒绝/候选原因。

## 1.0.20 前置窗口抢跑排障

测试前置 `4 → 3` 时，重点检查：

- `pre_window_capture_started`：官方窗口命中后先建立 capture；
- `pre_window_capture_handoff_barrier`：真实 paused → armed 的状态帧及其后 **4 张 scheduled tick** 都应产生无 Token handoff；
- `/temapping` 的 `handoffBarrierRequiredFrames=4`、`handoffBarrierRemainingFrames`、`handoffBarrierPublishedFrames`：四张 tick 后应显示 `remaining=0 / published=4`；
- TEK Trace：每张 handoff 为 `state=armed + observation_only=true + dispatch_origin=burst + binding_token=0`，其后**下一张**可输入 Burst 帧才应绑定 `4`；
- `old_frame_freshness` / `stale_frame_freshness`：延迟旧官方 3 帧应由 freshness 围栏拒绝；
- `pre_window_capture_departure_locked`：Evaluate 异常时，窗口应只观察至官方推荐离开。

前置阶段中任何 `dispatch_origin=official + binding=3` 的输入都属于缺陷，应连同 `TacticEcho.lua` 与 TEK 诊断包一并导出。

## 1.0.21 起手 Burst bridge 排障

当 Boss 开场、倒计时或首次攻击前官方已显示窗口技能时，正确链路为：

```text
脱战窗口 → precombat_burst_bridge_started
→ Burst handoff hold（4 个 scheduled tick，Token=0）
→ Burst 前置注入候选
→ PLAYER_REGEN_DISABLED（如由注入触发）
→ precombat_burst_bridge_combat_entered
→ 注入确认 → Burst 窗口候选
```

检查点：

- `/temapping` 中 `preCombatBurstBridge=true`；活动 plan 显示 `preCombatBridge=true`，进战后显示 `preCombatBridgeEnteredCombat=true`；
- bridge hold 必须为 `state=armed + inCombat=false + observation_only=true + dispatch_origin=burst + binding_token=0`；
- 第 5 张 fresh Burst 帧前不得出现前置注入 Token，也不得出现官方窗口 Token；
- 非窗口普通脱战推荐必须保持 `dispatch_origin=official` 但由原 Session Policy 编码为 paused，不应创建 plan/capture，更不得输入；
- 手动暂停、文本输入、引导/蓄力、死亡、载具、绑定缺失、窗口离开或过期 Token 时，bridge 必须 fail-closed。


## 1.0.22 注入技能动作条 CD 排障

当前规则为“窗口 `C=260243`（乱射）→ 注入 `X=288613`（百发百中）”时，若第一轮已使用 X，第二轮窗口出现而 X 的默认动作条按钮已处于真实自身 CD，正确顺序应为：

```text
pre_injection_cooldown_sample（第一次）
→ pre_injection_cooldown_confirmed（第二次）
→ injection_skipped
→ 乱射 C 候选
```

本版的新增合法证据为：

```text
cooldownSource=actionbar_api
cooldownDirectActionBarEvidence=true
cooldownActionBarPublicActive=true
cooldownActionBarPublicOnGCD=false
```

仍必须确认两次相同的 `spell:<SpellID>` 身份和同一 BindingToken。若 `cooldownActionBarPublicOnGCD=true`，它只是共享 GCD，绝不能跳过 X。普通图标灰度、资源不足、目标/距离问题、未知读数和宏猜测也绝不能作为跳过证据。

## 1.0.18 需要核对的诊断字段

当测试 `343527 → 31884` 或 `31884 → 343527` 时，重点查看：

- `autoBurst.lastStepObservation.phase`：应显示 `GCD_LOCKED` / `QUEUE_WINDOW`，而不是把共享 GCD 显示为注入技能 `COOLDOWN`；
- `cooldownGcdAlias=true` 与 `cooldownGcdAliasReason=gcd_snapshot_aligned`：仅表示严格对齐的共享 GCD；
- `bindingToken` 与 `binding`：确认 `4` 和 `1` 都存在默认动作条绑定；
- `lastDecision.reason`：可区分 `burst_candidate`、`await_window_departure`、`official_not_window` 与真正的 `binding_not_ready`；
- TEK Trace：Burst 候选应为 `dispatch_origin=burst`。只要当前步骤仍是可派发 `armed` 候选，连续新鲜帧会按 TEK 当前全局限频产生多次真实输入；观察帧才是 `observation_only=true`，不会输入。


## 1.0.18 前置注入诊断字段

`/temapping` 导出的 `autoBurst` 摘要新增：

- `plan.preInjectionSkipAllowed`：只在同一 SpellID、同一直接动作条绑定的两次实时非 GCD 自身 CD 采样均确认后为 `true`；
- `plan.candidateOfferCount`：当前步骤已持续发布候选帧的数量；
- `lastCandidate`：最后一个 Burst 候选的技能、绑定 Token、尝试号与发布次数；
- `lastSpellcastSuccess`：最近的玩家成功施法事件。

前置 `4 → 1` 的正确 Trace 顺序为：先有持续的 `dispatch_origin=burst + binding=4` 候选；确认后才有 Burst 绑定 `1`。若读数未知且 GCDGate 可分类，应仍看到 `dispatch_origin=burst` 的持续候选，并在映射中标记 `cooldownUncertain=true`；UNKNOWN 不得跳过或确认任何步骤。

前置饰品时应额外观察：`inventory_recovery_started`、`inventory_recovery_completed`、`soft_pause_clock_extended` 与 `gcd_locked_delivery_continues`。恢复完成只接受锁定槽位 + ItemID 的自身非 GCD CD，不能由图标灰度、泛 GCD 或 Buff 代替。


## 1.0.18 宏诊断

窗口或注入技能放在宏按钮时，先执行 `/teab status`，再在正式窗口出现后运行 `/temapping macro_112`。映射摘要中检查：

- `macroAssociation`：`GetMacroSpell` / `action_info_macro_spell` 或 `macro_body_*`；
- `macroAutoBurstEligible=true` 与 `actionBarStateTrusted=true`；
- `macroShape`：单技能、条件多技能或 `castsequence`；
- `macroBody` 不应出现。

`macro_spell_not_associated` 表示该宏正文/API 都没有识别到当前规则 SpellID；宏按钮被按下但游戏未形成当前规则步骤的精确确认时，计划保持同一候选/恢复，不会把泛 GCD 或其他宏分支当作成功。


## 1.0.18 新增排障字段

- `plan_gate_window_official_cooldown_conflict`：官方推荐已命中窗口，但本帧窗口冷却读取为 `COOLDOWN/UNKNOWN`；计划应仍创建并保留窗口所有权。
- `window_official_cooldown_revalidate`：记录窗口读数冲突；计划已经锁定，官方推荐旋转不会取消该计划。
- `official_window_departed_plan_latched`：官方推荐已离开窗口，但已创建计划继续运行；这是 1.0.18 的预期记录。
- `window_own_cooldown_sample / window_own_cooldown_confirmed`：窗口自身 CD 只有两次身份一致实时证据后才按规则结束。
- TEK trace 中同一逻辑步骤的 Burst 候选应有连续递增的 `sequence`；`input_sent` 次数应只随全局派发上限变化。
