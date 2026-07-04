Tactic Echo 1.0.39 P3.2 直接覆盖说明

适用基线：1.0.39 P3.1。

使用方法：
1. 将本压缩包解压至现有项目根目录，按目录结构选择“覆盖全部”。
2. 将项目中的 addon/!TacticEcho 同步至 WoW 的 Interface/AddOns/!TacticEcho。
3. 进入游戏后执行 /reload。
4. 打开 TE 设置 → 打断设置，观察“当前打断 / 控制监控”中的 P3 目标观测诊断。

本阶段仍为 P3 只读观察：
- 不会自动按键；
- 不会创建 BindingToken；
- 不会写入 TEAP/TEK；
- 不会修改 AutoBurst、HUD 布局、标签或冷却显示。

P3.2 调整内容：
- 读条存在性按 UnitCastingInfo / UnitChannelInfo 返回位数判定，不再依赖可读取的施法名称；
- 当前目标读条若 P3 观察器遗漏、但同轮 ProtocolMonitor 已确认，则仅回填显示诊断；
- P2 动作条/宏映射未就绪时，仍允许资料表图标以 bindingToken=0 进行只读高亮；
- 新增 P3 目标、读条、API 返回位数、监控回填、P2 映射状态的设置页诊断。

已知待办：反制射击“焦点优先 → targetenemy 回退 → targetlasttarget 恢复”宏在实机中仍未被 P2 正确识别，本包未改变该问题。
