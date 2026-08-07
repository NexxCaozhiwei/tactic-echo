# Tactic Echo 1.2.0 基线：TEUI 精简与 AutoBurst 稳定版

## 产品范围

- 设置中心只保留“常规、HUD、自动爆发、配置文件”四页；独立主键页并入 HUD，调试监控和退役功能不得重新加载或展示。
- HUD 只创建主键卡与最多五张 AutoBurst 卡。候选历史、打断、控制、位移、防御和生存卡保持空输出或隐藏。
- HUD 内容只允许“主键 + 自动爆发”与“仅主键”；`queueMode` 是唯一内容来源，旧 compact、候选历史、来源标签和模块显隐冲突必须在规范化时清除。
- 配置文件管理保持可用；全局、角色、职业、专精范围映射保留并默认折叠在高级设置。

## AutoBurst 与 HUD 序列

- HUD 爆发栏必须直接读取当前专精保存的 `autoBurstSequence`，按启用后的真实顺序展示窗口、最多三个注入和锁定槽位饰品；不得恢复职业冷却、药水、种族技能或旧窗口候选拼装。
- 未绑定步骤只可作为 `bindingToken=0` 的只读卡片；HUD、Tooltip、转盘和状态文字不得创建派发资格或改变计划。
- 自动爆发快捷键保存为 `settings.autoBurstToggleHotkey`，只切换 `tactics.autoBurstEnabled`，并与整体启停快捷键互斥。
- 自动派发可用时，自动爆发关闭显示 `LCC`，开启显示 `HAD`；HUD 主键按钮仍使用原有状态语义。

## 噬灭恶魔猎手

- `DEMONHUNTER_3` 固定对应 `specIndex=3`、`specID=1480`；默认序列为 `window:1225826 → injection:1217605`（根除 → 虚空变形）。
- 根除前的资源状态不得提前丢弃后置虚空变形。根除精确确认后，虚空变形进入 `POST_WINDOW_RESOURCE_SETTLING` 并重新读取公开可用性布尔值。
- `GCD_LOCKED` 期间只观察；明确可用时立即在同轮派发。持续资源不足或 UNKNOWN 只有在两个不同 `RuntimeSnapshot.cycleId` 的非 GCD 样本上成立后才可跳过。
- 特殊 `usable=false` 兼容只允许用于 `DEMONHUNTER_3` 的 `1217605`，且必须已有验证动作栏来源与真实 BindingToken；不得读取具体资源数值。

## 输入与宏安全边界

- 唯一常规输入路径保持：官方推荐 → 当前默认动作条绑定 → BindingToken → TEAP v3 → TEK 门禁 → 单次 SendInput。
- AutoBurst 不能绕过 BindingToken、TEAP、TEK、前台、Hook、手动让权、新鲜度、CRC、会话或限频门禁。
- 共享宏资格统一经过 `ActionBarBindingResolver:IsVerifiedCurrentMacroSource()`；AutoBurst 额外经过 `IsAutoBurstMacroEligible()`。宏名、图标、宏列表存在和未知正文不得授权身份。
- 自动打断继续生产硬暂停；任何 `inCombat=false` 帧不得创建或保留 Burst plan/capture、Burst candidate、Burst TEAP 或 TEK 请求。

## HUD、冷却与战斗保护

- `DurationObject` 只负责客户端原生转盘，CountdownNumbers 始终隐藏；HUD 徽标只使用安全标量并统一显示向上取整的纯秒数。
- 主键、Burst window 与物品卡隐藏纯共享 GCD/`61304`；自身非 GCD 冷却与充能冷却仍优先显示。
- 战斗中 HUD 卡片、secure proxy、blocker 和容器不得执行受保护的显隐、透明度、缩放或布局变更，只能记录 pending/dirty 并在脱战后应用。
- HUD/原动作条真实左键继续优先写入 `manual_hold`，在让权窗口中输出动作码 0、BindingToken 0。

## 性能与诊断

- 不新增高频 OnUpdate；AutoBurst 复用 SignalFrame、官方推荐与共享 `RuntimeSnapshot`。
- Signal 历史保持语义变化即时记录、稳定状态 0.5 秒心跳；AutoBurst 持续进度日志按计划/步骤/阶段合并。
- 保留 AutoBurst 计划创建、预检、派发、确认、中止、释放及顺序诊断；不得导出宏正文、原始受保护冷却数值或具体资源值。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tests/unit/test_teui_simplification_contract.py tests/unit/test_auto_burst_hotkey_status_contract.py tests/unit/test_state_display_unification_contract.py tests/unit/test_auto_burst_phase1_behavior.py tests/unit/test_burst_profile_configuration_table_contract.py tests/unit/test_current_scope_efficiency_contract.py`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
