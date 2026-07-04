# Tactic Echo Tasks

当前版本：`1.0.44 P5`

## P5 宏身份锚定实机验收

1. 将反制射击多行宏命名为 `打断`，再改名为 `DDD`，两次都应得到同一识别结果。
2. 可额外创建另一枚同名 `打断` 宏；P5 必须仍只读取当前动作条 actionInfo macro index，不能借用另一枚同名宏正文。
3. `/temapping p5_macro_identity` 应导出 `macroIdentitySource=action_info_id`、实际索引与读取次数；当前索引无正文时必须 `macro_body_unavailable` 且零 Token。
4. 详细步骤见 `docs/P5_MACRO_IDENTITY_TEST.md`。

## P4.6 反制射击多行宏实机验收（历史）

1. 将 `[@focus,nodead] 反制射击 → /cleartarget → /targetenemy → 反制射击 → /targetlasttarget` 宏放到当前可见默认动作条，并绑定受支持键位。
2. `/reload` 后检查 P2 打断映射：反制射击应有 `focus`、`target` 两条宏路由并显示“宏内目标逻辑，自动可按”。
3. 若仍未识别，执行 `/tecache refresh` 和 `/temapping p46_countershot`，退出游戏后核对导出字段：`macroLookupSource`、`macroActionInfoName`、`macroResolvedSpellTokenCount`、`macroFailureReason`。导出不得包含宏正文。
4. 识别通过后，按 P4.4 的严格可打断证据复测焦点读条与当前目标读条；本版不放宽钢条判定，也不改变 TEK 输入路径。

## 1.0.20 前置窗口 handoff 实机复测

1. 规则设为前置 `4 → 3`，保持 paused 时让官方推荐已经显示 `3`，随后切换 armed。状态帧与其后的 **4 张正常 tick 帧**均应为 `dispatch_origin=burst + observation_only=true + binding_token=0`；不得出现 `dispatch_origin=official + binding=3` 的先行输入。
2. `/temapping` 中 handoff 应从 `required=4 / remaining=4` 开始，四张 tick hold 后为 `remaining=0 / published=4`；**下一张**严格更新 freshness 的候选必须为 Burst `binding=4`。确认 4 后才可出现 Burst `binding=3`。
3. 反复测试“进入战斗第一技能即窗口”与“循环后续窗口”两种场景；两者均不允许 3 在 4 前抢跑。
4. 在 capture 阶段临时移除绑定、制造冷却 UNKNOWN、施法事件或 `/reload` 后恢复；即时 Refresh 只绘制 hold，不得压缩 4 帧预算或退回官方 3。
5. 导出 `/temapping` 与 TEK 诊断时核查 `preWindowCapture*`、`handoffBarrierRequiredFrames`、`handoffBarrierRemainingFrames`、`handoffBarrierPublishedFrames`、`pre_window_capture_handoff_barrier`、`pre_window_capture_handoff_ready`、TEK `old_frame_freshness/stale_frame_freshness`。

## 1.0.18 HUD / AutoBurst 联合实机复测

1. 13/14 槽饰品及药水/其他物品卡保持 ready 时，施放任意普通 GCD 技能：不得出现主 CD、数字、原生倒数、独立转盘或约 1～1.5 秒公共 GCD。
2. 使用真实自身冷却的物品：仅显示该物品自身 CD，且同一时间不叠加任何公共 GCD 层。普通 SpellID 卡的 GCD 展示必须保持原行为。
3. 前置与后置分别测试技能注入和 13 槽饰品注入。`READY_NOW / QUEUE_WINDOW / GCD_LOCKED` 下，同一未确认逻辑步骤的 TEAP sequence 必须持续递增；TEK 的 `input_sent` 仅随全局频率设置变化。
4. 饰品首次输入被游戏拒绝或打断多次后，序列不得因次数、确认期、重校验或恢复期超时卡住。手动补按锁定槽位物品后，检测到同 slot + ItemID 非 GCD 自身 CD 必须继续窗口。
5. 前置确认完成后，让官方推荐转为其他技能。应看到 `official_window_departed_plan_latched`，但窗口步骤仍持续候选；只有成功、规则确认自身 CD 或硬阻断才结束。
6. 制造窗口 `COOLDOWN/UNKNOWN` 冲突：真实自身 CD 只有两次身份一致证据才能按规则结束；UNKNOWN 不能跳过，GCDGate 可分类时应继续候选。
7. 在登录、换装或动作条重绑后的首个 HUD 刷新间隔，确认 13/14 槽饰品即使短暂未携带 ItemID、但仍保留装备槽位/物品类别，也绝不显示 `61304` 公共 GCD。
8. 后置简易注入 CD 时，同样验证两次同身份、非 GCD 自身 CD 证据后才结束；单次/未知/确认中的 `COOLDOWN` 不得越过或卡死，必须保持当前注入候选。

## 当前范围

