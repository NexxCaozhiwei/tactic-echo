# Tactic Echo 1.0.55 P5.10 基线：当前动作栏宏身份与 HUD 精确来源

## 变更范围

- **当前动作栏优先**：宏身份只以当前可见 Blizzard 默认动作条按钮、其 actionSlot 与当前 API 返回为事实。此前 SavedVariables、旧扫描缓存、宏列表存在、宏名、图标或其他同技能槽位均不是当前卡片来源。
- **有效 numeric index**：`GetActionInfo(actionSlot).id` 位于当前账号/角色宏有效 numeric index 范围时，只允许对同一 index 执行有界 `GetMacroInfo(index)` 读取。正文不可用、名称不一致或同 index 验证失败时立即保留失败；禁止扫描、恢复或替代其它宏 index。
- **代表 SpellID 唯一恢复**：仅当 action-info 数值不在有效 macro index 范围时，可使用动作条 `GetActionText` 和/或 action-info handle 的只读名称作为 join 标签。恢复必须同时满足：当前代表 SpellID、唯一真实 macro index、该 index 的已读取正文解析语义明确引用请求技能。`GetMacroSpell` 不能单独验证正文或宏身份。
- **冰冻陷阱 `CTRL+1`**：`[@cursor] 冰冻陷阱` 宏可由 action-info handle 宏名与正文语义唯一确认，即使 `GetActionText` 显示的是技能名。控制卡记录原 `buttonName + actionSlot + source + macroID + 语义身份`，HUD 只复用该按钮；同技能在 `CTRL+2` 或原槽位被替换时不能接管点击。
- **P4 例外**：正文/索引不可读的 action-info 代表技能兼容仅面向 P4 reaction target transport。登记前必须确认当前可见默认动作条按钮、所请求打断技能和真实 nonzero BindingToken。此兼容没有宏正文语义，不得成为 HUD 手动来源，不能推断 focus/mouseover/cursor，也不能作为 AutoBurst 授权。

## 硬边界

- 不调用 `GetMacroInfo(name)`；不按名称选择第一枚宏；不从宏名、图标、列表或历史缓存推断当前动作栏身份。
- 宏正文只能保留在当前运行时解析所需的临时内存中，不写入 SavedVariables、映射导出或版本文档。
- `macro_semantic_identity_ambiguous`、`macro_semantic_identity_no_spell_match`、`manual_macro_identity_unverified` 与 `manual_actionbar_source_changed` 必须 fail-closed。
- HUD 不创建快捷键、不更改宏、不调用程序化点击、不改变目标或宏分支；点击只通过 static secure proxy 指向当前可靠的原 Blizzard 按钮。
- 自动打断继续硬暂停；任何 P4 历史 transport 都不得恢复 reaction candidate、TEAP reaction 或 TEK 自动派发。AutoBurst 继续只允许战斗内运行，任何脱战帧不得建立或保留 plan/capture。

## 验收

- `docs/P5.10_CURRENT_ACTIONBAR_MACRO_IDENTITY_TEST.md`
- `tests/unit/test_p510_current_actionbar_macro_identity.py`
- 继续执行 P5.8 HUD 点击、脱战 AutoBurst 和自动打断硬暂停回归。
