# TEK / TEF颜色传输兼容更新

TE AddOn基线仍1.5.12，VERSION/TOC/Bootstrap一致；未改TE运行逻辑。本次TEK与TEF协同版本为TEF0.5.0，TEK构建版本由构建清单SHA256识别。

TEK改动仅screen_sampler.py与visual_decoder.py共享视觉传输层，兼容原TE与独立TEF的TEAP v3。修复实机1.2伽马颜色变换导致找不到TEAP的问题，不更改协议、目录、BindingToken、输入策略、Windows Hook或SendInput。

新增test_tef_colour_transport.py覆盖全字节精确颜色、标准/1.2颜色、TE/TEF帧、带间距/连续块定位、两份实机fixture完整CRC及损坏/不支持颜色拒绝。量化歧义最多枚举64个组合，只有唯一完整CRC/commit有效帧可接纳；零个、多个或超限均拒绝。保留旧RGB容差与全部协议/安全门禁测试。已有TE仍按原颜色路径解码。

S29确认四步游戏成功与循环；TEK另有11条真实Windows SendInput成功。TEF0.5.1仅收口请求入口读条门控；其新门控尚未实机验证。连续派发为下一阶段，当前保持每步主动请求。
