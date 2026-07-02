# AGENTS.md — Tactic Echo 1.0.08 开发与安全边界

## 1. 基线与交付

- 当前唯一开发基线：`1.0.08`。其来源为已验证的 `0.9.51` 代码树；`0.9.0` 和 `1.0.01` 仅保留历史记录。
- 默认交付完整源码包。压缩包只能有一个项目根目录，不得包含 `build/`、`dist/`、`release/`、缓存、日志、SavedVariables、EXE、历史补丁或本机配置。
- 每次代码修改必须保持根目录 `VERSION`、插件 TOC、`Core/Bootstrap.lua` 版本一致，并运行本文件第 9 节验证。
- 不得以离线测试、PyInstaller 成功或进程存活作为 Windows Hook、前台判断、SendInput、自动爆发实机成功的证据。

## 2. 常规派发路径

唯一常规输入路径：

```text
官方推荐（只读）
→ 当前可见 Blizzard 默认动作条绑定
→ BindingToken
→ TEAP v3
→ TEK 协议 / 前台 / Hook / 手动让权 / 限频门禁
→ 单次 SendInput
```

禁止新增任何绕过该路径的输入通道。AddOn 不得创建隐藏按钮、写按键、保存按键、编辑宏、合成宏、直接调用 Windows 输入或写虚拟键值。

## 3. 自动爆发 Phase 1：唯一允许的受控接管

`Tactics/AutoBurst.lua` 是唯一可临时覆盖官方推荐的模块，但它只能生成一个独立的 `DispatchCandidate`；不能修改 `OfficialRecommendation`，不能直接输入。

```text
OfficialRecommendation（不可变）
→ AutoBurst State Machine（候选）
→ 已解析的 BindingToken
→ TEAP v3（dispatchOrigin=burst）
→ TEK 全部门禁
→ 单次 SendInput
```

### 3.1 启动条件

必须同时满足：

1. SignalFrame 的“自动运行”处于 `armed`；
2. `autoBurstEnabled=true`；
3. 玩家处于战斗中；
4. 存在一条人工声明规则：优先使用同时填写的 `autoBurstWindowSpellID + autoBurstInjectionSpellID`；两项均为空时才允许兼容性回退到当前专精 Burst Profile 的首个窗口/注入条目；
5. 官方推荐进入该规则的窗口 generation；普通路径要求 `non-window -> window`，`paused -> armed` 后首个健康帧若已显示未消费窗口也可触发；
6. 两个技能都能解析到当前可见默认动作条上的有效 BindingToken；
7. TEAP 与 TEK 的现有安全门禁允许派发。

Phase 1 只启用一条规则：优先采用用户显式填写的窗口/注入 SpellID；只有两项均未填写时，兼容性使用 Profile 中第一个非黑名单窗口技能 + 第一个非黑名单注入技能。显式窗口 SpellID 必须是官方推荐实际可出现的锚点，不能把 HUD 爆发列表首项自动假定为推荐锚点。不得自动根据天赋、装备、技能文本、伤害、CD 或 Buff 推断爆发技能。

计划结束、拒绝或中止后，当前 `windowGeneration` 必须标记为已消费并保持离开锁；官方推荐必须先离开窗口技能、之后再次回到它，才可再创建计划。临时开启自动爆发时，如果窗口已经持续显示且该 generation 已消费或已锁定，不得半路插入。

### 3.2 固定模式

配置项：

```text
autoBurstDirection = pre | post
autoBurstMode = simple | focused
```

| 模式 | 序列 | 注入不可用时 |
|---|---|---|
| 前置简易 | 注入 → 窗口 | 仅当窗口边沿明确确认注入处于自身 CD 时才跳过；`UNKNOWN`、共享 GCD 来源不明或读取受保护均不得跳过，必须限时重采样并保持窗口所有权 |
| 前置集中 | 注入 → 窗口 | 不创建或中止 |
| 后置简易 | 窗口 → 注入 | 窗口成功后跳过注入并完成 |
| 后置集中 | 窗口 → 注入 | 不创建或中止 |

