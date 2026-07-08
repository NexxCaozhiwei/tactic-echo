# Tactic Echo 战术回响

当前版本：`1.1.7`

Tactic Echo 是一套 World of Warcraft Retail 辅助项目：游戏内 AddOn 只读观察官方主推荐和玩家既有动作条，Windows 端 TEK 通过 TEAP 协议在安全门控下执行单次按键派发。当前产品范围已经大幅收窄，只保留：首页/设置中心、HUD 主键、官方主推荐输入链路、AutoBurst 及其设置页/运行链路。

## 当前范围

- HUD 只展示主键与 AutoBurst 队列；候选历史、打断、控制、位移、防御、生存卡片保持隐藏或空输出。
- 打断、控制、防御、生存、TargetCastPrompt、姓名板群控扫描、只读反应高亮、监控/调试页面、MappingExport、OfficialApiProbe 均为退役功能，不应加载、轮询、显示或通过设置页重新启用。
- 自动打断、自动控制等反应自动化暂停开发并暂停使用；后续若恢复，必须先重新审计安全边界和性能成本。
- AutoBurst 继续保留脱战硬门控：只要 `inCombat=false`，不得创建/保留 plan/capture，不得生成 Burst candidate、TEAP Burst 帧或 TEK 请求。
- 默认策略“自动启停”在未进战斗或脱战时显示“待命”，区别于手动暂停和脱战停止。

## 输入链路

唯一常规输入路径：

```text
官方推荐（只读）
→ Blizzard 默认动作条槽位/已验证宏
→ BindingToken
→ TEAP v3
→ TEK 前台 / Hook / 手动让权 / 新鲜度 / 限频门禁
→ 单次 SendInput
```

- AddOn 不创建隐藏按钮，不写入或修改按键，不编辑宏，不直接输入。
- 默认动作条槽位可作为 TEAP/TEK 自动派发来源扫描，不要求对应动作条按钮当前可见。
- HUD 手动点击仍只能代理当前可见、已验证的 Blizzard 默认动作条按钮或已识别宏；隐藏按钮只能用于 TEAP/TEK 自动派发，不能作为 HUD 手动点击代理。
- TEK 支持主键和 `Shift+1` 至 `Shift+=` 这类绑定；真实键盘非白名单输入按下期间持续让步，抬起后再恢复派发。
- `W/A/S/D/SPACE` 等移动按键默认在 TEK 白名单内，不触发手动让步。

## HUD 展示规则

- HUD 底部蓝色状态行中，官方主推荐已通过安全校验时显示 `HAD`。
- HUD 按钮自身状态保持原有语义，不把按钮内状态改成 `HAD`；按钮 tooltip 的 dispatchable fallback 仍为“可用”。
- 正常灰条施法继续显示“施法”，引导显示“引导”。
- 射击猎等射击类灰条施法显示“射击”。实现只使用只读施法 spellID、等效 spellID、基础技能一致性和施法名称，不影响推荐、BindingToken、TEAP 或 TEK 派发权限。
- BBA 风格的按下反馈只在 `UNIT_SPELLCAST_SUCCEEDED` 后触发，用于表达技能最终被游戏确认使用，而不是鼠标按下动画。

## 战斗保护边界

- HUD 卡片与 HUD 手动点击层在战斗中不得直接调用受保护 `Button:Hide()` / secure proxy Hide 路径。
- 卡片 Button 在战斗中不得调用 `SetAlpha`、`EnableMouse`、`Show` 或 `Hide`，只能记录待处理状态。
- `HudClickRouter` 的 secure proxy 与 blocker 在战斗中不得调用 `SetAlpha`、`Show` 或 `Hide`，只能记录 pending/dirty。
- `TacticalBoard` 容器在战斗中不得调用 `SetScale`、`SetAlpha`、`SetShown`、`Show` 或 `Hide`。
- `TacticalHudLayout` 在战斗中不得执行 `SetScale`、`SetPoint`、`SetSize`、`SetShown` 等布局变更，只能记录 pending/dirty，脱战后再真实应用。

## 安装

1. 将仓库内 `addon/!TacticEcho` 覆盖到 WoW 实际加载目录；
2. 如 TEK 代码有更新，重启 TEK；
3. 在游戏内执行 `/reload`；
4. 如动作条或绑定刚变更，执行 `/tecache refresh`。

本机常用 AddOn 目录示例：

```text
E:\World of Warcraft\_retail_\Interface\AddOns\!TacticEcho
```

## 验证

常用验证命令：

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如系统存在 `luac` 或 `texluac`，还应检查 AddOn Lua 语法。

## 关键文档

- `AGENTS.md`：当前最高优先级开发边界和安全约束。
- `docs/baselines/BASELINE_1.1.7.md`：1.1.7 基线。
- `docs/patch-manifests/`：历史补丁清单归档。
- `HANDOFF.md`：阶段交接和人工实机测试提示。
