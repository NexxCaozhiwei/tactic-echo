# ChatGPT 交接：P1-08 TEK Live / SendInput（历史记录）

> 本文记录 2026-06-26 的早期 Live / SendInput 排障历史。它不是当前产品规范。
>
> 当前以 [`../HANDOFF.md`](../HANDOFF.md)、[`TEK_EXE.md`](TEK_EXE.md)、[`TEK_TRAY_APP.md`](TEK_TRAY_APP.md) 和 [`P1-08-tek-sendinput-verification.md`](P1-08-tek-sendinput-verification.md) 为准。

## 历史结论

- TEK dry-run 曾从真实屏幕读取 valid armed 帧，并将 ActionCode 1 映射为 `PALADIN_RETRIBUTION_JUDGMENT / SHIFT+Z`。
- 一次真实 SendInput 短测在后续帧为 `blocked/actionCode=0` 时正确没有发送输入。
- 该历史记录证明了“安全门没有在空动作帧误发键”，但不证明当前 TEK.exe 默认 UI 联动、托盘、连续 freshness、暂停/恢复或游戏效果已经完成验证。

## 当前交接要求

如需继续 TEK 排障，应提供：当前 commit、完整 unittest 结果、`tek-tray.log`、最近 JSONL trace、`tek-status.json`、WoW SavedVariables、DPI/窗口模式/多显示器信息与实际游戏效果。
