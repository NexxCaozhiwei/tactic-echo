# Tactic Echo 1.0.31 基线：切图预战桥接安全围栏

- 切图/载入事件会撤销仅用于脱战起手的隐式 `preCombatBridge` 权限，清空任何未完成的 bridge 计划、Capture 和窗口锁；该清理不得创建新的窗口离开锁。
- 普通 in-combat AutoBurst 不受该围栏影响；真实 `PLAYER_REGEN_DISABLED` 后围栏解除并按正常 combat epoch 重新评估官方窗口。
- 切图后若需要脱战起手，沿用已有“运行”动作重新授权，无新增 UI 标签或设置；首次前置序列仍必须完成 4 个 transport tick 的 observation-only handoff。
- 围栏只限制脱战 bridge，不为普通脱战官方推荐增加派发资格。
