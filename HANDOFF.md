# 1.1.2 交接：TEK 修饰键手动接管

- 当前版本：`1.1.2`。
- TEK 连发介入白名单主键继续不让步；非白名单真实键盘输入，包括 `Ctrl`、`Alt`、`Shift`、`Win` 修饰键，按下到抬起期间持续 `manual_input_held`，用于避免物理修饰键叠加自动派发主键。
- 默认策略“自动启停”在未进战斗或脱战时显示为“待命”；底层 TEAP 仍是非派发 `paused`，进战自动恢复运行。
- `ActionBarBindingResolver` 是 AutoBurst、P4 Reaction 常规路由、控制、防御、生存 HUD 的唯一常规宏资格入口；已确认的现有宏语义保持兼容，HUD 人工来源固定 `BindingToken=0`。
- `action_info_*` 正文不可读形态只保留有真实 BindingToken 的 P4 target-only transport；不进入 HUD 或 AutoBurst。
- 控制诊断仅显示与请求技能有关的当前宏失败。无关 `BUTTON3` / “坐骑”等宏不会污染胁迫、冰冻陷阱候选；同一有效 index 的当前文本命名技能时可保留同槽失败诊断。
- 实机验收使用 `docs/P5.11_SHARED_MACRO_POLICY_TEST.md`，并继续回归自动打断硬暂停、脱战 AutoBurst 硬门控、HUD `manual_hold`、CD/转盘/标签/排序。


# Tactic Echo Handoff — 1.0.53 P5.8

## 当前硬边界

- 自动打断设计暂停。不得只修改 UI 默认值；`Config/Normalize.lua` 和 `Tactics/AutoReaction.lua` 的硬暂停必须同时保留。旧 SavedVariables、完整读条证据与已识别绑定均不得恢复自动打断。
- 不得提供测试、调试或 SavedVariables 的隐藏重新启用通道。自动打断只能返回 `auto_interrupt_suspended`，不会形成 reaction candidate、BindingToken、TEAP reaction 标记或 TEK 请求。
- 自动爆发严格受战斗状态限制：任意 `inCombat=false` 帧必须在规则读取、capture 恢复、计划比较、计划创建和候选材料化之前清除残留 Burst plan/capture，并返回空结果。不得保留或恢复 `pre-combat bridge`、Burst candidate、Burst TEAP 帧或 TEK 请求；`Run`、`armed`、切图和进战事件均不能构成脱战例外。
- HUD 点击只能经 `UI/HudClickRouter.lua` 的 `SecureActionButtonTemplate` 静态代理复用已有、当前可见的默认动作条按钮/已识别宏；不得改为 `Button:Click()`、新建绑定、宏改写、目标选择或直接 TEK 输入。
- HUD proxy 必须同时接收 `LeftButtonDown` / `LeftButtonUp`，兼容 `ActionButtonUseKeyDown`；代理与 blocker 位于 HUD card 上方输入层。13/14 槽物品卡必须优先锚定对应装备槽位来源。
- `Tactics/ManualActionPriority.lua` 仅记录真实 HUD/原生默认动作条左键的短暂人工占用；`SignalFrame` 必须以 `manual_hold`、动作码 0、BindingToken 0 覆盖可能已计算的派发候选。
- 战斗内动作条页、宏、可见性或特殊动作条变化时，不可重定向 secure proxy；必须阻断直到脱战重建。

## 实机验收

以 `docs/P5.8_HUD_MANUAL_CLICK_AND_OOC_GATE_TEST.md` 为准：先验证任何脱战官方窗口都不会建立/派发 Burst；再分别在“按键按下即施放”开启、关闭时检查四类 HUD 手动卡、13/14 槽精确来源、无来源/战斗内失配阻断，以及 HUD/原生动作条人工点击的 `manual_hold` 优先级。CD/转盘/标签/排序不得回归。
