# Tactic Echo 1.4.12 基线

`1.4.12` 经用户明确授权，取消“DurationObject 永远不得显示原生数字”的绝对规则。可信技能自身冷却的安全普通数值不可读时，由客户端直接显示同一 DurationObject 的准确倒计时。

## 原生准确数字

- 仅已确认 `cooldownActive=true`、非共享 GCD、非 GCD alias、非物品卡且 remaining/duration 至少一个不可安全读取时，允许原生 CountdownNumbers。
- 任一当前已验证直接动作槽明确自身非 GCD 冷却时，优先使用 `C_ActionBar.GetActionCooldownDuration(actionSlot)`；所有天赋、英雄天赋与覆盖技能都不得改用声明 SpellID 的冲突旧基础 DurationObject，复仇之怒 120→60 只是已确认实例。
- 原生数字可见时，TE 必须清空自定义徽标和连续性缓存，避免旧 120 秒与客户端真实数字重叠。
- 同一可信动作槽重新提供安全 start/duration 后，原生数字必须隐藏，TE 恢复统一纯秒数徽标。
- Blizzard 可能把长冷却格式化为 `MM:SS`；准确性优先于纯秒数格式一致性。

## 不变边界

- 共享 GCD、13/14 饰品、药水和其他物品不得启用原生 CountdownNumbers。
- 每张卡仍只附着一个最终 DurationObject；对象不得解包、比较、持久化、导出或写入模型。
- 原生倒计时只影响 HUD 展示，不影响 AutoBurst、推荐、BindingToken、TEAP、TEK 或任何派发资格。
