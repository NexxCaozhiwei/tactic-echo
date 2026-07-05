# Tactic Echo 项目上下文 — 1.1.0

- 当前唯一基线：`1.1.0`；版本基线统一位于 `docs/baselines/`，每次版本化源码改动必须同步更新该目录下对应 baseline、根目录 `CHANGELOG.md`、`VERSION`、TOC 和 `Core/Bootstrap.lua`。
- 自动打断设计处于硬暂停：Defaults、Normalize 和 `AutoReaction:Evaluate()` 共同保证旧 SavedVariables 也不能产生 `reaction candidate`、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- `ReactionObservation`、`ReactionInterruptEvents`、P2 动作条/宏识别与 P3 HUD 打断提示仍为只读能力；不应由这些证据重新开启自动派发。
- AutoBurst 不允许任何脱战例外：`inCombat=false` 时必须清理残留 plan/capture 并返回空结果；`SignalFrame:SetState("armed")`、`Run`、切图和首次进战都不能建立或续接 pre-combat bridge，更不能产生 Burst TEAP/TEK 派发。
- 主 HUD 左键复用既有 `ToggleRun()`；爆发、打断、控制、防御/生存 HUD 图标只可通过 `HudClickRouter` 的静态 secure proxy 复用可靠、可见的暴雪默认动作条按钮或已识别宏。proxy 同时支持 `LeftButtonDown`/`LeftButtonUp`，以兼容 `ActionButtonUseKeyDown`。
- HUD 和原生默认动作条的真实左键会进入短暂 `manual_hold`，动作码与 BindingToken 为 0，优先于 TEAP/TEK 的后续派发。13/14 槽物品卡优先使用对应装备槽位的真实来源。
- 战斗中映射发生变化、来源缺失、按钮隐藏或处于特殊动作条时必须 fail-closed；不得直接 `Button:Click()`、新建绑定、写宏或重定向目标。
- 1.1.0 共享宏资格：AutoBurst、P4 Reaction 常规宏、控制、防御、生存 HUD 统一调用 Resolver 的当前动作栏身份规则；有效 index 只同 index 有界读取，非 index 恢复仍需动作条/handle 只读名称、代表 SpellID 与唯一正文语义。已验证宏继续兼容 `/cast`、`/use`、条件、`@focus`/`@mouseover`/`@cursor`、目标管理与 `/castsequence`，但控制、防御、生存始终 `BindingToken=0`、仅手动 HUD；AutoBurst 只接受正文关联且语义允许的来源。P4 opaque action-info 仍仅 target-only reaction transport。
- 1.1.0 诊断请求作用域化：无关 `BUTTON3` / “坐骑”宏不得显示为胁迫、冰冻陷阱等控制技能候选；若同一有效 index 的当前按钮正文暂不可读且动作条文本命名请求技能，仅显示该同一按钮失败记录，不授权扫描或替代。
- 主推荐、CD 数字、DurationObject 转盘、标签、技能排序及既有宏兼容策略保持不变。
