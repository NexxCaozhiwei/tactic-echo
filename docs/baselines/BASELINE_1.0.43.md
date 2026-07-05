# Tactic Echo 1.0.43 P4.6 基线：多行打断宏发现与 SpellID 关联韧性

## 目标

解决已存在于可见 Blizzard 默认动作条的同技能多行打断宏在实机中“正文语义正确、但动作条发现阶段没有交给解析器”的故障，而不改变任何输入边界。

典型形态：

```lua
#showtooltip
/stopcasting
/cast [@focus,nodead] 反制射击
/cleartarget
/targetenemy
/cast 反制射击
/targetlasttarget
```

## 固定合同

1. 动作条宏正文回收首先使用 `GetMacroInfo(actionInfoID)`；若首读只返回宏名称或正文为空，可顺序使用 `GetActionText(actionSlot)` 与该索引返回的宏名称，在现有账号/角色宏列表中查找正文。
2. 查找仅限当前可见默认动作条已指向的既有宏。不得按宏名称、图标、动作条位置或局部文本猜测技能。
3. `/cast` 动作令牌可通过 `C_Spell.GetSpellInfo(token)` 或兼容 API 只读解析为普通 SpellID。它仅解决“请求 SpellID 的本地化名称当下不可材料化”的关联问题；不评估宏条件、不改写宏、不创建 Token。
4. 仅缓存正向令牌→SpellID 结果；临时 API 空值不得形成会话级负缓存。
5. 自动资格仍要求：宏正文可回收、所有可执行施法动作均为同一请求技能、非 `/castsequence`、真实可见按钮、真实受支持键位，以及 P4.4 的严格可打断资格。P4.5 整合宏分支守卫不变。
6. 宏正文永不写入 SavedVariables、TEAP、TEK trace 或映射导出。诊断仅可记录查找路径、索引、宏名、正文长度和已解析 SpellID 令牌数量。

## 不变项

- 不新增/更改 BindingToken、TEAP v3 字段或 TEK 输入逻辑；
- 不创建/改写宏、不写绑定、不执行目标管理命令；
- AutoBurst、HUD CD、钢条判定及 P4.5 宏优先级守卫不变；
- 已有 P4.3 reaction TEK.exe 无需重新构建。

## 实机验收

见 `docs/P4.6_COUNTER_SHOT_MACRO_RECOVERY_TEST.md`。
