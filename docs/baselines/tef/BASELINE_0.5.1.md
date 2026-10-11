# TEF 0.5.1

继承0.5.0独立HUD/TEUI、TEAP v3、精确绑定和成功计步。Request入口与Packet共用CastIdle：只在读条和引导查询明确无数据时接受；公开正在施法、Secret、缺API或调用失败拒绝请求，固定原因TEK_CAST_PRESENT_OR_UNKNOWN。不会因此推进或建立pending。

S29实机确认116→205→205→143四步，两个205独立消费，循环回第一步；失败、中断、STOP和顺序外技能未推进。TEK另有11条Windows SendInput成功，两类证据无逐条因果关联。

下一阶段连续派发仍未实现；默认暂停/许可关闭、每步主动请求及全部输入门禁保持。
