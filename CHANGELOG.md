# 1.1.4 — HUD Button 战斗保护收口

- **保护调用再收口**：战斗中 HUD 卡片可见性变更不再调用卡片 Button 的 `SetAlpha`、`EnableMouse`、`Show` 或 `Hide`，只记录待处理状态，避免 `ADDON_ACTION_BLOCKED UNKNOWN()`。
- **点击层边界不变**：HUD secure proxy 仍由 blocker fail-closed 覆盖；脱战后再真实隐藏或重建。

# 1.1.3 — HUD 战斗中安全隐藏

- **保护调用修复**：HUD 卡片隐藏路径不再在战斗中直接调用 `Button:Hide()`，改为透明化并禁用卡片鼠标输入，避免 `ADDON_ACTION_BLOCKED`。
- **secure proxy fail-closed**：HUD 手动点击路由在战斗中不隐藏 `SecureActionButtonTemplate`，而是用非 secure blocker 覆盖旧 proxy，防止旧映射被误点。
- **输入边界不变**：TEK 白名单与修饰键手动接管规则保持 1.1.2 行为；自动打断继续硬暂停，AutoBurst 脱战硬门控不变。

# 1.1.2 — TEK 修饰键手动接管

- **白名单边界保持**：TEK 本地连发介入白名单继续只豁免配置中的主键，默认 `W/A/S/D/SPACE` 不进入手动让步。
- **修饰键持续让步**：`Ctrl`、`Alt`、`Shift` 等不能单独加入白名单的真实修饰键，现在按下即进入 `manual_input_held`，直到抬起后再进入既有 release delay、freshness 与 replay guard。
- **组合键误触收口**：避免玩家按住 `Alt/Ctrl/Shift` 时，TEK 在修饰键仍按下期间派发主键并被客户端解释成组合键。

# 1.1.1 — 自动启停待命状态

- **策略命名收口**：默认 `pause_out_of_combat` 策略对外从“脱战暂停”改为“自动启停”，设置页、策略说明与命令入口同步更新。
- **待命状态展示**：自动启停下因未进战斗或脱战产生的底层 `paused` 安全帧使用 `out_of_combat_auto_standby` 原因码，并在 HUD/紧凑条/设置中心显示为“待命”，区别于手动暂停和脱战停止。
- **协议边界不变**：TEAP/TEK 仍使用既有 `paused` 非派发状态，不新增输入通道；AutoBurst 脱战硬门控与自动打断硬暂停不变。

# 1.1.0 — 审计基线、自动打断硬暂停与共享宏资格冻结

- **基线升级**：将当前开发基线提升为 `1.1.0`，同步 `VERSION`、TOC、`Core/Bootstrap.lua`、`AGENTS.md`、`README.md` 与 `docs/baselines/BASELINE_1.1.0.md`。
- **代码审计结论固化**：`AutoReaction`、Defaults 与 Normalize 均保持 `auto_interrupt_suspended`，生产运行时不会生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- **共享宏资格继续冻结**：AutoBurst、Reaction、控制、防御与生存继续统一经 `ActionBarBindingResolver:IsVerifiedCurrentMacroSource()`；AutoBurst 额外经 `IsAutoBurstMacroEligible()`。宏名、图标、宏列表存在和未知正文仍不得授权当前动作栏身份。
- **交付文档归档收口**：所有 `PATCH_MANIFEST*` 统一归档到 `docs/patch-manifests/`，根目录和 `docs/` 根层不再保留重复清单；验证脚本同步阻止新的错位 patch manifest。
- **运行边界不变**：AutoBurst 脱战硬门控、HUD/原生动作条 `manual_hold` 人工优先、DurationObject 仅视觉转盘、HUD 徽标纯秒数、P4 target-only action-info 例外隔离均保持不变。

# 1.0.56 P5.11 — 宏资格统一、控制诊断收口与 HUD 手动来源一致性

