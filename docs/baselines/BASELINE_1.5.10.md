# Tactic Echo 1.5.10 基线

继承 1.5.9，修复高亮推荐运行门控与设置反馈。

- AutoBurst `kind="none"` 与 `kind="idle"` 均代表没有候选或所有权，SignalFrame 可继续评估高亮推荐；AutoBurst candidate/hold、Reaction candidate/hold、手动优先、输入焦点和施法保护仍具有既有优先级。
- 高亮技能设置每行通过独立回调绑定其 SpellID，避免跨行状态串用。专精身份暂不可用时，保存失败会在设置页提示，当前行显示实际已保存状态。
- 客户端高亮 API 的公开布尔 `false` 保持为 false；Secret/opaque/错误仍为 UNKNOWN，不影响 fail-closed 规则。
- 高亮候选继续使用当前动作条 resolver、真实 BindingToken、自身冷却/充能与 GCDGate；官方推荐保持不可变，自动注入仍以官方窗口为唯一锚点，特殊模式仍只替换官方来源。
- 不增加 TEAP 协议位、输入通道、事件或轮询；TEK 所有门禁保持不变。

## 验收范围

- `AutoBurst:Evaluate()` 返回 `kind="none"` 时高亮候选仍能被评估并进入同一常规派发链。
- AutoBurst candidate/hold 仍优先于高亮候选。
- 高亮接口返回 true/false/Secret/error 时，true 可参与候选，false 明确视作未高亮，Secret/error 不授权候选。
- 每专精技能停用状态正确保存；专精身份暂不可用时显示错误并保留真实复选框状态。
- 目标 Retail 客户端高亮 API、真实 BindingToken 及 TEAP/TEK 输入仍需人工实机验收；离线测试不替代实机派发证据。
