# TEF 0.6.0

固定练习连续派发实验，显式开启，默认关闭且不落盘活动状态。共用唯一Dispatch pending、TEAP v3和协议心跳，不新增输入通道。HUD提供连续开关，新增原生按键及/tef continuous；/tef continuousstatus输出固定状态原因。

每次候选必须确认公开存活敌对目标、范围、静止、usable=true、insufficientPower=false；精确技能及61304都须公开startTime=0、duration=0、isEnabled=true，充能查询须公开nil或公开正整数currentCharges。Secret/nil字段、缺API、失败不授权；不从isActive、图标、DurationObject、GCD事件或经过时间推断ready。这是严格公开数值实验路径，70338可能始终无法给出所需证据，尚未实机验证，不代表ready契约已经验收。

事件仅撤回当前输入并交给原引擎成功计步。成功后不同协议心跳重采，实际读条/引导未消失不请求下一步。内存receiptSerial区分相邻相同技能与单步循环，不把计时作为去重。失败/中断/顺序外成功停止连续，7268子事件例外忽略。请求发出后等待成功，未收到收据不猜超时、不自动重试。可能在游戏撤回事件前由既有TEK发送多次按键。

暂停、重置、重启、场景/配置变更、设置、绑定更新、目标/进战变化、许可关闭、信号关闭、reload全部停止。下一步保持用户启用循环的显式语义。默认四步完成停止。

诊断新增净化version字段，以免将旧会话误判为新版本实测。TE运行逻辑与其他插件数据库不变。TEK不需重建。
