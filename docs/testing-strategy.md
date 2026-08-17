# 测试策略

版本：`1.4.4`

## 自动验证

在项目根目录执行：

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

如系统存在 `luac` 或 `texluac`，还应编译检查全部 AddOn Lua。对设置页或 HUD 构造逻辑的修改，不能只运行 `luac -p`：还必须验证运行时 helper 定义顺序并实际构造相关页面或组件。

必须区分“没有新增失败”和“完整测试全部通过”。若完整测试存在已知失败或跳过，交付报告必须给出准确数量、原因和影响，不得把进程退出成功或局部测试通过写成全绿。

## 当前合同覆盖

自动测试至少覆盖以下边界：

- TEAP v3 长度、BindingToken、Burst flags `0x20`、未知 ActionCode、会话与帧新鲜度。
- TEK 前台保护、Hook/物理输入让权、限频、组合键编码和持续候选抑制。
- Blizzard 默认动作条缓存、当前宏身份、共享宏资格、宏正文不持久化与不可信来源 fail-closed。
- 每专精最多三个自动注入组、窗口/注入互斥、稳定步骤键、旧配置幂等迁移和唯一 Coordinator 所有权。
- AutoBurst OrderedPlan 的顺序预检、`simple/focused`、GCD/队列窗口、WAIT_CONFIRM、双快照不可用证据、精确失败收据与脱战硬门控。
- HUD 按组顺序展示最多 27 张自动注入卡，且展示层不建立 Token、不写 TEAP、不改变计划。
- 冷却单位边界、全局 cooldown reconcile、共享 GCD 隐藏、真实多充能与普通技能 `1/1` 过滤。
- HUD 卡片、secure proxy、主容器和布局在战斗中的受保护可见性/布局延迟应用。

## 人工实机门禁

以下结果不得由离线测试、PyInstaller 成功或 TEK 进程存活替代：

- Windows 前台识别、Hook 生效与真实单次 SendInput。
- WoW Retail Secret/opaque API 行为、SpellQueueWindow、不同急速/GCD 和真实施法确认事件。
- 自动注入组窗口命中、组间不抢占、组内实际释放顺序，以及 `simple/focused` 运行期差异。
- 玩家当前动作条直放技能、条件宏、饰品和组合键的真实身份与绑定。
- `/reload` 后设置页、HUD、27 张卡上限、拖拽/布局和战斗保护行为。
- 奥术弹幕等无自身 CD 技能不显示伪 CD；普通 CD 技能不显示 `1/1`；真实两充能技能按 `2/2 → 1/2 → 2/2` 更新；长 CD 数字与默认动作条同步校正。

人工检查完成后应结合 SavedVariables、AddOn 诊断和 TEK Trace 核对 `dispatchOrigin`、计划 ID、活动组、当前步骤和确认原因，但诊断只能辅助解释，不能单独证明按键或技能已成功使用。

## 失败与跳过处理

- 新失败必须定位并修复，或在取得用户确认后明确列为已知阻断；不得忽略。
- 已知失败也必须说明是否与本次修改相关，并保留后续清理责任。
- 跳过通常表示当前机器缺少可选运行时（例如 Lua 解释器）或测试前提不满足，不等于失败；交付前必须说明跳过原因，并用可用替代检查补足能补足的部分。
- 实机门禁未执行时必须写“未实机验证”，不得推断为成功。