- **统一宏资格入口**：`ActionBarBindingResolver` 新增并作为唯一判定口使用 `IsVerifiedCurrentMacroSource()` 与 `IsAutoBurstMacroEligible()`。AutoBurst、P4 Reaction 常规解析、控制、防御与生存 HUD 展示均不再各自复制或放宽 macro identity 逻辑。
- **保持宽松语义、先证明当前身份**：当前可见默认动作条上已经验证身份的 `/cast`、`/use`、条件分支、`@focus`、`@mouseover`、`@cursor`、目标管理辅助命令和 `/castsequence` 继续允许作为既有宏语义；控制、防御、生存仅作 `bindingToken=0` 的 HUD 手动复用，不进入 TEAP/TEK、自动控制、防御或生存。`/use item:ID`、ItemID 和本地化物品名仍由正文语义精确关联。
- **P4 例外仍隔离**：`action_info_represented_spell` / `action_info_macro_spell` 正文不可读兼容只保留 target-only reaction transport，仍要求当前真实 BindingToken；不能成为 HUD 手动来源，也不能获得 AutoBurst 资格。
- **修复控制诊断污染**：`ResolveSpell()` 只显示与请求 SpellID 有明确 action-info / macro-spell 证据的宏诊断；同一有效 numeric macro index 的当前按钮在其动作条文本可见命名请求技能时，可保留同槽位“正文暂不可读”诊断，但绝不恢复、扫描或替代其它 index。`BUTTON3` 的“坐骑”等无关宏不会再出现在胁迫、冰冻陷阱等控制卡的未匹配候选中。
- **回归覆盖**：新增共享宏资格、`[@cursor] 冰冻陷阱`、`/use item:5512`、P4 opaque 排除与无关坐骑宏过滤测试。
- **不变边界**：不改宏、不改目标、不新建按键、不程序化点击；自动打断继续硬暂停，AutoBurst 继续战斗内硬门控，HUD CD/转盘/标签/排序与 `manual_hold` 人工优先不变。

# 1.0.55 P5.10 — 当前动作栏宏身份收口与冰冻陷阱 HUD 精确锚定

- **修复 `CTRL+1` 冰冻陷阱宏未识别**：当当前可见动作条宏的 `GetActionInfo(...).id` 是代表 SpellID、`GetActionText()` 仅显示“冰冻陷阱”、而 action-info handle 可只读提供实际宏名时，Resolver 现在将两种允许的标签作为同一次受限 join 的候选。只有当前宏列表中唯一一枚、正文语义明确引用 `冰冻陷阱` 的宏才可恢复；HUD 固定复用该当前 `CTRL+1` 原按钮。
- **严格宏身份规则落地**：有效 numeric macro index 仅允许对同一 index 有界读取；该读取失败时不再扫描其他宏。非 index 的 Retail 形态只允许使用 `GetActionText` 或 action-info handle 的只读名称、代表 SpellID 和唯一正文语义共同确认。`GetMacroSpell`/代表 SpellID 只能辅助诊断，不能单独让正文恢复通过。
- **歧义与失配 fail-closed**：多个不同标签或同名同技能候选同时存活时返回 `macro_semantic_identity_ambiguous`；宏正文不引用请求技能时返回 `macro_semantic_identity_no_spell_match`。不调用 `GetMacroInfo(name)`，不按名称取第一枚，不将宏正文持久化。
- **HUD 点击精确来源进一步收紧**：HUD 卡除 `buttonName + actionSlot` 外，还复核当前来源类型、macroID 与只读语义身份；原栏位被同技能直放、另一枚同技能宏或不同语义宏替换时一律 `manual_actionbar_source_changed`，不会跳转到 `CTRL+2` 或其他同技能槽位。
- **P4 例外保持孤立**：`action_info_represented_spell` / `action_info_macro_spell` 的正文不可读兼容只保留给 P4 reaction 的 target-only transport，且必须已有真实 BindingToken。它不能成为控制、防御、生存 HUD 的宏来源，不能推断 focus/mouseover/cursor 分支，也不能授权 AutoBurst。
- **不变边界**：自动打断继续硬暂停；脱战 AutoBurst 硬门控、主键启停、CD/DurationObject、标签、排序、TEAP/TEK 和用户已有宏文本/目标语义均不改变。

# 1.0.54 P5.9 — 控制、防御与生存宏兼容统一

