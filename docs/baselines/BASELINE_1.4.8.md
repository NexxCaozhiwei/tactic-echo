# Tactic Echo 1.4.8 基线：前置注入冷却结束边沿复检

## 基线结论

`1.4.8` 修复官方窗口比可信直接前置技能的真实冷却结束早一个采样相位时，simple 预检永久删除该步骤的问题。修复复用唯一 pre-window capture，不新增计划器、状态机、候选源或输入路径。

## 边沿资格

- 仅序列第一步且位于窗口之前的技能步骤可进入边沿复检。
- Resolver 必须确认当前来源为直接 Blizzard 默认动作槽位、身份可信并具有真实 BindingToken；宏、物品、饰品和间接来源永不进入。
- 当前样本必须为已知、非 GCD、自身冷却，并由同一直接动作槽位提供 `actionbar_api`、`actionbar_numeric` 或 `actionbar_duration` 精确证据。
- UNKNOWN、共享 GCD、图标灰度、HUD 数字、原生 DurationObject、Tooltip/Base 静态值和 Tracker 展示缓存均不能建立边沿资格。

## 执行与失败关闭

- 边沿期间只保留既有 pre-window capture，输出 authenticated observation-only 帧且 `BindingToken=0`；不得建立 plan 或提前派发。
- 预算使用当前共享业务周期的受限 `SpellQueueWindow` 加 0.25 秒稳定余量，最少 0.35 秒、最多 0.70 秒；它只限制观察所有权，不替代 GCDGate 或输入调度。
- 同一可信动作槽位明确 ready 后，重新预检并按用户原顺序建立计划。
- 预算到期而动作仍冷却时，必须忽略边沿资格重新执行原 simple/focused 预检；窗口离开、规则变化、绑定变化、脱战和世界切换继续沿用既有 capture 清理与 departure-lock 保护。

## 诊断与架构

- 导出 `cooldownEdgePending`、步骤 key、SpellID、动作槽位和封顶预算等纯标量，不保存原始冷却数值或宏正文。
- 保留唯一 Coordinator、唯一 OrderedPlan、唯一 capture 与唯一候选；BindingToken、TEAP v3 20 字节、flags `0x20`、TEK、成功确认和不同样本稳定确认不变。
- 离线测试不能替代 Retail 动作条采样、SpellQueueWindow 与 Windows SendInput 实机验收。
