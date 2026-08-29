# Tactic Echo 1.4.11 基线

`1.4.11` 修复复仇之怒等天赋/覆盖技能的当前动作条实际冷却已缩短、声明 SpellID 或 Tracker 仍残留旧基础时长时，HUD 错误显示 `120` 秒的问题。

## 可信动作槽 opaque 数值

- 当前已验证直接默认动作槽若明确 `isActive=true`、`isOnGCD=false`，仍构成技能自身冷却的只读语义证据。
- 完整 HUD 与 cooldown-only 路径都必须通过显式赋值保留 `isOnGCD=false`，不得使用会把 false 折为 nil 的 Lua `and/or` 写法。
- 若同一动作槽没有同时给出可安全材料化的 start/duration，必须清除此前来自声明 SpellID、基础技能或 Tracker 的 remaining/duration/start，不得把旧 `120s` 显示为当前动作的真实数字。
- 该状态保持 `cooldownActive=true`，允许客户端 DurationObject 继续绘制原生转盘；HUD 纯秒数徽标保持隐藏，直到同一可信动作槽提供安全普通数值。
- 若动作槽明确给出安全数值，例如复仇之怒当前实际 `60s`，继续由 `actionbar_numeric` 覆盖并显示真实纯秒数。

## 不变边界

- opaque 自身 CD 仍是 AutoBurst 冷却 veto，不得因清除显示数值而解释为 ready。
- 1.4.10 多充能技能 DurationObject 恢复环与普通 `1/1` 隐藏规则保持不变。
- 不接入 Cooldown Manager，不改变推荐、BindingToken、TEAP、TEK、步骤确认或任何输入派发资格。
