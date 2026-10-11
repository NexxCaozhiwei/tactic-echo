# TEF 0.8.0 / S45 移动停止分析

只读取TEF自身落盘。文件mtime2026-10-11 15:22:43，SHA256 D89FDE5602387A69161520FCAA51276349BB268908B5FCA0976A4B29F8D6E5ED。客户端1.60.1/build70338/Interface16001，auto模式、permission/signal/autoStart开启、loop开启。

有界历史保留S45共128条，evicted2037，因此不能重建完整测试过程。cycle242→264、279→294、311→321、740→747均记录MOVING_OR_UNKNOWN阻断后重新CONTINUOUS_ON/RUNTIME_RUNNING，表明单纯移动没有持续关闭意图。

cycle754 SENT116，793 SUCCEEDED116推进到步骤2。cycle798 SENT205后立即CONTINUOUS_FAILURE_STOP，代次15→16，INTERRUPTED205被PAUSED_IGNORED；后续FAILED/INTERRUPTED也被忽略。cycle832手动启用，838 SENT205、885成功推进相邻205；cycle892仅保留FAILED205，没有本次SENT记录，再次FAILURE_STOP。cycle913再手动启用，919 SENT205、970成功进入143。

源码Dispatch在Engine消费前只按unit/当前步骤ID判断FAILED/INTERRUPTED，直接关闭Runtime意图，没有公开移动值或当前GUID关联校验。代码路径确认；日志没有持久化移动值/GUID，不据此断言cycle798由移动造成，亦不能断言cycle892一定是旧GUID。0.8.1补充移动分类与当前关联复核，并隔离移动失败身份。

历史能证明116和两个独立205成功，以及移动阻断恢复；不能证明0.8.1新修复成功。需要下轮读条中移动、停下恢复和相邻205迟到失败验收。