- 保持常规主派发：官方推荐 → 默认动作条 → BindingToken → TEAP → TEK → SendInput。
- AutoBurst Phase 1 已接入：单窗口 + 单注入，前置/后置、简易/集中，默认关闭。
- 当前支持一个显式 13/14 槽饰品作为注入动作；不接入药水、背包道具、第二饰品、第二注入技能或多规则竞争。用户已有的可见默认动作条宏和 `/castsequence` 已纳入动态关联。

## 首轮实机验证

1. 将 `addon/!TacticEcho` 同步至 WoW AddOns 目录并 `/reload`，确认无 Lua 错误。
2. 为当前专精确认 Burst Profile 的窗口与注入技能均已放入可见默认动作条，并使用支持的键位。
3. 控制面板依次测试前置简易、前置集中、后置简易、后置集中。
4. 先实测前置简易：窗口=处决宣判、注入=复仇之怒；确认 GCD 等待期间 TEK Trace 是 `dispatch_origin=burst + observation_only=true + state=armed`，随后出现带非零 BindingToken 的 Burst 候选。
5. 查验 AddOn `TacticEchoDB.autoBurst.events`、TEK Trace 的 `dispatch_origin=burst`、TEK status 的 `last_dispatch_origin`。
6. 检查窗口进入边沿、`GCD_LOCKED / QUEUE_WINDOW / READY_NOW` 下的持续候选、CD/充能确认、脱战清空与手动接管/失焦 fail-closed。
7. 检查不同急速、网络、窗口模式、DPI、多显示器和真实 Windows SendInput。

## 已知限制

- 成功确认不使用 Buff；没有可用 CD/充能确认信号的技能不得加入 Phase 1。
- TEAP 没有 TEK → AddOn 回执，AddOn 只能通过 CD/充能或施法成功事件确认步骤；未确认时保持候选/恢复，而不是依赖超时判断。
- 自定义动作条插件仍不属于 Phase 1 自动爆发来源；默认动作条宏应实测条件分支、`@cursor` 与 `/castsequence` 的预期步骤确认。

## 后续候选

- 实机稳定后再设计饰品、药水与互斥组。
- 在确认策略不需要 Buff 后，才考虑多注入或多规则优先级。
- 依据实机 Trace 校准 GCDGate 的队列窗口边界与实际全局派发频率；不得再引入 Burst 专用重试上限。

## 1.0.11 Burst 本轮重点复测

1. 前置简易规则：窗口 `343527`（处决宣判，键 `1`），注入 `31884`（复仇之怒，键 `4`）。官方推荐进入 `1` 后，先检查 `/temapping` 中 `plan.preInjectionSkipAllowed`：只有同一 SpellID、同一直接动作条绑定的两次实时非 GCD 自身 CD 证据均确认后才能为 `true`。
2. 当 `4` 可用时，TEK Trace 必须先出现 `dispatch_origin=burst + binding=4`；在 `4` 成功回执前不得出现官方来源的 `binding=1`。
3. 当 `4` 的 CD/GCD 来源未知时，应看到 `step_revalidate_started / step_revalidate_wait` 与 Burst observation 帧；超时后只观察到窗口离开，`1` 不得绕过。
4. `4` 成功后，诊断应出现 `step_spellcast_succeeded` 或专属 CD/充能确认；随后 `1` 在 `GCD_LOCKED / QUEUE_WINDOW / READY_NOW` 持续发布候选，实际输入频率仅受全局设置限制。
5. 暂停后再启动时，如果首个健康帧已经显示 `1` 且该窗口 generation 未消费，应仍先出现 Burst `binding=4`。
6. 完成、中止或超时后，官方仍显示 `1` 时只能 observation-only；HUD 显示官方键位 `1`，TEAP `BindingToken=0`。
7. `/temapping autoburst_108` 后检查 `armedEpoch`、`firstHealthyFramePending`、`windowGeneration`、`consumedWindowGeneration`、`departureLockGeneration`、`lastCandidate`、`candidateOfferCount`、`lastConfirmationSource`、`lastAbortReason`、`lastWindowRejectReason`。
8. 测试结束执行 `/reload` 或完全退出游戏，上传新的 TEK 诊断包及 `TacticEcho.lua`。


## 1.0.11 主键状态实机检查

1. 手动暂停后确认主推荐图标保持原色和正常亮度，仅显示“暂停”状态标签与暂停色边框。
2. 施放当前主推荐普通读条技能时，主键应显示“施法”。
3. 引导当前技能或处于引导锁时，主键应显示“引导”；TEK 仍必须阻断 `channeling` 帧。
4. 在暂停状态下人为制造资源不足、超距或无目标，主键不得重新出现灰色去色遮罩。


## 1.0.11 本轮重点复测

