# AGENTS.md — Tactic Echo 1.0.44 P5 开发与安全边界

## 1. 基线与交付

- 当前唯一开发基线：`1.0.44 P5`。AutoBurst 与输入路径仍以 1.0.35 为冻结基线；HUD 冷却渲染仍以已实测稳定的 1.0.31 实时转盘路径为基础，并由 1.0.38 收口为“DurationObject 只画转盘、HUD 徽标统一纯秒数”。1.0.39 P1–P3 提供设置、动作条/宏映射、只读读条候选与 HUD 高亮；1.0.40 P4.3 已实机证明 reaction 的 BindingToken→TEAP→TEK 动作链与稳定候选交付可用；1.0.41 P4.4 恢复严格钢条/可打断证据；1.0.42 P4.5 在不改输入链的前提下，严格识别并守卫 `@mouseover → @focus → target` 单技能整合打断宏；1.0.43 P4.6 修复多行打断宏的正文回收与 SpellID 关联韧性；1.0.44 P5 将宏身份收紧为动作条 `actionInfoID` 的 numeric macro index，彻底移除按宏名回收正文的路径。此前版本仅保留历史记录。
- 默认交付完整源码包。压缩包只能有一个项目根目录，不得包含 `build/`、`dist/`、`release/`、缓存、日志、SavedVariables、EXE、历史补丁或本机配置。
- 每次代码修改必须保持根目录 `VERSION`、插件 TOC、`Core/Bootstrap.lua` 版本一致，并运行本文件第 9 节验证。
- 不得以离线测试、PyInstaller 成功或进程存活作为 Windows Hook、前台判断、SendInput、自动爆发实机成功的证据。

## 2. 常规派发路径

唯一常规输入路径：

```text
官方推荐（只读）
→ 当前可见 Blizzard 默认动作条绑定
→ BindingToken
→ TEAP v3
→ TEK 协议 / 前台 / Hook / 手动让权 / 限频门禁
→ 单次 SendInput
```

禁止新增任何绕过该路径的输入通道。AddOn 不得创建隐藏按钮、写按键、保存按键、编辑宏、合成宏、直接调用 Windows 输入或写虚拟键值。

## 3. 自动爆发：可排序多步骤受控接管

AutoBurst 是官方推荐的受控候选层，不是第二条输入通道：

```text
OfficialRecommendation（不可变）
→ AutoBurst OrderedPlan（候选）
→ 已解析 BindingToken
→ TEAP v3（dispatchOrigin=burst）
→ TEK 全部门禁
→ 单次 SendInput
```

### 3.1 每专精数据模型

每个专精独立保存一条 sequence，步骤身份必须稳定：

```text
window                    -- 固定、不可停用
injection:<SpellID>       -- 最多 3 个，来自该专精“注入技能”列表的已启用前 3 项
trinket:13 / trinket:14   -- 固定装备栏身份，计划创建时锁定实际 ItemID
```

顺序、启用状态和 `offGCDExplicit` 必须写入 `tactics.burstProfiles[profileKey].autoBurstSequence`。禁止按“注入第 1/2/3 槽位”、动作条键位、瞬时 ItemID 或跨专精全局变量保存顺序。窗口步骤永远存在；注入/饰品可独立启用、停用、上移、下移。旧 Phase 1.5 的手填窗口/注入 SpellID、方向、单饰品入口和 fallback 字段不得恢复或参与运行时规则。

### 3.2 计划创建与预检

命中官方窗口后，先对每个已启用可选步骤执行真实绑定、装备身份、实时自身 CD/充能与 GCD 采样，再决定是否创建计划：

- `simple`：移除明确自身 CD、冷却 UNKNOWN、无绑定、未装备、装备身份变化或其他硬失效步骤；保留剩余步骤相对顺序。
- `focused`：任何已启用可选步骤不可用，即不创建计划，官方窗口保持普通路径。
- 所有可选步骤均被移除时，不创建计划。
- `READY_NOW`、`QUEUE_WINDOW` 与 `GCD_LOCKED` 是可用时序，不是自身 CD；共享 GCD 永远不得排除或确认一个步骤。
- 对 resolver 已验证的直接可信默认动作条，当前按钮的显式 ready（`isActive=false` 或可解释 `0/0`）可仅用于纠正覆盖/天赋变体造成的旧 SpellID 自身 CD；该证据不构成 CD 跳过、成功确认或任何额外派发资格。
- 窗口步骤始终保留；真实计划不得把窗口替换为旧缓存 SpellID。

