# P0-05 惩戒骑隐藏安全按钮绑定

## 目的

TE 参照旧 WR 的执行思路，不要求用户把宏拖到动作条。插件在游戏内为每个 ActionID 建立隐藏 `SecureActionButtonTemplate`，并把 TEK Profile 中的组合键绑定到对应按钮。

状态：TOC 加载顺序与契约测试已修复；真实游戏内 `/tebindings` 与 `/tebindings check` 仍需在 `/reload` 后重新人工核验。

执行链路：

```text
TEK 发送组合键
-> WoW 命中 TE 绑定
-> 点击隐藏安全按钮
-> 执行按钮 macrotext
-> /cast 对应技能
```

## 命令

```text
/tebindings
/tebindings check
/temacros
/temacros check
```

- `/tebindings`：非战斗状态下创建或更新隐藏按钮与按键绑定。
- `/tebindings check`：只检查隐藏按钮和绑定状态。
- `/temacros`：兼容旧命令，当前等同于 `/tebindings`。
- `/temacros check`：兼容旧命令，当前等同于 `/tebindings check`。

## 默认绑定

当前默认绑定使用相对冷门的 `SHIFT+字母`，并允许必要时使用 `SHIFT+0` 这类数字键，避免 `SHIFT+1~6` 这类常见动作条翻页冲突。

当前唯一可运行 TEK Profile 是 `laptop`。`desktop-numpad` 与这里的游戏内绑定不一致，已标记为不可运行示例，live / SendInput 路径必须阻断。

| ActionID | SpellID | 隐藏按钮 | WoW 绑定 | TEK Profile |
|---|---:|---|---|---|
| `PALADIN_RETRIBUTION_JUDGMENT` | 20271 | `TacticEchoSecureAction1` | `SHIFT-Z` | `SHIFT+Z` |
| `PALADIN_RETRIBUTION_BLADE_OF_JUSTICE` | 184575 | `TacticEchoSecureAction2` | `SHIFT-X` | `SHIFT+X` |
| `PALADIN_RETRIBUTION_DIVINE_STORM` | 53385 | `TacticEchoSecureAction3` | `SHIFT-C` | `SHIFT+C` |
| `PALADIN_RETRIBUTION_TEMPLAR_STRIKE` | 407480 / 406647 | `TacticEchoSecureAction4` | `SHIFT-G` | `SHIFT+G` |
| `PALADIN_RETRIBUTION_HAMMER_OF_WRATH` | 24275 | `TacticEchoSecureAction5` | `SHIFT-H` | `SHIFT+H` |
| `PALADIN_RETRIBUTION_WAKE_OF_ASHES` | 255937 | `TacticEchoSecureAction6` | `SHIFT-N` | `SHIFT+N` |
| `PALADIN_RETRIBUTION_DIVINE_TOLL` | 375576 | `TacticEchoSecureAction7` | `SHIFT-R` | `SHIFT+R` |
| `PALADIN_RETRIBUTION_HAMMER_OF_LIGHT` | 427453 | `TacticEchoSecureAction8` | `SHIFT-T` | `SHIFT+T` |
| `PALADIN_RETRIBUTION_FINAL_VERDICT` | 383328 | `TacticEchoSecureAction9` | `SHIFT-Y` | `SHIFT+Y` |
| `PALADIN_RETRIBUTION_EXECUTION_SENTENCE` | 343527 | `TacticEchoSecureAction10` | `SHIFT-0` | `SHIFT+0` |

## 覆盖/二阶段技能规则

部分 WoW 技能在动作条或法术按钮上表现为“覆盖技能”或“二阶段技能”：官方推荐 API 可能返回二阶段 SpellID，但游戏客户端实际可点击的宏入口仍是覆盖源技能。此时不能简单把推荐 SpellID 的本地化名称写进 `/cast`。

处理规则：

