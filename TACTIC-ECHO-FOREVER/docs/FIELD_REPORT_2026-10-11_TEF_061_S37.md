# TEF 0.6.1 S37 原因分析

只读TEF自身SavedVariables及TEK自身trace。落盘2026-10-11 14:10:51，SHA256 ECB3FB08FFB926591A9B81AF7A20F406C7DADAED6584193865CAB01625E1AD2A。

S37保留诊断明确version0.6.1：出现TEK_CONTINUOUS_REQUEST 116及CONTINUOUS_WAIT_RECEIPT，说明新固定尝试已越过旧零CD/GCD门控；随后出现CONTINUOUS_MANUAL_REQUEST、TEK_REQUEST_CANCELLED及大量TEK_MANUAL_REQUEST。Request的单步入口显式StopContinuous，导致连续运行被关闭。116成功推进1→2后，无205连续请求；5019顺序外成功保持2→2，最后PAUSE及TRANSPORT_OFF。

TEK按session_epoch=37过滤：input_sent 1条，2026-10-11 14:10:39本地时间，binding=1、Token5、gatePassed=true、inputSent=true；manual_wait_freshness 7条，manual_input_held 2条，manual_release_delay 1条，observation_frame 4条。TEF不记录逐条事件时刻与跨进程请求身份，不能将该输入唯一归因到连续或手动请求。

结论：本轮有有效TEF请求和真实TEK输入，主要断点是单步/连续/许可/练习多个控制入口互相覆盖；重复手工操作亦进入正常手动优先门禁。不能把正常门禁等待统称为协议不兼容，也不能通过移除手动优先掩盖控制流程问题。

后台稍后的前台不匹配和颜色读失败发生在测试结束后，不能证明其造成当前业务阶段未推进。TEK v3以BindingToken验证来源，不要求WoW官方推荐存在；当前dispatch_origin=official是协议默认元数据，非官方推荐真实性检查。

当前配置只有全局single/multi，没有职业键；所有职业继承法师默认，是已确认结构缺陷。下一版本应将推荐源、职业配置与运行控制分离，详见NEXT_MAJOR_DESIGN_0.7.0.md。
