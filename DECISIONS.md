# 1.1.2 决策：TEK 修饰键手动接管

## 决策

宏身份判断统一下沉到 `ActionBarBindingResolver`。AutoBurst 使用 `IsAutoBurstMacroEligible()`；P4 Reaction 的已解析宏、控制、防御、生存 HUD 使用 `IsVerifiedCurrentMacroSource()`。因此这些模块只能继承已经证明为“当前可见按钮/槽位 + 当前宏身份 + 正文语义”的既有宏，而不能从宏名、图标、历史缓存、另一个同技能按钮或 action-info 代表 SpellID 单独放宽来源。

1.1.2 不重新开启自动打断。Defaults、Normalize 与 `AutoReaction:Evaluate()` 的 `auto_interrupt_suspended` 是当前生产边界；读条、钢条、事件和冷却证据只服务于只读提示、高亮、诊断与 HUD 人工点击。

默认 `pause_out_of_combat` 策略对外命名为“自动启停”。它在未进战斗或脱战时仍输出底层 `paused` 安全帧，保证 TEK 不派发；显示层必须把该原因码渲染为“待命”，避免与手动暂停或脱战停止混淆。
TEK 本地连发介入白名单只豁免配置中的主键；默认 `W/A/S/D/SPACE` 不进入手动让步。`Ctrl`、`Alt`、`Shift`、`Win` 等不能单独加入白名单的修饰键属于非白名单真实键盘输入，必须从按下到抬起持续占用 `manual_input_held`，避免玩家物理按住修饰键时 TEK 派发主键并形成意外组合键。

确认身份后，玩家既有 `/cast`、`/use`、条件、`@focus`、`@mouseover`、`@cursor`、目标管理和 `/castsequence` 语义保持不变。控制、防御、生存只通过 HUD 真实左键复用原按钮，固定 `BindingToken=0`；P4 opaque action-info 仍只用于已有真实 BindingToken 的 target-only transport；AutoBurst 不接受该例外。

宏诊断改为请求作用域化。无关 `BUTTON3` / “坐骑”宏不再被渲染为胁迫或冰冻陷阱的未匹配候选；同一有效 macro index 的当前按钮在动作条文本明确命名请求技能时，可显示正文暂不可读的同槽失败记录，但没有任何恢复、替代或派发权限。

## 理由

现场控制面板把槽位 72 的“坐骑”宏同时报告为胁迫与冰冻陷阱的未匹配候选，说明各模块虽开始收紧身份确认，但诊断和资格判定仍存在分散逻辑。统一入口可保留已验证玩家宏的宽松语义兼容，同时避免单个模块以误匹配诊断或 action-info 代表 SpellID扩大来源。

## 不变边界

不创建按键、不改写/替换宏、不评估分支、不改目标、不调用程序化点击。自动打断继续硬暂停；脱战 AutoBurst 硬门控、主键启停、manual_hold 人工优先、CD/转盘、标签和排序均不变。

# 1.0.54 P5.9 决策：控制、防御与生存宏兼容统一

## 决策

控制、防御与生存 HUD 统一采用 Burst/Interrupt 已有的“当前可见默认动作条 + 已读取宏正文 + 宽松语义关联”规则。宏的 `/cast`、`/use`、条件分支、`@focus`、`@mouseover`、`@cursor`、目标管理辅助命令和 `/castsequence` 均保持可发现；HUD 只通过现有 secure proxy 真实左键复用对应原按钮。

无标准快捷键、或其键位不能产生合法 BindingToken 的已识别宏，仍是可靠的人工 HUD 点击来源，但其 `BindingToken` 固定为 `0`。它们不得新增控制、防御、生存自动化，也不得进入 TEAP 或 TEK。生存物品宏只接受当前宏正文中与请求物品精确一致的 ItemID、`item:ID` 或本地化名称语义；不从宏名、图标或宏列表猜测来源。

## 理由

此前底层 Resolver 已能宽松识别多数控制和防御技能宏，但上层展示逻辑把宏来源降级为“没有可信动作条来源”；生存 `ResolveItem()` 又只识别直接物品按钮，遗漏了玩家常用的 `/use` 宏。这与此前已确认的爆发/打断宏兼容策略不一致，并使 HUD 手动入口不必要地失效。

## 不变边界

不创建按键、不改写或替换宏、不改目标、不评估宏分支、不调用程序化点击。自动打断继续硬暂停；脱战 AutoBurst 硬门控、主键启停、manual_hold 人工优先、CD/转盘、标签和排序均不变。

# 1.0.53 P5.8 决策：HUD 真实点击兼容与脱战爆发硬门控

## 决策

自动打断继续处于硬暂停。即使旧 SavedVariables 仍保存启用状态，Normalize 与 `AutoReaction:Evaluate()` 也必须强制返回 `auto_interrupt_suspended`，不生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 请求。

AutoBurst 不保留脱战例外。只要 `inCombat=false`，`AutoBurst:Evaluate()` 必须在任何规则读取、capture 恢复、计划延续、计划创建和候选材料化之前清除残留 plan/capture，并返回空结果。`SignalFrame:SetState("armed")`、`Run`、切图或随后进战均不能授权或续接 pre-combat bridge。

主 HUD 左键复用既有 `ToggleRun()`。爆发、打断、控制、防御/生存 HUD 卡只作为真实人工鼠标左键入口：经 static secure proxy 转交给可靠、当前可见的 Blizzard 默认动作条按钮或已识别的现有宏。proxy 同时注册 `LeftButtonDown` 与 `LeftButtonUp`，兼容“按键按下即施放（ActionButtonUseKeyDown）”；13/14 槽物品卡优先解析同一装备槽位的来源。HUD 不新建按键、不写宏、不替换宏、不构造 spell/item 动作，也不改变目标。

HUD 与原生默认动作条的真实左键优先于后续派发：短暂 `manual_hold` 以动作码 0、BindingToken 0 覆盖当前 TEAP 输出。战斗中映射变化不能重新绑定 secure proxy，必须 fail-closed。

## 理由

运行日志已证明旧的 pre-combat bridge 会在脱战建立爆发计划并向 TEAP/TEK 交付饰品或窗口技能，这与“只在战斗中自动爆发”的边界冲突。因此删除该授权路径，而不是在 TEK 末端补救。HUD 非主键卡无法在部分客户端输入设置下收到鼠标事件，则通过双点击沿注册解决，同时仍完全复用玩家原有动作条语义。

## 兼容性边界

本决定不修改玩家宏文本、动作栏绑定、宏发现、主推荐、CD 数字、DurationObject 转盘、标签、爆发排序或既有宏兼容策略。含目标处理的既有宏在 HUD 手动复用时仍完全按宏自身语义执行，HUD 本身不插入目标命令。
