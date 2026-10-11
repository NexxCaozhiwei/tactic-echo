# TEF 0.1.1 基线

仓库统一归档于docs/baselines/tef；独立源码包内映射为TEF根目录下docs/baselines。

继承0.1.0固定顺序205→143→2136→5143、公开起始关联、GUID去重、generation隔离、默认暂停、循环和128条诊断边界。无ready、动态优先级或输入通道；不改变TE逻辑或读取其他插件数据库。

本次仅改诊断：单位事件诊断包含固定白名单event，未知字段不保留原值。活动期间的同消费标识SUCCEEDED记DUPLICATE_SUCCESS，非成功后续事件记CONSUMED_IDENTITY_EVENT，不修改任何推进资格。旧0.1.0历史保持原分类，缺event不猜测、不回填；schema仍1，新增字段可选。castGUID仍只在内存内，不存档。

自身VERSION、Config版本、TOC、Core/Bootstrap及CHANGELOG统一0.1.1；TE版本不变。存档文件为TACTIC-ECHO-FOREVER.lua、变量TEF_DB。部署完整备份已有TEF目录，保留未知文件，不修改WTF。26项Lua5.1模拟及TOC/哈希检查，新诊断事件身份需按UPGRADE_TEST_0.1.1.md实机核对。
