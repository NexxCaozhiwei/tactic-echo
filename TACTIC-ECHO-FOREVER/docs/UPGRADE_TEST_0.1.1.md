# 0.1.1 单次飞弹诊断短测

本版只改善诊断，固定顺序和推进规则不变。旧日志缺event仍为空，不将旧DUPLICATE_IDENTITY解释成重复成功。

1. /reload，确认TEF v0.1.1，默认暂停。取消循环勾选，/tef reset后主动开始。
2. 正常完成205→143→2136，停在4/4奥术飞弹；这一遍只用于到达飞弹步骤，不需额外重复四步。
3. 手动发动一次奥术飞弹，看到成功开始/TEF完成后立即Esc取消引导。本版开始成功即完成，取消不得再推进或撤回；若取消发生在成功之前，不应完成。
4. /tef diag。每条单位事件前应显示UNIT_SPELLCAST_*。IDENTITY_NO_DATA现在能关联具体事件；不要预设它来自CHANNEL_START或STOP。成功应为SUCCEEDED的COMPLETED；同标识非成功后续事件在活动期记CONSUMED_IDENTITY_EVENT，完成暂停后仍可能记PAUSED_IGNORED。真正同标识重复SUCCEEDED在活动期间才记DUPLICATE_SUCCESS；实机未发生则不要求出现，不人为合成事件。
5. /tef stop，正常/reload或退出落盘；告诉我“已落盘”。只分析TEF自身TACTIC-ECHO-FOREVER.lua中的TEF_DB；不读取其他插件数据库。当前还不测试相邻同技能配置。
