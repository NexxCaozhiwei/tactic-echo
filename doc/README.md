# Tactic Echo 项目管理文档索引

当前权威开发基线：`1.5.0`

本目录收口当前项目管理、安全边界与交付验收规则。版本基线统一位于 `docs/baselines/`，补丁清单历史统一位于 `docs/patch-manifests/`；根目录不得保存重复 baseline 或 patch manifest。

## 文档入口

- `PROJECT_MANAGEMENT_SPEC.md`：需求、变更、版本、证据与文档治理规范。
- `RELEASE_AND_VALIDATION.md`：交付前验证、打包边界和人工实机验收要求。

## 权威顺序

1. 用户当次明确指令与 `AGENTS.md`。
2. 当前版本基线：`docs/baselines/BASELINE_1.5.0.md`。
3. 实时源码、测试及根目录当前文件：`VERSION`、`CHANGELOG.md`、`DECISIONS.md`、`HANDOFF.md`、`TASKS.md`、`PROJECT_CONTEXT.md`。
4. 本目录的项目管理和交付规范。
5. `docs/` 下当前架构、自动注入、测试与 TEK 专题。
6. `docs/archive/`、历史 baseline 和 patch manifest，仅作为历史证据。

## 使用规则

- 当前产品只保留主键、官方主推荐输入链路、HUD 和自动注入；退役模块不得从历史文档或 SavedVariables 恢复。
- 代码修改必须评估唯一输入链、AutoBurst/Coordinator、HUD CD/充能、宏身份、脱战门控、战斗保护和协议边界。
- 版本化源码修改必须同步 `VERSION`、TOC、`Core/Bootstrap.lua`、`CHANGELOG.md` 和当前 baseline。
- 离线测试只能证明代码合同和语法，不得声明 Windows Hook、前台识别、真实 SendInput 或 WoW 实机顺序成功。
- 默认交付完整源码；部署还必须核对 live TOC 与代表性文件哈希。