- **控制/防御宏不再被上层降级**：控制与防御卡现在保留 Resolver 已确认的 `actionBarStateTrusted`、当前动作条槽位与宏语义身份；`@focus`、`@mouseover`、`@cursor`、条件分支、辅助命令、目标管理和 `/castsequence` 等既有宽松关联形态，均继续由现有宏解析器识别为当前可见玩家宏的来源。无键位或不受 TEK 支持的既有宏仍可显示并由 HUD 真实鼠标点击复用，但 BindingToken 固定为 0，绝不进入 TEAP/TEK 派发。
- **生存消耗品支持已有 `/use` 宏**：`ResolveItem` 新增与 `ResolveSpell` 同级的语义关联，可识别 `/use <ItemID>`、`/use item:<ItemID>`、本地化物品名、条件分支、多物品分支及 `/castsequence` 中的既有物品引用；仍仅接受当前可见 Blizzard 默认动作条上的唯一已解析宏按钮，不按宏名/图标/宏列表猜测来源。
- **HUD 兼容**：无标准快捷键但动作条来源可靠的控制、防御、生存卡可继续显示，并允许 secure proxy 复用同一真实按钮；宏的目标、条件、分支和原本行为完全由玩家既有宏执行。找不到可靠来源时保持卡片显示并 fail-closed。
- **不变边界**：不创建按键、不改写或替换宏、不切换目标、不新增输入通道；控制、防御、生存仍是只读/手动 HUD 入口，自动打断继续硬暂停，TEAP/TEK、爆发排序、CD 数字和 DurationObject 转盘不变。

# 1.0.53 P5.8 — HUD 点击修复、脱战爆发硬门控与基线归档规范

- **修复脱战爆发派发**：删除 `pre-combat bridge` 的运行时授权。`AutoBurst` 在任何脱战帧先清除旧 plan/capture 并返回空结果；不会创建 Burst candidate、写入 Burst TEAP 帧或交给 TEK。`Run` 重新启动和切图后均不能恢复脱战起手派发。
- **修复 HUD 非主键点击**：secure proxy 同时接收 `LeftButtonDown` / `LeftButtonUp`，兼容 `ActionButtonUseKeyDown`；代理和 fail-closed blocker 提升到 `HIGH` 输入层，确保真实 HUD 左键能先取得 `manual_hold`，再由既有动作条按钮执行原始动作。
- **精确复用饰品来源**：13/14 槽 HUD 卡先解析对应装备槽位的现有动作条按钮或已识别 `/use 13|14` 宏，避免同物品/共享效果的错误来源。
- **保持边界**：不新建快捷键、不改写宏、不替换目标、不创建 spell/item 动作；主键启停、CD/转盘、标签、技能排序和既有宏兼容策略不变。
- **文档规范**：所有版本基线移入 `docs/baselines/`；新增交付规则，版本化源码改动必须同步更新 baseline 与 `CHANGELOG.md`。

# 1.0.52 P5.7 — HUD 手动点击与自动打断暂停

- 自动打断改为全局暂停：默认、SavedVariables 规范化与运行时均强制 `auto_interrupt_suspended`；保留只读打断观察/高亮。
- 主 HUD 左键复用原 `ToggleRun()`；爆发、打断、控制、防御/生存 HUD 卡片可安全代理现有可见默认动作条按钮或已识别宏。
- 无可靠来源、特殊动作条、按钮不可见及战斗中映射变化均 fail-closed；HUD 保持显示并给出原因。
- HUD/原生动作条鼠标左键触发既有 `manual_hold`，清空派发动作码与 BindingToken，人工点击优先于 TEAP/TEK 派发。
- 不改写 AutoBurst 顺序、CD/转盘/标签/排序、现有宏或 TEK。

# 1.0.51 P5.6 — API/事件确认打断资格，修复 `false` 证据丢失

- **修复直接 API false 丢失**：`ReactionObservation` 不再用 Lua `and/or` 处理 `notInterruptible`，避免合法 `false` 被折成 `nil`。当前 API `notInterruptible=false` 会正确产出 `directInterruptibilityKnown=true` 与 `interruptible=true`。
- **收紧自动派发资格**：P4.3 transport 只在 `unit_api_confirmed` 或 `unit_event_interruptible_confirmed` 后派发；`interruptibility_unknown` 仅观察，不再生成 `compat_interrupt_candidate`。
- **钢条硬阻断**：`notInterruptible=true`、`UNIT_SPELLCAST_NOT_INTERRUPTIBLE` 和真实可见盾继续零 Token 阻断。
- **CD 门控保持**：实际打断动作条按钮存在已知非 GCD 自身 CD 时，返回 `interrupt_action_cooldown`，不占主键。
- **宏兼容未改动**：P5.5 的当前动作栏 `action_info_represented_spell` / `action_info_macro_spell` target-only transport 保持。

# 1.0.50 P5.5 — 双 action-info 宏身份兼容，恢复 P4.3 target transport