窗口技能未确认成功时，后置模式绝对不得派发注入技能。集中模式不能在执行中静默降级为简易模式。

### 3.3 可读取的策略输入

AutoBurst 仅允许通过 `IconState:CollectCooldownOnly()` 与 `GCDGate` 读取：

- 技能自身冷却状态；
- 技能充能状态；
- 归一化 GCD 阶段：`READY_NOW`、`QUEUE_WINDOW`、`GCD_LOCKED`、`UNKNOWN`；
- 当前官方推荐、当前有效 BindingToken、自动运行状态与战斗状态。

不得把玩家 Buff、目标 Debuff、资源、目标生命值、敌人数量、团队状态、首领机制、范围或读条对象作为自动爆发时机输入。`CollectCooldownOnly()` 不得调用可用性、资源、目标/距离、Proc 或 Aura 查询。

### 3.4 GCD、候选帧与确认

- 每轮最多一个 BindingToken，禁止同帧多键或持续连按。
- `GCD_LOCKED` 只是时序等待，不是技能 CD；进入 `QUEUE_WINDOW` 后允许一次预输入。若某技能 API 冷却与全局 GCD 的开始、持续和剩余时间严格对齐，`IconState` 只能将其归类为共享 GCD，不得把它误判为自身 CD 并跳过。
- AutoBurst 的内部 `hold` 必须编码为 `state=armed + observationOnly=true + dispatchOrigin=burst + BindingToken=0`。它只抑制当前自动输入，不得伪装成用户“暂停中”，不得反向让状态机把自身判为 `runtime_paused`。观察帧必须携带独立的只读官方展示绑定；它不得成为实际派发 Token。
- 窗口步骤已被候选派发或确认后，若官方推荐短暂仍显示同一窗口技能，必须保持观察直到推荐离开，避免重复发送窗口键。
- 前置计划若在窗口边沿确认注入自身可用，则从创建时起取得窗口所有权；即使注入候选、实时采样或确认随后异常，窗口技能也不得回落到普通官方派发链，必须观察锁定至官方推荐离开窗口。
- 每个逻辑步骤从首次候选开始持续发布同一个 TEAP 候选，直到技能成功确认、明确失效或确认超时；TEK 依据稳定 action sequence 去重，同一 Burst 候选最多尝试一次真实输入。
- AddOn 没有 SendInput 回执。派发后进入 `WAIT_CONFIRM`，不允许同步派发其他自动动作。
- 成功确认按优先级接受：该技能自身的非 GCD 冷却开始、可用充能减少、或仅对当前 `WAIT_CONFIRM` 步骤有效的 `UNIT_SPELLCAST_SUCCEEDED` 事件。Phase 1 禁止使用 Buff、泛 GCD 遮罩或普通动作条灰度作为成功证据。
- 窗口技能确认超时允许受控重试一次；注入技能不重试。
- 计划总时限和步骤时限均按真实时间推进；软暂停不冻结时钟。

### 3.5 UNKNOWN、暂停与中止

- 简易模式下，仅当**窗口边沿**已明确确认前置注入技能处于自身 `COOLDOWN` 时，才可以跳过该注入。`UNKNOWN`、`active=true` 但 GCD 来源不明、瞬态 `COOLDOWN` 或确认超时均不得转换为跳过；它们先进入有界重采样，超时后中止并保持窗口所有权直到官方推荐离开。
- 后置简易在窗口已经确认成功后，注入技能 `COOLDOWN` 或 `UNKNOWN` 可以跳过；窗口技能 `UNKNOWN` 必须中止。
- 集中模式下，任何步骤 `COOLDOWN`、`UNKNOWN`、`UNUSABLE` 或 `BLOCKED` 都不得启动或继续。
- AddOn 本地硬中止：脱战。专精变化、规则变化、绑定失效、步骤无效、未知重采样/计划/确认超时或 AutoBurst evaluator 故障属于计划中止；任何已经创建的自动爆发计划终止后都保持只观察，直到官方推荐离开该窗口，绝不回落到普通官方派发链。
- 文本输入、引导/蓄力、死亡、载具、失焦、目标变化和短暂刷新异常进入软暂停或既有 TEK 阻断；恢复后必须重新检查当前未完成步骤、BindingToken、双开关、战斗状态和总时限。
- TEK 对 CRC、Commit、采样、前台、Hook、人工键盘和新鲜度异常始终 fail-closed。TEAP 是单向链路，TEK 的连续解码异常不能直接清空 AddOn 内存计划；AddOn 的计划总时限会自然失效，不得声称存在未实现的反向确认通道。

