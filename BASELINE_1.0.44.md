# Tactic Echo 1.0.44 P5 基线：宏身份锚定与同名宏防错配

## 目标

修复 P4.6 的宏正文恢复把“宏名”当作身份键的缺陷。账号宏与角色宏允许同名，中文名（例如“打断”）尤其容易重复；按名称取回正文可能取得另一枚同名宏，导致已绑定的 `反制射击` 宏被误判、错配或 fail-open。

P5 将宏身份收紧为：

```text
当前可见 Blizzard 默认动作条槽位
→ GetActionInfo(actionSlot) 返回的数值 macroIndex
→ 仅对同一 macroIndex 读取宏正文（首读 + 有界重读）
→ 宏正文 / SpellID 语义确认
→ 原有 BindingToken 路由
```

## 固定合同

1. **数值 `actionInfoID` 是唯一宏身份。** `GetActionInfo(actionSlot)` 返回的 macro index 是正文恢复唯一允许的键；宏名、图标、动作条文本、动作条位置及局部文本都不能用于取得另一枚宏正文。
2. 当 `GetMacroInfo(macroIndex)` 首读仅给出名称但正文为空时，只允许在当前事件驱动扫描内对**相同 numeric macroIndex**最多重读两次；不使用 `GetMacroInfo(name)`，不枚举账号/角色宏按名称查找。
3. 同名宏无法由当前 macro index 取回正文时必须 fail-closed：`bindingToken=0`，原因保留为 `macro_body_unavailable`，诊断写明 `macro_body_unavailable_action_info_id`。即使另一枚同名宏包含请求技能，也不得借用其正文。
4. `/cast` 令牌 → SpellID 的只读关联保持；它解决本地化名称暂未材料化，不改变宏身份锚点。
5. 宏正文仍不得写入 SavedVariables、TEAP、TEK trace 或映射导出。仅导出 macro index、身份来源、读次数、正文长度、语义计数与失败原因。

## 不变项

- 不修改 TEK、BindingToken、TEAP、SendInput、钢条判定、P4.5 分支守卫或宏自身执行顺序；
- 不创建/编辑宏，不写绑定，不自动选择目标；
- 仍只读取玩家当前可见 Blizzard 默认动作条；
- 已具备 P4.3 reaction 去重的 TEK.exe 无需重新构建。

## 实机验收

见 `docs/P5_MACRO_IDENTITY_TEST.md`。