- **修复 P5.4 的实际 API 形态遗漏**：P5.4 只接受 `action_info_represented_spell`，但现场当前可见反制射击宏被 Resolver 匹配为 `action_info_macro_spell`。P5.5 将两种精确 action-info 身份同等作为正文不可读时的 target-only compatibility transport。
- **以当前动作栏按钮为唯一事实**：路由仍要求当前可见宏按钮、当前请求的打断 SpellID、真实 BindingToken 和正文不可读状态；不读取其他宏、不会按宏名恢复正文、不会把宏列表存在的任何宏推断为当前绑定。
- **钢条/CD 门控不变**：3 次共享观察、0.40 秒钢条稳定、硬钢条否决和实际 action slot 的非 GCD 自身 CD 门控均保留。CD 中仍为 `interrupt_action_cooldown`，不得占 reaction 主键。
- **宏兼容性**：本版只恢复 P4.3 已验证的当前 target transport，未收紧、删除或改写任何现有宏；不会通过该 opaque 路由猜测 focus/mouseover。

# 1.0.49 P5.4 — P4.3 当前动作栏路由恢复、钢条稳定与冷却门控收口

- **恢复 P4.3 已验证动作链的实际动作栏路由**：当当前可见默认动作栏按钮是宏、`GetActionInfo` 返回所请求打断技能的代表 SpellID、且按钮已有真实绑定，但 Retail 不提供宏正文/有效宏索引时，P2 以“实际按钮 + 代表 SpellID + BindingToken”建立 `target` 专用 `action_info_represented_spell_compat` 路由。不会按宏名查找、不会从宏列表存在某种形态推断当前绑定，也不会推断 focus/mouseover 分支。
- **钢条稳定窗口**：兼容未确认读条继续要求同一 `castKey` 的 3 次不同观察；额外要求至少 0.40 秒稳定等待，并在候选前再次检查事件缓存。API 明确不可打断、真实可见盾、`NOT_INTERRUPTIBLE`、原生明确不可打断和 native scalar/method 钢条嫌疑继续零 Token 硬拦截。
- **冷却不占主键**：对 TEK 将实际按下的 action slot 保留精确只读 CD 门控。已知非 GCD 自身 CD 且无可用 charges 时记录 `interrupt_action_cooldown`，不写 reaction candidate、不覆盖官方正常序列。
- **宏兼容性边界**：未修改玩家宏文本、宏发现、宏绑定、TEK、TEAP 或输入门禁。正文可见的现有宏沿原有解析/分支守卫走；正文不可见的当前按钮仅恢复 target transport，不以它的名字或其他宏猜测路由。

# 1.0.48 P5.3.1 — legacy 目标管理打断宏兼容恢复

- **恢复已验证 legacy target 路由**：P5.3 不再一律阻断当前目标的目标管理宏。仅对解析为严格 `focus → target` 回退链的旧宏，在不存在活敌焦点抢占首分支时，允许继续使用 P4.3 reaction 交付链，诊断为 `macro_managed_target_target_compat`。
- **保留关键边界**：敌对焦点存在时，target 候选记录 `macro_managed_target_target_preempted_by_focus`；不具有精确 fallback metadata 的目标管理宏和 mouseover 目标管理路由仍 fail-closed。普通 direct target 动作条按钮保持优先。
- **修复代表 SpellID 宏名空窗**：当 `GetActionText` 为空、`GetActionInfo` 返回代表 SpellID（例如 147362）且 action-info probe 只能得到宏名时，该宏名可作为唯一语义回收的 join key。仍要求真实宏 index 正文与 SpellID 语义唯一一致；不按名称盲取正文。
- **不变项**：P5.3 的 3 次兼容稳定、钢条硬否决、native scalar 嫌疑、打断自身 CD 门控、TEK/TEAP/BindingToken 均不变；无需重建 `TEK.exe`。

# 1.0.47 P5.3 — 钢条稳定证据、打断冷却门控与目标管理宏收紧

