# Tactic Echo 1.0.49 P5.4 基线：P4.3 动作链重锚定、钢条稳定与打断冷却门控

## 现场证据

最新实机 SavedVariables 显示，当前可见打断按钮位于动作条槽位 60，类型为 `macro`，有真实键位和 BindingToken；Retail 将该动作表示为反制射击代表 SpellID `147362`，但 `GetActionText` 与 `GetMacroInfo` 无法提供可用宏正文/索引。P5.3 的 3 次兼容观察已完成，却在宏正文路由层停止，未进入 P4.3 已验证的 `BindingToken → TEAP reaction → TEK` 交付链。

该事实不说明宏列表中的任一宏就是当前绑定。P5.4 仅以当前可见动作栏按钮、它的代表 SpellID 和已有真实键位建立兼容路由。

## P5.4 规则

### 1. 当前动作栏代表 SpellID 路由

仅当以下全部成立时，为 `target` 建立 `action_info_represented_spell_compat`：

- 当前可见 Blizzard 默认动作栏按钮的 action type 为 `macro`；
- `GetActionInfo(actionSlot)` 返回的代表 SpellID 与请求打断技能一致；
- 该按钮具有现有真实 BindingToken；
- 当前客户端未能恢复可用宏正文/有效宏索引。

此路由不读取其他同名宏、不调用 `GetMacroInfo(name)`、不从宏列表的存在性推断当前绑定，也不注册 focus/mouseover 路由。宏正文可见时，既有解析逻辑优先。

### 2. 钢条规则

硬否决保持：`unit_api_not_interruptible`、`native_visible_shield`、`unit_event_not_interruptible`、`native_not_interruptible` 与 native scalar/method 钢条嫌疑均不能产生 reaction candidate。

兼容未确认读条需同时满足：

- 同一 `castKey` 三次不同 shared-observation 样本；
- 首个样本后至少 0.40 秒钢条稳定窗口；
- 候选写入前再次检查事件缓存未转为 `not_interruptible`。

`showShield` 和 `barType` 只做诊断。客户端若不公开任何盾、事件或 API 否决，插件无法从完全未知状态百分百识别钢条；P5.4 只避免首帧和短暂事件迟到造成的误派发。

### 3. 冷却规则

候选路由已存在时，`IconState:CollectCooldownOnly()` 必须读取 TEK 将实际按下的 action slot。已知非 GCD 自身 CD 且无可用 charges 时返回：

```text
reason = interrupt_action_cooldown
bindingToken = 0
kind = none
```

不得产生 reaction candidate，也不得占用主键。CD 未知仅诊断，不能伪造 CD 中或重新授权未知宏。

## 不变项

- P4.3 stable reaction candidate、SignalFrame stable sequence 与 TEK successful-send dedupe 不变；
- TEAP、TEK、BindingToken、宏正文、宏执行顺序、AutoBurst、HUD CD 均未修改；
- 不需要重建 `TEK.exe`。