- `ActionRegistry.spellIDs` 仍记录官方推荐 SpellID，用于 TE 识别和 TEAP ActionCode 输出。
- 如执行入口必须走覆盖源技能，Action 元数据使用 `macroCastSpellID` 指定真正写入 macrotext 的 SpellID。
- 如同一官方动作在游戏内存在二阶段候选，Action 元数据可使用 `macroCastSpellIDs` 写入多行 fallback macrotext；这只能用于同一个语义动作的阶段兼容，不得用于堆叠多个独立爆发动作。
- TEK Profile、ActionCode、绑定键位不因此改变；改变的是隐藏安全按钮的 `macrotext`。
- 必须在文档中写明“推荐 SpellID”和“宏执行 SpellID”的差异，并用 `/tebindings check` 或 SavedVariables 证明按钮 body 已更新。
- `input_sent` 只能证明 TEK 发送了绑定键；若游戏中二阶段未触发，应优先检查 macrotext 是否错误地直接 `/cast` 二阶段技能名。

当前已知案例：

| ActionID | 官方推荐 SpellID | macroCastSpellID / macroCastSpellIDs | 原错误 | 修正 |
|---|---:|---:|---|---|
| `PALADIN_RETRIBUTION_JUDGMENT` | 20271 | 24275, 20271 | 审判推荐持续显示时，二阶段愤怒之锤可能无法由单一 `/cast 审判` 稳定触发 | 生成两行 macrotext：先 `/cast 愤怒之锤`，再 `/cast 审判` |
| `PALADIN_RETRIBUTION_HAMMER_OF_WRATH` | 24275 | 24275, 20271 | 独立愤怒之锤动作在覆盖状态下可能只发到不生效的单一技能名 | 与审判使用同一 fallback macrotext：先愤怒之锤，再审判 |
| `PALADIN_RETRIBUTION_HAMMER_OF_LIGHT` | 427453 | 255937 | `/cast 圣光之锤` 二阶段不能稳定触发 | 使用灰烬觉醒技能名生成 macrotext，即 `/cast 灰烬觉醒` |

## 验证步骤

1. 非战斗状态执行 `/tebindings`。
2. 执行 `/tebindings check`，预期当前惩戒骑 10 个动作均为 `ready` 或本次刚刚 `bound`。
3. 若某按键已有旧绑定，`TacticEchoDB.bindings.backups` 必须记录可恢复的旧 Binding Action。
4. 执行 `/reload`，让 `!TacticEcho.lua` 落盘。
5. Codex 读取 `TacticEchoDB.bindings.records` 与 `TacticEchoDB.bindings.backups`。
6. 进入战斗后若再次建立绑定，预期缺失或不匹配项返回 `blocked / in_combat`，不得假装成功。

## 注意

- 隐藏安全按钮仍遵守 WoW 保护机制；战斗中不能创建按钮、改 macrotext 或改绑定。
- `input_sent` 只代表 TEK 已发送按键，不代表 WoW 一定施法成功。
- `PALADIN_RETRIBUTION_JUDGMENT` 与 `PALADIN_RETRIBUTION_HAMMER_OF_WRATH` 当前隐藏按钮会生成二阶段 fallback macrotext，预期 body 包含 `/cast 愤怒之锤` 与 `/cast 审判` 两行；更新后必须重新 `/tebindings`，否则旧按钮仍可能保留单行 body。
- 后续需要做可配置 Profile，允许用户避开自己已有的组合键。
- `PALADIN_RETRIBUTION_HAMMER_OF_LIGHT` 官方推荐 SpellID 为 `427453`，但隐藏按钮 macrotext 使用 `255937` 灰烬觉醒的技能名执行，依赖 WoW 客户端的覆盖技能机制触发圣光之锤二阶段。
- `PALADIN_RETRIBUTION_TEMPLAR_STRIKE` 当前同一 ActionID 覆盖 `407480` 与 `406647`，宏策略为 `primary_spell_name_manual_verify`；两个推荐状态下是否都能正确施放仍待人工验证。

## 历史说明

早期 P0-05 曾创建账号宏用于验证宏模板；该路径已被隐藏安全按钮绑定取代。旧 `/temacros` 命令保留为兼容入口。