- **兼容读条先稳定**：P4.3 兼容派发不再在首张 `unit_event_pending` 帧立即放行；同一 `castKey` 必须经过 3 次不同共享观察样本。这样为 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` 和动态原生盾组件提供有限稳定窗口。
- **扩展真实盾组件探测**：除直接字段和既有全局命名外，原生施法条现在只读扫描名称、atlas 或 texture 明确包含 shield/uninterruptible/notinterruptible 的当前子组件与 region。`showShield`/`barType` 仍仅是诊断。
- **native scalar 嫌疑阻断兼容派发**：scalar-only / method-only 不可打断 `true` 仍不会被 P3 当作可见钢条结论，但 P5.3 不会再将其视为“无钢条”；兼容路径记录 `compat_native_steel_suspected` 并 fail-closed。
- **打断冷却门控**：候选路由建立后，对 TEK 将实际按下的 action slot 进行只读 CD/charges/GCD 采样。已知非 GCD 自身 CD 且无可用 charges 时返回 `interrupt_action_cooldown`，不产生 reaction candidate，不覆盖正常主推荐。宏按钮仅能提供 CD 否决证据，不能用“ready”反向授权派发。
- **目标管理宏收紧**：现场日志显示某些解析形态未标出 exact fallback 元数据，仍让当前目标使用 `/targetenemy` 宏。P5.3 以 `macroManagedTarget` 为整体安全边界：带目标管理命令的宏仅可用于已验证的焦点分支；target/mouseover 均不自动使用。
- **不变项**：未修改 TEK、TEAP 字段、BindingToken、宏正文、宏执行顺序、AutoBurst 或 HUD CD 渲染；无需重建 `TEK.exe`。

# 1.0.46 P5.2 — P4.3 兼容打断派发与宏命中守卫

- **恢复已验证动作链**：当真实活跃读条因 Retail 证据不透明而停在 `interruptibility_unconfirmed` 时，默认启用 `compatibilityActiveCast`，生成稳定 `compat_interrupt_candidate`，继续使用既有 BindingToken → TEAP reaction → TEK 链。
- **硬钢条仍不可绕过**：直接 API 明确不可打断、真实可见盾、有效 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE`、原生明确不可打断仍一律零 Token；`showShield`/`barType`/未知值不单独作为判定。
- **可切换策略**：打断设置新增“兼容未确认读条派发”；关闭后恢复 P4.4 严格正向确认模式。
- **宏命中守卫**：P5.1 的宏身份语义回收保留。严格 mouseover→focus→target 宏继续检查上游宏分支。焦点优先 `/targetenemy` 回退宏仅允许焦点读条路径自动派发；当前目标 fallback 在按键前无法验证最终目标，记录 `macro_managed_target_fallback_target_unverifiable`。
- **路由优先级**：同一技能同时存在普通当前目标按钮和目标管理宏时，优先普通当前目标按钮。
- **不变项**：不改宏、不切换目标、不新增输入路径，不修改 TEK、AutoBurst 或 HUD 冷却；无需重建 TEK.exe。

# 1.0.45 P5.1 — 宏动作身份与唯一语义回收

- **修复 P5 实机错误假设**：部分 Retail 宏动作的 `GetActionInfo(actionSlot).id` 为代表技能 SpellID，而不是宏列表 index；反制射击宏现场返回 `147362`，P5 误把它用于 `GetMacroInfo(147362)`，导致宏正文必然不可用。
- **双路径身份模型**：动作信息值处于当前账号/角色宏索引范围时，继续以同一 numeric index 读取正文；动作信息值不属于有效宏索引时，进入受限的“动作条宏名 + 代表 SpellID + 宏正文语义”唯一匹配。
- **同名不再盲取第一枚**：仅名称相同不会授权；候选宏必须引用动作条代表技能，且仅有一枚候选时才恢复正文。多个同名且同技能候选记录 `macro_semantic_identity_ambiguous` 并 fail-closed。
- **诊断扩展**：记录 `actionInfoLooksLikeMacroIndex`、`representedSpellID`、`actionTextCandidateCount`、`semanticCandidateCount`、`semanticCandidateIndexes` 与身份来源；仍不保存宏正文。
- **不变项**：没有修改宏文本、目标处理、BindingToken、TEAP、TEK 或任何输入门禁；无需重建 TEK.exe。

# 1.0.44 P5 — 宏身份锚定与同名宏防错配

- **取消宏名正文回收**：宏正文只允许通过当前动作条 `GetActionInfo` 返回的数值 `macroIndex` 回收；不再按 `GetMacroInfo(name)` 或账号/角色宏列表中的同名条目取正文。
- **有界同索引重读**：`GetMacroInfo(macroIndex)` 首读名称存在而正文为空时，仅对相同 numeric index 最多重读两次，覆盖客户端短暂正文空窗而不引入同名错配。
- **同名宏 fail-closed**：当前 index 无正文时，即使另一枚账号/角色同名宏引用 `反制射击`，也不能提供派发资格；诊断为 `macro_body_unavailable_action_info_id`。
- **诊断增强**：映射导出、面板与 `/temapping` 增加 macro identity source、动作条 macro index、读取次数、身份确认结果；不保存宏正文。
- **不变项**：P4.4 严格钢条、P4.5 宏分支守卫、P4.6 SpellID 令牌关联、BindingToken → TEAP → TEK 链均未修改；无需重建 TEK.exe。

