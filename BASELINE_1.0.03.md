# Tactic Echo 1.0.03 基线

本版本基于 1.0.02 自动爆发最小状态机，修正了实机诊断中的两个问题：

1. 自动爆发的官方推荐锚点不再只能隐式取 Burst Profile 第一项；可显式设置窗口技能与注入技能。
2. AutoBurst 的拒绝、规则解析和异常状态会进入脱敏映射导出与 TEK 诊断包。

`!WR.lua` 不是 Tactic Echo 的 SavedVariables。1.0.03 的运行数据必须写入 `TacticEcho.lua`，并可通过 `/teab status` 显示构建号验证实际加载版本。
