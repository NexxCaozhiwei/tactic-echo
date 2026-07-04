# Tactic Echo 战术回响

当前版本：`1.0.44 P5`  
更新时间：2026-07-04  

Tactic Echo 是一套以游戏内 AddOn 观察与既有动作条键位映射为前提、通过 TEAP 与 TEK 受控交付的战术提示与自动爆发/自动打断项目。

## 当前自动打断状态

P4.3 已实机确认 reaction 动作链可用；P4.4 在保留稳定候选交付的前提下，恢复严格钢条判定：

```text
敌方真实读条
→ 直连 API / 单位施法事件 / 真实盾组件连续视觉证据
→ P2 既有安全 BindingToken 路由
→ TEAP v3 reaction (0x40)
→ TEK 现有前台、Hook、人工接管、新鲜度、限频门禁
→ 一次已有键位输入
```

P4.4 不允许以下信息单独驱动自动输入：`showShield`、`barType`、native scalar-only true、短暂读条桥接或未知值。

P4.5 额外支持一种严格的既有整合宏：`@mouseover → @focus → target`。它只会在 AddOn 确认该宏此刻会命中**同一个读条来源**时进入 reaction；若更高优先级宏分支仍有活敌目标，则保持零按键并输出 `macro_priority_preempted_by_*`。宏自身不能判断“是否正在施法”，因此这不是“焦点未读条就自动回退当前目标”的宏语言能力。

P5 将宏身份锚定为当前动作条 `GetActionInfo` 返回的数值 macro index。即使宏名为中文“打断”且账号/角色宏存在同名项，也不会按名字借用另一枚宏正文；首读正文为空时只重读同一 index。P4.6 的 `/cast` 令牌→SpellID 只读关联继续保留。

## 运行边界

- AddOn 不创建隐藏按钮，不写入/修改按键，不编辑宏，不直接输入。
- P4 仅自动打断；控制与群控仍仅提示。
- 仅使用玩家当前可见 Blizzard 默认动作条与已有宏中可确认的安全 BindingToken。
- Burst plan / pre-window capture 活跃时，自动打断仅高亮，保持 Burst 优先级。

## 安装

1. 将补丁包内文件直接覆盖项目根目录；
2. 将 `addon/!TacticEcho` 覆盖至 WoW 实际加载目录；
3. 本版不修改 TEK 输入逻辑。已运行 P4.3 TEK.exe 时只需重启 TEK；未构建过 P4.3 TEK 时，按既有流程运行根目录 `TEKEXEBUILD.CMD`；
4. 启动游戏后执行 `/reload`，在打断设置中确认版本和诊断。

## 文档

- `BASELINE_1.0.44.md`：P5 宏身份锚定与同名宏防错配合同；
- `docs/P5_MACRO_IDENTITY_TEST.md`：中文同名宏/反制射击实机验收步骤；
- `docs/P4.6_COUNTER_SHOT_MACRO_RECOVERY_TEST.md`：P4.6 历史宏恢复验收步骤；
- `docs/P4.5_PRIORITY_INTERRUPT_MACRO_TEST.md`：整合宏实机验收步骤；
- `docs/P4.4_NATIVE_SHIELD_REVALIDATION_TEST.md`：钢条判定实机验收步骤；
- `HANDOFF.md`：当前工作状态与下一步测试。
