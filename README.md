# Tactic Echo 战术回响

当前版本：`1.1.7`

1.1.7 是当前基线，延续 P5.11 的共享宏资格，并保持自动打断硬暂停与脱战 Burst 硬门控；HUD 主键可启动/暂停。HUD 在战斗中变更卡片、点击路由、容器可见性、容器缩放或布局时不得调用受保护显示、缩放和布局方法，只记录待处理状态并在脱战后真实刷新。TEK 本地白名单按键默认 `W/A/S/D/SPACE` 不触发手动让步；非白名单真实键盘输入，包括 `Ctrl`、`Alt`、`Shift` 修饰键，按住期间持续让步，抬起后再恢复派发。默认策略为“自动启停”：未进战斗或脱战时显示“待命”，进战后自动恢复运行，区别于手动暂停和脱战停止。爆发、打断、控制、防御与生存共享同一套“当前可见按钮/槽位 + 当前宏身份 + 正文语义”资格规则。

Tactic Echo 是一套以游戏内 AddOn 观察与既有动作条映射为前提、通过 TEAP 与 TEK 受控交付官方推荐与自动爆发，同时提供只读打断提示和 HUD 人工点击入口的战术辅助项目。

## 当前自动打断状态

1.1.7 中自动打断设计继续硬暂停。设置项保持可见但不可选择；Defaults、SavedVariables 规范化与运行时都会强制 `auto_interrupt_suspended`。读条 API、事件、钢条证据、冷却采样、动作条/宏解析继续服务于只读提示、高亮与诊断，不会生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。

## 运行边界

- AddOn 不创建隐藏按钮，不写入/修改按键，不编辑宏，不直接输入。
- 自动打断处于硬暂停；打断、控制与群控保留只读提示，HUD 可作为人工点击入口。
- 仅使用玩家当前可见 Blizzard 默认动作条与已有宏中可确认的安全 BindingToken。
- 战斗中 `HudClickRouter` 不对 proxy/blocker 调用 `SetAlpha`、`Show` 或 `Hide`；路由变化仅标记 `dirty`，脱战后再重建。
- 战斗中 `TacticalBoard` 不对 HUD 容器调用 `SetScale` 或 `SetAlpha`，`TacticalHudLayout` 不执行重排；缩放与布局变化延迟到脱战后应用。
- 战斗中 `TacticalBoard` 不对 HUD 容器调用 `SetShown`、`Show` 或 `Hide`；可见性变化只记录 `tacticEchoCombatShownPending`。
- AutoBurst 仅在战斗内创建 plan/capture 或派发；任何脱战官方窗口、Run 操作、切图或旧 bridge 数据均不能产生 Burst TEAP/TEK 派发。HUD/原生动作条人工点击通过 `manual_hold` 优先于后续派发。

## 安装

1. 将补丁包内文件直接覆盖项目根目录；
2. 将 `addon/!TacticEcho` 覆盖至 WoW 实际加载目录；
3. 本版不修改 TEK 输入逻辑。已运行 P4.3 TEK.exe 时只需重启 TEK；
4. 启动游戏后执行 `/reload` 与 `/tecache refresh`。

## 文档

- `docs/baselines/BASELINE_1.1.7.md`：1.1.7 HUD 容器可见性战斗保护收口、TEK 修饰键手动接管、自动启停待命显示、自动打断硬暂停与共享宏资格冻结；
- `docs/P5.11_SHARED_MACRO_POLICY_TEST.md`：P5.11 控制、防御、生存与 Burst/Reaction 共享宏资格实机验收；
- `docs/P5.6_API_EVENT_INTERRUPTIBILITY_TEST.md`：P5.6 实机验收；
- `docs/P5.3_INTERRUPT_SAFETY_TEST.md`：历史钢条与打断冷却验收；
- `docs/baselines/BASELINE_1.0.46.md`、`docs/P5.2_REACTION_COMPAT_AND_MACRO_TEST.md`：P5.2 历史兼容派发基线；
- `HANDOFF.md`：当前工作状态与下一步测试。
