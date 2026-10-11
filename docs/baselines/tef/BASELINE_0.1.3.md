# TEF 0.1.3 精确等级ID与相邻技能实验

用户指定运行序列116→205→205→143，每步只匹配对应精确ID。116/205已在TEF自身落盘成功事件中分别观察；不建立完整等级映射、不宣称两个ID可在全部API互换。原205→143→2136→5143及两步205配置分别保留为StandardConfig、AdjacentConfig。

继承0.1.1推进/起始关联/GUID去重/generation/事件诊断及128条历史，Engine不变。默认暂停，测试关闭循环，原循环偏好保存方式不变、不修改WTF。第二步205第一次独立成功到第三步205，第二次独立成功才到第四步143，最后143成功完成；顺序外不跳步，后续STOP或重复成功不额外消费。

自身VERSION、Config、TOC、Core/Bootstrap、CHANGELOG统一0.1.3。28项Lua5.1模拟及TOC检查，实机按RANK_SEQUENCE_TEST_0.1.3.md验收。部署仅TEF目录、先完整备份并核对9文件SHA256；基线归档于仓库docs/baselines/tef、ZIP内映射docs/baselines。
