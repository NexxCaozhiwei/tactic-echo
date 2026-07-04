# 交付与验证清单

本清单适用于 `1.0.44 P5` 当前基线的代码修改、源码包交付和人工实机验收。

## 必跑离线验证

在仓库根目录运行：

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如系统存在 `luac` 或 `texluac`，还必须检查全部 AddOn Lua 语法。

## 版本一致性

代码修改后必须确认：

- `VERSION`
- `addon/!TacticEcho/!TacticEcho.toc`
- `addon/!TacticEcho/Core/Bootstrap.lua`
- 当前 baseline、patch manifest、CHANGELOG、DECISIONS、HANDOFF、TASKS

这些位置记录的当前版本和语义一致。

## ZIP 内容边界

源码 ZIP 必须满足：

- 只有一个顶层项目根目录。
- 包含完整源码、脚本、测试和当前文档。
- 不包含 `build/`、`dist/`、`release/`。
- 不包含缓存、日志、SavedVariables、本机配置、EXE、历史补丁包。
- 不包含用户宏正文、原始受保护 cooldown 数值或敏感诊断数据。

## 人工实机验收

以下结果不得由离线测试替代：

- Windows 前台识别。
- Hook 有效性。
- 真实 SendInput。
- WoW 采样相位与 SpellQueueWindow。
- 不同急速/GCD 下的顺序。
- 宏正文首读/重读窗口。
- DPI、多显示器、窗口模式。
- 四种双技能组合的实际释放顺序。
- AutoBurst pre-window handoff 四帧 hold 后第 5 张新鲜帧派发。
- P4/P5 reaction 候选稳定 sequence 与 TEK 去重。

## 交付报告模板

交付说明应包含：

```text
版本：
变更范围：
未改变的安全边界：
离线验证：
Lua 语法检查：
打包结果：
仍需人工实机验收：
已知风险：
```

## 失败处理

- 任一必跑命令失败：不得交付为可用版本，必须记录失败命令和首个关键错误。
- Lua 语法失败：不得覆盖 AddOn。
- ZIP 不干净：重新打包，不得手工删除后跳过验证。
- 实机验收未做：说明“未实机验证”，不得写成 Windows Hook、SendInput 或自动爆发实机成功。
