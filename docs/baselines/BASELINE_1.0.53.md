# Tactic Echo 1.0.53 P5.8 基线：HUD 点击修复、脱战爆发硬门控与基线归档规范

## 变更范围

- **脱战自动爆发硬门控**：`AutoBurst:Evaluate()` 在任何脱战帧、任何规则预检、捕获恢复、计划创建和候选材料化之前直接返回 `none`。若内存中残留旧版 `plan` 或 `preWindowCapture`，会以 `out_of_combat` 清除；不会生成 Burst candidate、TEAP Burst 帧或 TEK 派发。
- **取消 pre-combat bridge 授权**：`SignalFrame:SetState("armed")` 不再为 AutoBurst 授权脱战起手；`AuthorizePreCombatBridge()` 仅保留为兼容诊断 no-op。`PLAYER_REGEN_DISABLED` 总是从干净 encounter epoch 开始，不会接续脱战计划或 capture。
- **HUD 人工点击修复**：爆发、打断、控制、防御/生存卡的 secure proxy 同时注册 `LeftButtonDown` 与 `LeftButtonUp`，兼容客户端 `ActionButtonUseKeyDown`。代理与阻断层固定在 `HIGH` 输入层并保持 UIParent sibling 结构；仍只在玩家真实左键时点击既有可见 Blizzard 默认动作条按钮或已识别宏。
- **阻断反馈**：无可靠来源时 blocker 同时覆盖按下/抬起点击并在按下阶段报告具体不可用原因；HUD 图标本身仍显示。
- **饰品来源精确性**：13/14 槽 HUD 卡优先按装备槽位解析已有动作条按钮或 `/use 13`、`/use 14` 宏，再考虑 spell/item 身份，避免同物品、共享效果或重复来源错配。
- **文档归档规范**：全部版本基线统一存放于 `docs/baselines/`；根目录不再保留 `BASELINE_*.md`。每个版本必须同时有对应 baseline 与根目录 `CHANGELOG.md` 条目。

## 不变边界

- 自动打断继续可见但硬暂停；只读打断观察、高亮与诊断不受影响。
- HUD 主键仍使用既有 `ControlPanel:ToggleRun()`；HUD 与原生默认动作条的真实左键均写入既有 `manual_hold`，从而先于 TEAP/TEK 的后续自动派发。
- 不创建按键、不修改或替换宏、不构造 spell/item secure action、不改变目标、不修改 CD 数字、DurationObject 转盘、标签、爆发排序或既有宏兼容策略。
- TEK/Windows 输入实现未变，不需要重建 `TEK.exe`。
