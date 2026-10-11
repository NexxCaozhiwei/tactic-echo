# TEF 0.11.0 基线

第一版 MAGE_FOREVER_60 职业APL，以已学技能、实际天赋rank和公开状态选择规则；不按现代专精分包。默认保持固定序列，人工/代码序列配置不被APL覆盖。设置中的APL开关、填充偏好与精确ID均在TEF_DB独立保存。

Ability Registry覆盖TEFSim的272条法师技能候选记录，Talent Registry覆盖54个无限服候选节点；来源unverified，声明70170，仅在当前70338公开法术书/天赋配置返回符合身份时确认，不自动授权等级别名或静态效果。

三值条件、候选优先级和有界trace为纯数据求值。唯一Runtime/Dispatch/TEAP/TEK链路不变。APL额外要求公开自身冷却与GCD零冷却、已学、usable、power_ok、范围等；UNKNOWN不派发，不借计时推断ready。施法/引导与当前起始关联保持精确当前技能，SUCCEEDED只消费该次收据后重新求值，不完成固定序列、不循环旧快照。暂停/重置/换配置/换目标/切图失效旧请求与关联。

自动填充权重、资源区间、灼烧维护、地面技能、无限服proc/层数、防御和通用能力策略保持未支持。当前不是最优DPS循环，也不是客户端状态能力已闭合的证明。验收与架构详见TEF docs/APL_ARCHITECTURE_V0.md、APL_MAGE_60_V0.md、PRODUCTION_0.11.0.md。
