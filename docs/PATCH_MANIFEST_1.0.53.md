# Tactic Echo 1.0.53 P5.8 完整源码包清单

## 核心变更

- `addon/!TacticEcho/Tactics/AutoBurst.lua`：脱战硬门控；移除 pre-combat bridge 授权与跨进战计划保留。
- `addon/!TacticEcho/Signal/SignalFrame.lua`：不再从 `armed` 状态授权或提升脱战 Burst transport。
- `addon/!TacticEcho/UI/HudClickRouter.lua`：HUD secure proxy 双点击沿、HIGH 输入层、阻断层按下提示。
- `addon/!TacticEcho/Actions/ActionBarBindingResolver.lua`：13/14 槽 HUD 卡优先解析 exact inventory source。
- `docs/baselines/`：所有历史与当前 baseline 的唯一存放位置。
- `CHANGELOG.md`、`AGENTS.md`、`README.md`、`VERSION`、TOC、Bootstrap：同步到 1.0.53 P5.8。

## 交付边界

- 只包含单一源码根目录；不包含 SavedVariables、日志、缓存、构建输出、历史 ZIP 或 EXE。
- 不修改 TEK/Windows 输入实现，不需要重建 `TEK.exe`。
