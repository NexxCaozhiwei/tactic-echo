# 1.1.7 实机验收

先执行 `docs/P5.11_SHARED_MACRO_POLICY_TEST.md`，并保留 P5.10 当前动作栏身份、P5.8 脱战 Burst、自动打断暂停与 HUD 基础点击验证。

1. 用猎人 `[@cursor] 冰冻陷阱` 宏验证当前 `CTRL+1` 精确来源；同时保留 `CTRL+2` 的同技能按钮，确认 HUD 不会跨槽位替代。
2. 在控制诊断中确认无关 `BUTTON3` / “坐骑”宏没有被列为胁迫或冰冻陷阱候选；若同一 CTRL+1 有效 index 正文暂不可读，只有该当前按钮可显示失败记录，仍不得执行。
3. 验证 action-info 代表 SpellID 不能单独通过：正文不含请求技能、或两个允许标签指向不同可匹配宏时，分别应报告语义失配/歧义并阻断。
4. 回归控制、防御、生存已有宏（含 `/use`、条件、`@focus`、`@mouseover`、`@cursor`、目标管理和 `/castsequence`）：只允许正文已验证的当前宏成为 HUD 手动来源，且 BindingToken 恒为 0。
5. 验证 `/use item:5512` 等生存物品宏只在当前身份与正文精确 Item 语义都确认时可被 HUD 复用；宏名/图标/列表不能建立来源。
6. 隐藏来源、切换特殊动作条或在战斗中改变来源时，HUD 必须 fail-closed；脱战重新映射后才可恢复，且战斗中不得再出现 `HudClickRouter.lua` 触发的 `ADDON_ACTION_BLOCKED UNKNOWN()`。
7. 战斗中调整 HUD 缩放、脱战淡化缩放、防御栏分离/缩放或布局预设时，HUD 可以延迟到脱战后应用新布局，但不得出现 `TacticEchoTacticalBoard:SetScale()` 或布局 API 的 `ADDON_ACTION_BLOCKED`。
8. 战斗中切换防御卡显示、HUD 隐藏/显示、空闲隐藏或安全 fallback 时，不得出现 `TacticEchoDefenseBoard:SetShown()`、`Show()` 或 `Hide()` 的 `ADDON_ACTION_BLOCKED`。
9. 按键按下即施放开启、关闭均测试；HUD 与原生默认动作条左键均应写入 `manual_hold`，动作码/BindingToken 为 0，优先于后续派发。
10. 回归 P5.8：自动打断仍为 `auto_interrupt_suspended`；任何脱战帧不得产生 Burst plan/capture/TEAP/TEK；主键启停、CD 数字、DurationObject 转盘、状态/来源标签、爆发顺序和 HUD 排序不得变化。

当前版本：`1.1.7`
