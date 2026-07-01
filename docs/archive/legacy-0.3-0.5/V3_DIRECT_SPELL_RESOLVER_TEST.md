# V3 ButtonCache 动作条回归场景

> 本文用于 WoW 实机验证；不替代 Python 自动测试。

## 1. 无关宏不抢占目标按钮

1. 在较靠前位置放置无关宏；
2. 在当前有效默认动作条的按钮 `3` 放置 SpellID `375576`，并将该按钮绑定为 `3`；
3. `/tecache refresh` 后执行 `/tecurrent`。

预期：

```text
动态绑定就绪：键=3 token=<non-zero> 槽位=<actual action> 来源=spell
```

无关宏不得产生 `macro_unsupported`、`macro_spell_not_referenced` 或使 token 归零。

## 2. 目标宏按钮

1. 当前有效按钮 `E` 放置一个正文/显示可关联目标 SpellID 的宏；
2. 宏可包含 `#showtooltip`、条件、`@mouseover`、`/castsequence`、`/use` 等用户自定义内容；
3. 官方推荐切到该 SpellID 后执行 `/tecurrent`。

预期：

```text
动态绑定就绪：键=E token=<non-zero> 来源=macro 宏=<macro name>
```

宏关联优先读取 `GetActionInfo(slot)` 的第四返回值 `macroSpellID`；动作文本/宏信息/正文中的本地化技能名或 SpellID 是兼容回退。TEK 只按 E，不解释宏分支。

## 3. 当前页与形态

1. 切换主动作条分页；
2. 在不同页给同一键放不同技能；
3. 切换德鲁伊等职业的姿态/形态；
4. `/tecache refresh` 后检查 `/tecurrent`。

预期：只命中当前实际有效的主条/Bonus Bar/可见姿态或扩展条按钮；非当前页不得被当作可派发来源。

## 4. Fail-closed

- 目标按钮无绑定：`binding_missing`；
- 首个绑定不在 schema 1：`binding_unsupported:*`；
- 动作条中没有当前推荐技能/关联宏：`actionbar_spell_not_found`；
- Token 为 0 或无法解码：TEK Blocked，不发送输入。

## 5. 安全暂停

打开聊天框、宏编辑、按键绑定或 StaticPopup 后，TE 应发送 `paused`；TEK trace 应显示 `frame_state_paused`，不得出现 `input_sent`。
