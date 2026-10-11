# TEF 0.1.0 基线

仓库统一归档于docs/baselines/tef；独立源码包内映射为TEF根目录下docs/baselines。

独立用户授权范围，TE项目版本和生产逻辑不变。TEF自身VERSION、TOC、Core/Bootstrap.lua及CHANGELOG均为0.1.0。

唯一序列：205→143→2136→5143，名称为寒冰箭、火球术、火焰冲击、奥术飞弹。仅精确匹配当前步骤的公开player成功收据推进，每个事件至多一步；公开起始关联及GUID去重为保守附加条件。无完整等级映射、APL、ready、读条状态预测或任何自动输入。飞弹5143成功开始引导即完成，7268不匹配，取消不能撤回已发生的成功。

独立命名空间由TOC loader私有表提供，唯一全局数据TEF_DB，面板TEF_PracticePanel、事件框架TEF_EventFrame、slash TEF。登录/切图/reload安全暂停，重置回第一步并暂停；没有延后任务，generation保护所有状态入口。公开GUID只存在本次加载的内存内，不持久化；128条诊断不储存目标身份、Secret/API对象或异常全文。

目标客户端文件版本1.60.1.70338，TOC Interface16001。本机生成文档为一手签名来源，公开行为按逐字段官方检测处理；模拟测试不能替代实机。按docs/FIRST_TEST.md首测，用户“已落盘”后仅读取TEF自身TEF_DB分析。
