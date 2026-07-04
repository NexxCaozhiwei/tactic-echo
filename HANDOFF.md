# Tactic Echo Handoff — 1.0.45 P5.1

## 当前状态

- P4.3 已实机验证 reaction：已有打断键位可经 BindingToken → TEAP reaction → TEK → 游戏内动作完成一次打断。
- P4.4 保持严格的可打断资格：直连 API、单位施法事件或真实原生盾组件连续视觉证据；`showShield`/`barType`/scalar-only true 不可授权输入。
- P4.5 保留严格 `@mouseover → @focus → target` 同技能整合宏守卫；焦点/当前目标候选若会被更高宏分支抢占，仍零按键并记录 `macro_priority_preempted_by_<source>`。
- P5.1 修复 P5 的 Retail 实机误判：反制射击宏在动作条上可能以代表 SpellID `147362` 出现，而非宏 index。此时只读采用“动作条宏名 + 代表 SpellID + 宏正文语义”的唯一匹配；同名不同技能宏会被排除，同名同技能多候选仍 fail-closed。P4.6 `/cast` 令牌→SpellID 关联仍保留。
- P4.6 不改 TEK；已具备 P4.3 reaction 去重的 TEK.exe 可继续使用。

## 已覆盖宏形态

```lua
#showtooltip
/stopcasting
/cast [@focus,nodead] 反制射击
/cleartarget
/targetenemy
/cast 反制射击
/targetlasttarget
```

P2 应将该宏标记为 `macro_target_switch_fallback_auto` / `macro_managed_target`，为 `focus` 与 `target` 两条路由登记同一个已有真实键位。目标处理仍全部由玩家宏完成；TE 不执行任何 `/target*` 命令。

## 下一次实机验证

1. 将上述反制射击宏放在当前可见 Blizzard 默认动作条并绑定受支持键位。
2. `/reload` 后打开自动打断设置，确认“反制射击”显示为已识别焦点/当前目标宏，而不是“未找到”。
3. 若仍未识别，执行 `/tecache refresh`、`/temapping p51_macro_action_identity`，保存退出后提供 `TacticEcho.lua`；映射导出应包含 `macroIdentitySource`、`macroActionInfoMacroIndex`、`macroActionInfoReadAttempts`、`macroResolvedSpellTokenCount` 与失败原因，不含宏正文。
4. P4.4 的可打断证据与 P4.5 的整合宏场景继续按既有文档验证。

## 不在本版范围

- 自动单体控制与群控；
- 自动选目标、移动鼠标、点击姓名板；
- 宏改写、宏创建、写入绑定；
- TEAP/TEK 输入路径、AutoBurst 策略与 HUD 冷却展示变更。
