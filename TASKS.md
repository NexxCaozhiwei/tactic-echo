# Tactic Echo Tasks

当前版本：`1.0.08`

## 当前范围

- 保持常规主派发：官方推荐 → 默认动作条 → BindingToken → TEAP → TEK → SendInput。
- AutoBurst Phase 1 已接入：单窗口 + 单注入，前置/后置、简易/集中，默认关闭。
- 当前不接入饰品、药水、第二注入技能、多规则竞争、组合宏或 `/castsequence`。

## 首轮实机验证

1. 将 `addon/!TacticEcho` 同步至 WoW AddOns 目录并 `/reload`，确认无 Lua 错误。
2. 为当前专精确认 Burst Profile 的窗口与注入技能均已放入可见默认动作条，并使用支持的键位。
3. 控制面板依次测试前置简易、前置集中、后置简易、后置集中。
4. 先实测前置简易：窗口=处决宣判、注入=复仇之怒；确认 GCD 等待期间 TEK Trace 是 `dispatch_origin=burst + observation_only=true + state=armed`，随后出现带非零 BindingToken 的 Burst 候选。
5. 查验 AddOn `TacticEchoDB.autoBurst.events`、TEK Trace 的 `dispatch_origin=burst`、TEK status 的 `last_dispatch_origin`。
6. 检查窗口进入边沿、GCD 预输入、CD/充能确认、窗口单次重试、注入不重试、脱战清空与手动接管/失焦 fail-closed。
7. 检查不同急速、网络、窗口模式、DPI、多显示器和真实 Windows SendInput。

## 已知限制

- 成功确认不使用 Buff；没有可用 CD/充能确认信号的技能不得加入 Phase 1。
- TEAP 没有 TEK → AddOn 回执，AddOn 只能通过 CD/充能或超时判断步骤结果。
- 复杂宏与自定义动作条插件不属于 Phase 1 自动爆发来源。

## 后续候选

- 实机稳定后再设计饰品、药水与互斥组。
- 在确认策略不需要 Buff 后，才考虑多注入或多规则优先级。
- 依据实机 Trace 校准候选保持窗口、确认期限和 GCDGate 的队列窗口边界。

## 1.0.08 本轮重点复测

1. 前置简易规则：窗口 `343527`（处决宣判，键 `1`），注入 `31884`（复仇之怒，键 `4`）。官方推荐进入 `1` 后，先检查 `/temapping` 中 `plan.preInjectionSkipAllowed`：只有明确自身 CD 才能为 `true`。
2. 当 `4` 可用时，TEK Trace 必须先出现 `dispatch_origin=burst + binding=4`；在 `4` 成功回执前不得出现官方来源的 `binding=1`。
3. 当 `4` 的 CD/GCD 来源未知时，应看到 `step_revalidate_started / step_revalidate_wait` 与 Burst observation 帧；超时后只观察到窗口离开，`1` 不得绕过。
4. `4` 成功后，诊断应出现 `step_spellcast_succeeded` 或专属 CD/充能确认；随后 `1` 在下一合法队列窗口只派发一次。
5. 暂停后再启动时，如果首个健康帧已经显示 `1` 且该窗口 generation 未消费，应仍先出现 Burst `binding=4`。
6. 完成、中止或超时后，官方仍显示 `1` 时只能 observation-only；HUD 显示官方键位 `1`，TEAP `BindingToken=0`。
7. `/temapping autoburst_108` 后检查 `armedEpoch`、`firstHealthyFramePending`、`windowGeneration`、`consumedWindowGeneration`、`departureLockGeneration`、`lastCandidate`、`candidateOfferCount`、`lastConfirmationSource`、`lastAbortReason`、`lastWindowRejectReason`。
8. 测试结束执行 `/reload` 或完全退出游戏，上传新的 TEK 诊断包及 `TacticEcho.lua`。
