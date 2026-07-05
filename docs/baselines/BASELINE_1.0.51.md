# Tactic Echo 1.0.51 P5.6 基线：API/事件确认打断资格

## 目标

保留 **P4.3 已实机验证**的动作交付链：

```text
当前实际动作栏绑定
→ BindingToken
→ TEAP v3（reaction）
→ TEK 既有安全门禁
→ 单次 SendInput
```

但自动打断是否可以进入该链路，改为只由当前读条的 API/事件确认决定；宏发现、宏绑定与宏路由兼容不参与钢条判定。

## 资格规则

### 允许进入 reaction

满足战斗内、`armed`、敌对存活、P3 真正 live 读条、当前动作栏存在安全 BindingToken 路由后，必须再满足以下之一：

1. `UnitCastingInfo()` 或 `UnitChannelInfo()` 的当前 `notInterruptible == false`，即 `directInterruptibilityKnown=true` 且 `interruptible=true`；
2. 与当前读条同源且未过期的 `UNIT_SPELLCAST_INTERRUPTIBLE` 事件。

### 一律不派发

- `notInterruptible == true`：`unit_api_not_interruptible`；
- 真实原生盾组件可见：`native_visible_shield`；
- 同源 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE`：`unit_event_not_interruptible`；
- `notInterruptible` 无法材料化、事件仍 pending/stale/unknown：`interruptibility_unknown`；
- P3 display bridge：`transient_gap_display_only`；
- 打断按钮存在已知、非 GCD 自身冷却：`interrupt_action_cooldown`。

`showShield`、`barType`、图标、宏名及宏列表都不是钢条或可打断证据。

## P5.6 修复

`ReactionObservation.lua` 之前使用：

```lua
apiRecord and plainBoolean(apiRecord.notInterruptible) or nil
```

Lua 会把合法的 `false` 折为 `nil`。P5.6 改为显式赋值，确保 `notInterruptible=false` 原样保留为“可打断”的直接 API 证据。

## 宏与当前动作栏

P5.5 的当前动作栏宏身份兼容保持不变：`action_info_represented_spell` 与 `action_info_macro_spell` 仍可在正文/索引不可读时为当前目标提供已有 BindingToken 路由。P5.6 未收紧、删除或改写任何宏；只改变读条可打断资格。

## TEK

TEK、TEAP、BindingToken 与 Windows 输入路径未修改，不需要重建 `TEK.exe`。
