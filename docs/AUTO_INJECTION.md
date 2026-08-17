# 自动注入

版本：`1.4.0`

“自动注入”是 AutoBurst 的用户可见扩展名称。每个专精最多配置三个独立技能组，但运行时始终只有一个 Coordinator、一个活动组、一个 plan 和一个 pre-window capture。

## 配置

- 总开关位于 `/teui` 的“自动注入”页。
- 每组可设置名称、启用状态、`simple/focused` 模式和唯一窗口 SpellID。
- 窗口可以是普通技能；只有官方推荐精确等于该 SpellID 时才会考虑启动。
- 每组最多六个注入技能，并固定提供饰品 13、14；窗口不可停用，但九个步骤都可调整位置。
- 不同启用组不能使用相同窗口，也不能把某组窗口放入另一组注入链。普通注入和饰品可以跨组复用。

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

HUD 只展示活动组；空闲时展示当前窗口命中组或设置页选中组，并显示组名。全部卡片保持只读和 `bindingToken=0`；只有 SignalFrame 已产生真实 Burst TEAP 候选时，精确当前步骤显示“派发”。

TEAP v3 仍为 20 字节，`dispatchOrigin="burst"` 与 flags `0x20` 不变。groupId 只存在于 AddOn 配置、状态、HUD 和诊断中，不编码到协议。
