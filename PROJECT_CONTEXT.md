# Tactic Echo 项目上下文 — 1.5.0

## 当前基线与范围

当前唯一开发基线是 `1.5.0`。最高优先级规则位于 `AGENTS.md`；当前版本行为以 `docs/baselines/BASELINE_1.5.0.md`、实时源码和测试共同解释。

产品范围只保留：首页/设置中心、HUD 主键、官方主推荐输入链路，以及最多三个自动注入组。打断、控制、防御、生存、TargetCastPrompt、姓名板群控扫描、反应高亮、监控/调试页、MappingExport 与 OfficialApiProbe 是历史功能，不得从旧配置或历史文档恢复。

## 输入与自动注入

唯一输入通道为：

```text
官方推荐（只读）
→ 主键或 AutoBurst OrderedPlan 候选
→ 当前已验证 Blizzard 默认动作条/宏
→ BindingToken
→ TEAP v3
→ TEK 全部门禁
→ 单次 SendInput
```

每个专精最多配置三个平级自动注入组。每组有一个窗口、最多六个注入技能和饰品 13/14；HUD 最多展示 27 张组内顺序卡。所有组共享一个 Coordinator、一个活动组和一套 AutoBurst plan/capture 状态机。活动计划不被其他组窗口抢占或递归生成新计划。

窗口和步骤必须使用稳定技能/装备身份，不保存动作条位置或瞬时键位作为步骤身份。宏来源必须经过共享解析器验证当前按钮/槽位、当前宏身份和正文语义；AddOn 不创建、不修改宏，也不保存宏正文。

## 计划与确认

计划创建和每步派发前都使用共享 RuntimeSnapshot、IconState/CooldownResolver、GCDGate 和当前动作条绑定进行预检。共享 GCD 是时序，不是技能自身 CD。初始自身 CD 步骤不进入活动前缀，但位于单向游标之后的步骤保留为候补；在计划结束前恢复后只按原始位置向后补入，不重建或重放前缀。

当前步骤只由精确 `UNIT_SPELLCAST_SUCCEEDED`、自身非 GCD CD 开始或真实多充能减少确认。明确资源不足仍需两个不同共享快照确认；通用 `usable=false/false` 只暂停当前步骤并输出无 Token hold。已进入活动链的可选步骤不会因两个匹配失败被删除；失败发生时若玩家正在移动，则持续无 Token 等待，停下后经隔离帧重试同一步。

任何脱战帧都必须先清除 plan/capture，再返回无 Burst 候选。进战从干净 encounter epoch 开始。

## HUD 与冷却

HUD 只消费普通标量快照，不拥有派发权限。主键和全部已启用组按配置顺序显示；只有真实 Burst 候选的活动组当前步骤显示派发状态。

HUD 有安全动作槽秒数时由 IconState/Tracker 向上取整显示纯秒；已验证技能自身 CD 数值为 opaque 时，允许同一最终 DurationObject 显示客户端原生准确倒计时并清空 TE 徽标。纯共享 GCD 隐藏；普通技能的 `1/1` 隐藏；只有 `maxCharges > 1` 的真实多充能技能显示充能。

HUD 卡、secure proxy、blocker、主容器和布局在战斗中不得直接执行受保护的显隐、透明度、缩放、位置或尺寸变化，必须延迟到脱战应用。

## 交付边界

每次版本化源码修改必须同步：`VERSION`、AddOn TOC、`Core/Bootstrap.lua`、`CHANGELOG.md` 和 `docs/baselines/BASELINE_<VERSION>.md`。根目录不得保存 baseline 或 patch manifest 副本。

单元测试、合同测试、Python compileall 和 Lua 语法检查只证明离线合同；Windows Hook、前台判断、真实 SendInput、SpellQueueWindow、宏行为、自动注入顺序和 HUD 实时数字必须实机验证。部署还必须核对 live TOC 和代表性 SHA256。
