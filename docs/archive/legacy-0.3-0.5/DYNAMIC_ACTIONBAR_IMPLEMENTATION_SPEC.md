# 现实动作条动态键位：实施规格（TEAP v3）

> 状态：**已编码进入默认测试路径；WoW / Windows 实机验证进行中。**
>
> 当前实施与未验证边界以根目录 `AGENTS.md`、`HANDOFF.md`、`TASKS.md` 为准。

## 1. 运行模型

```text
官方推荐 SpellID
→ TE ButtonCache（当前默认 Blizzard 动作条）
→ 当前可见按钮的首个 GetBindingKey
→ BindingToken16
→ TEAP v3 / 20 色块
→ TEK 协议、前台、freshness、限速与失败门
→ Windows 输入
→ 玩家现有动作条技能或宏按钮
```

v2 隐藏按钮/Profile 路径保留为显式 Legacy 兼容。v3 不调用 `SetBinding()`、`SaveBindings()`，不改动作条、宏或用户键位。

## 2. ButtonCache

- 只在动作条、分页、绑定、宏、专精、姿态/形态相关事件后失效；下一次推荐读取时重建。
- 当前扫描范围：当前主动作条页/Bonus Bar、可见默认 MultiBar、可见姿态/变形按钮。
- 当前不承诺第三方动作条插件、载具/控制/覆盖/任务特殊条；它们不应作为已验证的 v3 派发来源。
- 多候选按可见按钮实际坐标排序：上方优先，同排从左到右；无坐标时回退稳定默认条顺序。
- 首个 `GetBindingKey()` 是唯一候选；首键不在 schema 1 即 fail-closed，不使用第二绑定。

## 3. 宏

宏的本质是“按用户已有宏按钮”，不是让 TE/TEK 重写或解释宏。

关联顺序：

1. `GetActionInfo(slot)` 的 `macroSpellID`；
2. `GetActionText(slot) → GetMacroInfo()` / `GetMacroSpell()`；
3. 宏正文中当前推荐技能的本地化名称或数值 SpellID。

关联成功后，TE 输出该宏按钮的现有 BindingToken；TEK 仅按这个键。无关宏必须跳过。宏的条件、`@mouseover`、`#showtooltip`、`/castsequence`、`/use`、目标切换等由 WoW 宏系统最终处理；TEK 不补修饰键、不推断分支。

## 4. BindingToken schema 1

```text
Q E R F / 1 2 3 4 5 / Z X C V / T G / F1 F2 F3 F4 / `
ALT+Q/E/R/F/1/2/3/4
CTRL+1/2/3/4/`
MOUSEWHEELUP / MOUSEWHEELDOWN / BUTTON3
```

未支持键、无绑定、Token=0、解码失败必须 `NoBinding/Blocked`，绝不猜键或自动回退 v2。

## 5. 会话与暂停

- 每次 WoW 登录默认 `paused`，本次会话需玩家手动启动。
- `manual_keep`：脱战保持 Armed；
- `pause_out_of_combat`：默认。脱战输出 `paused`，进战自动恢复；
- `close_out_of_combat`：离开战斗事件后关闭，下一场需手动启动。
- 聊天、键盘焦点、宏编辑、按键绑定编辑、StaticPopup 应输出 `paused`；TEK 因 `frame_state_paused` 不派发。该路径仍需 WoW 实测。

## 6. TEK

- TEK v3 只按 frame.binding_token 构造输入计划，不要求 ActionCode 或 Legacy Profile 映射。
- 协议模式设置显式为 `v3_dynamic` 或 `v2_legacy`；收到非期望协议帧时 `protocol_mode_mismatch` fail-closed。
- 全局限速默认 10/s，设置范围 5–20；滚轮默认 5/s，设置范围 1–5。
- 无总次数预算；同一推荐可随 freshness 连续处理，但受限速和所有安全门约束。
- 单次 SendInput 失败先 Blocked；5 秒内连续 3 次才 ErrorLocked；任意成功清零失败窗口。

## 7. 待验证与后续

- 主动作条分页、Bonus Bar、姿态/变形按钮实机映射；
- 聊天/输入/弹窗暂停；
- 用户物理按键协作与注入事件区分；
- 载具/控制/覆盖/任务特殊条显式阻断；
- 当前映射导出、非激活 TEK 状态窗、DPI/多显示器与第三方动作条支持。
