# Tactic Echo 当前维护提示

你正在维护 `tactic-echo` 当前基线 `1.4.4`。

开始工作前按以下顺序读取：

1. `AGENTS.md` 与用户当次明确指令；
2. `docs/baselines/BASELINE_1.4.4.md`；
3. `PROJECT_CONTEXT.md`、`HANDOFF.md`、`TASKS.md`、`DECISIONS.md`；
4. 与任务直接相关的当前源码、测试和 `docs/` 专题文档。

不要把 `docs/archive/`、历史 baseline、patch manifest、旧 SavedVariables 或旧宏缓存当作当前实现授权。若历史文档与 `AGENTS.md` 或当前 baseline 冲突，以当前规则为准。

当前产品范围只保留：首页/设置中心、HUD 主键、官方主推荐输入链路，以及最多三个自动注入组。打断、控制、防御、生存、TargetCastPrompt、姓名板群控扫描、反应高亮、监控/调试页、MappingExport 与 OfficialApiProbe 已退役；未经用户明确扩大范围，不得恢复加载、轮询、展示或派发。

任何自动注入修改都必须保持：

- 官方推荐不可变；
- AutoBurst 只产生受控候选；
- 当前动作条/宏身份经共享 resolver 验证；
- BindingToken → TEAP v3 → TEK 是唯一输入路径；
- 每帧最多一个 BindingToken；
- 脱战清除 plan/capture 且不产生 Burst candidate；
- HUD、Tooltip、转盘和诊断不建立派发权限；
- 步骤只由精确成功事件、自身非 GCD CD 或真实多充能减少确认。

修改前先读代码和现有测试；修改后运行与风险相称的聚焦测试、完整测试、基线合同、Lua 语法检查和 Python compileall。离线验证不能证明 Windows Hook、前台判断、真实 SendInput、SpellQueueWindow、宏分支或 WoW 实机顺序。

版本化源码改动必须同步 `VERSION`、TOC、`Core/Bootstrap.lua`、`CHANGELOG.md` 和 `docs/baselines/BASELINE_<VERSION>.md`。部署时使用项目约定的同步流程，并核对 live TOC 与代表性 SHA256。
