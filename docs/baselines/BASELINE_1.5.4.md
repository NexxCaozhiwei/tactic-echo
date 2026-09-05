# Tactic Echo 1.5.4 基线

`1.5.4` 修复新一轮窗口在冷却结束边沿被错误转换为不可恢复离开锁的问题，保留 1.5.3 的单向顺序与施法期精确收据规则。

## 故障与原因

- 惩戒骑前四轮计划完成后，第五轮官方窗口 343527 在距上次成功约 59.915 秒出现；当帧采样为自身 CD。
- 旧 `duplicateConfirmedWindowCooldown` 分支仅检查同技能、本场战斗曾成功过，即消费新的窗口代次、释放 capture 并建立 `requireWindowDeparture`。
- 后续同一官方推荐在采样之前直接返回等待；即使实际冷却已恢复，也不能再次复检。日志记录约 15 秒无 Token 观察帧，不能据此确定最初剩余 CD 或量化 DPS 损失。

## 可恢复重入等待

- 仅替换上述未派发重入冲突分支；已完成或硬终止的防重放离开锁不放宽。
- 保留同一个窗口代次，不写入 `consumedWindowGeneration`，不创建计划、不发布候选；由现有唯一 capture/Coordinator 保持所有权。
- 窄例外：窗口排首的重入冲突也可复用同一个 observation-only capture。它不是隐藏计划，不会允许窗口或后续注入提前派发。
- 在既有健康业务节奏中只采样当前窗口，不逐帧重做整条可选步骤预检。同一 runtime cycle 不重复采样或凭变化的测试读数恢复。
- CD、UNKNOWN 与未满足时序门控保持等待；只有明确自身可用及合法 GCD 时序才解除等待，重新运行绑定、装备与序列预检，再按配置顺序创建计划。
- 绑定硬失效沿用 capture Abort 与必要离开锁；官方窗口离开、配置变化、关闭功能、脱战和切图按既有生命周期清理。其他组被当前所有权遮挡的窗口仍需新边沿，不可抢占或补发。
- 等待中暂停再恢复仍保留四个 transport handoff 帧，包括窗口排首；事件刷新不消耗该预算。

## 不变边界与验收

- 唯一 OrderedPlan、单向 `configuredCursor`、后续候补原位置补入、当前步骤确认后推进，以及施法期不检测/不建链/不推进全部保持。
- 精确成功收据可以在 SOFT_PAUSED/WAIT_CONFIRM 中接收；自身 CD/充能回退确认仍至少两个不同业务快照并相隔 0.15 秒，不给普通精确成功额外增加固定等待。
- 不用静态 CD、HUD 数字、Buff、泛 GCD 或超时猜测可用/成功；不改变宏资格、TEAP/TEK 协议和任何安全门禁。
- 等待诊断只导出安全标量：pending、phase、cycleId、采样次数、最近采样时间。原成功收据继续保留供审计，不参与伪造新一轮成功。
- 回归覆盖推荐保持不变的恢复、普通/充能、simple/focused、前置/窗口排首、A-W-B-C 顺序、已完成不重放、施法/引导/蓄力、跨组、暂停和生命周期清理。
- 离线测试不能证明真实客户端释放成功；部署后仍需连续多轮实机核对 AddOn 确认事件与 TEK SendInput 记录。

## 本地验证记录

- 基线契约通过；全部 52 个 AddOn Lua 文件通过 `luac -p`。
- `pytest tek/tests tests/unit`：746 passed、7 skipped、17 subtests passed；其中 22 项重入相关用例通过（新增 21 项、修订 1 项）。
- `unittest discover -s tek/tests`：227 项通过；`unittest discover -s tests/unit`：243 项通过；Python compileall 通过。
- 并行验证时 TEK 的 `test_worker_exception_becomes_worker_exited_snapshot` 曾在 50 毫秒等待后仍读到 Starting；该测试在全量 pytest 和随后单独运行的完整 TEK unittest 中通过。未修改其测试或运行时代码，这一时序波动仍应另行跟踪。
- 未部署客户端，尚无本版本真实输入和连续窗口恢复的实机验收结果。
