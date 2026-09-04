# Tactic Echo 1.5.3 基线

`1.5.3` 修复已派发读条技能在施法保护期间成功，却因计划外层处于 `SOFT_PAUSED` 而丢失成功收据、导致后续窗口技能无法轮到的问题。

## 实测故障

- 自动注入计划依次派发镜像、奥术涌动，并等待奥术涌动确认。
- 奥术涌动读条期间，施法保护正确地把计划外层包装为 `SOFT_PAUSED`，内部仍保留原 `WAIT_CONFIRM` 和同一步 `wait`。
- 客户端随后发出精确 `UNIT_SPELLCAST_SUCCEEDED(365350)`，但旧收据入口只接受字面状态 `WAIT_CONFIRM`，因此拒绝了这次成功。
- 恢复后计划只看到奥术涌动已进入自身 CD，却没有可消费的成功收据，持续停在第 2 步；大法师之触实际施放时仍未轮到窗口步骤。

## 收据状态修复

- 收据入口将 `state=SOFT_PAUSED + pauseResumeState=WAIT_CONFIRM + wait 存在` 识别为同一个已锁定确认步骤。
- 成功、失败和中断收据仍必须匹配当前步骤的精确 SpellID、已冻结等效 SpellID 与当前 `dispatchAttempt` 时间边界。
- 成功收据在软暂停期间只写入当前 `wait`；不会在施法过程中推进游标。施法结束后的首个健康业务帧恢复 `WAIT_CONFIRM`，再按既有确认路径推进。
- 失败或中断收据继续只建立既有无 Token 隔离和同一步重试，不会确认、跳过或删除当前可选步骤。

## 不变边界

- 普通施法、引导和蓄力期间仍不选择规则、不扫描候补、不创建计划、不推进游标。
- 当前步骤仍必须先确认，下一步骤才可派发；CD、UNKNOWN、共享 GCD、Buff 和单个失败事件均不构成成功。
- `configuredCursor`、不同业务快照缺口处理、窗口身份栅栏、唯一 AutoInjectionCoordinator/OrderedPlan 以及 BindingToken → TEAP v3 → TEK 路径保持不变。
