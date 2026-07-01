# V3 宏放宽与输入焦点暂停验证

## 宏按钮原则

v3 只读扫描动作条。若宏正文中出现当前推荐技能的本地化名称或 SpellID，TE 使用该宏所在 slot 的首个 `GetBindingKey()` 作为 BindingToken。TE/TEK 不解析宏分支、不补修饰键、不改写宏。

以下宏在官方推荐为“神圣震击”时应命中宏按钮：

```lua
#showtooltips 神圣震击
/cast [@mouseover,help] 神圣震击
/cast [@target,help] 神圣震击
/cast 神圣震击
```

预期：来源 `macro`、非零 token、TEK 只发送该宏已有的动作条键。

无关宏不含目标技能名或 SpellID 时必须跳过；不应抢占直接技能候选。

## 输入焦点

打开聊天输入框、宏编辑器、按键绑定编辑器、带编辑框的 StaticPopup 时，TE 应输出既有协议状态 `paused`，TEK 记录 `frame_state_paused` 且不得 `input_sent`。关闭界面后下一有效帧可自动恢复。
