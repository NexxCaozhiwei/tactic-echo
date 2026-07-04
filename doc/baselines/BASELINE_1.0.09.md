# Tactic Echo 1.0.09 基线

## 修订目标

修复 1.0.08 实机复测暴露的两条自动爆发异常：

```text
窗口：343527（处决宣判，键 1）
注入：31884（复仇之怒，键 4）
方向/模式：pre simple
期望：4 -> 1
```

1. `paused -> armed` 后，首个官方推荐若仍为窗口 `343527`，旧的同窗口观测状态不得压制新 armed epoch。
2. 前置简易模式不能依据单帧 `COOLDOWN` 跳过 `31884`；只有连续两次独立实时采样均确认“同一 SpellID、非 GCD、自身冷却、直接默认动作条绑定、非确认中”时，才允许跳过注入。
3. HUD 的灰色仅表示已确认的冷却/不可用；CD 数据未知或校验中保留彩色图标，并用“待确认/校验”叠层区分。

## 固定规则

1. 每次从非 `armed` 转回 `armed`，若不存在活动计划和窗口离开锁，AutoBurst 清空继承的 `lastOfficialSpellID/currentWindowSpellID` 观测基线，并在首个健康帧为当前窗口创建新的 generation。
2. 已创建计划或已消费窗口离开锁期间绝不重置观测基线；同一已消费窗口仍必须先离开再回来。
3. 前置简易的 `COOLDOWN` skip 采用两样本证书：`count=1` 时只观察，`count=2` 且 identity/binding 一致时才记录 `confirmed_own_cooldown` 并跳过。
4. `UNKNOWN`、公共 GCD、Tracker 确认中、SpellID identity 不一致、非实时读数、非直接动作条绑定等全部不能构成 skip 证据；计划进入有界重采样，超时后保持窗口离开锁。
5. `auto_run_not_armed`、脱战、非窗口等静态决策采用低频诊断心跳；计划创建、重采样、CD 确认、跳过、派发、确认、中止等关键事件进入独立优先级 ring。
6. `/temapping` 导出 armed rebase、前置注入确认状态、最近优先级事件与完整的冷却 identity/确认字段。

## 实机验收

- 暂停时保持官方推荐为 `343527`，再切回自动运行：必须先出现 Burst `4`；诊断必须有 `armed_window_observation_rebased`。
- 将 `31884` 置于真实自身 CD：第一帧只观察，第二个独立采样后才允许 Burst `1`，并记录 `confirmed_own_cooldown`。
- 出现灰色但 CD 状态未知/校验中时，HUD 不应显示纯灰；应显示彩色“待确认/校验”，AutoBurst 不能直接发 `1`。
- `4` 成功前，任何来源均不得将 `1` 作为 Burst 前置计划的下一派发动作。
