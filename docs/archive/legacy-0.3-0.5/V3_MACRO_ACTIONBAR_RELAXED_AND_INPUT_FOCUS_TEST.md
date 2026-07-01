# v3 宏按钮与输入焦点暂停验证

> 当前宏规则：TE 只确认“当前推荐 SpellID 是否关联到一个当前有效宏按钮”，随后只传该按钮的真实首绑定。TEK 不解释宏语义。

## 宏候选

- 当前有效直接技能与宏按钮都进入 ButtonCache，按可见视觉顺序选择；不硬编码直接技能优先。
- 宏关联优先使用 `GetActionInfo(slot)` 的第四返回值 `macroSpellID`；失败时再读取 `GetActionText(slot)`、`GetMacroInfo()`、宏正文中的技能名或 SpellID。
- `#showtooltip`、条件、`@mouseover`、`/castsequence`、`/use`、`/click`、目标切换等不再是拒绝理由；最终语义由 WoW 宏系统决定。
- 无法证明与当前推荐 SpellID 关联的无关宏继续跳过；无绑定或首绑定不受 schema 1 支持仍 fail-closed。

## 输入/对话暂停

聊天编辑框、任意键盘焦点、宏编辑器、按键绑定编辑器或 StaticPopup 对话框存在时，TE 将当前帧状态设为 `paused`；TEK 必须因 `frame_state_paused` 不发送按键。

## 手工验证

1. 宏按钮绑定 `E`，正文包含当前推荐技能（可包含 `#showtooltip`、多行条件 `/cast`）：应显示 `来源=macro`、键=`E`、非零 token。
2. 无关宏在更靠前位置、目标宏/技能在后：无关宏不能阻断或抢占目标候选。
3. 打开聊天、宏窗口、按键绑定窗口或确认弹窗：TE 应显示“动态联动已暂停”，TEK trace 不应出现 `input_sent`。
4. 关闭界面后：下一有效帧自动恢复到会话策略允许的状态。
