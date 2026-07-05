# Tactic Echo 1.0.54 P5.9 基线：控制、防御与生存宏兼容统一

## 变更范围

- **控制与防御宏来源贯通**：`TacticalAdvisors`、`AdvisoryPlanner` 与共享 HUD 状态层不再把 Resolver 已确认的宏来源降级为非可信动作条状态。卡片保留当前可见动作条槽位、`actionBarStateTrusted`、解析到的宏身份与相关技能等价信息，用于既有 CD/转盘展示和 HUD 的重新解析。
- **无键位宏可手动点击**：当前可见 Blizzard 默认动作条按钮或已识别宏即使没有标准快捷键、或其键位不属于 TEK 的 BindingToken 白名单，也可成为控制、防御与生存 HUD 的手动入口。其 `bindingToken` 始终为 `0`，因此不可能作为 TEAP/TEK 派发资格。
- **生存 `/use` 宏关联**：`MacroSemantics:MatchItem()` 与 `ActionBarBindingResolver:ResolveItem()` 采用和技能宏相同的宽松、只读语义策略，支持 ItemID、`item:ID`、本地化物品名、条件分支、多物品分支和 `/castsequence`。关联只在当前可见动作条宏按钮的已读取正文与请求物品语义精确相符时成立；宏名、图标和宏列表存在均不能单独作为来源。
- **控制路由边界不变**：P3/P4 的只读控制观察与未来自动路由仍按既有 target/focus/mouseover/cursor 分支规则工作。P5.9 只扩展 HUD 手动复用与显示来源，不评估宏分支、不改目标、不恢复自动控制或自动打断。

## 不变边界

- 自动打断保持可见但硬暂停；控制、防御与生存不新增 TEAP、TEK 或任何自动输入资格。
- HUD 仅以玩家真实左键通过既有 secure proxy 复用当前可见 Blizzard 默认动作条按钮/已识别宏；不创建按键、不调用程序化点击、不构造 spell/item secure action、不改写宏。
- 爆发序列、脱战 AutoBurst 硬门控、HUD 主键启停、CD 数字、DurationObject 转盘、标签与技能排序均不变。
- 每次版本化源码改动继续遵守 `docs/baselines/`、`CHANGELOG.md`、`VERSION`、TOC、`Core/Bootstrap.lua` 的同步更新规则。
