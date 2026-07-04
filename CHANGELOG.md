# 1.0.44 P5 — 宏身份锚定与同名宏防错配

- **取消宏名正文回收**：宏正文只允许通过当前动作条 `GetActionInfo` 返回的数值 `macroIndex` 回收；不再按 `GetMacroInfo(name)` 或账号/角色宏列表中的同名条目取正文。
- **有界同索引重读**：`GetMacroInfo(macroIndex)` 首读名称存在而正文为空时，仅对相同 numeric index 最多重读两次，覆盖客户端短暂正文空窗而不引入同名错配。
- **同名宏 fail-closed**：当前 index 无正文时，即使另一枚账号/角色同名宏引用 `反制射击`，也不能提供派发资格；诊断为 `macro_body_unavailable_action_info_id`。
- **诊断增强**：映射导出、面板与 `/temapping` 增加 macro identity source、动作条 macro index、读取次数、身份确认结果；不保存宏正文。
- **不变项**：P4.4 严格钢条、P4.5 宏分支守卫、P4.6 SpellID 令牌关联、BindingToken → TEAP → TEK 链均未修改；无需重建 TEK.exe。

# 1.0.43 P4.6 — 多行打断宏发现与 SpellID 关联韧性

- **修复宏正文回收后备**：当 `GetMacroInfo(actionInfoID)` 首读只给出宏名称而正文缺失时，解析器会继续使用动作条文本与该索引返回名称，从已有账号/角色宏列表回收同一宏正文；不再仅依赖 `GetActionText`。
- **新增 `/cast` 令牌 SpellID 关联**：宏内技能名称可只读查询为普通 SpellID。请求技能名称在当次 API 调用中不可材料化时，仍可安全关联已知的 `反制射击`（147362）等同技能多行宏；不依赖宏名称或图标猜测。
- **避免负缓存锁死**：名称/SpellID 临时读取失败不会写入会话级负缓存；下一次既有动作条失效/重建后可重新确认。
- **诊断增强**：P2 映射与 `/temapping` 增加宏正文回收来源、查找次数、动作条宏名与已解析 `/cast` SpellID 令牌数量；仍不保存宏正文。
- **不变项**：P4.4 严格钢条资格、P4.5 宏分支守卫、现有 BindingToken → TEAP → TEK 输入链与全部 Windows 门禁均未修改；无需重建 TEK.exe。

# 1.0.42 P4.5 — 受守卫的整合打断宏

- **修正整合宏解析**：`/cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 技能` 不再被误判为单一 `@mouseover` 宏；解析器保留全部条件块，并仅接受严格 `mouseover → focus → target` 单技能链。
- **新增 `macro_priority_chain` 路由元数据**：P2 对同一已有宏键位登记 mouseover、focus、target 三个来源及固定优先级；不创建 BindingToken、不编辑宏、不增加输入路径。
- **新增 P4 分支兼容性守卫**：focus/target 读条候选前，检查是否存在会先被宏命中的上游活敌单位；若存在，则记录 `macro_priority_preempted_by_mouseover/focus` 并 fail-closed。
- **未知链保持手动**：部分链、修饰键、战斗状态、混合条件、目标管理或多技能宏统一标记为 `macro_conditional_chain_opaque` / 既有不透明原因，不再把首个条件分支误升格为自动路由。
- **保留 P4.4 与 P4.3 所有动作链保障**：严格钢条证据、稳定 candidate、stable sequence 与 TEK reaction dedupe 均未改变。

# 1.0.41 P4.4 — 严格钢条判定与原生视觉复核

- **取消 P4.3 探测例外**：删除 `probe_active_cast_ignore_steel`。读条存在但不具备可打断证据时，恢复为 `interruptibility_unconfirmed`，只高亮、不派发。
- **修正 `showShield` 误用**：该字段及 `barType` 仅保留为诊断，不再作为当前读条的钢条或可打断结论。
- **真实盾组件判定**：读取 `BorderShield` / 等价子组件的实际 `IsShown()` / `IsVisible()` 状态；可见盾为硬否决，明确无盾可作为视觉证据。
- **视觉防抖**：原生无盾或原生 explicit-false 路径必须在同一读条连续两次 P3 样本中一致，才可派发；直接 API 与单位施法事件不受此等待影响。
- **事件身份保留**：`ReactionInterruptEvents` 的 status 事件不再以 nil 覆盖 START 事件中已取得的 spellID/castGUID，避免削弱 stale-event mismatch 防线。
- **保留 P4.3 可靠性交付修复**：reaction candidate 仍稳定保留到读条结束；SignalFrame 保持同 sequence；TEK 继续按稳定 reaction sequence 成功后去重。
- **诊断增强**：面板显示真实盾组件来源、原生证据以及视觉采样 `1/2`、`2/2`。

# 1.0.40 P4.3 — 自动打断动作链探测与稳定投递（历史）

- P4.3 已确认现有 BindingToken → TEAP reaction → TEK → 游戏内打断动作链可达。
- P4.4 已替代其临时“忽略钢条”探测资格；P4.3 不再作为正式判定策略。