1. 对打断、防御、控制等普通技能施放一次：任何非当前 AutoBurst 注入/窗口技能不得显示“校验”。
2. 分别在主键、爆发、打断、防御模块调整 CD 时间字体、颜色、缩放、锚点；默认 HUD 模式必须直接变化。切换“原生”后则由 Blizzard 数字接管。
3. 真实自身 CD 保留单个 CD 转盘与一组数字，图标本体保持彩色；资源、超距、目标问题仅显示对应状态，不额外灰化。
4. 在前置/后置 Burst 中人为制造窗口队列边缘：诊断应记录持续的候选发布与 `window_queue_delivery_continues`，而非固定一次重试；检查 TEK Trace 的真实输入次数不超过当前全局限频。
5. 仍需验证普通窗口确认、等价 SpellID 成功事件、等待确认超时和脱战离开锁。


## 1.0.12 宏兼容实机复测

1. 将 `乱射（260243）` 放入现有宏按钮，例如 `#showtooltip\n/cast [@cursor] 乱射`，并保持一个有效实体按键；显式规则设为窗口 `260243`、注入 `288613`。
2. `/teab status` 的规则保持 `manual_spell_ids` 后，在官方=`260243` 的 armed 战斗帧验证不会再出现 `macro_not_single_use` 或 `macro_spell_not_associated`。
3. 观察 Burst：前置模式应先给百发百中宏/直技能候选，再给乱射宏候选；“校验”仅出现在当前步骤。
4. 测试带 `/stopcasting`、`[@cursor]`、条件分支和 `/castsequence` 的既有宏。若实际宏分支未释放当前规则 SpellID，诊断应只出现当前步骤确认超时/窗口锁，不能派发额外按键或跨过窗口。
5. `/temapping` 检查 `macroAssociation`、`macroAutoBurstEligible`、`macroShape`、`actionBarStateTrusted`，确认导出不包含 `macroBody`。


## 1.0.13 饰品注入与 TEUI 实机复测

1. 将一个饰品直放动作条，或放入仅含 `/use 13`（或 `/use 14`）的既有宏，并确保有实体按键。
2. 用 `/teab trinket <窗口SpellID> 13` 配置规则，先用默认 follow-GCD 测试；只有确认该具体饰品脱 GCD 后，再使用末尾 `offgcd`。
3. 前置简易：饰品可用时必须先出现 Burst 饰品候选，确认该槽位锁定 ItemID 自身 CD 后才派发窗口；饰品自身 CD 只可在两次证据后跳过。
4. 测试无绑定、装备替换、API 未知和确认超时：必须中止并等待官方窗口离开，不能直接派发窗口。
5. 双槽宏 `/use 13` + `/use 14` 必须被拒绝，不得创建计划。
6. 分别右键主键、爆发、打断/控制、防御和 HUD 底纹，检查 TEUI 页面跳转与左侧导航高亮；爆发页两个子页均应可用。


## 1.0.14 持续派发与饰品恢复实机复测（历史）

1. 设置较低与较高的 TEK 最大派发频率，分别测试普通官方推荐与同一 Burst 步骤；二者的 `input_sent` 次数都应仅随全局限频变化，而不是因 Burst sequence 被单独去重。
2. 在普通 GCD 中进入前置 Burst。当前注入/窗口为自身 ready 时，应持续发布 Burst 候选，不能退为 observation-only；成功仍只能由精确 CD、充能或施法回执推进。
3. 前置饰品候选首次输入后，以暂停、普通读条、引导/蓄力或手动输入打断。恢复后确认期限必须冻结延长；在恢复期手动补按同一锁定饰品，检测到精确 slot + ItemID 的非 GCD CD 后必须继续派发窗口。
4. 在恢复期制造通用 GCD、HUD 灰色、换饰品、无绑定或未知冷却；均不得被当成成功或跳过，恢复超时后必须只观察至官方窗口离开。

## 1.0.15 实机复测

1. 将 TEK 最大派发频率分别设置为较低和较高值。保持同一 Burst 饰品或技能步骤未确认时，诊断中 sequence 应持续递增，`input_sent` 数量只受该全局频率控制。
2. 制造“官方窗口已推荐、窗口 CD 采样短暂异常”的现场。应记录 `plan_gate_window_official_cooldown_conflict`，而不是 `plan_rejected:spell_cooldown_active`；前置动作成功后，窗口就绪才派发。
3. 前置饰品被打断后，手动补按导致锁定槽位/ItemID 出现非 GCD 自身 CD 时，应继续派发窗口；未确认时不得自动越过饰品。


## 1.0.16 饰品 HUD 显示实机复测

1. 分别放置 13/14 槽饰品，施放其他普通 GCD 技能；饰品自身 ready 时不得显示公共 GCD 倒数。
2. 使用带真实个人冷却的饰品，确认显示为真实物品 CD，且在同一次公共 GCD 内不被约 1～1.5 秒倒数覆盖。
3. 将同一饰品用于前置和后置 AutoBurst；确认 Burst 计划、锁定 ItemID、冷却确认、恢复期与窗口推进均未改变。
