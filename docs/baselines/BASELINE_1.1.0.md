# Tactic Echo 1.1.0 基线：审计收口、自动打断硬暂停与共享宏资格冻结

## 审计结论

- **自动打断仍为生产硬暂停**：`AutoReaction` 运行时、Defaults 与 SavedVariables Normalize 均强制 `auto_interrupt_suspended`。读条、钢条、事件、冷却与路由证据只可服务于只读提示、高亮、诊断和 HUD 人工点击；不得生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- **脱战 Burst 硬门控仍有效**：任何 `inCombat=false` 帧必须在规则预检、capture 恢复、计划创建和候选材料化前返回 `none`，并清除遗留 plan/capture。`Run`、官方窗口、切图、旧 bridge 字段或 SavedVariables 均不得恢复脱战 Burst 派发。
- **HUD 人工点击优先**：HUD secure proxy 与原生默认动作条真实左键必须先进入 `manual_hold`，SignalFrame 在让权窗口内输出动作码 0、BindingToken 0。
- **HUD 冷却只展示不授权**：DurationObject 只用于视觉转盘；HUD 徽标数字只取安全标量。任何 HUD CD、Tooltip、图标灰度或视觉层信息不得反馈到 AutoBurst、BindingToken、TEAP 或 TEK。

## 当前宏资格规则

- **唯一常规身份入口**：任何常规宏来源必须先通过 `ActionBarBindingResolver:IsVerifiedCurrentMacroSource()`。该规则同时被 AutoBurst、Reaction 的已解析宏路由、控制、防御、生存 HUD 手动展示与 HUD secure proxy 复核使用。
- **当前按钮事实优先**：身份仍以当前可见 Blizzard 默认动作条的 `buttonName + actionSlot` 与实时 API 为唯一事实。有效 numeric macro index 只读取同一 index；非 index 的 Retail 形态必须由 `GetActionText` 和/或 action-info handle 只读名称、代表 SpellID 与唯一正文语义共同确认。
- **已验证后保留既有语义**：已确认身份的玩家宏可继续使用 `/cast`、`/use`、条件分支、`@focus`、`@mouseover`、`@cursor`、目标管理辅助命令及 `/castsequence`。TE 不评估或改写分支；控制、防御、生存只复用原按钮作为手动 HUD 入口，`bindingToken=0`。
- **物品宏**：生存 `/use` 宏必须由同一已验证正文与精确 ItemID、`item:ID` 或本地化物品名关联；不能以宏名、图标或宏列表猜测。
- **AutoBurst 更严**：AutoBurst 只接受身份已验证、正文关联为 `macro_body_*` / `macro_inventory_*` 且 `MacroSemantics.autoBurstEligible=true` 的当前宏来源。P4 opaque action-info 兼容不具备 AutoBurst 资格。
- **P4 例外隔离**：正文/索引不可读时，`action_info_represented_spell` / `action_info_macro_spell` 仅可在当前可见默认动作条存在真实 nonzero BindingToken 的前提下作为 reaction target-only transport。不得推断 focus/mouseover/cursor；不得成为 HUD、控制、防御、生存或 AutoBurst 来源。

## 控制诊断规则

- 诊断必须请求作用域化：只显示具有请求 SpellID 明确证据的当前宏失败。
- 当同一有效 numeric macro index 的当前动作条文本明确包含请求技能名、但同 index 正文暂不可读时，可显示该**同一按钮**的只读失败记录，便于定位当前宏状态；该记录不授权映射、不触发跨宏扫描。
- 与请求无关的宏，例如 `BUTTON3` / 槽位 72 的“坐骑”，不得显示在胁迫、冰冻陷阱或任何其他控制技能的未匹配候选中。

## 硬边界

- 不调用 `GetMacroInfo(name)`；不按名称取第一枚；不持久化宏正文；身份歧义、正文失配、来源变化均 fail-closed。
- HUD 不创建按键、不改宏、不改目标、不调用 `Button:Click()`；只可经 static secure proxy 指向已经验证的当前原生按钮。
- 自动打断继续硬暂停；AutoBurst 任何脱战帧都不得创建或保留 plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。

## 验收

- `docs/P5.11_SHARED_MACRO_POLICY_TEST.md`
- `docs/P5.8_HUD_MANUAL_CLICK_AND_OOC_GATE_TEST.md`
- `tests/unit/test_p511_shared_macro_policy.py`
- `tests/unit/test_p511_hunter_control_macro_identity.py`
- `tests/unit/test_p510_current_actionbar_macro_identity.py`
- `tests/unit/test_p57_hud_manual_click_and_auto_interrupt_suspend.py`
