# TEF 0.14.2 CDM帧身份隔离

S72发现全部CDM条件报CDM_FRAME_ID_UNKNOWN。旧实现遇到一个无法确认cooldownID的帧就中止并将整个类别置UNKNOWN；TEProbe参考实现继续扫描，仅匹配明确目录身份的帧。本版收窄单帧错误影响范围：读取cooldownID失败时尝试公开GetCooldownID，两者均不可确认则跳过，继续原有有界扫描。

某个精确匹配帧的公开isActive=true/false继续产生ACTIVE/INACTIVE。不明身份不贡献状态；没有匹配帧仍UNKNOWN。关联帧Secret、不同公开状态冲突、目录错误、枚举调用失败、容量超限仍阻断，不把扫描不完整伪装为完整。没有复制探针hook、延时回调或新增轮询；推荐采样与派发前复核统一使用P.CDM。

诊断新增cdmScanReason=CDM_FRAME_ID_UNKNOWN与cdmSkippedFrames（每类最多160）；这只是扫描警告，与该技能cdmReason/活动布尔分开。匹配结果可同时为PUBLIC及存在扫描警告。未知请求在遇到未知帧时仍记录该原因。清洗只允许固定原因与有界整数，不保存Secret、异常全文、原始帧或身份。

本补丁不更改用户配置、不开放7300支持名单、不改变蓝量Secret/精确距离/范围/自身ready门槛。原S72的其他阻断可能继续存在，不能把此修复当作六条规则已经可运行。

## 短实测

1. 停止派发后`/reload`确认0.14.2。为隔离CDM，临时只启用143火球术规则，移动/蓝量/精确距离/额外冷却活动设不限，CDM选择buff133、不活动。保存，选择APL并开启练习，关闭设置。
2. 选择存活敌对目标，站定在火球术范围内，脱战观察10秒。规则页应显示该技能真实PUBLIC true/false，或具体UNKNOWN原因；若出现“跳过身份未知帧”，它不应单独抹除已精确匹配的状态。缺帧仍可能没有推荐。
3. 手动施放143进战，观察10秒，比较CDM前后活动变化及其他条件；若ready仍UNKNOWN，记录该独立阻断，不把CDM活动当自身冷却ready。
4. 停止派发，正常`/reload`或退出落盘，回复“已落盘”。只读取TEF自身数据，检查cdmActive/cdmReason、cdmScanReason及跳过计数。新版实机结果以本轮落盘为准。
