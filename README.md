# Tactic Echo

更新时间：2026-07-02  
当前版本：`1.0.07`

Tactic Echo 由《魔兽世界》AddOn 与 Windows 端 TEK 组成。AddOn 读取官方辅助战斗推荐，解析当前可见 Blizzard 默认动作条上的现实按键；TEK 只在前台、协议、Hook、手动接管、限频等门禁均通过时，才执行一次 Windows 输入。

`1.0.07` 按实测问答重写前置注入的未知状态与确认链：只有窗口边沿明确证明注入技能自身 CD 时才允许跳过；受保护冷却、共享 GCD 来源不明或其他 `UNKNOWN` 均会限时重采样并锁住窗口。Burst 候选持续发布至确认、明确失效或超时，且 `UNIT_SPELLCAST_SUCCEEDED` 仅作为当前已派发步骤的成功回执。最小双技能自动爆发仍默认关闭，且需要 WoW + Windows 实机验收。

## 主派发架构

```text
官方推荐（只读）
→ Blizzard 默认动作条现有绑定
→ BindingToken
→ TEAP v3 可视信号帧
→ TEK 安全门禁
→ 单次 SendInput
```

AddOn 不创建隐藏动作按钮，不写绑定，不编辑宏，也不直接执行 Windows 输入。

## 自动爆发 Phase 1

自动爆发不是第二条输入通道。它仅在满足条件时，把“当前计划的下一步”作为独立候选，仍走同一条 BindingToken → TEAP → TEK 链路。

```text
OfficialRecommendation（保持不变）
→ AutoBurst DispatchCandidate
→ 已扫描确认的动作条 BindingToken
→ TEAP v3（dispatchOrigin=burst）
→ TEK 全部门禁
→ 单次输入
→ 技能自身 CD / 充能确认
```

### 启用条件

- 运行状态为“运行中”；
- 控制面板“启用自动爆发”已开启；
- 玩家在战斗中；
- 当前专精存在人工声明的窗口技能与注入技能；
- 官方推荐首次进入窗口技能；
- 两个技能均在当前可见默认动作条上有可用 BindingToken。

同一窗口只会在官方推荐离开后再次进入时重新触发。临时开启自动爆发时，不会插入已持续显示的旧窗口。

### 当前四种组合

| 方向 / 模式 | 行为 |
|---|---|
| 前置简易 | 注入 → 窗口；只有窗口边沿明确为注入自身 CD 才跳过；未知状态限时重采样并锁住窗口 |
| 前置集中 | 注入 → 窗口；任一步不就绪则不启动 |
| 后置简易 | 窗口 → 注入；窗口确认后，注入不可用则完成 |
| 后置集中 | 窗口 → 注入；任一步不就绪则不启动或中止 |

当前版本不包含饰品、药水、多条规则竞争、第二注入技能或组合宏。

### 调度与确认规则

- 每次只允许一个 BindingToken，禁止同帧连按和持续刷键。
- 两个技能均可占 GCD。`GCDGate` 使用客户端 `SpellQueueWindow` 将状态归一化为 `READY_NOW / QUEUE_WINDOW / GCD_LOCKED`；允许在合法预输入窗口提交一次下一步。
- 为避免 TEK 采样错过候选，AddOn 会持续发布同一候选帧，直至成功确认、明确失效或超时；TEK 按稳定 burst action sequence 去重，同一逻辑步骤最多尝试一次真实输入。
- 在 `GCD_LOCKED`、`WAIT_CONFIRM`、软暂停重校验或“等待窗口推荐离开”期间，AddOn 发送的是 `armed + observationOnly` 的 Burst hold 帧。该帧不含 BindingToken，TEK 只观察不输入；它不是用户“暂停中”，不会导致状态机自锁。
- 发送候选不等于释放成功。Phase 1 使用该技能自身的**非 GCD 冷却开始**、**充能减少**，或仅匹配当前等待步骤的 `UNIT_SPELLCAST_SUCCEEDED` 回执确认成功；不使用 Buff、泛 GCD 遮罩或普通图标灰度。
- 窗口技能确认超时最多受控重试一次；注入技能不重试。

### 数据边界

自动爆发策略只读取：官方推荐、动作条绑定、技能 CD、充能和归一化 GCD 阶段。它不使用 Buff、Debuff、资源、目标血量、敌人数、团队状态、首领机制、距离或范围作为自动派发依据。

## 宏边界

Phase 1 只允许有明确预期技能的单一用途宏；现有文本关联回退仅支持无条件单行 `/cast <spell>`。组合宏、`/castsequence`、条件分支、目标修饰、`/use` 及不可通过 CD/充能确认的宏不进入当前自动爆发测试范围。

## 关键路径

- 自动爆发状态机：`addon/!TacticEcho/Tactics/AutoBurst.lua`
- GCD 归一化门：`addon/!TacticEcho/Tactics/GCDGate.lua`
- 冷却/充能专用采样：`addon/!TacticEcho/Tactics/IconState.lua`
- TEAP 编码：`addon/!TacticEcho/Signal/SignalEncoder.lua`
- 信号派发候选接入：`addon/!TacticEcho/Signal/SignalFrame.lua`
- TEK 协议解码：`tek/src/teap.py`
- TEK 安全门禁与 burst 去重：`tek/src/safety_gate.py`
- TEK 真实派发：`tek/src/engine.py`
- 详细开发合同：`AGENTS.md`
- Phase 1 设计与实机测试矩阵：`docs/AUTOBURST_PHASE1.md`

## 验证

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

## 实机验收说明

本包的离线测试只能证明代码路径与协议合同。仍需在真实 WoW/Windows 环境检查：TEAP 采样相位、窗口技能/注入技能 CD 确认、GCD 预输入、Hook、前台识别、手动接管、SendInput、不同急速与窗口模式。

## 自动爆发 1.0.07 实机安装与诊断

自动爆发 Phase 1 的测试规则现支持显式填写“官方窗口 SpellID + 注入 SpellID”。官方窗口技能必须是 Blizzard 官方推荐实际会出现的锚点；请不要默认把 HUD 爆发列表的首项当作该锚点。

实机安装与诊断步骤见：[docs/AUTOBURST_DIAGNOSTIC_AND_INSTALL.md](docs/AUTOBURST_DIAGNOSTIC_AND_INSTALL.md)。其中包括正确的 `!TacticEcho` 覆盖目录、`/teab status` 版本验证，以及 `TacticEcho.lua` SavedVariables 的诊断包配置。


### 1.0.07 修复摘要

- **未知不跳过**：`复仇之怒（31884）` 的冷却读数无法安全解释、或 API 仅报告 `active=true` 但无法证明它是自身 CD 而非公共 GCD 时，AutoBurst 进入有界重采样；不再把它当作“注入 CD”而直接派发 `处决宣判（343527）`。
- **严格前置所有权**：官方推荐进入窗口后，前置计划一经创建即持有窗口。`4` 未确认成功、候选超时或未知重采样超时，`1` 均不得回落到普通官方链；只能等待官方推荐离开窗口后再次进入。
- **候选持续与回执**：同一 Burst 候选保持同一 TEAP sequence 直到结果明确；TEK 去重避免重复物理输入。`UNIT_SPELLCAST_SUCCEEDED` 只可确认已经处于 `WAIT_CONFIRM` 的同一技能，不参与触发时机判断。
- **诊断**：`/temapping` 新增初始窗口状态、候选帧计数、最后候选与最近施法成功摘要，用于直接区分“计划未建立”“候选未进入 TEAP”“TEK 未派发”和“等待确认”。
