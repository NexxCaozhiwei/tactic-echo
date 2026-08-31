# 交付与验证清单

本清单适用于 `1.5.0` 当前基线及后续版本的源码修改、部署和人工实机验收。

## 必跑离线验证

在仓库根目录运行：

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如系统存在 `luac` 或 `texluac`，还必须检查全部 AddOn Lua。设置页和 HUD 构造变更还要实际执行对应 Lua harness，不能只做语法检查。

## 版本与文档一致性

版本化源码修改后必须确认：

- `VERSION`；
- `addon/!TacticEcho/!TacticEcho.toc`；
- `addon/!TacticEcho/Core/Bootstrap.lua`；
- `CHANGELOG.md`；
- `docs/baselines/BASELINE_<VERSION>.md`；
- `README.md`、`PROJECT_CONTEXT.md`、`HANDOFF.md`、`TASKS.md` 和当前专题索引没有继续宣称旧版本或退役架构。

## 部署验证

- 使用项目约定的 AddOn 同步流程部署完整 `addon/!TacticEcho`。
- `robocopy` 返回码 `0–7` 均需按其语义判断；返回码 `1` 通常表示成功复制，不能误判为失败。
- 核对 live TOC 与源码版本一致。
- 对本次修改相关的代表性文件计算源码/live SHA256；UI 修改至少核对 `UI/ControlPanel.lua` 或对应 HUD 文件。
- 如 TEK 源码有变化，必须重新构建/替换并重启 TEK；仅 AddOn/文档变化不得无理由触碰 TEK。

## 人工实机验收

以下结果不得由离线测试替代：

- Windows 前台识别、Hook 和真实 SendInput。
- WoW SpellQueueWindow、不同急速/GCD、真实施法事件和 Secret/opaque API 表现。
- 多自动注入组窗口命中、唯一所有权、组内实际释放顺序及 `simple/focused` 失败边界。
- 玩家当前动作条技能、宏、饰品和组合键来源。
- HUD 组顺序、27 张卡上限、战斗保护与 `/reload` 稳定性。
- 无 CD 技能不显示伪 CD、普通技能不显示 `1/1`、真实多充能和长 CD 与动作条同步。

详细当前清单见根目录 `TASKS.md`。

## 源码包边界

源码 ZIP 必须满足：

- 只有一个顶层项目根目录。
- 包含完整源码、脚本、测试和当前文档。
- 不包含 `build/`、`dist/`、`release/`、缓存、日志、SavedVariables、本机配置、EXE 或历史补丁包。
- 不包含用户宏正文、原始受保护 cooldown 数值或敏感诊断数据。

## 交付报告模板

```text
版本：
变更范围：
未改变的安全边界：
聚焦测试：
完整测试（通过/失败/跳过）：
Lua 语法与运行时构造检查：
部署与哈希：
人工实机验收：
已知风险：
```

## 失败与跳过处理

- 任一新增失败必须定位并修复，或取得用户确认后明确记录为阻断。
- 已知失败仍要说明是否与本次修改相关，并保留清理责任。
- 跳过不等于失败，但必须说明缺少的运行时或前提，并执行可用替代检查。
- Lua 语法或关键合同失败时不得部署。
- 实机未验证时必须写“未实机验证”，不能表述为 Hook、SendInput 或自动注入实机成功。
