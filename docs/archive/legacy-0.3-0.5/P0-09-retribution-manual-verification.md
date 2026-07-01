# P0-09 官方推荐到真实动作条的人工验证

> 本文保留早期 P0 验证目标，但当前默认测试路径已更新为 **TEAP v3 / ButtonCache / BindingToken16**。TEAP v2 / 隐藏按钮仅为 Legacy 兼容。

## 当前验证目标

```text
TE 官方推荐 SpellID
→ 当前有效 ButtonCache 候选
→ 现实首绑定 / BindingToken
→ TEAP v3 视觉信号
→ TEK.exe / TEK Core 解码与状态
→ Windows 输入计划
→ SavedVariables 与 TEK trace 关联
→ WoW 实际效果观察
```

必须区分：

```text
recommended
binding_ready
planned
input_sent
blocked
error_locked
effect_observed
```

`input_sent` 不是 `effect_observed`。

## 当前用户侧步骤

1. 覆盖 AddOn 后进入 WoW，执行 `/reload`。
2. 使用 `/teui start` 打开启动页，确认本次登录默认暂停；点击启动动态联动。
3. 使用 `/tecache refresh`、`/tecurrent` 核对推荐 SpellID、按钮、首绑定、BindingToken 与来源（spell/macro）。
4. 启动 `TEK.exe`，在连接设置选择 `v3_dynamic`；确认前台、色块、协议和 Token 诊断均正常。
5. 在训练假人或可产生官方推荐的状态测试直接技能、宏按钮、分页/形态/扩展条。
6. 验证聊天/宏编辑/按键绑定/弹窗打开时 `paused`，并留存 trace 与 SavedVariables。

## 当前重点

- ButtonCache 当前页、Bonus Bar、姿态/变形和常驻扩展条；
- v3 Token 与 Windows 实际键位一致；
- Blocked 自动恢复，ErrorLocked 仅显式恢复；
- 同一推荐在 freshness 前进时可持续处理，但受全局/滚轮限速约束；
- 脱战三档策略、前台、自动定位与固定坐标回退；
- 退出 TEK.exe 后 worker 不残留。

历史 v1/v2 dry-run 结论仅作背景，不能替代上述 v3/TEK.exe 验证。
