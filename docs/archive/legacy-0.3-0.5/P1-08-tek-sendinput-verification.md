# P1-08 TEK UI 联动与输入验证

状态：`IN_PROGRESS`。TEK Core、`TEK.exe` 构建脚本、物理输入 50ms 协作、显示校准和 Notepad SendInput 人工门禁已具备；默认 UI 联动、真实 Windows 构建和真实游戏效果仍需按当前产品行为补齐人工证据。

## 1. 当前产品行为

`TEK.exe` 是正式用户入口。它默认启动 UI 联动 worker，先等待 WoW 前台与游戏内 TE 的有效武装信号；Dry-run 是次要入口。

UI 联动不使用固定数值 dispatch budget：在 TE 未暂停、TEK 未暂停、TEAP 有效、WoW 前台且未 ErrorLocked 的条件下，同一推荐动作可随 freshness 持续处理。v3 使用 BindingToken，不要求 ActionID/Profile/Catalog 映射；v2 Legacy 保留原 Profile/Catalog 校验。

这不改变以下硬条件：

- TEAP v3 / session / sequence / freshness / CRC / commit；v2 仅为 Legacy；
- 双采样与旧帧防护；
- WoW 前台与分发前二次检查；
- v3 BindingToken 白名单与协议模式一致性；v2 Profile / Catalog 一致性；
- trace；
- 部分发送处理、修饰键清理与 ErrorLocked；
- `--require-start-toggle` 的首次联动保护。

## 2. 状态与操作

| 操作/状态 | 行为 |
|---|---|
| TEK.exe 启动 | UI 联动等待，不因启动本身派发 |
| 游戏内 TE 武装 | 首次满足 paused/non-armed → 新鲜 armed 后，TEK 可进入 Armed |
| TEK 暂停 | 持续采样/更新状态，绝不派发 |
| TEK 恢复 | TE 仍 Armed 且实时检查通过时恢复处理 |
| Stop / Exit | 完整停止 worker 并清理 dispatcher 状态 |
| Blocked | 条件恢复后自动恢复 |
| ErrorLocked | 用户明确点击“恢复”后才重新等待有效帧 |

## 3. 开发者短测（非普通用户入口）

CLI 的单次/有限预算测试仍可用于排障。它们不是 `TEK.exe` 默认运行模式。

```powershell
# dry-run 开发验证
python -m tek.src.cli --live --trace logs/p1-08-dry-run.jsonl

# 单次真实输入短测；仅用于明确人工验证
python -m tek.src.cli --live --send-input --confirm-send-input I_UNDERSTAND_TEK_SENDS_KEYS --max-frames 20 --dispatch-budget 1 --trace logs/p1-08-sendinput-short.jsonl
```

不要再使用 `--dispatch-budget 100000` 作为 UI 联动命令。UI 联动的持续运行由 TEK.exe 内部明确的“无预算模式”表达，而不是由一个巨大整数模拟。


## 3.1 物理输入协作

Windows 低级键盘/鼠标 Hook 检测到真实键盘、鼠标键或滚轮输入时，TEK 让出 50ms；带 injected 标志的自身输入不延长暂停。该机制只让出派发时机，不绕过协议、前台、freshness、CRC、ErrorLocked 或其他安全门。

## 3.2 真实 SendInput 验收（Notepad）

```powershell
.\scripts\verify-tek-sendinput.ps1
```

脚本仅接受前台 `notepad.exe`，要求确认短语和可见字符人工确认，拒绝 WoW。验收 evidence JSON 只能作为 Windows 发送链路证据，不可写成“WoW 已施法”。

## 4. 需要记录的 trace 语义

至少区分：

```text
gatePassed
dispatchAttempted
inputSent
partialFailure
dispatchBlocked
dispatchError
```

`input_sent` 仅表示 Windows 已接受完整输入事件，不代表 WoW 已开始施法、施法成功或效果生效。

## 5. 当前人工验证清单

1. TEK.exe 启动后显示正确托盘颜色和 Waiting；
2. WoW 前台后自动定位并缓存 layout；
3. 游戏内武装后，TEK 正确进入 Armed；
4. 同一动作的新 freshness 产生连续处理记录；
5. TEK 暂停仍记录帧但不派发；
6. TE 暂停、WoW 失焦、Profile 不匹配、信号失效均正确阻断；
7. Blocked 自动恢复；
8. ErrorLocked 显式恢复；
9. Stop 与 Exit 不留 worker、修饰键或持续输入循环；
10. 真实 WoW 施法、覆盖宏、二阶段技能分别观察并归档证据。

## 6. 历史说明

2026-06-26 的短测曾证明：dry-run 可从真实屏幕读取 valid armed 帧；一次 SendInput 测试因后续 TE 信号为 `blocked/actionCode=0` 而正确未发送。该记录只能证明当时安全门工作，不能代替当前 TEK.exe 连续 UI 联动的人工验证。
