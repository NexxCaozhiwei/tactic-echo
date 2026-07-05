# Tactic Echo 1.0.52 P5.7 基线：HUD 手动点击与自动打断暂停

## 变更范围

- 自动打断设计暂停：`autoReaction.interrupt.enabled` 被 Normalize 强制为 `false`，同时写入 `suspended=true` 与 `auto_interrupt_suspended`。`AutoReaction:Evaluate()` 在扫描目标、路由、冷却和候选交付之前直接返回；不会形成 reaction candidate、BindingToken、TEAP reaction 标记或 TEK 自动打断请求。
- 打断提示、钢条/可打断观察、原有 HUD 高亮保留为只读能力。
- 主 HUD 图标左键复用既有 `ControlPanel:ToggleRun()`，因此保持原来的启动/暂停状态机。
- 爆发、打断、控制、防御/生存卡片左键只通过静态 `SecureActionButtonTemplate` 代理一个已验证的、当前可见的暴雪默认动作条按钮。来源可为直接技能/物品按钮，或 Resolver 已识别的现有宏。不会新建快捷键、修改宏、构造 spell/item 动作、选择或切换目标。
- 没有可靠来源、特殊动作条、按钮不可见，或战斗中动作条来源发生变化时，HUD 卡片保持显示但由透明阻断层拦截左键，并提示具体原因；战斗中绝不重定向 secure proxy。
- HUD 左键和原生默认动作条左键均触发短暂 `manual_hold`。SignalFrame 清除动作码与 BindingToken，因此该人工点击优先于已排队的 Burst/Reaction/官方派发；TEK 继续使用既有 `manual_hold` 门禁。

## 不变边界

- AutoBurst 顺序、主推荐、CD 数字、DurationObject 转盘、来源标签、技能排序和已有宏兼容策略均未改写。
- TEK/Windows 输入实现未修改，不需要重建 `TEK.exe`。
