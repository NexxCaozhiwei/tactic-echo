# Tactic Echo 1.4.9 基线：前置注入冷却边沿抖动修复

## 基线结论

`1.4.9` 修复可信直接前置技能在真实 ready 前约一个采样相位进入官方窗口时，旧 0.70 秒观察预算过早结束的问题。修复只延长既有 pre-window capture 的有界只读复检，不新增状态机、候选源、计划器或输入路径。

## 实机依据与预算

- 惩戒骑 31884 的精确成功记录为 `92377.462`，下一官方窗口的冷却边沿捕获在 `92436.588` 开始，即成功后 59.126 秒。
- 旧预算在 `92437.286` 到期，即成功后 59.824 秒；动作槽位仍明确报告自身冷却，约早于 60 秒 ready 边沿 0.176 秒释放。
- 新预算使用受限 `SpellQueueWindow + 0.75s`，最少 0.85 秒、最多 1.20 秒。该预算只限制观察所有权，不猜测冷却完成、不替代 GCDGate，也不构成派发或成功证据。

## 资格与派发边界

- 仅序列第一步、窗口之前、Resolver 已验证且具备真实 BindingToken 的直接 Blizzard 默认动作槽位技能可进入。
- 当前样本必须是已知、非 GCD、自身冷却，并由同一直接槽位提供精确 `actionbar_api`、`actionbar_numeric` 或 `actionbar_duration` 证据。
- capture 期间固定 observation-only、`BindingToken=0`，不创建 plan、不发送 Burst TEAP 动作。
- 只有同一可信动作槽位明确 ready 后才重新预检并按用户原顺序建立计划；HUD、DurationObject、Tooltip/Base 时长、图标灰度和原始受保护冷却数值均不得授权。
- 预算到期仍冷却时恢复原 simple/focused 预检；窗口离开、脱战、规则或绑定变化继续沿用既有 capture 清理与 departure-lock 保护。

## 架构与验证

- 保留唯一 AutoInjectionCoordinator、唯一 AutoBurst OrderedPlan、唯一 pre-window capture 和唯一候选。
- BindingToken、TEAP v3 20 字节、flags `0x20`、TEK、精确成功事件和不同样本稳定确认均未改变。
- 行为回归必须覆盖 0.90 秒晚到 ready 恢复原顺序，以及超过 1.20 秒仍冷却时安全释放。
- 离线测试不能替代 Retail 动作栏采样、SpellQueueWindow 与 Windows SendInput 实机验收。
