# Tactic Echo 1.4.0 基线：多技能组自动注入

## 基线结论

`1.4.0` 将用户可见 AutoBurst 泛化并更名为“自动注入”。每个专精最多三个独立配置组，共享一个 Coordinator 和既有 OrderedPlan 执行器；不存在三套并行状态机、事件、轮询或输入派发器。

## 已冻结行为

- 每组使用稳定 `groupId`，独立保存名称、启用、模式、窗口、最多六个注入、饰品 13/14、九步顺序和 `offGCDExplicit`。
- 空闲时通过 `windowSpellID → groupId` 索引精确匹配官方推荐；活动时只有 `activeGroupId` 可评估并产生候选。
- 其他组窗口在所有权期间只记录诊断，不抢占、不排队、不补发；必须观察新的离开/进入边沿。
- 当前计划冻结 groupId、窗口和 sequence signature；未活动组配置变化不会触发 `rule_changed`，活动组行为配置变化或关闭会安全终止。
- 窗口收据、代次和离开锁按组保存/切换；普通窗口仍沿用精确成功、稳定自身非 GCD 冷却或充能减少的重入保护。
- 旧 `autoBurstEnabled`、`autoBurstMode`、每专精 `autoBurstSequence` 只迁移一次到组 1，并保持 1.3.0 的实际顺序与启用行为。
- 设置页可操作完整九步；HUD 只投影活动、命中或设置选中组，并在第一份有效结构快照直接显示。

## 安全边界

- 唯一输入路径仍是：官方推荐/自动注入候选 → 已验证默认动作条 → BindingToken → TEAP v3 → TEK 全部门禁 → 单次 SendInput。
- TEAP v3 长度、Burst flags `0x20` 和 `dispatchOrigin="burst"` 均未修改；groupId 不进入协议。
- HUD 卡保持 `displayOnly=true`、`bindingToken=0`，不得反向授权推荐、计划、TEAP 或 TEK。
- 脱战硬门控、宏资格、GCD/资源稳定确认、失败回执、手动让权、前台、Hook、CRC、会话、新鲜度、重放防护和全局限频保持不变。

## 验收

- `python scripts/verify-baseline-contract.py --repo-root .`
- `python -m pytest -q tek/tests tests/unit`
- `python -m unittest discover -s tek/tests -q`
- `python -m unittest discover -s tests/unit -q`
- `python -m compileall -q tek/src tek/app tek/runtime`
- 全部 AddOn Lua 文件通过 `luac -p`。

Windows/WoW 实机仍需验证：三个组的设置交互、普通技能窗口边沿、跨组错过窗口不补发、活动组改动终止、九卡 HUD 首帧稳定显示，以及各职业真实动作条/宏/饰品组合。

## 交付要求

- `VERSION`、TOC、`Core/Bootstrap.lua` 必须保持 `1.4.0` 一致。
- 当前基线文档为 `docs/baselines/BASELINE_1.4.0.md`，历史基线只作追溯。
- 未经明确要求不得推送、创建 PR、发布 Release 或部署到游戏目录。
