# Tactic Echo 1.0.36 基线：HUD 冷却渲染回迁至 1.0.31 稳定路径

## 本版范围

1.0.36 以 1.0.35 的 AutoBurst、TEAP、TEK、设置页和切图安全围栏为运行基线；**仅回迁 HUD 冷却渲染链到已实测稳定的 1.0.31 实时 DurationObject 路径**。

本版不再继续使用 1.0.32–1.0.35 的 `cooldownPresentation` / `HudCooldownDurationObjects` 侧车架构。该架构在目标 Retail 客户端上会出现窗口、注入、打断和防御卡的 CD 转盘、CD 数字或来源随机切换，而饰品因走独立物品路径仍能正常显示，不能作为普通技能路径稳定的证据。

## 保持不变

- AutoBurst 有序多步骤计划、简易/集中预检、运行期漂移处理；
- GCDGate、四帧 handoff、起手 bridge、切图安全围栏；
- 官方推荐 → 当前动作条绑定 → BindingToken → TEAP → TEK 的唯一派发路径；
- 每专精爆发顺序、窗口/注入/饰品步骤和既有设置页优化；
- 饰品 13/14 的自身 CD 权威与共享 GCD 隔离；
- HUD 自定义字体、颜色、大小、位置和独立状态/来源文本层。

## 回迁后的 HUD 冷却链

```text
IconState / CooldownResolver / CooldownTracker
→ 安全标量状态、动作条绑定和 CD/GCD 语义
→ TacticalHudModel（只传递普通标量）
→ TacticalIconButton.showDurationObjectCooldown()
→ 当前客户端可渲染的单个实时 DurationObject 转盘
→ HUD 自定义 CD 数字 / 用户显式选择的原生数字
```

- `TacticalHudModel`、SavedVariables、Trace 和卡片数据不携带 `DurationObject`；
- 但 `TacticalIconButton` 恢复为实时查询 `C_ActionBar`、`C_Spell` 与 `CooldownResolver`，因为这正是 1.0.31 已实测可稳定渲染普通技能 CD 的路径；
- 每次渲染由 `showDurationObjectCooldown()` 顺序选择一个当前可用的客户端对象，不把对象存入侧车，不让对象反向影响 AutoBurst、预检、TEAP 或 TEK；
- HUD 默认使用可配置自定义数字；用户明确选择原生数字模式时才显示客户端原生数字；
- 主键和 Burst-window 的纯共享 GCD 继续隐藏；自身 CD 与 GCD 同时存在时优先显示自身 CD；
- 饰品、药水和其他物品卡不借用通用动作条 GCD，13/14 槽不显示泛 GCD；
- `cooldownGcdAlias` 仍从 `IconState` 透传到 HUD，用于阻断 `61304` 别名误显示。

## 删除的失败架构

以下展示侧车只存在于 1.0.32–1.0.35，1.0.36 不再使用：

```text
IconState:BuildCooldownPresentation()
TE.HudCooldownDurationObjects
TacticalHudModel.sanitizeCooldownPresentation()
runtimeDurationObject()
showSnapshotDurationObject()
```

## 验收重点

1. 爆发窗口、注入、打断/控制、防御/生存、饰品分别进入真实自身 CD；每张卡应出现一套转盘和一套符合设置的数字，不应突然消失或重叠。
2. 主键/窗口仅处于共享 GCD 时不显示 CD 数字或转盘；饰品 13/14 仅处于共享 GCD 时不显示倒计时。
3. 复仇之怒等覆盖/天赋影响技能的 HUD 数字与当前暴雪动作条一致，不应误显示静态旧基础 CD。
4. AutoBurst 的简易/集中预检、窗口前 handoff、切图围栏和 TEK 实际派发行为与 1.0.35 保持一致。
