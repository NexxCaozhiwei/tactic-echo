# 自动注入

版本：`1.4.6`

“自动注入”是 AutoBurst 的用户可见扩展名称。每个专精最多配置三个独立技能组，但运行时始终只有一个 Coordinator、一个活动组、一个 plan 和一个 pre-window capture。

## 配置

- 总开关位于 `/teui` 的“自动注入”页。
- 每组可设置名称、启用状态、`simple/focused` 模式和唯一窗口 SpellID。
- 新组默认关闭，可先配置窗口 SpellID、注入/饰品与顺序；缺项不会阻止继续编辑，只会阻止启用。
- 当前组启用/停用入口位于“当前组基本设置”上方；窗口栏只接受数字 SpellID，按 Enter 或点击“保存窗口技能”均可提交，周期刷新不会覆盖正在输入的内容。
- 窗口可以是普通技能；只有官方推荐精确等于该 SpellID 时才会考虑启动。
- 每组最多六个注入技能，并固定提供饰品 13、14；窗口不可停用，但九个步骤都可调整位置。
- 本组窗口不能再次作为本组注入；不同启用组不能使用相同窗口，也不能把某组窗口放入另一组注入链。普通注入和饰品可以跨组复用。

## 运行语义

```text
官方推荐精确匹配组窗口
→ AutoInjectionCoordinator 选择唯一匹配组（尚未 Claim）
→ 现有 AutoBurst OrderedPlan 预检
→ plan / pre-window capture / departure lock 建立后 Claim 唯一所有权
→ OrderedPlan 逐步确认
→ 已验证动作条 BindingToken
→ TEAP v3
→ TEK 全部门禁
→ 单次 SendInput
```

活动期间出现的其他组窗口不会抢占、排队或补发。当前计划结束后，错过的组必须等待官方推荐真正离开并重新进入其窗口。修改未活动组不影响当前计划；修改或关闭活动组会按既有安全边界终止。

departure lock 离开的同一观察帧仍属于旧组所有权：若官方推荐直接切为另一组窗口，Coordinator 必须先将新窗口记录为活动期间错过，再释放旧锁。活动 capture 因组关闭、模式变化、配置冲突或其他 Abort 原因终止时，必须先建立 departure lock，不能让仍可见窗口直接回落到普通路径。

`activeGroupId` 只表示执行器真实持有 plan、pre-window capture 或 departure lock；`matchedGroupId` 可只表示当前窗口匹配。每个 armed epoch 只允许在首次健康观察中恢复一次继承的前置窗口；若预检失败并返回普通官方路径，同一窗口持续可见期间不会再次生成代次，必须等待窗口离开后重新进入。组运行状态固定使用 `<profileKey>:<groupId>`，不会创建 `unknown:<groupId>` 或让不同专精的同名组共享收据、代次或离开锁。

技能和饰品仅凭自身非 GCD 冷却开始或充能减少进行回退确认时，都必须在至少两个不同样本中稳定持续 0.15 秒。runtime cycleId 可用时，重复读取同一共享业务快照不得增加确认样本数。单帧预测性冷却、普通 GCD、图标灰度和未知来源冷却都不是成功；精确 `UNIT_SPELLCAST_SUCCEEDED` 仍可立即确认。

## 旧配置迁移

首次读取某专精时，`autoBurstEnabled` 映射为总开关，`autoBurstMode` 和 `autoBurstSequence` 幂等迁移为 `group-1`。原窗口、顺序、最多六个注入、饰品启用状态与 `offGCDExplicit` 均保留；不会自动创建组 2/3。

## HUD 与协议

HUD 按 `autoInjectionGroups.order` 展示全部已启用组，并把每组序列分别排列；组内严格保持已保存步骤顺序，最多三组、每组九张、合计 27 张卡。全部卡片保持只读和 `bindingToken=0`；只有 SignalFrame 已产生真实 Burst TEAP 候选时，活动组的精确当前步骤显示“派发”。

HUD 使用与运行路径相同的缓存后组校验。合法组可显示 READY/ACTIVE；损坏或冲突但已启用的组仍可显示用于诊断，但状态固定为 INVALID，并显示具体冲突原因及“不会执行”，不会获得 `burstReady`、BindingToken 或活动覆盖。

HUD 冷却数字只读取 `IconState` / `CooldownTracker` 已确认的安全秒数，Blizzard `DurationObject` 只绘制转盘。没有安全数字时隐藏徽标；纯共享 GCD 不显示为技能自身 CD。只有当前 `maxCharges > 1` 的真实多充能技能才显示充能，普通技能的 `1/1` 不得显示。

TEAP v3 仍为 20 字节，`dispatchOrigin="burst"` 与 flags `0x20` 不变。groupId 只存在于 AddOn 配置、状态、HUD 和诊断中，不编码到协议。

AutoBurst 高频 Evaluate 在首次设置初始化后直接读取当前 `TacticEchoDB.tactics`，不再逐帧运行完整 `Normalize:All()`；设置保存和组 revision 更新仍会在下一次 Evaluate 被读取。饰品 persistent recovery 仍保持永久 fail-closed、等待可信成功/失败/自身冷却/充能证据的既有策略；本版本只增加纯标量诊断，没有把候选发送、等待时间或普通 GCD 当作成功。
