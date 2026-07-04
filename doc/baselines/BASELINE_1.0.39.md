# Tactic Echo 1.0.39 基线：打断控制重构 P1–P4

## 本版范围

1.0.39 的 P1–P3 完成设置结构、配置预设、**只读**动作条/宏关联识别，以及**只读**读条候选与 HUD 高亮。原“打断与控制”页面保留原导航入口，页内现拆为三个子页，顺序固定为：**打断设置｜控制设置｜样式设置**。

- `打断设置`：保留既有打断提示策略，新增自动打断目标来源与顺序预设，并展示当前职业打断技能的动作条/宏识别结果。
- `控制设置`：保留既有控制/位移提示策略，新增自动单体控制、自动群控及目标来源预设，并展示单体控制、群体控制的动作条/宏识别结果。
- `样式设置`：承接原打断与控制 HUD 共用的按键、充能、CD、状态标签、转盘与光效样式；仅改变表现层。

`/teui interrupt`、`/teui control`、`/teui interruptstyle`（或 `/teui reactionstyle`）分别可直达三页。

自动化预设只存在于 `tactics.autoReaction`：

```text
autoReaction.interrupt.enabled
autoReaction.interrupt.targetOrder
autoReaction.interrupt.targetEnabled
autoReaction.control.enabled
autoReaction.control.aoeEnabled
autoReaction.control.targetOrder
autoReaction.control.targetEnabled
```

默认策略：自动开关全部关闭；目标来源默认仅勾选当前目标，焦点与鼠标指向保持未勾选但始终可排序。



## P4.2 事件确认补充合同

当 `UnitCastingInfo` / `UnitChannelInfo` 已证实活跃读条但 `notInterruptible` 仍为不透明值时，P4.2 可以消费 `ReactionInterruptEvents` 的短时普通单位施法事件：`UNIT_SPELLCAST_INTERRUPTIBLE` 在 P3 同源活跃读条仍存在时构成自动打断确认；`UNIT_SPELLCAST_NOT_INTERRUPTIBLE` 构成硬性否决。事件缓存不会独立证明读条、不会越过 P3、不会生成 BindingToken 或直接输入；目标/焦点/世界切换会清空缓存，且可读 SpellID 不一致时 fail-closed。

## P4 自动打断合同

P4 新增 `Tactics/AutoReaction.lua`，但不修改 `AutoBurst` 状态机、HUD 布局、标签、冷却数字/转盘或现有 TEK 门禁。它只消费 P3 标量读条观察与 P2 现有动作条/宏路由，再由 `SignalFrame` 选择普通 TEAP v3 派发候选。

- 仅自动打断：战斗内、TE 有效状态为 `armed`、目标敌对且存活、读条已由直接单位 API 或原生**明确无盾／false／可打断**结论确认可打断、P2 路由 `bindingReady=true`、`safeForFutureAuto=true` 且存在非零 BindingToken。P3 `interrupt_unverified`、scalar-only、transient gap、资料表回退、钢条均不得进入自动输入。
- 按“当前目标｜焦点｜鼠标指向”勾选与排序选择第一个候选。不主动发出 `/target`、不改宏；若用户宏已被 P2 识别为同技能安全宏路由，P4 只按该动作条宏键位一次，宏内目标逻辑保持 Blizzard 原行为。
- 同一读条只创建一次 Reaction candidate；此后输出 observation-only hold，直到读条消失或身份变化，避免重复按键。
- 用户确认的 Burst 冲突策略为：活跃 Burst plan 或 pre-window capture 期间，P4 不自动打断、只保留高亮；Burst 完结后才允许后续确认读条派发。
- TEAP v3 长度仍为 20 bytes。Burst 保留 bit `0x20`，P4 Reaction 使用 bit `0x40`；两位同时出现由 TEK 解码器 fail-closed 为 `dispatch_origin_conflict`。没有新增第二条输入通道。

## P2 动作条与宏学习合同

P2 新增 `Tactics/ReactionBindings.lua`，它只复用既有 `ActionBarBindingResolver` 与 `MacroSemantics`，从当前可见 Blizzard 默认动作条及玩家已有宏读取映射。P2 不扫描读条、不判断可打断/免控、不高亮、不创建输入请求。

宏关联沿用 Burst 已有宽松关联范围：`/cast`、`/use`、条件和分号分支、多行辅助命令、`/castsequence`、`@focus`、`@mouseover`、`@cursor` 均可被识别为已有宏按钮关联。为后续自动化安全路由，P2 额外仅做描述性标记：

- 普通直绑技能只登记为当前目标路由；
- 焦点、鼠标指向必须来自明确的 `@focus`、`@mouseover` 宏；
- 多目标分支、多技能宏、`/castsequence` 等不透明宏仍会展示为已识别，但仅保留手动动作条使用资格；
- `@cursor` 仅作为显式标为群控技能的未来候选，P2 本身不会释放任何技能。
- 包含目标管理命令（例如 `/cleartarget`、`/targetenemy`、`/targetlasttarget`）的同技能宏会识别为 `macroManagedTargetAuto`：焦点优先→选敌回退→恢复目标的模式明确显示为“宏内目标逻辑，自动可按”。后续自动打断/控制只会按该已有宏按钮一次，不拆分、推断、改写或代替宏内目标处理；多技能宏、`/castsequence`、无真实键位或无法确认同一技能身份的宏仍仅手动/失败关闭。

