Tactic Echo 1.0.39 P4 — 确认读条自动打断

覆盖范围
1. 将本压缩包内的文件按目录覆盖到 Tactic Echo 项目根目录。
2. 必须同时覆盖 addon/!TacticEcho 和 tek/，P4 使用 TEAP v3 的 reaction 来源标记（0x40）。
3. 若当前运行的是已打包的 TEK.exe，而不是本仓库 Python 源码，请在覆盖后执行项目根目录 TEKEXEBUILD.CMD 重建 TEK。
4. 将 addon/!TacticEcho 同步到 WoW 的 Interface/AddOns/!TacticEcho，然后在游戏内执行 /reload。

P4 范围
- 自动打断仅对：战斗中、系统已启动、敌对存活目标、P3 已确认可打断读条、P2 已解析安全动作条/宏路由生效。
- 目标顺序使用“打断设置”的当前目标 / 焦点 / 鼠标指向配置。
- AutoBurst 活跃计划或 pre-window capture 时仅高亮，不抢占自动打断；计划结束后才允许自动打断。
- 同一读条只发起一次自动打断候选；后续保持观察，直到读条消失或更换。
- P4 不包含自动单控、自动群控或 HUD 点击，这些留待 P5。

已知待处理
- 猎人“反制射击”焦点优先 → targetenemy 回退 → targetlasttarget 恢复目标的多行宏，P2.2 在实机中仍存在识别缺口。本补丁未声称修复该识别问题；只要其路线未被 P2 识别，P4 不会自动按该宏。
