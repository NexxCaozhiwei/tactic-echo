# 自动注入

版本：`1.4.3`

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
→ AutoInjectionCoordinator 取得唯一组所有权
→ 现有 AutoBurst OrderedPlan 预检与逐步确认
→ 已验证动作条 BindingToken
→ TEAP v3
→ TEK 全部门禁
→ 单次 SendInput
```

活动期间出现的其他组窗口不会抢占、排队或补发。当前计划结束后，错过的组必须等待官方推荐真正离开并重新进入其窗口。修改未活动组不影响当前计划；修改或关闭活动组会按既有安全边界终止。

## 旧配置迁移

首次读取某专精时，`autoBurstEnabled` 映射为总开关，`autoBurstMode` 和 `autoBurstSequence` 幂等迁移为 `group-1`。原窗口、顺序、最多六个注入、饰品启用状态与 `offGCDExplicit` 均保留；不会自动创建组 2/3。

## HUD 与协议

HUD 按 `autoInjectionGroups.order` 展示全部已启用组，并把每组序列分别排列；组内严格保持已保存步骤顺序，最多三组、每组九张、合计 27 张卡。全部卡片保持只读和 `bindingToken=0`；只有 SignalFrame 已产生真实 Burst TEAP 候选时，活动组的精确当前步骤显示“派发”。

TEAP v3 仍为 20 字节，`dispatchOrigin="burst"` 与 flags `0x20` 不变。groupId 只存在于 AddOn 配置、状态、HUD 和诊断中，不编码到协议。
