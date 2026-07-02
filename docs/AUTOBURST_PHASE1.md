# 自动爆发 Phase 1：双技能注入模型

版本：`1.0.07`  
状态：代码已接入；等待 WoW + Windows 实机验收。

## 范围

一次仅运行一条规则：

```text
windowSpell + injectionSpell + direction(pre/post) + mode(simple/focused)
```

`AutoBurst` 优先读取用户显式填写的两个 SpellID：

```text
官方窗口 SpellID：必须是 Blizzard 官方推荐实际会出现的锚点
注入 SpellID：Tactic Echo 需要在锚点前或后插入的技能
```

两个 SpellID 必须同时填写。两项都为 `0` 时，才兼容性回退到当前专精 Burst Profile 的第一个非黑名单窗口技能与第一个注入技能；该回退不保证首项会被 Blizzard 官方推荐。它不会从天赋、装备、Buff、描述或冷却时间推断技能。

使用 `/teab status` 可直接查看当前加载构建、解析到的规则和最近未触发原因；`/teab set <窗口SpellID> <注入SpellID>` 可不打开设置面板直接写入测试规则。

## 战斗边沿说明（1.0.06 延续）

官方窗口边沿按**本次战斗周期**计算。插件在 `PLAYER_REGEN_DISABLED` 进入战斗时清除上一场战斗和脱战期间遗留的窗口离开锁与最后官方推荐。

这意味着：即使处决宣判在进入战斗的第一帧已是官方推荐，前置测试规则 `复仇之怒（31884） → 处决宣判（343527）` 仍可建立计划。该重置不等同于无条件派发；自动运行、自动爆发、规则、动作条绑定、冷却/GCD、TEAP 与 TEK 门禁仍必须全部通过。

## 状态机

```text
IDLE
→ PLAN_CREATED
→ STEP_PENDING
→ DISPATCH_OFFERED
→ WAIT_CONFIRM
→ STEP_CONFIRMED
→ 下一步 / DONE

软暂停：SOFT_PAUSED → 全量重新校验 → 原步骤
中止：PLAN_ABORTED → 若窗口未派发则归还官方推荐；若窗口已派发则只观察至官方推荐离开窗口
```

一个候选从首次发布起保持相同 action sequence，直到成功确认、明确失效或有界确认超时，解决 AddOn 刷新和 TEK 屏幕采样相位不一致的问题。TEK 对相同 burst sequence 拒绝第二次物理输入。

GCD/确认/重校验等待不是用户暂停。此时 AddOn 输出 `state=armed + observationOnly=true + dispatchOrigin=burst` 的非派发帧，TEK 只观察，不会校验空 Token 或发送输入；下一步进入 `QUEUE_WINDOW` 后才产生带有效 BindingToken 的 Burst 候选。

`TacticEchoDB.autoBurst.events` 会记录计划创建、拒绝、候选、确认、暂停和中止。`/temapping` 生成的安全映射快照还会附带 AutoBurst 摘要；配置了 `TacticEcho.lua` SavedVariables 路径的 TEK 诊断包会在 `SUMMARY.md` 显示这份摘要。

## 成功确认

当前阶段仅认可：

1. 技能自身非 GCD 冷却开始；
2. 可用充能减少。

没有可验证确认信号的技能或宏不应配置为 Phase 1 规则。Buff、普通 GCD 遮罩与图标灰度不作为确认来源。

## 实机测试矩阵

每个组合至少记录：规则 ID、窗口/注入 SpellID、官方推荐进入时刻、候选帧 sequence、TEK trace 的 `dispatch_origin`、输入是否发送、CD/充能确认来源、确认耗时、是否进入 `QUEUE_WINDOW`、计划结果。

1. 前置简易：注入可用。
2. 前置简易：注入 CD，验证跳过后窗口照常释放。
3. 前置集中：注入 CD，验证不接管。
4. 后置简易：窗口成功后注入可用。
5. 后置简易：窗口成功后注入 CD，验证结束而非重试。
6. 后置集中：注入 CD，验证不接管。
7. 窗口确认超时，验证最多重试一次。
8. 注入确认超时，验证不重试；简易/集中按规则分别结束或中止。
9. GCD 中进入 `QUEUE_WINDOW`，验证下一步只发送一次且无持续刷键。
10. 手动输入、聊天框、切目标、死亡、载具、引导/蓄力、失焦后，验证 TEK 不会继续输入；恢复后必须重新校验。
11. 脱战后，验证计划立刻清空并要求新的官方推荐边沿。
12. TEK 采样异常或前台/Hook 门禁失败，验证 TEK fail-closed；AddOn 计划不得无限悬挂。

## 已知结构限制

TEAP 是 AddOn → TEK 的单向可视协议。TEK 无法向 AddOn 回传“SendInput 已执行”的即时确认；AddOn 通过技能自身 CD/充能变化，或当前 `WAIT_CONFIRM` 步骤的 `UNIT_SPELLCAST_SUCCEEDED` 事件确认结果。该限制也是持续候选保持与 TEK 去重同时存在的原因。

## 共享 GCD、窗口锁与 HUD 展示（1.0.06 延续）

- 技能短冷却与全局 GCD 快照严格对齐时，归类为 `GCD_LOCKED / QUEUE_WINDOW`，不是自身 `COOLDOWN`；前置注入会等待而非跳过。
- Burst hold 的真实 Token 仍为 0，但 HUD 使用独立的官方展示绑定，因此窗口锁观察不会显示“未绑定”。
- 已派发窗口技能时，官方推荐仍显示旧窗口会触发观察锁，直到推荐离开；这是防重复按键，不是暂停。


## 1.0.07 严格未知状态合同

前置简易模式中，`UNKNOWN` 不等于注入技能 CD。以下情况均进入有限重采样而不是跳过 `4`：

- 冷却/充能数值受保护；
- API 仅报告 `active=true`，却不能证明它是技能自身 CD 而非共享 GCD；
- GCD 快照不可解释；
- 动作条或冷却来源暂时未刷新。

重采样超时后计划中止，但窗口仍为 Burst 所有，直到官方推荐离开 `1`。因此前置测试中不允许出现“没有 Burst `4`，却由 official 链路发送 `1`”。
