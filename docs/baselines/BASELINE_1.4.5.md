# Tactic Echo 1.4.5 基线：自动注入状态机所有权与稳定确认

## 基线结论

`1.4.5` 修复多组自动注入的虚假所有权、同一窗口重复代次、错误 runtime 命名空间、饰品预测性冷却误确认、非法组 HUD READY 误导和高频完整 Normalize。唯一 AutoInjectionCoordinator 与唯一 AutoBurst OrderedPlan 架构保持不变。

## 所有权与窗口代次

- `matchedGroupId` 只表示官方推荐匹配某个合法组窗口；匹配、规则构造、预检与绑定验证都不取得所有权。
- `activeGroupId` 只在执行器已经持有 plan、pre-window capture 或 departure lock 后由 `Claim(groupId)` 建立。Coordinator 判断其他窗口是否“活动期间错过”前必须重新核对执行器真实 `owns`；没有所有权的残留身份先释放。
- `pre_window_capture_recover` 是每个 armed epoch 的一次性首次健康观察能力。一次预检失败并返回 `none` 后，同一仍可见窗口不能再次增加 `windowGeneration` 或被自动注入接管；必须观察到窗口离开并重新进入。
- paused → armed 可对继承的前置窗口合法恢复一次，且继续经过既有 handoff barrier。已消费代次和 departure lock 不能被恢复分支绕过。

## Runtime 与失效处理

- group runtime key 固定为 `<profileKey>:<groupId>`。只有同时取得明确 profileKey 和 groupId 才能切换；生产运行不得创建 `unknown:<groupId>`。
- 活动组模式变化、关闭或配置非法时，执行器先在当前正确 runtime 中终止 plan/capture、建立必要 departure lock 并保存状态，然后才清除或切换身份。
- 不同专精即使都使用 `group-1`，窗口代次、已确认收据和 departure lock 也完全隔离。

## 确认、HUD 与性能

- 精确 `UNIT_SPELLCAST_SUCCEEDED` 仍立即确认技能。所有仅凭自身非 GCD 冷却开始或充能减少的回退，包括饰品 13/14，必须至少两个不同观察样本稳定持续 `0.15s`；期间回滚、失败或装备变化不会推进。
- HUD 读取 `AutoInjectionGroups:Validate()` 的 revision 缓存。合法组显示 READY/ACTIVE；非法启用组显示 INVALID、具体冲突与“不会执行”，所有卡片保持 `bindingToken=0`、`burstReady=false`、只读且不 Claim。
- AutoBurst 第一次设置读取可执行一次完整 Normalize；之后高频 Evaluate 直接读取当前 `TacticEchoDB.tactics`。设置保存、总开关变化和组 revision 仍在下一次 Evaluate 生效，不新增定时器或轮询。
- persistent recovery 继续保持永久 fail-closed 策略。本版本只导出活动状态、持续时间、步骤键、动作类型、候选次数、确认可用性和最近原因等纯标量，不把候选次数、等待时间或普通 GCD 当作成功。

## 协议与安全边界

- 未修改 BindingToken、TEAP v3 20 字节、flags `0x20`、`dispatchOrigin="burst"`、TEK、前台/Hook/手动让权/新鲜度/限频门禁或单次 SendInput。
- 未新增并行状态机、Coordinator、事件、OnUpdate、轮询器、候选源或输入路径；脱战硬门控和退役模块冻结范围不变。
- 离线 Python/Lua 测试不能替代 WoW Retail 与 Windows 实机对前台、Hook、真实 SendInput、动作条、宏、GCD/队列窗口和预测性冷却回滚的验收。
