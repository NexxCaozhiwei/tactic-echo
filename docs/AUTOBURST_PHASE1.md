# 自动爆发：可排序多步骤序列

版本：`1.0.26`  
状态：已接入；需继续 WoW + Windows 实机覆盖各职业专精、真实动作条和 TEK 门禁。

## 目标

AutoBurst 只会把当前计划的**下一步**作为 Burst 候选，经既有 BindingToken → TEAP v3 → TEK 全部门禁派发。它不会修改官方推荐、宏、动作条绑定或 TEK 的全局输入频率。

```text
官方窗口出现
→ 当前专精 sequence 预检
→ 过滤不可用可选步骤
→ 有序 Burst plan
→ 每步实时复核与确认
→ 窗口离开观察锁
```

## 当前专精的顺序模型

每个专精独立保存以下逻辑步骤：

```text
窗口技能（固定、不可停用）
注入技能 1（来自下方注入技能列表）
注入技能 2（来自下方注入技能列表）
注入技能 3（来自下方注入技能列表）
饰品 13
饰品 14
```

- 注入最多 3 个，引用该专精下方“注入技能”列表中已启用的前 3 个 SpellID。
- 上方顺序只控制启用/停用/位置；要改 SpellID，必须在下方注入技能列表改。
- 持久化按 `injection:<SpellID>`、`trinket:13`、`trinket:14` 保存，切换专精不会把旧第 N 槽错误映射到新技能。
- 饰品计划创建时锁定实际 ItemID；未装备、绑定无效、装备变化均不入队或会在运行期失效。

示例：

```text
饰品13 → 饰品14 → 注入技能1 → 窗口
饰品13 → 窗口 → 注入技能1
窗口 → 注入技能1 → 饰品14
```

## 组装模式与 CD / GCD

### 简易

窗口出现时，逐项读取真实绑定和冷却：

- 处于自身 CD、冷却 UNKNOWN、无绑定、未装备、装备身份异常：排除该可选步骤。
- `READY_NOW`、`QUEUE_WINDOW`、`GCD_LOCKED`：保留为可用步骤。
- 所有可选步骤均被排除：不创建计划，官方窗口走普通官方流程。
- 保留下来的步骤严格保持你设置的相对顺序。

### 集中

任一已启用可选步骤不可用，即本轮不创建计划。官方窗口不被 Burst 接管。

### 重要边界

- 公共 GCD 不是技能/饰品自身 CD；不能导致预检排除、跳过或确认。
- 图标灰色、Buff、失败事件、资源、目标、距离、普通动作条阴影都不是自身 CD 证据。
- 计划创建后，当前可选步骤如果变为自身 CD 或 UNKNOWN：简易跳过该步骤继续；集中在窗口未派发前释放官方窗口，在窗口已派发后保持离开锁。

## Handoff 与起手

若实际筛选后第一步在窗口之前：

```text
窗口
→ 4 个 observation-only transport handoff hold
→ 第一个前置步骤
→ 后续顺序步骤
```

- `paused → armed` 的事件刷新不消耗 handoff 帧；只有正常 transport tick 计数。
- 已 arm 的前置顺序可在受控条件下跨越脱战→进战；普通脱战官方推荐仍不可派发。
- 若窗口排在第一位，不会创建起手 bridge，也不会扩大普通脱战派发权限。

## 饰品 GCD 选项

饰品 13/14 默认遵循普通 GCDGate。只有用户已实测确认该饰品不触发公共 GCD 时，才可在爆发页勾选“已确认脱 GCD”。系统不会根据物品类型、说明、图标或宏猜测脱 GCD。

## 诊断

`/teab status` 用于查看当前专精的解析顺序和自动爆发状态；`/temapping autoburst_105` 会导出关键摘要。

重点字段：

```text
sequence_preflight_selected / sequence_preflight_no_eligible
selectedOrder / excludedOrder
sequenceLength / sequenceKeys
handoffBarrierRequiredFrames / Remaining / Published
currentStep / currentRole
preCombatBridge
```

## 实机测试矩阵

1. 单注入前置、窗口、后置各一次。
2. 3 注入 + 双饰品混合顺序，确认每步严格按 UI 顺序。
3. 简易模式：一个注入自身 CD，确认仅排除该步骤且窗口/其它步骤仍按顺序。
4. 简易模式：全部可选步骤 CD，确认不建计划且不尝试任何注入。
5. 集中模式：任一启用步骤 CD，确认不建计划。
6. 共享 GCD，确认步骤仍可进入候选而不是被当 CD 排除。
7. 计划运行中技能转 CD / UNKNOWN，分别验证简易跳过与集中释放/锁定行为。
8. 饰品 13/14：未装备、无绑定、换装、实际自身 CD、已确认脱 GCD。
9. 前置首轮：paused→armed、4 帧 hold、脱战 bridge→进战后保留计划。
10. 专精切换后检查顺序、启用状态和注入 SpellID 无错位。