预检只使用 `IconState:CollectCooldownOnly()`、`CollectInventoryCooldownOnly()`、`GCDGate`、已验证的动作条绑定和当前官方推荐。不得使用 Buff、Debuff、资源、目标生命、敌人数量、首领机制、距离、范围或读条对象作为爆发时机输入。

### 3.3 执行、确认与运行期漂移

- 每个计划严格按用户 sequence 的实际筛选结果逐步执行；每帧最多一个 BindingToken。
- 每步派发前再次实时采样。`simple` 运行期失效时只跳过该可选步骤并继续；`focused` 在窗口尚未派发时释放官方窗口，窗口已派发后才保留离开锁。
- 步骤仅由当前 `WAIT_CONFIRM` 的精确 `UNIT_SPELLCAST_SUCCEEDED`、自身非 GCD CD 开始或充能减少确认；饰品还必须匹配锁定 slot + ItemID。
- UNKNOWN、图标灰度、泛 GCD、失败事件、Buff、资源/目标状态不得作为跳过或成功证据。
- 已确认窗口后需观察官方窗口离开，避免重复派发；已创建计划内官方推荐旋转仅记录诊断，不取消完成中的步骤。

### 3.4 Handoff 与起手 bridge

只有实际筛选后的第一步骤位于窗口之前时，AutoBurst 才创建 `PreWindowCapture`；真实 paused→armed 需先输出 4 张正常 transport tick 的 `observationOnly + BindingToken=0` hold，第 5 张新鲜帧才可输出第一可选步骤。事件/状态刷新不得消耗该预算。

已 arm 的前置序列可通过既有 bridge 跨越脱战→`PLAYER_REGEN_DISABLED`，且 bridge 计划不得被进战事件清空。窗口第一的顺序不启动 bridge；普通脱战官方推荐始终没有普通派发资格。

### 3.4 切图安全围栏

- `PLAYER_LEAVING_WORLD`、`PLAYER_ENTERING_WORLD`、`ZONE_CHANGED_NEW_AREA` 必须撤销仅用于脱战起手的隐式 bridge 授权，清除旧 plan/capture/window ownership，且不得建立 departure lock。
- 围栏期间，脱战窗口只能观察，不能创建或派发 Burst plan；普通进战自动运行不受影响。真实 `PLAYER_REGEN_DISABLED` 可解除围栏。
- 切图后需要脱战起手时，只能经已有“运行”动作重新授权；不得新增用户可见模式、标签或普通脱战派发权限。重新授权后的前置序列必须重新执行四帧 handoff。

### 3.5 UI 与诊断

爆发页只允许：自动爆发开关、`simple/focused`、当前专精的顺序调整、可选步骤启停、已实测确认的饰品脱 GCD标记，以及下方专精注入技能列表。不得重新加入手填规则或“测试规则”入口。

必须保留并导出：`sequence_preflight_selected`、`sequence_preflight_no_eligible`、`selectedOrder`、`excludedOrder`、`sequenceLength`、`sequenceKeys`、handoff 帧数、当前步骤、锁定饰品 slot/ItemID、计划中止/释放原因。诊断不得导出宏正文、原始受保护 cooldown 数值或用户敏感数据。

## 3.6 HUD 冷却展示、实时对象与真实动作条数值

