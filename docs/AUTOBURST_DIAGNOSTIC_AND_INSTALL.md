# 自动爆发 1.0.07：安装与诊断

## 本次故障的直接证据

上传的 SavedVariables 压缩包只包含 `!WR.lua`，没有 `TacticEcho.lua` / `TacticEchoDB`。这表示本次测试无法证明 `!TacticEcho` 1.0.02 已加载并保存数据；旧 1.0.02 trace 中全部是 `dispatch_origin=official`；后续 trace 已证明 Burst hold 曾进入协议链但被错误编码为 `paused`。1.0.07 在该基础上进一步将未知状态与明确自身 CD 分离、持续发布候选并加入当前步骤的施法成功回执。

## 正确覆盖位置

完整源码包用于项目根目录；WoW 实机安装必须把包内：

```text
addon/!TacticEcho/
```

整个目录覆盖到：

```text
World of Warcraft/_retail_/Interface/AddOns/!TacticEcho/
```

不要把 `Tactic-Echo-1.0.07` 根目录、`addon` 父目录或旧 `!WR` 目录直接当作插件目录。确认游戏角色选择界面的插件列表中显示：

```text
Tactic Echo 1.0.07
```

游戏完全退出或执行 `/reload` 后，应出现：

```text
World of Warcraft/_retail_/WTF/Account/<账号>/SavedVariables/TacticEcho.lua
```

## Phase 1 测试规则

1. 使用 `/teab set <官方窗口SpellID> <注入SpellID>`，或在“爆发”页面填写两个 SpellID。
2. `官方窗口SpellID` 是暴雪官方推荐实际会出现的锚点，不一定是 HUD 爆发列表中的第一个大技能。
3. `注入SpellID` 是 Tactic Echo 要在锚点之前或之后插入的技能。
4. 执行 `/teab status`，必须能看到 `构建=1.0.07` 和两项 SpellID。
5. 执行 `/tesignal armed`，勾选“启用自动爆发”，进入战斗，等待官方推荐**先离开再边沿进入**窗口技能。
6. 测试后执行 `/temapping autoburst_105`，再 `/reload` 或完全退出游戏。
7. 在 TEK 设置中选择上述 `TacticEcho.lua` 作为 SavedVariables 路径，再生成诊断包。

诊断包的摘要将显示自动爆发的启用状态、实际规则、最近拒绝/候选原因。

## 1.0.07 需要核对的诊断字段

当测试 `343527 → 31884` 或 `31884 → 343527` 时，重点查看：

- `autoBurst.lastStepObservation.phase`：应显示 `GCD_LOCKED` / `QUEUE_WINDOW`，而不是把共享 GCD 显示为注入技能 `COOLDOWN`；
- `cooldownGcdAlias=true` 与 `cooldownGcdAliasReason=gcd_snapshot_aligned`：仅表示严格对齐的共享 GCD；
- `bindingToken` 与 `binding`：确认 `4` 和 `1` 都存在默认动作条绑定；
- `lastDecision.reason`：可区分 `burst_candidate`、`await_window_departure`、`official_not_window` 与真正的 `binding_not_ready`；
- TEK Trace：Burst 候选应为 `dispatch_origin=burst` 且只产生一次真实输入；观察帧应为 `observation_only=true`，不会输入。


## 1.0.07 前置注入诊断字段

`/temapping` 导出的 `autoBurst` 摘要新增：

- `plan.preInjectionSkipAllowed`：只在窗口边沿明确确认注入自身 CD 时为 `true`；
- `plan.candidateOfferCount`：当前步骤已持续发布候选帧的数量；
- `lastCandidate`：最后一个 Burst 候选的技能、绑定 Token、尝试号与发布次数；
- `lastSpellcastSuccess`：最近的玩家成功施法事件。

前置 `4 → 1` 的正确 Trace 顺序为：先有 `dispatch_origin=burst` 与绑定 `4`；确认后才有 Burst 绑定 `1`。若读数未知，应看到 `burst_step_revalidate` 观察帧，而不是 official 绑定 `1`。
