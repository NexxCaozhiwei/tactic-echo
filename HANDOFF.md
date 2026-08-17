# Tactic Echo 1.4.4 交接

## 当前状态

- 当前唯一开发基线：`1.4.4`。
- 当前产品范围：首页/设置中心、HUD 主键、官方主推荐输入链路，以及最多三个自动注入组。
- 自动注入继续复用 AutoBurst OrderedPlan；运行时只有一个 Coordinator、一个活动组、一个 plan 和一个 pre-window capture。
- 打断、控制、防御、生存、TargetCastPrompt、姓名板群控扫描、只读反应高亮、监控/调试页、MappingExport 与 OfficialApiProbe 均已退役，不得恢复加载或派发。
- 版本化源码交付必须同时更新 `VERSION`、TOC、`Core/Bootstrap.lua`、`CHANGELOG.md` 和 `docs/baselines/BASELINE_<VERSION>.md`。

## 1.4.4 变更重点

1. `GetSpellBaseCooldown()` 的毫秒值固定在 API 边界转换为秒，运行时 `C_Spell`、动作条、Tooltip、充能 recharge 和 tracker 数值继续按秒处理。
2. 转换后不超过 2.5 秒的基础时长不能启动 HUD 自身 CD 兜底，避免奥术弹幕的 500ms 公共时序显示成 500s。
3. `SPELL_UPDATE_COOLDOWN` 作为全局失效事件重新校正所有活动 tracker 条目。
4. 只有 `maxCharges > 1` 的真实多充能技能进入 IconState、HUD、Tooltip 和 AutoBurst 充能语义；普通技能不显示 `1/1`。
5. HUD 数字继续只读取安全普通标量；Blizzard `DurationObject` 只绘制转盘并隐藏自身数字。

## 不可回归边界

- AutoBurst 不是第二条输入通道；候选必须经过已验证动作条来源、BindingToken、TEAP v3 和 TEK 全部门禁。
- 任何 `inCombat=false` 帧都不能创建或保留 Burst plan/capture，也不能产生 Burst candidate。
- HUD、Tooltip、转盘和诊断不得建立 Token、写 TEAP 或改变派发资格。
- 计划步骤只接受精确成功事件、自身非 GCD CD 开始或真实多充能减少确认；泛 GCD、UNKNOWN、单个失败事件和图标灰度不能确认成功。
- 战斗中不得直接重排或显隐受保护 HUD/secure 元素，只能记录 pending/dirty。
- 玩家真实键盘或动作条输入优先于后续自动派发。

## 下一步

按 [TASKS.md](TASKS.md) 完成 1.4.4 实机验收。任何实机失败都应先保存 AddOn 诊断、TEK Trace、角色/专精、注入组配置和大致时间点，再判断是展示、计划、BindingToken、协议还是 TEK 门禁问题。

离线测试通过不能替代 Windows Hook、真实 SendInput、WoW 施法顺序和 HUD 实时数值验收。部署状态也不是文档中的永久事实；每次交付仍需核对 live TOC 与代表性文件哈希。
