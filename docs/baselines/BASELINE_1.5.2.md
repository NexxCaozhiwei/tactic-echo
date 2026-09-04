# Tactic Echo 1.5.2 基线

`1.5.2` 将自动注入冻结为严格的单游标有序执行：正在进行的施法不受检测干扰，窗口不会从官方主链提前漏出；当前步骤确认后，后续配置缺口必须在新的业务快照上按原位置处理。

## 施法期窗口栅栏

- 普通施法、引导或蓄力期间，不选择自动注入规则、不创建 plan/capture、不扫描候补，也不推进 group、stepIndex 或配置游标。
- 若此时官方推荐恰好是已启用且验证通过的组窗口，只做只读身份匹配，并返回 observation-only、`BindingToken=0` 的窗口栅栏。
- 栅栏不 Claim 组所有权、不消费窗口边沿、不改变 missed-window latch；施法结束后的首个健康业务帧仍从未消费的窗口建立唯一计划。
- 已存在 plan、capture 或 departure lock 时继续保持其原有所有权和当前步骤，不允许官方推荐绕过自动注入链。

## 严格顺序与确认门槛

- 每个计划只有一个单调递增的 `configuredCursor`；`configuredIndex` 是步骤相对顺序的唯一权威。
- 当前步骤只有在精确 `UNIT_SPELLCAST_SUCCEEDED`、稳定自身非 GCD 冷却开始或充能减少后才视为完成并推进。
- 发布候选、SendInput 尝试、移动失败、普通失败收据、共享 GCD 或短暂 UNKNOWN 都不能确认当前步骤，也不能让后续步骤越过它。
- 已明确准入的当前步骤在移动、失败隔离或短暂 UNKNOWN 中保持队首；任何新步骤都不得插到它之前。

## 后续候补与新业务快照

- 创建计划时为 CD/UNKNOWN、但绑定与装备身份仍有效的未来步骤保留原始 `configuredIndex`，不加入活动链前缀。
- 当前步骤确认后，如果下一活动步骤之前存在配置缺口，同一个 runtime cycle 只返回 observation-only hold，不得既确认当前步骤又越过缺口。
- 下一不同 `runtimeSnapshot.cycleId` 才能复检该缺口：明确自身可用时按原位置加入；仍为 CD/UNKNOWN 时永久越过该位置并继续后续活动步骤。
- 已越过或位于 `configuredCursor` 之前的步骤永久失效；之后恢复也不得回插、重建或重放已经过去的链前缀。
- 窗口/步骤自身 CD 的稳定证据要求至少两个不同业务样本，且采样间隔不少于 0.15 秒。

## A-W-B-C 参考语义

- W 被官方推荐时建立唯一计划，并按配置顺序执行 A、W、B、C 中已经明确可用的步骤。
- A 未确认前 W 不得派发；W 未确认前 B 不得派发；B 未确认前 C 不得派发。
- 若 B 初始冷却，在 W 确认后的新业务快照上恢复，则插回 W 与 C 之间；若该快照上仍不可用，则越过 B 并执行 C，B 后续恢复不得再插回 C 前面。

## 不变安全边界

- 自动注入继续共享唯一 `AutoInjectionCoordinator`、唯一 AutoBurst OrderedPlan、唯一 capture 和唯一候选。
- 输入路径仍只有官方推荐 → AutoInjectionCoordinator → AutoBurst → BindingToken → TEAP v3 → TEK → 单次 SendInput。
- 每个步骤首次派发仍要求当前可信动作条/装备身份和明确自身可用证据；CD/UNKNOWN 不得借共享 GCD 降级派发。
- 脱战硬门控、手动让权、前台/Hook/限频、宏身份、HUD 冷却展示隔离和诊断隐私边界均保持不变。
