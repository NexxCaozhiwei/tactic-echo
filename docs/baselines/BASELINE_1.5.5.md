# Tactic Echo 1.5.5 基线

继承 1.5.4 的自动注入、窗口冷却重入与输入安全契约，本版本仅调整 HUD 展示。

- 冷却转盘以 SetSwipeColor 控制透明度，Cooldown 框保持不透明，避免原生倒计时随转盘变淡。
- 保留 Blizzard 原生 FontString 与 DurationObject 数字权威，将原生文字放入现有高层文字容器；切换文字来源或冷却隐藏时同步隐藏，避免残留与双数字。
- HUD 可见时，状态行常驻 HAD/LCC 模式与独立运行状态，采用较大字体和区分色；暂停、待命、引导、阻断不会覆盖模式标识。继续尊重 HUD 隐藏与状态行开关。
- 自动注入总开关关闭后仍显示当前专精已启用组的技能与冷却；清除展示层活动组身份，输出 DISPLAY_ONLY，不恢复执行高亮。
- 不更改唯一 Coordinator、OrderedPlan、运行期开关门控、脱战门控、BindingToken、TEAP 或 TEK；不新增轮询或输入路径。

本地验证：pytest 749 passed、7 skipped、17 subtests passed；TEK unittest 227 项通过，AddOn unittest 243 项通过；基线契约、52 个 Lua 文件语法与 Python compileall 均通过。原生文字层级、透明度及切换效果仍需游戏内 reload 验收。
