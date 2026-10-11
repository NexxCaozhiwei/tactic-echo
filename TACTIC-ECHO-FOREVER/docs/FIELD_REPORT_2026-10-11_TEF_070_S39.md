# TEF 0.7.0 S39 连续固定序列实测

## 证据

仅读取TEF自身SavedVariables与TEK自身trace。TEF落盘2026-10-11 14:41:25，SHA256 `CB24C7243AEAF737D08E99927A379B4113E8D3D90B744665DC2A1E3052FF5421`。客户端1.60.1 / 70338 / Interface16001，当前session39、版本0.7.0、人工单体、MAGE:base。许可/信号/autoStart为true，最终模式manual，loop=true，快捷键为空。历史128条包含S37旧版20条、S38旧版25条、S39新版83条；累计淘汰1560不能解释为本会话故障数。

## 当前业务链

本会话日志从LOGIN_PAUSED到LOGOUT完整保留。首次进入世界自动启用后RUNTIME_AUTO_STANDBY，request0，没有提前派发。选择目标停止旧意图；随后用户手动暂停、切manual、重置、重新启用。generation10保持同一连续运行，以下均是TEK_CONTINUOUS_REQUEST，没有本会话TEK_MANUAL_REQUEST。

| 请求 | 精确ID | 请求轮 | SENT关联轮 | SUCCEEDED轮 | 推进 |
|---|---|---|---|---|---|
| 1 | 116 | 1820 | 1826 | 1856 | 1→2 CURRENT_MATCH |
| 2 | 205 | 1858 | 1866 | 1900 | 2→3 CURRENT_MATCH |
| 3 | 205 | 1901 | 1908 | 1965 | 3→4 CURRENT_MATCH |
| 4 | 143 | 1966 | 2005 | 2061 | 4→1 LOOP_COMPLETED |

因此本次已证明0.7.0的连续固定练习完整一轮、不同等级116/205精确分步、相邻两次205独立成功推进、后续143正常推荐/请求以及末步循环回首步。STOP在成功后记录CONSUMED_IDENTITY_EVENT，没有再次推进。循环设置实际为开启，本次不能证明关闭循环后的完成停止。

第二轮请求5在cycle2062发布116，cycle2064出现CONTINUOUS_FAILURE_STOP和当前116的UNIT_SPELLCAST_FAILED；该收据因控制器已经暂停记录PAUSED_IGNORED，没有错误计步。随后目标变化、手动暂停、LOGOUT、TRANSPORT_OFF。只能确定游戏失败事件触发停止，现有日志没有失败原因/目标生命证据，不能推断为死亡、范围、资源或协议错误。

## TEK输入层

按session_epoch39筛得55条保留trace：input_sent7、frame_state_paused19、manual_wait_freshness15、manual_input_held9、manual_release_delay1、observation_frame4。7条inputSent=true且gatePassed=true、backend=windows_sendinput、events_sent2，无partialFailure。北京时间：

- 14:41:02.553：键1、Token5。
- 14:41:04.234 / 14:41:04.487：键2、Token6。
- 14:41:06.435 / 14:41:06.697：键2、Token6。
- 14:41:11.481：键3、Token7。
- 14:41:14.265：键1、Token5（循环后）。

TEK日志有节流与input_sent_summary，7条是保留的成功发送记录，不承诺全部物理发送总数。TEAP v3已被解码并通过真实输入门禁。TEF业务轮和TEK序号不属于同一编号系统；当前不具备跨进程唯一请求ID，不将每个物理输入与游戏成功强行逐条绑定。TEF独立成功收据证明游戏计步，TEK独立发送收据证明Windows发送接口，两层证据分别成立。

分析时后台WaitingForForeground/window_process_mismatch是在测试并退出落盘之后；不能倒推为本轮连续失败原因。正常手动让权等待不视为TEAP/TEK不兼容。

## 下一轮

关闭循环后复测一次完成停止；单独验证当前读条取消停止、顺序外技能不跳步、5143成功开始引导与7268不重复计步；再分开验证自动启停/脱战停止、自定义键及其他职业隔离。当前S39不证明这些全部通过，也不证明动态APL或技能始终ready。