P2 的映射页只显示当前可见动作条/已有宏与安全键位状态；不会保存宏正文、不会改写宏、不会创建或修改动作条绑定。

> 已知实机缺口：用户的“焦点优先 → 清目标/选敌回退 → 恢复目标”的反制射击同技能宏，在 P2.2 后仍未显示为已识别。该宏兼容设计保留，但本基线不把它视为实机已验收；需以动作条解析诊断单独修复。

## P3 读条观察与 HUD 高亮合同

P3 新增 `Tactics/ReactionObservation.lua`。该模块由既有 `ProtocolMonitor` 的 0.12 秒轮询调用，不注册事件、不建立第二条高频刷新链，也不创建任何输入能力。`TacticalAdvisors` 只消费同一监控快照，向现有 HUD 卡片投影一个只读反应候选。

- **观察来源**：当前目标、焦点目标、鼠标指向目标，以及当前客户端可见姓名板；目标来源顺序和勾选读取 `autoReaction.interrupt/control.targetOrder/targetEnabled`，自动总开关关闭时仍保留高亮。
- **打断候选**：敌对、存活、API 或原生施法条明确判定为可打断的施法或引导；不可打断钢条不会作为打断候选。若客户端只公开活跃读条而钢条状态仍不可读，P3 可显示 `interrupt_unverified` 只读预警用于验证观察链，但该卡固定 `bindingToken=0`、`reactionProbeOnly=true`、`reactionAutoEligible=false`，绝不能成为 P4/P5 自动派发资格。
- **单体控制候选**：敌对、存活、API 明确判定为不可打断的读条；仅敌对玩家或普通 NPC 可进入候选，`elite`、`rareelite`、`worldboss`、Boss API、`UnitLevel=-1` 均被排除。
- **群控候选**：当前可见姓名板中至少 4 个有效不可打断读条，且当前职业存在已识别且明确 `@cursor` 的群控宏路由。无法证明 `@cursor` 路由时只提示“范围钢条达到阈值”，不生成可高亮群控卡。
- **唯一高亮**：优先级固定为 `打断 > 群控 > 单体控制`；选中项以 `procHighlight/reactionHighlight` 呈现，并携带 `bindingToken=0`、`readOnly=true`、`dispatchAllowed=false`。

P3 不创建 BindingToken、不写 TEAP、不调用 TEK 或 SendInput，不改 AutoBurst、官方推荐、HUD 布局、标签、DurationObject 或 CD 数字链。P4/P5 才能讨论实际自动打断、单控、群控及 HUD 点击。


### P3.4 原生钢条证据分级与读条连续性

- 当前 Retail 姓名板施法条的 `notInterruptible` / `isUninterruptible` 标量可能在外部打断后的下一段读条中残留；P3.4 不再把**仅有标量 true、没有可见盾**的状态视为硬钢条。直接单位 API 的明确 true 与原生 `BorderShield:IsShown()` 的可见盾仍是硬不可打断；原生明确无盾 / false 仍可确认可打断；标量-only true 降级为 `interrupt_unverified`，只读高亮且固定 `bindingToken=0`。
- 目标、焦点、鼠标指向的原生施法条在一次轮询短暂消失时，P3 可保持最多 `0.22s` 的只读“读条连续性桥接”，并强制降级为未验证提示；不会恢复已确认读条为自动资格，也不会影响 P4/P5 的任何派发规则。
- 现场诊断新增钢条证据、可见盾和连续性字段，以区分真实钢条、原生字段滞留与一次轮询空洞。

### P3.3 原生施法条兜底与目标观察收敛

- `ReactionObservation` 继续先读取 `UnitCastingInfo` / `UnitChannelInfo`；当当前 Retail 客户端把单位读条记录或 `notInterruptible` 标量限制为不可材料化时，才以 Blizzard 已可见的目标、焦点或姓名板施法条为**只读兜底**。
- 原生施法条只读取 `casting/channeling/empowering`、`isActiveCast`、`notInterruptible/isUninterruptible/interruptible`、`showShield`、`BorderShield:IsShown()`、`barType` 等普通标量，并全部在 `pcall` 内处理；不保存 frame、读条名称、宏正文或受保护值。只有原生施法条明确显示“无盾”时才补足可打断状态；显示盾或 `uninterruptible` 时绝不作为打断候选。完全无法确认钢条状态时，仅允许 P3 显示不可派发的 `interrupt_unverified` 预警。
- `ProtocolMonitor` 同步改为以完整 API 返回位数判断当前目标读条，不再以可能是 Secret Value 的技能名称真值判断读条存在；若直读仍不可用，可仅回填 `ReactionObservation` 的目标观察事实。
- P3 仍无事件注册、无独立刷新链、无 BindingToken、无 TEAP/TEK/SendInput。所有原生施法条结果仅用于高亮与诊断。

### P3.2 读条记录 arity 判定、监控回退与现场诊断