## 4. 宏与动作条

- 只支持 Blizzard 默认可见动作条。载具、控制单位、覆盖动作条、宠物战斗 fail-closed；ExtraActionBar 仅观察。
- Phase 1 宏仅接受一个明确预期技能的单一用途宏，当前文本语义回退仅支持无条件单行 `/cast <spell>`。
- 禁止组合宏、多动作宏、`/castsequence`、条件分支、目标修饰、`/use` 与无法以 CD/充能确认的宏进入 Phase 1 自动爆发。
- 复杂宏可以保留为普通动作条诊断对象，但不得作为 AutoBurst 规则步骤。

## 5. 协议、审计与状态展示

- TEAP v3 保持 20 字节长度；flags bit 5（`0x20`）固定表示 `dispatchOrigin=burst`。
- 保留 `officialSpellID`、`dispatchSpellID`、`dispatchOrigin`、`planId`、步骤角色与派发尝试号用于 SavedVariables、Trace 和状态遥测。
- AddOn 保存的 Burst 元数据必须是简化审计记录，不得保存完整 resolver 对象、宏诊断对象或潜在 secret 值。
- AutoBurst 必须持续记录 `official_not_window`、`window_edge_missing`、规则不完整与 evaluator 故障；`/temapping` 的安全映射快照仅导出规则、计划和最近原因的纯标量摘要。
- TEK Trace 与状态快照必须暴露 `dispatch_origin` / `last_dispatch_origin`。

## 6. 绝对禁止

- HUD、Tooltip、视觉层、防御、打断、控制、位移或普通 Burst 展示层建立 Token、改写官方推荐、写 TEAP 或请求 TEK 输入。
- AutoBurst 绕过 BindingToken、TEAP、TEK、前台、Hook、手动让权、新鲜度、CRC、会话、限频或动作条解析。
- 用固定睡眠毫秒或持续重复输入代替 GCDGate 与确认状态机。
- 将原始 GCD 剩余数值泄漏给 AutoBurst 状态机；原始数值只能存在于 GCDGate 时序适配层。

## 7. 性能与刷新约束

- HUD 与视觉层仅用于呈现；不得改变推荐、候选、BindingToken、TEAP 或派发条件。
- 不新增高频 OnUpdate 链。AutoBurst 必须复用 SignalFrame 刷新、官方推荐和 GCD 上下文。
- Bootstrap 之外不得直接 `:RegisterEvent()`；AddOn 仅可经 `TE:RegisterEventSafe` / `TE:RegisterEventsSafe` 注册一次性事件。
- HUD 冷却展示继续使用现有缓存/事件驱动路径。AutoBurst 的单一规则步骤与 GCDGate 可在既有 SignalFrame 刷新内读取一次实时公共冷却快照；该窄例外不得扩展为 HUD 全量扫描或独立高频 OnUpdate。

## 8. Windows 实机验收

以下始终属于人工实机验收：Windows 前台识别、Hook、真实 SendInput、采样相位、SpellQueueWindow、不同急速/GCD、宏、DPI、多显示器、窗口模式，以及四种双技能组合的实际释放顺序。

## 9. 必需验证

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如系统存在 `luac` 或 `texluac`，还必须检查全部 AddOn Lua 语法。交付前验证完整 ZIP 只有一个顶层根目录且内容干净。
