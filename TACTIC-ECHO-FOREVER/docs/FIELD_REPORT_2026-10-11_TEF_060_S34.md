# 0.6.0 S34 连续失败定位

仅读取TEF自身数据库，落盘2026-10-11 14:02:34，SHA256 0034D5C6D973DD85691D86030140C5514C4AEE605CA6C1FB84B90E57C9E9780B。新诊断version明确0.6.0，session34。

没有TEK_CONTINUOUS_REQUEST；反复出现CONTINUOUS_GCD_UNKNOWN_OR_BLOCKED、CONTINUOUS_COOLDOWN_UNKNOWN_OR_BLOCKED，以及无关动作栏刷新产生CONTINUOUS_BINDING_CHANGED。切换手动出现TEK_MANUAL_REQUEST后，四条精确成功确认116 1→2、205 2→3、205 3→4、143 4→1循环完成。

结论：未连续的首要原因是TEF在请求发布前阻塞，不能将其归咎TEAP或TEK。TEK后台稍后处于无输入等待，曾有颜色不匹配，最后前台进程不匹配；该尾部状态不能解释已明确没有连续请求的业务阶段，也不能据此扩展颜色容差。目标/移动/读条原因也曾出现，仍保留必要过滤。

只读对照TE：Signal/SignalFrame.lua的普通官方候选传输、文本输入及施法保护，Tactics/GCDGate.lua的AutoBurst时序门控，Tactics/RuntimeSnapshot.lua的共享采样。普通推荐不要求零61304；AutoBurst/特殊模式/高亮规则与普通推荐资格不同。TEF独立固定意图尝试，不复制TE状态机、数值解密或未官方检测的字段操作。

修复0.6.1：固定练习不以自身冷却/GCD/充能作ready准入，无关刷新只复核锁定来源，进入战斗保留同一请求；增加键盘文本焦点保护。成功计步、实际读条保护、失败停止及TEK门禁不变。修复实机结果待下一轮落盘。
