# Codex 接手提示词

你正在维护 `tactic-echo` 当前基线版本 `0.9.0`。本项目的功能基线来自已验证的 `0.8.11-trace-retention` 工作树；禁止复制、迁移、对比或叠加任何历史高版本源码、补丁或测试。开始前先阅读：`AGENTS.md`、`HANDOFF.md`、`PROJECT_CONTEXT.md`、`TASKS.md`、`DECISIONS.md`、`AUDIT_REPORT.md` 和 `docs/README.md`。

## 必须保持的架构边界

1. 唯一现实输入链路固定为：官方主推荐 → 暴雪默认动作条已有现实绑定 → TEAP v3 → TEK 安全门禁 → SendInput。
2. 候选、打断、防御、爆发、控制、位移和 HUD 全部只读；不得生成 Token、改官方主推荐、改 TEAP 或发起 TEK 输入。
3. HUD 默认只消费 `TacticalAdvisors` 快照。唯一例外是 `TacticalIconButton` 为受保护的 CD/GCD 值直接调用原生 `CooldownFrameTemplate:SetCooldown()`；该调用只能停留在展示层，原始值不得进入 `TacticalHudModel`、策略、TEAP 或 TEK。所有 HUD 模块均不得动态注册事件或写动作条。
4. 对 WoW cooldown/charge/aura 等潜在 secret number，任何比较、算术、格式化、`tostring`、拼接或 `table.concat` 都不能直接作用于原值。必须先在 `pcall` 内验证为普通 Lua 值；失败时清除该字段。仅冷却转盘允许把原始 start/duration 直接交给原生 `CooldownFrameTemplate:SetCooldown()`，不得解释、比较或传播这些值。
5. 所有 AddOn 事件订阅仅允许 Bootstrap 加载期安全注册；Tactics/UI 模块使用轮询/快照，不要运行期 `RegisterEvent()` / `UnregisterEvent()`。
6. 只保证默认动作条。载具、控制单位、覆盖条、宠物战斗硬阻断；ExtraActionBar 仅观察。
7. 不复制第三方插件代码、素材或运行时依赖；可参考交互思路，但 TE 只做独立的只读实现。
8. 防御资料必须按完整 `CLASS_SPECINDEX → empty` 解析；缺少专精身份或条目时返回空集，绝不回退到职业级列表。每条记录必须保留 `spellID`、类型、有效优先级和适用条件；不得为任何单独职业、SpellID 或键位写特例。
9. `GetBindingKey(command)` 的主、次绑定必须显式分别检查；不可用 `ipairs({ primary, secondary })` 遍历可能为 nil 的键位。有效解析出的现实绑定优先于未绑定重复项。
10. HUD 图标主体必须保持原始纹理颜色。允许 `UI/TacticalIconEffects.lua` 在独立展示层创建经 TEUI 开关控制的暴雪 atlas 跑马边框、Proc、打断、爆发、位移、按键闪烁和引导填充效果；任何效果不得改建议、绑定、BindingToken、TEAP 或 TEK。不得把效果实现回每个规划器。
11. HUD 快捷键标签可以把 `SHIFT/CTRL/ALT` 缩写为 `S/C/A`，但只限显示层；不得改变 `ActionBarBindingResolver` 的派发修饰键白名单、BindingToken、TEAP 或 TEK 输入策略。
12. 脱战防御待命只允许当前专精已知且动作条存在真实绑定的技能；必须固定 `BindingToken=0`，不得成为派发候选。
13. 爆发/防御列表均以显式 `CLASS_SPECINDEX` 注册表为唯一数据入口。爆发没有种子资料的专精保持空列表；防御 UI 只允许重排或停用当前专精现有项。爆发触发/注入候选、饰品和药水提示永远不能进入 TEAP/TEK。
14. 性能约束：每轮 TacticalAdvisors 刷新仅采样一次 ProtocolMonitor、环境和 GCD 上下文；BurstPlanner 已生成的 iconState 必须复用；TacticalBoard 只能订阅快照，不能再建第二条全量 OnUpdate 刷新。模型不得为物理空槽创建卡片；布局与效果必须有签名缓存。

## 当前实现重点

- 队列式 HUD：横向、纵向、环绕布局；防御队列可拆分。
- 固定候选/防御槽位，防抖、淡入淡出、单图标 fail-soft。
- 图标可显示冷却/充能、按键、层数、状态遮罩和 Tooltip；secret value 不可靠时降级为未知。
- 明确视觉状态：官方主推荐、预览候选、打断、防御、可派发、已阻止、状态未知、无绑定、暂停。
- 防御注册表：13 个职业、39 个专精均有显式数据；用户配置可在当前专精统一防御列表中调整/停用现有技能；爆发触发和注入列表可排序、启用/停用，并可加入当前专精已知技能。

## 修改后的最低验证

```bash
PYTHONPATH="$PWD" python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

此外必须运行：`python scripts/verify-baseline-contract.py --repo-root .`。若系统提供 `texluac` 或 `luac`，再对全部 AddOn Lua 执行语法检查；确认 HUD/Tactics 文件不存在直接 `RegisterEvent(`。
