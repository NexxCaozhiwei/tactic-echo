# 0.3.0 首轮验收

1. 禁用TE，仅加载TEF，`/reload`。应显示紧凑HUD及左上角协议条，默认暂停。`/tef test`显示原测试面板；`/tef hud`显示交付HUD。现有设置仍可编辑序列、循环、锁定和缩放。
2. 单体主动开始，手动116→205→205→143；两次205各使用一次。取消火球术、插入顺序外技能不推进；测试暂停、重置、完成与循环。多目标切换后开始，118变形术→5143奥术飞弹；5143成功开始引导完成，7268不额外推进，提前取消可能已经完成。
3. 把当前精确技能直接放在默认动作条有真实绑定的槽位；宏、其他等级替代不在本轮验收支持范围。先关闭设置并开始练习，确认技能、目标及施放条件由你人工检查。TEF没有自动ready证据，不宣称推荐立即可施放。
4. 先运行TEK dry-run，确认能采到观察帧；然后在游戏执行 `/tef tektest`，确认trace为绑定派发计划且 `inputSent=false`。`/tef tekstop`撤回，暂停后重开TEK真实验收进程。
5. 在项目根目录用PowerShell7分别执行下列命令；TEK现有桌面UI无单次预算，**本轮不要用无限预算UI代替验收脚本**。先验证配置可运行；命令不跳过前台/Hook/手动让权门禁。

```text
python TACTIC-ECHO-FOREVER/scripts/tek_acceptance.py --trace dist/tef/tek-dry-run.jsonl
python TACTIC-ECHO-FOREVER/scripts/tek_acceptance.py --send-input --confirm I_UNDERSTAND_TEK_SENDS_KEYS --trace dist/tef/tek-input-one.jsonl
```

真实验收进程启动时保持TEF暂停，使TEK先读到暂停帧；切回WoW前台，主动开始后 `/tef tektest`。每个真实进程最多成功发送一次；每测下一步需停止旧进程并重启预算1。TEF请求会持续提供新鲜帧直到撤回，无法核验外部预算，使用其它无预算运行器不能保证单次按键。未出现对应游戏事件时请求不会自行计时成功，执行 `/tef tekstop` 后检查trace，不自动重试。

6. 观察一次真实输入、对应SENT/START/SUCCEEDED与一次步骤推进分别成立；人工按键/修饰键按住时应让权，失去WoW前台不输入，暂停/重置后旧请求不能释放。测试5143后子事件不重复推进。
7. `/tef tekstop`、`/tef pause`，回终端Ctrl+C停止验收脚本，再正常 `/reload`或退出落盘。说“已落盘”后分析TEF自身数据库；TEK trace单独证明发送链，不能用TEF日志代替物理输入证明。

限制：Atlas/遮罩可能在此客户端缺失，使用动作按钮边框回退；不伪造冷却、不可用灰度或实时读条。自动场景/动态优先级仍是旁路原型。

旧TEK CLI缺少Hook初始化，真实输入会被安全门禁拒绝。本次脚本初始化现有WindowsPhysicalInputMonitor，不跳过Hook。脚本使用现有默认手动让权策略及W/A/S/D/SPACE白名单，不读取或修改TEK本机设置。