- P3 读条存在性改用 `UnitCastingInfo` / `UnitChannelInfo` 的完整返回位数判定，不再以任何可读/可判断的技能名称作为记录存在性依据；完整施法记录与空返回区分后，才读取安全的 `notInterruptible` / SpellID 标量。
- 当前目标的 P3 观察若因 API 材料化失败而漏失，但既有 `ProtocolMonitor` 已确认同一轮询的当前目标读条，则仅把该显示事实回填为 `protocol_monitor_target_fallback`；不会扩展观察范围、不会假定敌对/存活/钢条状态。
- P2 映射缓存暂不可用时，P3 继续使用职业资料表只读图标验证读条，而非整条高亮链路消失；该图标仍固定 `bindingToken=0`、`dispatchAllowed=false`。
- 打断设置新增 P3 目标观测读数：目标存在/敌对/存活、读条、可打断状态、API 证据和 P2 映射是否可用。输出仅为普通标量，不记录技能名、宏正文或受保护值。

### P3.1 读条可见性与映射解耦修复

- `UnitCastingInfo` / `UnitChannelInfo` 的**读条存在性**不再以“技能名称能否安全转为普通 Lua 字符串”为前提。P3 仅在 `pcall` 内确认 API 返回了读条记录，并且不保存原始技能名称；`notInterruptible` 与 SpellID 仍按既有普通标量规则 fail-closed。
- P3 的高亮验证不再被 P2 动作条/宏映射缺失完全阻断：对已证明的可打断读条或合格单控读条，若 P2 没有路由，会显示当前职业资料表中的只读、不可派发图标，明确标注“未识别动作条/宏，仅提示”。P4/P5 自动输入仍必须要求 P2 已解析的真实路由，不能使用此回退。
- 此修复不改变 AutoBurst、TEAP、TEK、BindingToken、HUD CD、标签、目标逻辑或宏。

### P4.1 自动打断确认、路由恢复与诊断

- 当直接 `UnitCastingInfo` / `UnitChannelInfo` 的 `notInterruptible` 字段在 Retail 中不透明，但 Blizzard 原生施法条明确给出“无盾／可打断”普通标量时，`ReactionObservation` 保留该原生证据；P4 仅接受 `showShield=false`、隐藏可见盾、`notInterruptible=false`、`interruptible=true` 或等价原生明确可打断结论。原生 true/未验证、可见盾、P3 profile fallback 与 `transient_gap_hold` 继续只读，不能自动输入。
- P4 对确认读条但没有 P2 安全路由的情况，按**每个真实读条**最多调用一次 `ReactionBindings:RefreshForAuto()`，以重建既有可见 Blizzard 默认动作条缓存并重试；该路径不创建 BindingToken、不写绑定、不编辑宏、不访问第三方动作条，也不在每轮轮询重扫。
- 目标、焦点、鼠标指向读条加入 `castSerial`。每次原始读条 inactive→active 或可读身份变化递增，避免外部打断后的下一段施法被 P4 当作同一次已尝试读条。短暂显示桥接仍固定为未验证。
- `TacticEchoDB.autoReactionRuntime` 现在保存有界的 P4 状态转换与候选记录，供现场诊断区分“TE 未启动”“读条未确认”“动作条路由未识别”“Burst 占用”和“已提交 reaction 候选”。诊断不保存读条名称、宏正文或原生 frame。

## 冻结合同

以下运行链在 1.0.39 P1–P3 均不改动：

- AutoBurst 有序序列、预检、确认、四帧 handoff、起手 bridge 与切图围栏；
- 官方推荐、现有动作条解析、BindingToken、TEAP v3、TEK 门禁与 SendInput；
- HUD 布局、标签、DurationObject 转盘、HUD 纯秒数与 CooldownTracker；
- 现有打断、控制、位移、防御的只读显示建议。

P3 读取读条但仅用于显示；不创建 BindingToken、不写 TEAP、不调用 TEK、不触发 SendInput。自动开关仍不触发任何自动操作。后续 P4/P5 才在独立反应层接入自动打断、自动控制、自动群控与 HUD 点击。

## 已确认的后续规则

- 自动打断与 Burst 冲突时：**Burst 未结束仅提示，Burst 结束后才允许自动打断尝试**。
- 自动打断时机：识别到有效读条后立即尝试一次。
- 地面群控：只允许玩家已有明确 `@cursor` 宏时，才可能进入后续自动释放候选。
- 适配范围：后续按现有全部支持职业与专精实施。

## 验收

1. 设置页内顺序为“打断设置｜控制设置｜样式设置”，并可保存当前子页。
2. 打断与控制页可重扫当前动作条/宏，显示直绑、`@focus`、`@mouseover`、`@cursor` 与不透明宏的不同状态。
3. P3 对可打断读条、不可打断单体读条和至少 4 个可见钢条按“打断 > 群控 > 单体控制”仅高亮一个技能；不自动施法。
4. P3 不创建 BindingToken，不发送 TEAP/TEK 请求，不修改宏或动作条。
5. AutoBurst、HUD、标签及 CD 显示与 1.0.38 稳定路径一致。
