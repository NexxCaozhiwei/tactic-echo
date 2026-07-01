# Tactic Echo 当前架构

## 1. 主派发链路

`C_AssistedCombat.GetNextCastSpell()` 产生官方主推荐。AddOn 只读取当前暴雪默认动作条和既有宏槽，解析为现实绑定后写入 20 块 TEAP v3 信号帧。Field 4 的 `channeling` / `empowering` / `manual_hold` 状态都是硬无输入信号；`manual_hold` 仅表达 AddOn 可识别的游戏内输入或界面阻断。TEK 采样、校验、前台保护、限频和人工输入让权后，才可能通过 Windows `SendInput` 发送该**唯一主推荐**的已存在绑定。

```text
官方主推荐 → 动作条只读解析 → TEAP v3 → TEK 校验/前台保护/限频 → 现有绑定输入
```

## 2. 不可突破的安全边界

- AddOn 不创建隐藏按钮，不改写按键绑定，不编辑玩家宏。
- 只支持暴雪默认动作条；第三方动作条插件不保证兼容。
- 载具、控制单位、覆盖动作条和宠物战斗硬阻断；额外动作按钮只记录，不阻断主条。
- TEAP v3 的 `BindingToken` 是唯一运行时派发依据。
- TEK 只在 WoW 前台、非文本输入、非引导、通过新鲜度/会话/CRC/限频检查时输入。
- 所有战术建议、爆发窗口和 HUD 状态均为只读展示，不产生 Token、不影响主推荐、不触发输入。

## 3. AddOn 分层

- `Recommendation/*`：官方推荐读取。
- `Actions/*`：默认动作条、现实绑定与宏诊断。
- `Signal/*`：TEAP v3 编码与信号帧。
- `Tactics/*`：图标状态、低血/环境兼容、爆发窗口、战术建议、队列和遥测。
- `UI/TacticalHudModel.lua`：把 `TacticalAdvisors` 快照转换为固定显示槽位。
- `UI/TacticalIconButton.lua`：图标、冷却/充能、边框、状态遮罩、快捷键和 Tooltip。
- `UI/TacticalHudLayout.lua`：横向、纵向、环绕、独立防御队列与布局保存。
- `UI/TacticalBoard.lua`：只读渲染调度与 fail-soft。
- `UI/ControlPanel.lua`：设置中心。

## 4. 队列式战术 HUD

默认布局是横向主队列：官方主推荐在首位，最多三个候选稳定排列在同一行，打断、爆发、控制、位移位于战术行，防御可跟随主 HUD 或拆成独立队列。

```text
[ 官方主推荐 ] [ 候选1 ] [ 候选2 ] [ 候选3 ]
[ 打断 ] [ 爆发 ] [ 控制 ] [ 位移 ]
[ 防御1 ] [ 防御2 ] [ 防御3 ] [ 防御4 ]
```

HUD 仅消费快照，不调用官方推荐 API，不注册事件，不写 TEAP。内容切换有防抖，阻断/暂停/未知状态即时显示；某个图标渲染失败只能影响该图标。

## 5. 环境与低血兼容

AddOn 不读取或比较数值生命值。防御与位移只消费兼容源提供的布尔低血信号、近期受伤事件和具有时间戳的环境布尔信号；信号缺失、无时间戳或过期时必须失效关闭。