- `IconState`、`CooldownResolver` 与 `CooldownTracker` 负责 CD/GCD/充能的安全语义和标量状态；`TacticalHudModel` 只传递普通标量，绝不保存 `DurationObject`、受保护值、宏正文或任何派发权限。
- `TacticalIconButton` 使用 1.0.31 已实测稳定的实时渲染路径：`showDurationObjectCooldown()` 可为**视觉展示**查询当前 `C_ActionBar`、`C_Spell` 与 `CooldownResolver`，顺序选择一个可用客户端 `DurationObject` 绘制转盘。此读取不得回写推荐、AutoBurst、BindingToken、TEAP、TEK 或任何输入条件。
- 每次卡片绘制只允许附着一份最终选定的客户端转盘对象；`DurationObject` 的 CountdownNumbers 必须无条件隐藏，永远不能成为 HUD 数字来源。HUD 徽标是唯一数字层，只使用 `IconState`/Tracker 已确认的安全数值与连续性缓存，并统一以向上取整的纯秒数显示。
- 当前专精防御、爆发窗口与爆发注入技能必须在脱战时由 `CooldownTracker:PrimeCurrentSpec()` 预注册。预注册条目可缓存 Tooltip/Base 时长；后续直接动作条槽位建立时必须迁移同一条目而不丢失缓存。该缓存只用于已确认施放事件后的本地展示计时，并须由后续动作条/技能 API 观察自动校正。
- HUD 暂无安全数值时只保留原生转盘、隐藏数字；不得以 Blizzard `MM:SS`、Tooltip/Base 静态值、宏猜测、图标灰度或不可信动作条伪造即时 HUD 数字。直接可信默认动作条的安全、可解释、非 GCD 自身 CD 数值仍可显示真实剩余时间与总时长。
- `BuildCooldownPresentation`、`TE.HudCooldownDurationObjects`、`cooldownPresentation` 侧车、`runtimeDurationObject` 与 `showSnapshotDurationObject` 不得恢复。该架构在目标 Retail 客户端上会导致普通技能 CD 转盘或数字失效，或 reload 后冷却来源随机切换。
- 主键与 Burst-window 的纯共享 GCD 必须隐藏；13/14 槽饰品和其他物品卡不得显示泛 GCD。自身 CD 与共享 GCD 同时存在时，展示自身 CD。`cooldownGcdAlias` 可由 `IconState` 透传到 HUD，仅用于阻止 `61304` 别名误显示。
- HUD CD 展示数据不得改变 AutoBurst 预检、步骤跳过、成功确认、TEAP、TEK 或任何输入派发权限。


## 3.8 P4 自动打断

