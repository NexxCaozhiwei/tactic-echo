# TEF 0.4.0 实测

## 启停与标签

1. 停止桌面TEK运行，禁用TE，仅加载TEF，正常 `/reload`。应为练习暂停、TEK请求许可关闭；旧测试界面 `/tef test`仍保留。
2. 游戏菜单→按键设置，查找TACTIC-ECHO-FOREVER分类，自行配置：练习启/停、TEK请求许可启/停、请求当前技能、停止练习及请求。插件不替你绑定或改写其它快捷键。
3. 用HUD“开启练习/停止练习”或快捷键验证暂停/继续保持当前步骤；“重新开始”回首步。设置总览也有练习启停按钮；TEK页或HUD有独立请求许可按钮。许可开启不会自动派发或启动外部程序。reload全部回暂停和许可关闭。
4. 当前精确技能直接放在默认动作条并设置真实键位，HUD角标应显示它；宏或身份未解析显示“未解析”。CD/充能标签与游戏动作条比对：明确公开自身CD才显示秒数；共享GCD不伪装成自身CD，未知/受限显示未知。客户端转盘只供视觉。非充能或无数据“—”，未知“未知”。观察战斗内、取消、连续读条和reload后显示，确认标签不改变步骤。

## TEK dry-run

在项目根目录PowerShell7执行（脚本路径未改变）：

```powershell
pwsh.exe -NoLogo -NoProfile -Command 'Set-Location G:\CODES\tactic-echo; python TACTIC-ECHO-FOREVER/scripts/tek_acceptance.py --trace dist/tef/tek-dry-run.jsonl'
```

应立即出现 `TEF acceptance: DRY RUN` 和等待说明。脚本复用TEK客户端范围定位器，未切回WoW或协议条暂未出现时继续等待并输出门禁原因，不因首次未定位退出。若报导入/依赖错误，保留终端文字。保持进程运行，切回WoW前台，先选目标并确认精确116绑定。协议条若不可见，执行 `/tef protocol`显示。

关闭设置窗口；`/tef single`、`/tef start`、`/tef tekon`、`/tef tektest`（或相应快捷键）。请求提交后不切目标/改绑定/动作栏。dry-run不自动按键或计步，trace应显示绑定计划且inputSent=false。阻塞将明确为许可关闭、练习暂停、设置打开、完成或未解析，并落盘。请求撤回会记录具体事件原因。

## 真实单次验收

先游戏 `/tef tekoff`、`/tef pause`，回终端实际同时按Ctrl与C停止dry-run；**不要输入字符串 `Ctrl+C`**。真实验收命令：

```powershell
pwsh.exe -NoLogo -NoProfile -Command 'Set-Location G:\CODES\tactic-echo; python TACTIC-ECHO-FOREVER/scripts/tek_acceptance.py --send-input --confirm I_UNDERSTAND_TEK_SENDS_KEYS --trace dist/tef/tek-input-one.jsonl'
```

启动时TEF保持暂停供TEK观察，切回游戏后先目标不变、设置关闭，`/tef start`、`/tef tekon`、`/tef tektest`。松开键盘等待门禁；每个进程最多一次成功发送并退出。输入成功与游戏116成功1→2要分别核对。无释放不要人工补放116，执行 `/tef tekoff`撤回并检查trace。不用无限预算桌面模式替代脚本。

结束“停止练习及请求”快捷键，或 `/tef tekoff`、`/tef pause`；终端实际Ctrl+C（若已退出无需再按）；正常reload/退出落盘。说“已落盘”后读取TEF自身数据和验收trace，不能以TEF计步替代Hook/SendInput证明。

多目标仍118→5143，循环关闭时末步保持完成；提前取消5143可能已完成，7268不重复推进。自动场景/动态优先级仍是旁路，未开放自动ready释放。
