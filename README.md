# Tactic Echo

最后更新：2026-07-01 22:35:00 +08:00

Tactic Echo 是一个 World of Warcraft 插件，以及配套的 Windows TEK 组件。当前源码发行版本为 `0.9.51`。

## 当前契约

唯一的 Windows 输入路径为：

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3
-> TEK safety gates
-> SendInput
```

HUD、爆发、防御、中断/控制、提示信息、队列与视觉系统均为只读的展示/建议层。它们不得修改官方主推荐、生成 BindingToken 值、写入 TEAP 负载或请求 TEK 输入。

## 版本状态

- `VERSION`：`0.9.51`
- AddOn TOC：`addon/!TacticEcho/!TacticEcho.toc`
- AddOn Bootstrap 版本：`addon/!TacticEcho/Core/Bootstrap.lua`
- TEK Windows 一键构建入口：`TEKEXEBUILD.CMD`

当前功能基线仍然是冻结的 `0.9.0` 维护线，其功能基础为已验证的 `0.8.11-trace-retention` 树。请不要将历史更高版本源码树复制、Cherry-pick 或叠加到此基线中。

## 当前架构

### AddOn

- 读取官方辅助战斗推荐。
- 根据当前可见的暴雪默认动作栏按钮解析对应的 SpellID。
- 仅使用玩家现有的按键绑定；不会创建隐藏按钮、写入绑定、编辑宏或切换动作条。
- 以 20 个视觉字段输出 TEAP v3，包含 `T / E / 3 / State`、CRC16、提交字节、目录指纹和 BindingToken。
- 将战术 HUD 与冷却渲染与实际派发分离。

### TEK

- 在当前 WoW 客户端区域内定位 TEAP v3 条带。
- 在派发前要求完成完整的 v3 CRC/提交/新鲜度校验。
- 直接在 v3 中解码 BindingToken；动作目录元数据仅用于派发过程中的追踪。
- 依赖 WoW 前台、最新会话/帧数据、有效协议/目录/Token、本地运行状态、物理输入钩子健康度、手动输入配合以及速率限制。
- 将 `paused`、`waiting`、`manual_hold`、`channeling` 与 `empowering` 视为非派发状态。

## 宏策略

宏处理故意保持保守，且本轮不作修改。

- 宏按钮仅能通过按下玩家现有可见动作条绑定来派发。
- AddOn 不会评估宏分支或目标条件。
- 文本回退仅关联一个无条件、单行 `/cast <spell>` 宏。
- 复杂的鼠标悬停/目标/回退宏仅作为诊断信息，除非暴雪 API 能报告宏当前关联的法术。

## 自动定位

TEK 的自动模式仅在当前 WoW 客户端区域的左上角边界区域内搜索 v3 的 `T / E / 3` 头部。它支持区块之间零视觉间隙，并在允许派发前通过具备递增新鲜度的完整 v3 帧验证候选结果。自动模式不会回退到固定桌面坐标。

## 验证

对于影响 AddOn、TEK、文档、构建、状态模型或测试的变更，至少运行：

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如果 `luac` 或 `texluac` 可用，也应对每个 AddOn 的 Lua 文件进行语法检查。

Windows GUI、托盘、Hook、多显示器/DPI、WoW 前台、真实 SendInput 以及打包后的 EXE 行为，除非有用户提供的测试证据支持，否则仍然属于实时机器验收项。

## 重要路径

- AddOn 源码：`addon/!TacticEcho`
- TEK 源码：`tek/src`、`tek/app`、`tek/runtime`
- TEK 测试：`tek/tests`
- AddOn/静态契约测试：`tests/unit`
- 当前交接说明：`HANDOFF.md`
- 当前任务：`TASKS.md`
- 当前决策：`DECISIONS.md`
- 历史记录：`CHANGELOG.md`、`docs/archive`
