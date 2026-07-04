# Tactic Echo 项目管理文档索引

当前权威开发基线：`1.0.44 P5`

本目录用于收口项目管理、基线、安全边界与交付验收规则。历史 `BASELINE_*.md` 已归档到 `doc/baselines/`；根目录保留当前 `BASELINE_1.0.44.md` 作为版本入口。根目录 `PATCH_MANIFEST_*.md` 和既有 `docs/` 仍保留为版本记录、专项测试或实现说明；日常开发应先读取本目录，再按需追溯历史文档。

## 文档入口

- `BASELINE_1.0.44_P5.md`：当前唯一开发基线与不可突破的技术边界。
- `PROJECT_MANAGEMENT_SPEC.md`：需求、变更、版本、证据与文档治理规范。
- `RELEASE_AND_VALIDATION.md`：交付前验证、打包边界和人工实机验收要求。

## 权威顺序

1. `AGENTS.md` 与用户当次明确指令。
2. 本目录中的当前基线与项目管理规范。
3. 根目录当前版本文件：`VERSION`、`CHANGELOG.md`、`DECISIONS.md`、`HANDOFF.md`、`TASKS.md`、`PROJECT_CONTEXT.md`。
4. 当前版本根基线和清单：`BASELINE_1.0.44.md`、`PATCH_MANIFEST_1.0.44.md`。
5. `docs/` 下专项测试、架构、TEK 与历史说明。
6. `doc/baselines/` 中的更早版本基线，仅作为历史参考，不得自动恢复其运行时规则。

## 使用规则

- 任何代码修改都必须确认是否影响 `BASELINE_1.0.44_P5.md` 中的输入链、AutoBurst、AutoReaction、HUD CD、宏身份或协议边界。
- 修改版本相关代码时，必须同步根目录 `VERSION`、AddOn TOC、`Core/Bootstrap.lua`，并更新相应交付记录。
- 离线测试只能证明代码合同和语法，不得声明 Windows Hook、前台识别、真实 SendInput 或 WoW 实机顺序成功。
- 交付包必须是完整源码包，且仅包含一个项目根目录。
