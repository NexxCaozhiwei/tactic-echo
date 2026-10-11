# TEF 0.8.2 对照TE普通派发与手动恢复

用户明确要求移动、插入其他按键不得永久中断派发。本版本覆盖0.8.0/0.8.1的“当前静止失败即停”和“全局移动阻断”策略；不扩展成功计步、身份公开性、绑定类型或TEK输入权限。

## 已逐段核对的原代码

- addon/!TacticEcho/Recommendation/RecommendationAdapter.lua：ReadOfficialSpellID读取官方身份，ReadOfficial冻结业务推荐。
- addon/!TacticEcho/Signal/SignalFrame.lua：GetEffectiveState分离armed意图、文本焦点manual_hold、channel/empower及自动启停待命；普通官方绑定缓存与Token发布段、advanceSequence每新可派发帧更新sequence；失败watcher仅清匹配的castLock，不SetState暂停。
- tek/src/engine.py：_manual_gate_reason和_consume_manual_frame仅消费手动持有帧与新鲜度，不永久关闭context.tek_armed；process_frame执行手动门禁、SafetyGate、限频及发送前二次门禁。
- tek/src/physical_input.py：按住非白名单主键/修饰键保持MANUAL_HELD，松开后RELEASE_DELAY→WAIT_FRESHNESS→REPLAY_GUARD/DISPATCHABLE；新候选帧满足原恢复规则后允许输入。W/A/S/D/SPACE豁免与修饰键持续让权保持原样。

TEF复用这些方法而不调用TE内部函数，不把固定序列变成TE的AutoBurst计划，也不复制TEK恢复时钟。TEF仍保留自身公开target/range/usable与真实读条/引导保护；普通TE路径的全部客户端行为不能直接推断为build70338实机结论。

## 两个实际差异与修复

1. TEF把当前失败等价为手动停止；移动打断、插入手动技能或自动射击冲突都可能关意图。现在公开当前失败只撤回候选并建立有界失败身份隔离，保持步骤/意图，下一业务轮重新校验后尝试原步。失败不计步，不依靠STOP/CD/GCD/超时推进。
2. TEF发出候选即写waitReceipt，读条检测撤销pending却未释放未发起候选的wait。顺序外技能不增加当前成功serial，产生永久等待。现在公开当前SENT/START及Engine本代次关联才拥有成功等待；YieldCast对未建立当前关联的撤回清wait，实际读条/引导消失后可以重新发布。已发起的当前步继续保留关联，S61即时仍读条的成功也正常计步。

移动不再作为全局Token资格。合格瞬发可以移动尝试；读条技能若游戏判定失败则原步重试，不声称当前技能一定可施放。文本焦点、真实施法存在性未知、target/range/usable未知或不合格仍零Token。按键按住期间TEK照常让权，不绕过前台/Hook/限频/新鲜度/重放门禁。

显式停止/重置、配置修改、切图、关闭许可/输出、完成非循环和致命异常仍关闭意图。失败GUID仅在内存有界保留128个，满额异常停机，reload失效，不保存Secret/GUID原值到数据库。无关联旧失败只诊断，不能关闭新请求；旧失败身份的迟到START/SUCCEEDED不计步。

## 最新证据与验证

本轮启动时落盘mtime2026-10-11 15:29:32，SHA256 FD4F115882126185B472F12B96CA8742525B2112AE1AC417C2D46733FE656971，数据库0.8.0/S46。保留128条、淘汰2308条，自动模式/循环开。cycle3423 SENT/SUCCEEDED5019；3425发布116，3433 FAILED116触发FAILURE_STOP。cycle3456成功5019只记OUT_OF_SEQUENCE，3457发布116，3459失败又关意图。cycle3615–3830完成116→205→205→143及循环。此历史记录说明失败清意图阻断恢复，不能代替新版实机证据。

交付复核时出现后续落盘mtime15:32:27，SHA256 737C34050C1F8FFD973812F9EC86E28C49F39C23F57A1F3D02E929E83BE857C8，0.8.1/S47，128条/evicted2526。保留记录中MOVEMENT_FAILURE5条、NO_CURRENT_INITIATION失败11条、CURRENT_MATCH2条、LOOP_COMPLETED1条，未保留FAILURE_STOP。cycle845移动中断，849恢复并请求116，851/883成功5019只记偏离；116多次无当前起始关联失败不关意图，912 SENT116，961成功进205；969移动中断，随后1017独立205成功。可确认0.8.1移动恢复与旧失败隔离已有部分实机记录，但不能断言完整过程没有卡死（历史有淘汰），也不能证明本次新增未发起等待释放、全局移动门禁移除和普通失败恢复。0.8.2仍尚未实机验证。

141项Lua5.1测试保留旧用例并按新用户语义更新移动和静止失败断言，新增9项：顺序外开怪进战、外来读条释放未发起等待、无SENT读条、已有当前关联保护、移动非全局门禁、重复失败及迟到成功、手动停止粘性、7268/顺序外不解锁当前成功等待、usable未知零Token恢复。另2项以TEF实际Encode帧通过原TEKEngine和PhysicalInputPause验证Q/SHIFT按住让权、松开delay/两帧freshness恢复，全部dry-run无Windows输入。真实Hook、游戏行为另验。
