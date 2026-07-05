# 项目管理规范

本规范用于 Tactic Echo `1.1.2` 之后的需求、实现、验证和交付管理。

## 版本治理

- 当前唯一开发基线为 `1.1.2`。
- 每次代码修改必须保持根目录 `VERSION`、AddOn TOC、`addon/!TacticEcho/Core/Bootstrap.lua` 版本一致。
- 当前版本基线、补丁清单和本目录文档必须能互相解释，不得出现相互矛盾的运行时规则。
- 旧版本文档只能作为历史证据，不能作为恢复旧字段、旧入口或旧派发路径的依据。

## 变更分类

- 安全边界变更：输入链、TEAP/TEK、BindingToken、SendInput、Hook、前台、限频、宏身份、AutoBurst、AutoReaction。此类变更必须 fail-closed，且必须补合同测试。
- 展示层变更：HUD、转盘、数字徽标、设置页展示、诊断面板。此类变更不得反馈到派发资格。
- 数据模型变更：SavedVariables、burstProfiles、sequence、mapping export、Trace/status schema。此类变更必须保留迁移或兼容策略，并说明不保存敏感数据。
- 文档/交付变更：README、CHANGELOG、DECISIONS、HANDOFF、TASKS、baseline、patch manifest。此类变更不得暗示未验证的实机能力。

## 需求准入

新需求进入实现前必须回答：

1. 是否改变唯一输入链。
2. 是否新增或放宽任何自动派发资格。
3. 是否读取、保存或导出宏正文、受保护值、secret 值或用户敏感数据。
4. 是否需要实机证据，而不是离线测试证据。
5. 是否影响现有 AutoBurst plan、pre-window capture、reaction candidate 或 HUD CD 展示。

任一答案为“是”时，必须更新基线或决策记录，并补充专项测试或人工验收步骤。

## 实现原则

- 默认 fail-closed：未知、无法材料化、不一致、过期、来源不可信时不授权派发。
- 展示与派发隔离：HUD、Tooltip、诊断、只读观察不得创建 BindingToken 或写入 TEAP/TEK。
- 候选与输入隔离：AutoBurst/AutoReaction 只能产生候选，最终仍必须经过 BindingToken、TEAP v3、TEK 全部门禁。
- 宏只读：只读取玩家已放在可见 Blizzard 默认动作条上的既有宏，不创建、不修改、不枚举借用同名宏正文。
- 每帧最多一个 BindingToken，持续候选去重交给既有 sequence 与 TEK 限频/抑制机制。

## 文档职责

- `doc/`：当前项目管理和交付规则入口。
- `docs/baselines/BASELINE_*.md`：版本基线归档；当前版本必须有对应 `BASELINE_<VERSION>.md`。
- `docs/patch-manifests/PATCH_MANIFEST*`：版本覆盖/交付清单历史。
- 根目录不得保留 `BASELINE_*.md` 或 `PATCH_MANIFEST*` 副本。
- `docs/`：专项架构、TEK、测试方案和实机脚本说明。
- `DECISIONS.md`：关键技术决策，尤其是边界收紧或历史规则废弃。
- `HANDOFF.md`：当前交接状态、已知风险和下一步。
- `TASKS.md`：当前待验证事项。

## 证据标准

- 单元测试、合同测试、compileall 和 Lua 语法检查只能证明离线代码合同。
- PyInstaller 成功或 TEK 进程存活只能证明构建/启动状态。
- Windows 前台识别、Hook、真实 SendInput、采样相位、SpellQueueWindow、不同急速/GCD、宏、DPI、多显示器、窗口模式和真实技能顺序必须用人工实机验收。
- SavedVariables、Trace、status snapshot 可作为诊断证据，但不得替代真实 SendInput 成功证据。

## 交付纪律

- 默认交付完整源码包。
- 压缩包只能有一个项目根目录。
- 不得包含 `build/`、`dist/`、`release/`、缓存、日志、SavedVariables、EXE、历史补丁或本机配置。
- 打包前必须验证 ZIP 顶层结构和内容清洁。
- 交付说明必须明确哪些能力已离线验证，哪些仍需人工实机验收。
