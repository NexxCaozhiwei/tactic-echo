# Tactic Echo 1.4.4 基线：HUD 冷却与充能真实性

## 基线结论

`1.4.4` 修复 HUD 冷却单位混用、全局冷却事件无法校正 tracker、普通技能错误显示 `1/1` 以及等效技能身份残留旧充能状态的问题。HUD 数字继续只读取安全普通标量，Blizzard `DurationObject` 继续只负责转盘。

## 冷却冻结行为

- `GetSpellBaseCooldown()` 的返回值固定按毫秒在调用边界转换为秒；`C_Spell.GetSpellCooldown()`、动作条、Tooltip、充能 recharge 和 tracker 内部值固定按秒处理，不得再用数值大小猜测单位。
- 转换后不超过 `2.5s` 的静态基础时长不得启动 HUD 自身 CD 兜底；奥术弹幕等无自身 CD 技能不得把 `500ms` 公共时序显示为 `500s`。
- `SPELL_UPDATE_COOLDOWN` 按全局失效事件处理，不依赖事件参数中的 SpellID。只重新检查当前活跃 tracker 条目：可读实时自身 CD 覆盖本地兜底，明确非 GCD 就绪清除兜底，未知/受保护值不伪造结论。
- 原生 `DurationObject` 仍只绘制转盘。HUD 徽标仍只显示 `IconState`/Tracker 已确认的普通数值并向上取整；没有安全数字时隐藏徽标，不读取 DurationObject 数字。

## 充能冻结行为

- 只有当前 `maxCharges > 1` 的技能才是充能技能。`1/1` 属于普通 CD 语义，不得进入 IconState、HUD 充能文字、Tooltip 或充能边框。
- tracker 只有在当前技能或其等效身份返回可读 `maxCharges` 时更新资格：任一当前身份仍明确为多充能则保留；全部当前身份都返回可读且均不大于一时才清除旧充能；任一身份未知/受保护时保留最后确认状态但不得伪造新数量。
- 当前充能数不可读时不得默认等于最大充能。只有可读当前值才能建立新的 tracker 计数，且数值必须收敛到 `0..maxCharges`。
- 物品堆叠数量继续使用独立 `itemCount` 标签，不得被技能充能过滤影响。
- AutoBurst 仍只以 `maxCharges > 1` 的真实多充能变化作为可用性或确认辅助；`1/1` 和已明确失效的陈旧 tracker 状态不得改变自动注入计划。

## 协议与验证

- 未修改 BindingToken、TEAP v3 20 字节、Burst flags `0x20`、TEK、宏资格、脱战硬门控、自动注入组协调器或 OrderedPlan 顺序。
- 必须运行 HUD 冷却/充能行为测试、IconState 与 cooldown tracker 聚焦测试、AutoBurst 行为测试、基线契约、完整 pytest、全部 AddOn Lua 语法检查及 Python compileall。
- 实机需验证：奥术弹幕不显示自身 CD；普通 CD 技能不显示 `1/1`；真实两充能技能正确显示 `2/2 → 1/2 → 2/2`；长 CD 技能的 HUD 数字与默认动作条同步校正。

## 文档治理

- 当前 README、架构、自动注入、测试、项目上下文、交接、任务与项目管理文档统一以 1.4.4 和当前加载范围为准。
- 旧 P4/P5 Reaction/自动打断测试与战术/环境专题已移入 `docs/archive/`；归档内容只用于历史追溯，不得恢复退役模块或扩大输入权限。