- P4 仅允许 `AutoReaction` 生成自动**打断**候选；不得实现单体控制、群控、HUD 点击、自动选目标或宏改写。
- **P4.4 严格可打断资格**：候选必须同时满足战斗内、intent/effective state 均为 `armed`、敌对存活、P3 证明为真实活跃读条（非 `transient_gap_hold`）、以及已有 P2 `safeForFutureAuto=true` 的真实 BindingToken 路由。
- 可打断证据的固定优先级：① `UnitCastingInfo`/`UnitChannelInfo` 可材料化的 `notInterruptible=false`；② 当前真实原生盾组件明确**可见**时硬性否决；③ 同源、未过期的 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` 硬性否决，`UNIT_SPELLCAST_INTERRUPTIBLE` 正向确认；④ 当前真实盾组件连续两次 P3 采样均明确隐藏，或连续两次明确的原生 `interruptible/notInterruptible=false`。直接 API 与单位事件不需要原生两次采样。
- `showShield`、`barType`、原生 scalar-only `true`、P3 bridge、profile fallback、无法材料化的未知值均仅可诊断，绝不能授权自动派发。P4.3 的 `probe_active_cast_ignore_steel` 例外已移除。
- 事件状态帧可能没有 spellID/castGUID；`ReactionInterruptEvents` 必须保留最近一次 START 事件的可读身份，不能被 status 事件的 nil 覆盖。缓存仍受 TTL、目标切换和终止事件约束；读条与缓存都可读 SpellID 且不一致时 fail-closed。
- 同一活跃读条保持同一个 `reaction` candidate，直到读条消失/身份变化。SignalFrame 必须为这段候选保持稳定 sequence；TEK 仅在该 sequence 第一次成功 SendInput 后抑制重复帧。不得通过缩短候选为单帧或新增第二输入通道来规避跨进程采样竞争。
- **P4.5 严格整合宏资格**：仅可识别单一 `/cast`、单一技能身份、无 `/castsequence`、无目标管理命令、且条件链精确为 `[@mouseover,exists?,harm,nodead][@focus,exists?,harm,nodead][@target?,exists?,harm,nodead]` 的既有宏。P2 可将其三个来源登记为 `macro_priority_chain`，但 P4 在针对 focus/target 候选派发前必须确认不存在任何更高优先级、仍满足宏 `harm,nodead` 条件的单位；否则记录 `macro_priority_preempted_by_<source>` 并 fail-closed。该宏**不能判断“是否正在施法”**，因此不得把“上游单位未读条”当作宏分支不成立；不符合精确条件链的多条件宏保持手动使用。
- **P5 宏身份锚定**：对当前可见动作条上的既有宏，`GetActionInfo(actionSlot)` 返回的 numeric `actionInfoID` 是唯一正文身份。`GetMacroInfo(actionInfoID)` 首读仅有名称/无正文时，只能对**同一 numeric index**有界重读；不得调用 `GetMacroInfo(name)`，不得按账号/角色宏名枚举或借用另一枚同名宏正文。当前 index 无正文必须 fail-closed，即使另一同名宏包含请求技能也不得授权。`/cast` token 可只读解析为普通 SpellID 以克服名称 API 临时不可材料化；不得持久化宏正文、不得将未解析 token 作为派发资格；正文、同一技能身份和真实键位仍必须全部确认。
- 活跃 `AutoBurst` plan 或 pre-window capture 具有优先权：只高亮，不自动打断；不得调用 `AutoBurst:Abort`、推进或重置其状态。
- SignalEncoder 使用 TEAP v3 预留 bit `0x40` 标记 `reaction`，并保持单一 20-byte 传输。TEK 在 `0x20|0x40` 同时存在时拒绝帧。
- 当确认读条没有 P2 安全路由时，仅可对该读条调用一次 `ReactionBindings:RefreshForAuto()` 重建既有默认动作条缓存。`castSerial` 用于区分外部打断后的下一段读条；P4 状态诊断必须区分 runtime、读条确认、视觉采样与路由阻断。不得将 native true／未知、P3 bridge 或 profile fallback 放宽为自动资格。

## 3.7 P3 只读打断/控制候选与 HUD 高亮

- `ReactionObservation` 只能由既有 `ProtocolMonitor` 轮询节奏采样；不得注册事件、建立独立高频 OnUpdate、创建 BindingToken 或向任何输入链写入数据。
- P3 读条存在性可在 `pcall` 内依据 `UnitCastingInfo` / `UnitChannelInfo` 的完整 API 返回位数判断；不得以可保存/可显示的技能名称或其真值判断作为活跃读条前提，也不得保存原始读条名称。当前目标观察器若遗漏但同轮 `ProtocolMonitor` 已确认读条，可仅回填该显示事实，不得猜测敌对、存活或钢条状态。若直接单位读条 API 被 Retail 的 Secret Value 限制，P3 可只读查询 Blizzard 已显示的目标/焦点/姓名板施法条的 `casting/channeling/empowering/isActiveCast` 与盾牌状态（包括 `BorderShield:IsShown()`）；直接 API 的明确 true 与原生**可见盾**必须保持不可打断，原生明确无盾/false 才可作为可打断状态补足。仅来自原生 `notInterruptible` / `isUninterruptible` 的 true、但没有可见盾的状态不得作为硬钢条结论：它只能降级为 `interrupt_unverified` 验证预警，并强制 `bindingToken=0`、`reactionProbeOnly=true`、`reactionAutoEligible=false`；它不是可打断结论，绝不能进入 P4/P5 派发资格。目标/焦点/鼠标指向可在一次轮询短暂缺失时保持最多 0.22 秒的未验证显示桥接，桥接不得恢复自动资格。该兜底不得注册事件、保存 frame/读条名称、创建 BindingToken 或写入输入链。P2 映射缺失或缓存重建时，P3 可显示 `bindingToken=0` 的只读资料表回退高亮，供观察验证；该回退绝不能成为 P4/P5 派发资格。
- 观察范围仅限当前目标、焦点、鼠标指向和**当前客户端可见**姓名板。可打断候选必须是敌对、存活且 API 明确判定为可打断的读条；不可打断钢条绝不能高亮为打断。
- 单体控制候选必须是敌对、存活、API 明确判定为不可打断的读条，且目标为敌对玩家或非精英 NPC；`elite`、`rareelite`、`worldboss`、`UnitLevel=-1` 或 `UnitIsBossMob` 均 fail-closed。
- 群控候选只统计当前可见姓名板中 4 个及以上有效不可打断读条，且必须已有已识别的 `@cursor` 群控宏路由；无法证实路由时只显示观察状态，不产生群控卡。
- 反应高亮固定只选择一个优先项：`打断 > 群控 > 单体控制`。高亮读取 `autoReaction` 的来源勾选和排序，但不受自动开关影响，以便关闭自动化时仍能手动观察。
- P3 只能设置 `bindingToken=0`、`readOnly=true`、`dispatchAllowed=false` 的 HUD 数据；不得调用 `SignalFrame`、`SignalEncoder`、TEK、SendInput，亦不得影响 AutoBurst、官方推荐、HUD 冷却、标签或现有输入门禁。

## 4. 宏与动作条

- 只支持 Blizzard 默认可见动作条。载具、控制单位、覆盖动作条、宠物战斗 fail-closed；ExtraActionBar 仅观察。
- Phase 1.5 允许用户已经放在**可见 Blizzard 默认动作条**上的宏按钮。宏关联可读取 `/cast`、`/use`、条件/分号分支、目标修饰（包括 `@cursor`）、多行辅助命令与 `/castsequence` 中的明确 SpellID/本地化技能名；饰品宏可关联明确的 `/use 13` 或 `/use 14`；TE 只按玩家现有绑定，不写入、改造或执行宏分支。
- 解析器优先采用 Blizzard `GetActionInfo` / `GetMacroSpell` 的当前宏技能；文本宽松关联用于 API 未提供关联时。它不判断哪一个条件分支会成立，派发后仍必须通过**当前步骤的精确施法事件、技能自身非 GCD CD 或充能变化**确认，否则按现有受控超时/窗口锁规则失败关闭。
- 宏正文回收只能使用动作条返回的 numeric macro index；当该索引首读仅有名称或正文缺失时，可对同一 index 有界重读，不得使用 `GetActionText` 或宏名查找账号/角色宏列表。宏内 `/cast` 技能名称可只读解析为 SpellID 作为名称 API 临时不可用时的关联后备；不得依据宏名称、图标、动作条文本或部分文本猜测技能身份。
- 包含 `/cleartarget`、`/targetenemy`、`/targetlasttarget`、`/target`、`/focus`、`/assist` 等目标管理命令的宏，仍只可宽松关联到玩家现有可见按钮；TE 不会拆分、重排或执行其目标管理命令。若宏只包含一个被请求技能身份、无 `/castsequence`、且所有可执行施法动作均为该技能，则可标为 `macroManagedTargetAuto`：后续打断/控制自动化只按该已有宏键位一次，宏自身负责焦点优先、选敌回退、目标恢复等行为。多技能宏、`/castsequence`、无真实绑定或无法确认同一技能身份的宏仍 fail-closed。
- 多技能条件宏和 `/castsequence` 可以作为已关联宏按钮进入 Phase 1.5；诊断必须保留宏关联方式与宏形态摘要，但不得保存宏正文。一个宏同时包含 `/use 13` 与 `/use 14` 必须拒绝关联，双饰品必须建模为两个显式步骤；无法关联到规则 ActionRef、没有真实绑定、装备已变更或无法取得确认信号的宏仍 fail-closed。

## 5. 协议、审计与状态展示

- TEAP v3 保持 20 字节长度；flags bit 5（`0x20`）固定表示 `dispatchOrigin=burst`。
- 保留 `officialSpellID`、`dispatchSpellID`、`dispatchActionKind`、`dispatchInventorySlot`、`dispatchItemID`、`dispatchOrigin`、`planId`、步骤角色与派发尝试号用于 SavedVariables、Trace 和状态遥测。
- AddOn 保存的 Burst 元数据必须是简化审计记录，不得保存完整 resolver 对象、宏诊断对象或潜在 secret 值。
- AutoBurst 必须持续记录 `official_not_window`、`window_edge_missing`、规则不完整与 evaluator 故障；`/temapping` 的安全映射快照仅导出规则、计划和最近原因的纯标量摘要。
- TEK Trace 与状态快照必须暴露 `dispatch_origin` / `last_dispatch_origin`。

## 6. 绝对禁止

- HUD、Tooltip、视觉层、防御、打断、控制、位移或普通 Burst 展示层建立 Token、改写官方推荐、写 TEAP 或请求 TEK 输入。
- AutoBurst 绕过 BindingToken、TEAP、TEK、前台、Hook、手动让权、新鲜度、CRC、会话、限频或动作条解析。
- 用固定睡眠毫秒代替 GCDGate 与确认状态机；持续候选派发只能经 TEK 的既有全局限频、前台、Hook、手动让权与新鲜度门禁。
- 将原始 GCD 剩余数值泄漏给 AutoBurst 状态机；原始数值只能存在于 GCDGate 时序适配层。

## 7. 性能与刷新约束

- HUD 与视觉层仅用于呈现；不得改变推荐、候选、BindingToken、TEAP 或派发条件。
- 不新增高频 OnUpdate 链。AutoBurst 必须复用 SignalFrame 刷新、官方推荐和 GCD 上下文。
- Bootstrap 之外不得直接 `:RegisterEvent()`；AddOn 仅可经 `TE:RegisterEventSafe` / `TE:RegisterEventsSafe` 注册一次性事件。
- HUD 冷却展示继续使用现有缓存/事件驱动路径。AutoBurst 的单一规则步骤与 GCDGate 可在既有 SignalFrame 刷新内读取一次实时公共冷却快照；该窄例外不得扩展为 HUD 全量扫描或独立高频 OnUpdate。
- 所有物品来源 HUD 卡（`itemID`，或临时仍只保留的稳定装备槽位/物品类别；包括 13/14 槽饰品、药水及其他物品卡）必须使用 `CooldownResolver` 已归一化的非 GCD 自身冷却作为展示权威；不得绘制 `gcdCooldown` 或 `61304` 通用覆盖层。主、Burst、打断、控制、防御、药水模块均复用 `TacticalIconButton.lua`，不得另建 Cooldown 绘制路径。此展示判断不得反馈到 AutoBurst、BindingToken、TEAP 或 TEK。
- 主键和 Burst-window 卡必须隐藏纯共享 GCD 的转盘与数字；真实自身 CD 仍显示。该判断由 `TacticalIconButton` 的实时展示分支执行，不得改变 `GCDGate`、AutoBurst 预检、计划组装、TEAP 或 TEK。
- 直接映射动作条的技能不得以 Tooltip / `GetSpellBaseCooldown` 静态值启动本地 HUD 倒计时；天赋、英雄天赋或覆盖技能造成的实际 CD 差异，必须优先读取同一可信动作条的安全数值快照作为 HUD 自定义文本权威。实时 `DurationObject` 默认仅保留转盘/动画；只有用户明确选择 `duration` 文本模式，或已确认非 GCD 自身 CD 但安全数值暂不可读时，才可显示同一最终原生对象的倒计时。无法取得可信数值不得展示静态错误秒数。
- 设置窗口的周期刷新只允许同步当前可见页面；运行时 readout 可刷新，隐藏页面的列表、排序控件和文本输入不得在 0.25 秒轮询中被重建或抢占焦点。

## 8. Windows 实机验收

以下始终属于人工实机验收：Windows 前台识别、Hook、真实 SendInput、采样相位、SpellQueueWindow、不同急速/GCD、宏、DPI、多显示器、窗口模式，以及四种双技能组合的实际释放顺序。

## 9. 必需验证

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如系统存在 `luac` 或 `texluac`，还必须检查全部 AddOn Lua 语法。交付前验证完整 ZIP 只有一个顶层根目录且内容干净。