# 1.0.43 P4.6 — 多行打断宏发现与 SpellID 关联韧性

- **修复宏正文回收后备**：当 `GetMacroInfo(actionInfoID)` 首读只给出宏名称而正文缺失时，解析器会继续使用动作条文本与该索引返回名称，从已有账号/角色宏列表回收同一宏正文；不再仅依赖 `GetActionText`。
- **新增 `/cast` 令牌 SpellID 关联**：宏内技能名称可只读查询为普通 SpellID。请求技能名称在当次 API 调用中不可材料化时，仍可安全关联已知的 `反制射击`（147362）等同技能多行宏；不依赖宏名称或图标猜测。
- **避免负缓存锁死**：名称/SpellID 临时读取失败不会写入会话级负缓存；下一次既有动作条失效/重建后可重新确认。
- **诊断增强**：P2 映射与 `/temapping` 增加宏正文回收来源、查找次数、动作条宏名与已解析 `/cast` SpellID 令牌数量；仍不保存宏正文。
- **不变项**：P4.4 严格钢条资格、P4.5 宏分支守卫、现有 BindingToken → TEAP → TEK 输入链与全部 Windows 门禁均未修改；无需重建 TEK.exe。

# 1.0.42 P4.5 — 受守卫的整合打断宏

- **修正整合宏解析**：`/cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 技能` 不再被误判为单一 `@mouseover` 宏；解析器保留全部条件块，并仅接受严格 `mouseover → focus → target` 单技能链。
- **新增 `macro_priority_chain` 路由元数据**：P2 对同一已有宏键位登记 mouseover、focus、target 三个来源及固定优先级；不创建 BindingToken、不编辑宏、不增加输入路径。
- **新增 P4 分支兼容性守卫**：focus/target 读条候选前，检查是否存在会先被宏命中的上游活敌单位；若存在，则记录 `macro_priority_preempted_by_mouseover/focus` 并 fail-closed。
- **未知链保持手动**：部分链、修饰键、战斗状态、混合条件、目标管理或多技能宏统一标记为 `macro_conditional_chain_opaque` / 既有不透明原因，不再把首个条件分支误升格为自动路由。
- **保留 P4.4 与 P4.3 所有动作链保障**：严格钢条证据、稳定 candidate、stable sequence 与 TEK reaction dedupe 均未改变。

# 1.0.41 P4.4 — 严格钢条判定与原生视觉复核

- **取消 P4.3 探测例外**：删除 `probe_active_cast_ignore_steel`。读条存在但不具备可打断证据时，恢复为 `interruptibility_unconfirmed`，只高亮、不派发。
- **修正 `showShield` 误用**：该字段及 `barType` 仅保留为诊断，不再作为当前读条的钢条或可打断结论。
- **真实盾组件判定**：读取 `BorderShield` / 等价子组件的实际 `IsShown()` / `IsVisible()` 状态；可见盾为硬否决，明确无盾可作为视觉证据。
- **视觉防抖**：原生无盾或原生 explicit-false 路径必须在同一读条连续两次 P3 样本中一致，才可派发；直接 API 与单位施法事件不受此等待影响。
- **事件身份保留**：`ReactionInterruptEvents` 的 status 事件不再以 nil 覆盖 START 事件中已取得的 spellID/castGUID，避免削弱 stale-event mismatch 防线。
- **保留 P4.3 可靠性交付修复**：reaction candidate 仍稳定保留到读条结束；SignalFrame 保持同 sequence；TEK 继续按稳定 reaction sequence 成功后去重。
- **诊断增强**：面板显示真实盾组件来源、原生证据以及视觉采样 `1/2`、`2/2`。

# 1.0.40 P4.3 — 自动打断动作链探测与稳定投递（历史）

- P4.3 已确认现有 BindingToken → TEAP reaction → TEK → 游戏内打断动作链可达。
- P4.4 已替代其临时“忽略钢条”探测资格；P4.3 不再作为正式判定策略。
