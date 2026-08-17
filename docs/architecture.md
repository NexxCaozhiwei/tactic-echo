# Tactic Echo 当前架构

版本：`1.4.4`

## 1. 当前产品范围

当前运行范围只保留：首页/设置中心、HUD 主键、官方主推荐输入链路，以及最多三个自动注入组。打断、控制、防御、生存、TargetCastPrompt、姓名板群控扫描、只读反应高亮、监控/调试页、MappingExport 与 OfficialApiProbe 均已退役，不得加载、轮询、显示或通过旧 SavedVariables 恢复。

HUD 只展示主键与全部已启用自动注入组的步骤卡片。HUD、Tooltip、冷却转盘和诊断都是展示消费者，不得反向建立 BindingToken、改写候选或改变派发资格。

## 2. 唯一输入链路

官方主推荐是不可变输入。正常主键和 AutoBurst 受控候选最终都必须经过同一条派发路径：

```text
OfficialRecommendation（只读）
→ 主键或 AutoBurst OrderedPlan 候选
→ 已验证 Blizzard 默认动作条/宏来源
→ BindingToken
→ TEAP v3
→ TEK 前台、Hook、手动让权、新鲜度、会话、CRC 与限频门禁
→ 单次 SendInput
```

AutoBurst 不是第二条输入通道。它只能在官方推荐命中某个启用组的窗口时，通过 `AutoInjectionCoordinator` 取得唯一活动组所有权，再由既有 OrderedPlan 逐步产生候选。每帧最多一个 BindingToken，任何步骤都不能绕过 TEAP 或 TEK。

## 3. AddOn 分层

- `Recommendation/*`：只读取得官方主推荐。
- `Actions/*`：扫描 Blizzard 默认动作条，验证当前槽位、绑定和宏语义身份。
- `Tactics/AutoInjectionGroups.lua`：保存、迁移并校验每专精最多三个注入组。
- `Tactics/AutoInjectionCoordinator.lua`：选择唯一活动组，阻止组间抢占、排队和递归触发。
- `Tactics/AutoBurst.lua`、`BurstPlanner.lua`：OrderedPlan 预检、逐步派发、精确确认和失败释放。
- `Tactics/RuntimeSnapshot.lua`、`IconState.lua`、`CooldownResolver.lua`、`CooldownTracker.lua`、`GCDGate.lua`：提供受控运行快照、CD/GCD/充能安全语义。
- `Signal/*`：编码 TEAP v3 信号帧；Burst 使用 `dispatchOrigin="burst"` 与 flags `0x20`。
- `UI/TacticalHudModel.lua`：把主键和各启用组的普通标量快照投影到 HUD。
- `UI/TacticalIconButton.lua`：渲染图标、转盘、纯秒数徽标、真实多充能、状态与 Tooltip。
- `UI/HudClickRouter.lua`：仅为当前可见且已验证的 Blizzard 默认动作条按钮提供人工点击代理。
- `UI/TacticalBoard.lua`、`TacticalHudLayout.lua`：渲染与布局；战斗中只记录受保护可见性/布局变更，脱战后应用。
- `UI/ControlPanel.lua`：设置中心与自动注入组编辑。

## 4. 自动注入与计划所有权

每个专精最多保存三个平级组，每组包含一个固定窗口、最多六个注入技能和饰品槽 13/14。组内顺序由稳定步骤键保存，窗口不能再次作为本组注入，不同启用组的窗口也不能进入对方注入链；普通注入技能和饰品可跨组复用。

同一时刻只有一个 Coordinator、一个活动组、一个 plan 和一个 pre-window capture。活动计划期间观察到其他组窗口时不抢占、不排队、不补发；当前计划结束后必须重新观察到窗口离开并再次进入。

任何 `inCombat=false` 帧都必须在计划或候选材料化前清除 plan/capture 并返回无 Burst 候选。`PLAYER_REGEN_DISABLED` 从干净 encounter epoch 开始。

## 5. 步骤确认与失败关闭

计划创建和每步派发前都重新验证动作条来源、BindingToken、装备身份、实时自身 CD/充能和 GCD 阶段。`READY_NOW`、`QUEUE_WINDOW`、`GCD_LOCKED` 是时序状态，不是自身 CD。

步骤只接受当前 `WAIT_CONFIRM` 的精确成功事件、自身非 GCD CD 开始或真实多充能减少作为成功确认。UNKNOWN、图标灰度、泛 GCD、单个失败事件、Buff、目标或资源数值不能伪造成功或跳过。两个不同共享快照持续给出允许的不可用证据，或两个精确匹配失败/中断收据，才按 `simple/focused` 边界有界释放。

## 6. HUD 冷却与充能

`IconState`、`CooldownResolver` 和 `CooldownTracker` 负责安全标量；`TacticalHudModel` 不保存 `DurationObject` 或受保护值。`TacticalIconButton` 可只为视觉转盘选择一个客户端 `DurationObject`，但必须隐藏其 CountdownNumbers，且不得把它回写到推荐或派发链。

HUD 数字只显示已确认的安全剩余秒数并向上取整。没有安全数字时保留可用转盘并隐藏徽标；纯共享 GCD 不显示为自身 CD。只有 `maxCharges > 1` 的真实多充能技能显示充能，普通技能的 `1/1` 不显示。

## 7. 战斗保护与人工优先

HUD 卡片、secure proxy、blocker、主容器与布局在战斗中不得直接执行受保护的显示、隐藏、透明度、缩放、定位或尺寸变更，只记录 pending/dirty，脱战后应用。

HUD 或原生动作条真实左键先进入 `manual_hold`，该窗口内 SignalFrame 输出动作码 0、BindingToken 0。TEK 对非白名单真实键盘输入从按下到抬起持续让权，之后再经过既有 release delay、freshness 和 replay guard。
