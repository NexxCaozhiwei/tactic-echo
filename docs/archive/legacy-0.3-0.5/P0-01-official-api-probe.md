# P0-01 官方推荐 API 探针

> 目标客户端：WoW 12.0.7，简体中文客户端（zhCN）。

## 目的

本探针只用于观察当前客户端中官方辅助战斗推荐 API 的存在性、返回结构和战斗/非战斗行为。它不发送按键、不创建宏、不实现职业循环。

## 安装

将仓库内 `addon/!TacticEcho/` 目录复制到 WoW 的 AddOns 目录，确保游戏插件列表中启用 `Tactic Echo`。

## 游戏内命令

```text
/teprobe
/teprobe scan
/teprobe status
/teprobe clear
```

- `/teprobe`：立即记录一条候选 API 观测。
- `/teprobe scan`：扫描 `_G` 中疑似辅助/推荐相关的 `C_*` API 名称。
- `/teprobe status`：打印当前已保存的观测数量。
- `/teprobe clear`：清空本探针保存的 P0-01 数据。

## 建议验证步骤

1. 登录复仇 DH，进入世界后执行 `/teprobe status`。
2. 在非战斗状态执行 `/teprobe` 与 `/teprobe scan`。
3. 进入战斗，等待 5 到 10 秒，期间使用几次技能。
4. 战斗中执行一次 `/teprobe`。
5. 脱战后退出游戏，读取 SavedVariables。

## 数据位置

SavedVariables 文件通常位于：

```text
World of Warcraft/_retail_/WTF/Account/<账号>/SavedVariables/TacticEcho.lua
```

请回传 `TacticEchoDB.p0_01` 相关内容，或直接提供该文件。

## 预期产出

- 客户端 build、interface、locale；
- 候选 API 是否存在；
- 候选 API 在非战斗和战斗中调用时是否成功；
- 返回值类型和简短字符串化结果；
- 疑似辅助/推荐相关 API 名称清单。

## 观测记录

### 2026-06-26 初次非战斗观测

- 客户端：WoW 12.0.7，interface `120007`，locale `zhCN`；
- 角色：`PALADIN`，specIndex `3`；
- `C_AssistedCombat.IsAvailable()` 存在，返回 `true, ""`；
- `C_AssistedCombat.GetNextCastSpell()` 存在，返回数字 SpellID：`20271`；
- `C_AssistedCombat.GetNextSpell()`、`GetRecommendedSpell()`、`GetNextRecommendedSpell()`、`IsEnabled()` 未发现；
- `/teprobe scan` 发现额外相关 API：`C_AssistedCombat.GetActionSpell`、`C_AssistedCombat.GetRotationSpells`；
- 当前 40 条观测均为非战斗记录，尚未覆盖 `inCombat=true`。

结论：P0-01 已确认官方辅助战斗命名空间存在，且最小推荐入口很可能是 `C_AssistedCombat.GetNextCastSpell()`。完成 P0-01 前仍需战斗中记录，并验证返回 SpellID 与游戏内官方推荐的一致性。

### 2026-06-26 战斗中观测

- SavedVariables：`WTF/Account/VINZCN/SavedVariables/!TacticEcho.lua`；
- 观测数量：40 条，其中 33 条为 `inCombat=true`；
- `C_AssistedCombat.GetNextCastSpell()` 在战斗中稳定返回数字 SpellID；
- 已解析到的返回示例：
  - `383328`：最终审判；
  - `343527`：处决宣判；
  - `255937`：灰烬觉醒；
  - `20271`：审判；
- `C_AssistedCombat.GetRotationSpells()` 返回当前轮转 SpellID 表：
  `{20271, 53385, 184575, 255937, 343527, 375576, 383328, 407480}`；
- `C_AssistedCombat.GetActionSpell()` 返回数字 `1229376`，语义仍需后续确认；
- `C_AssistedCombat.IsAvailable()` 在观测中可用并返回 true。

结论：P0-01 的核心 API 可用性已验证。后续 `RecommendationAdapter` 可先以 `GetNextCastSpell()` 作为官方推荐入口，但仍需在 DH 最小闭环中确认它与屏幕官方推荐显示一致。

## 注意

P0-01 完成前，不得将任一候选 API 写入稳定实现。观测结果只作为后续 `RecommendationAdapter` 设计输入。
