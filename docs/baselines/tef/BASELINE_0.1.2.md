# TEF 0.1.2 相邻同技能临时实验

运行配置为寒冰箭205→寒冰箭205，每步仅匹配205；不授权116等级等价。原205→143→2136→5143保存在Config.lua的StandardConfig，可在测试后恢复。默认仍暂停；原循环偏好保存规则保持，测试前须关闭循环。未修改WTF或TE/其他插件。

Engine/公开起始关联/GUID去重/generation/128条日志与0.1.1一致。第一次独立成功只到第二步，第二次独立成功才完成；后续STOP和同标识重复成功不推进。新增加当前部署配置专项，连同原四步等回归共27项Lua5.1模拟；实机按ADJACENT_TEST_0.1.2.md验收，模拟不代替实测。

VERSION、Config、TOC、Core/Bootstrap及CHANGELOG统一0.1.2。基线统一在仓库docs/baselines/tef，独立源码包映射docs/baselines；部署先备份已有TEF目录并逐文件核对SHA256。
