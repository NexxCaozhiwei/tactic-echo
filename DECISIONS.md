# Tactic Echo 技术决策

当前版本：`1.0.07`

## D1. 主派发路径

常规路径唯一且不可替代：

```text
官方推荐（不可变）
→ 可见 Blizzard 默认动作条绑定
→ BindingToken
→ TEAP v3
→ TEK 安全门禁
→ SendInput
```

HUD、提示、防御、打断、控制、位移和爆发展示层均为只读。只有 AutoBurst Phase 1 可以在限定条件下产生独立的 `DispatchCandidate`，但它不改写官方推荐，也不建立旁路输入。

## D2. 动作条范围

只接受 Blizzard 默认可见动作按钮。载具、控制单位、覆盖动作条和宠物对战 fail-closed；ExtraActionBar 仅诊断观察。自定义动作条插件不在当前派发来源范围。

## D3. 宏范围

Tactic Echo 不解释或执行宏分支。当前自动爆发第一阶段仅接受一个明确预期技能的单一用途宏，文本关联回退仅支持无条件单行 `/cast <spell>`。条件、mouseover、目标修饰、分号分支、`/use`、`/castsequence` 和多动作宏不进入自动爆发。

## D4. TEAP v3 自动定位与派发来源

TEK 自动定位只在当前 WoW 客户区左上有界区域搜索 `T / E / 3` 头部；完整帧 CRC、Commit、会话和新鲜度通过后才可派发。自动定位不回退固定桌面坐标。

TEAP v3 保持 20 字节。flags bit 5 固定为 `dispatchOrigin=burst`；常规帧为 `official`。该标记只用于审计和 TEK burst 候选去重，不改变 BindingToken、CRC 或输入门禁。

## D5. Secret 值

受保护/secret 值不得进入模型、策略、Tooltip、TEAP 或 TEK。不能被安全转换为普通 Lua 标量的观测一律降级为未知。

## D6. 冷却、充能与 GCD

冷却主要用于 HUD 展示。AutoBurst Phase 1 的唯一例外是 `CollectCooldownOnly()`：它只读取技能自身 CD、充能和共享 GCD 快照。`GCDGate` 将原始时序归一化为状态标签，原始剩余毫秒不进入 AutoBurst、TEAP 或 TEK。

Buff、资源、目标、距离、范围、Proc、敌人数量、团队状态和首领机制不参与 Phase 1 自动爆发。

## D7. AutoBurst Phase 1

一次只运行一条人工声明的窗口技能 + 注入技能规则，支持 `pre/post` 和 `simple/focused`，默认关闭。窗口由官方推荐边沿触发；每次仍只经原 BindingToken → TEAP → TEK 链发送一步。

确认仅接受该技能自身 CD/充能变化。窗口技能最多受控重试一次；注入技能不重试。AddOn 没有 Windows SendInput 回执，只能以状态变化或超时间接判断步骤结果。

## D8. 验证声明

离线单元测试、Python 编译、PyInstaller 构建成功均不证明 Windows 真实行为。Hook、前台、DPI、多显示器、WoW 采样、SpellQueueWindow、真实 SendInput 和自动爆发顺序必须以人工实机测试证据为准。

## 1.0.03：AutoBurst 触发锚点与诊断可观测性

- 实机诊断包仅出现 `dispatch_origin=official`；用户上传的 SavedVariables 中没有 `TacticEcho.lua`，只有历史 `!WR.lua`。因此不能把“未出现 burst 帧”误判为 TEK 端拒绝。
- AutoBurst Phase 1 增加显式 `autoBurstWindowSpellID` 与 `autoBurstInjectionSpellID`。窗口 SpellID 的语义是“官方推荐锚点”，不是“HUD 爆发卡首项”。
- 保留 Profile 首项作为兼容回退，但在状态、`/teab status`、MappingExport 与 TEK 诊断摘要中公开规则来源和最近拒绝原因。
- SignalFrame 捕获 AutoBurst evaluator 错误后必须写入 AddOn 审计，不得静默退回官方派发。

## 1.0.07：前置未知、候选持续与施法成功回执

- 受保护的冷却数值、`active=true` 但 `isOnGCD` 来源缺失、GCD 读取未知均不是自身冷却。它们必须进入有界重采样，不能触发前置简易的“跳过注入”。
- 前置简易仅允许在窗口边沿已明确确认注入自身 CD 时跳过注入。窗口已经被计划接管后，任何 `UNKNOWN`、确认失败或超时都不允许窗口回落到官方派发。
- Burst 候选保持相同 TEAP sequence，直到确认、明确失效或有界超时；TEK 对该 sequence 仅尝试一次真实输入。
- `UNIT_SPELLCAST_SUCCEEDED` 只作为当前已派发且同 SpellID 的步骤成功确认回执；不读取 Buff，不决定是否创建计划，也不作为策略输入。
- 所有已创建计划的中止/超时均保持窗口离开锁，只有官方推荐离开窗口并再次进入才可建立下一计划。

## 1.0.06：AutoBurst 实机前置修订

- 内部等待（GCD 锁、确认等待、短暂重校验和窗口离开锁）使用 `armed + observationOnly + dispatchOrigin=burst`，不是用户暂停；TEK 只观察，不输入。
- 当技能 API 短冷却与全局 GCD 的开始、持续和剩余时间严格对齐时，`IconState` 将其归类为共享 GCD。AutoBurst 等待 `QUEUE_WINDOW`，不得把准备就绪的注入技能误跳过为自身 CD。
- 观察帧的真实 BindingToken 保持为 0，但 SignalFrame 必须带只读官方展示绑定；HUD 不能因此显示“未绑定”。
- 已候选派发/确认的窗口技能在官方推荐仍短暂显示时必须保持观察，直到推荐离开，以避免重复窗口键；从未派发窗口的计划中止后才可立刻归还普通官方派发。
- `PLAYER_REGEN_DISABLED` 开始新的 combat epoch，清理上一战斗的窗口边沿与离开锁。
