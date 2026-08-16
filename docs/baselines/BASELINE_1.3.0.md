# Tactic Echo 1.3.0 基线：AutoBurst 稳定锁链、真实派发 HUD 与结构收口

## 基线结论

`1.3.0` 是 P1、P2、P3 均完成实机测试后的正式稳定基线。当前产品范围只保留官方主推荐与 AutoBurst；本基线冻结爆发链派发时序、HUD 用户可见状态和当前加载链路结构，后续修改不得恢复已退役模块或绕过既有输入安全边界。

## 已确认行为

- AutoBurst 创建计划后按当前专精保存的真实 sequence 锁定步骤，官方推荐旋转、共享 GCD 和单次失败事件不会越过当前步骤或重排爆发链。
- 首实际步骤只在 `READY_NOW` 建立逻辑派发；后续受 GCD 影响的步骤在 `GCD_LOCKED` 保持无 Token 所有权，进入 `QUEUE_WINDOW` 或 `READY_NOW` 后才建立逻辑派发。
- 精确失败回执按逻辑尝试去重；失败后经过 observation-only 隔离，并只在 `READY_NOW` 创建安全重试。步骤仍只由精确成功事件、稳定自身非 GCD 冷却或充能减少确认。
- HUD 只在真实 Burst TEAP 帧具有有效 BindingToken、`dispatchAllowed=true` 且非 observation-only 时，对精确技能或饰品卡显示“派发”；内部校验、等待、确认与重试过程不显示。硬阻止继续显示“阻止”。
- AutoBurst HUD 按当前专精保存顺序展示一个窗口、最多六个注入和两个饰品，共九张卡；HUD 卡始终为只读、`bindingToken=0`。
- 当前加载的 `TacticalAdvisors`、设置中心和 AutoBurst HUD 投影不包含旧打断、控制、Reaction P3、候选预测、重复 `window/followups` 视图或孤儿局部 helper。

## 安全边界

- 唯一输入路径保持为：官方推荐/AutoBurst 候选 → 已验证默认动作条 → BindingToken → TEAP v3 → TEK 全部门禁 → 单次 SendInput。
- HUD、样式、Tooltip、冷却展示和诊断不得创建 BindingToken、改写推荐、写入 TEAP 或请求 TEK 输入。
- `inCombat=false` 时不得创建或保留 Burst plan/capture，不得产生 Burst candidate、TEAP Burst 帧或 TEK 请求。
- 宏资格继续统一由 `ActionBarBindingResolver:IsVerifiedCurrentMacroSource()` 与 `IsAutoBurstMacroEligible()` 管理；未知宏正文和 opaque action-info 兼容不得授权 AutoBurst。
- 手动让权、前台、Hook、CRC、会话、新鲜度、重放防护和全局限频门禁均保持不变。

## 验收基线

- P1、P2、P3 均已完成用户实机测试并确认通过。
- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。
- 完整测试预期：`654 passed, 7 skipped, 17 subtests passed`；七项跳过仅为已退役自动打断候选派发历史契约。

## 交付要求

- `VERSION`、`!TacticEcho.toc`、`Core/Bootstrap.lua` 必须保持 `1.3.0` 一致。
- 当前基线文档为 `docs/baselines/BASELINE_1.3.0.md`；此前 `1.2.x` 文件只作为阶段历史。
- 正式部署必须镜像到 `_retail_/Interface/AddOns/!TacticEcho`，并核对 TOC 版本与关键源码 SHA256。
