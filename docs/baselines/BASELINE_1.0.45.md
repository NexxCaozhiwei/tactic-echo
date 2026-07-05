# Tactic Echo 1.0.45 P5.1 基线：宏动作身份与唯一语义回收

## 问题与修复范围

P5 假设 `GetActionInfo(actionSlot).id` 对宏始终是宏列表 numeric index。实机 SavedVariables 已证明该假设不成立：反制射击宏所在的可见动作条槽位返回：

```text
actionType = macro
actionInfoId = 147362
actionText = 反射
```

其中 `147362` 是反制射击的 SpellID，而不是当前宏列表 index。P5 调用 `GetMacroInfo(147362)` 必然无法取得宏正文。

P5.1 仅修正宏正文发现与身份确认；不改宏、动作条、目标、BindingToken、TEAP、TEK 或输入派发。

## P5.1 身份规则

1. 读取当前可见动作条的 `GetActionInfo(actionSlot)`、`GetActionText(actionSlot)`。
2. 若 `id` 位于当前 `GetNumMacros()` 声明的账号/角色宏 index 范围，仅可读取该同一 index；允许有界重读。
3. 若 `id` 不在当前有效宏 index 范围，将其视为动作条代表 SpellID。
4. 代表 SpellID 路径只读枚举当前宏列表。候选必须同时满足：
   - 宏名与 `GetActionText(actionSlot)` 精确一致；
   - `GetMacroSpell(index)` 或解析后的 `/cast` 语义命中代表 SpellID；
   - 全部候选中仅有一枚满足。
5. 匹配零枚、宏名缺失、宏列表不可读或多枚同时命中，一律 `bindingToken=0` / fail-closed。

## 不允许的回退

- 不调用 `GetMacroInfo(name)`；
- 不按名称取第一枚宏；
- 不使用图标、宏名或技能名称猜测派发资格；
- 不在多个同名同技能候选中选择账号宏或角色宏优先级；
- 不保存宏正文。

## 诊断

宏映射应可导出：

```text
actionInfoValue
actionInfoLooksLikeMacroIndex
representedSpellID
representedSpellSource
macroIdentitySource
actionTextCandidateCount
semanticCandidateCount
semanticCandidateIndexes
failureReason
```

宏正文不得写入 SavedVariables。

## 既有保障

P4.4 严格钢条证据、P4.5 整合宏优先级守卫、P4.6 `/cast` token→SpellID 关联、P4.3 reaction 稳定候选/TEK 去重均保持不变。
