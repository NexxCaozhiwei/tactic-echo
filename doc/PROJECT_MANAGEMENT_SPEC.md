# 项目管理规范

本规范用于 Tactic Echo `1.4.4` 及后续版本的需求、实现、验证和交付管理。

## 版本治理

- 当前唯一开发基线为 `1.4.4`。
- 每次版本化源码修改必须保持根目录 `VERSION`、AddOn TOC、`addon/!TacticEcho/Core/Bootstrap.lua` 一致，并同步 `CHANGELOG.md` 与 `docs/baselines/BASELINE_<VERSION>.md`。
- 旧版本文档、patch manifest 和归档测试只能作为历史证据，不能恢复旧字段、旧模块或旧派发路径。
- 当前文档应描述当前源码；发现版本、范围或安全边界漂移时，应先修正文档或明确记录待办。

## 当前范围

当前产品只保留：首页/设置中心、HUD 主键、官方主推荐输入链路，以及最多三个自动注入组。打断、控制、防御、生存、TargetCastPrompt、姓名板群控扫描、反应高亮、监控/调试页、MappingExport 与 OfficialApiProbe 均为退役功能。重新引入任何退役能力都属于范围扩大，必须先获得用户明确确认并重新审计输入和性能边界。

## 变更分类

- 安全边界变更：BindingToken、TEAP/TEK、SendInput、Hook、前台、限频、手动让权、宏身份、AutoBurst、Coordinator 和脱战门控。必须 fail-closed 并补合同测试。
- 展示层变更：HUD、转盘、数字徽标、充能、设置页和诊断。不得反馈到推荐、候选或派发资格。
- 数据模型变更：SavedVariables、注入组、稳定步骤键、sequence、Trace/status schema。必须提供幂等迁移，并避免保存宏正文、受保护值或敏感数据。
- 文档/交付变更：README、CHANGELOG、DECISIONS、HANDOFF、TASKS、baseline、索引和归档。不得暗示未验证的实机能力。

## 需求准入

新需求进入实现前必须回答：

1. 是否改变唯一 BindingToken → TEAP → TEK 输入链？
2. 是否新增、放宽或绕过任何 AutoBurst 候选、宏资格或 TEK 门禁？
3. 是否改变多组唯一所有权、组间互斥、步骤顺序或脱战硬门控？
4. 是否让 HUD、Tooltip、转盘或诊断影响派发？
5. 是否读取、保存或导出宏正文、受保护值、secret 值或敏感数据？
6. 是否必须依赖 WoW/Windows 实机证据？

任一答案为“是”时，必须更新当前 baseline 或决策记录，并补充专项自动测试和人工验收步骤。

## 实现原则

- 默认 fail-closed：未知、无法材料化、不一致、过期或来源不可信时不授权派发。
- AutoBurst 是官方推荐的受控候选层，不是第二条输入通道。
- HUD 与派发隔离：展示层只消费普通标量，不创建 BindingToken、不写 TEAP/TEK。
- 所有组共享唯一 Coordinator、活动组、plan 和 capture；不得组间抢占、排队或递归。
- 宏只读且身份共享验证；不创建、不修改、不按名称扫描借用宏，也不持久化正文。
- 每帧最多一个 BindingToken；步骤只由精确成功事件、自身非 GCD CD 或真实多充能减少确认。
- 战斗中受保护 HUD/secure 元素只记录 pending/dirty，脱战后应用。

## 文档职责

- `AGENTS.md`：最高优先级当前开发与安全边界。
- `PROJECT_CONTEXT.md`：当前架构上下文；`HANDOFF.md`：当前交接；`TASKS.md`：当前人工验收。
- `docs/baselines/BASELINE_*.md`：版本基线归档；当前版本必须有对应文件。
- `docs/patch-manifests/`：历史交付清单，不替代当前 baseline。
- `docs/`：当前架构、自动注入、测试与 TEK 专题；历史设计移入 `docs/archive/`。
- `DECISIONS.md`：保留历史决策，并在顶部追加当前版本关键决策。

## 证据标准与交付纪律

- 单元测试、合同测试、compileall 和 Lua 语法检查只证明离线代码合同。
- PyInstaller 成功或 TEK 进程存活只证明构建/启动状态。
- Windows 前台、Hook、真实 SendInput、SpellQueueWindow、动作条/宏、自动注入实际顺序、HUD 数值、DPI 和窗口模式必须实机验收。
- 默认交付完整源码；压缩包只能包含一个项目根目录，不得包含构建产物、缓存、日志、SavedVariables、EXE、历史补丁或本机配置。
- 交付说明必须分别列出通过、失败、跳过和未执行的验证，不得把“无新增失败”写成“全部通过”。
