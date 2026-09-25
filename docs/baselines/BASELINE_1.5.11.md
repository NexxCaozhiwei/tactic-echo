# Tactic Echo 1.5.11 基线

继承 1.5.10，修复高亮推荐逐专精技能设置不能保存的问题。

- `HighlightRecommendation:GetProfile()` 通过 `BurstProfiles:SpecKey(classFile, specIndex)` 的方法调用生成专精键，正确读写 `TacticEchoDB.tactics.highlightRecommendationProfiles[profileKey]`。
- 技能勾选和取消保存于当前专精；未载入专精时仍明确报告保存失败。
- 保留 1.5.10 的 AutoBurst `none` 空闲派发门控、高亮 `false` 状态处理、特殊模式来源隔离、官方推荐不变及唯一 TEAP/TEK 输入链。

## 验收范围

- 测试采用与生产一致的 `BurstProfiles:SpecKey()` 方法签名。
- 验证技能停用后当前专精读取为停用，且数据保存在对应专精键下。
- 验证当前专精索引缺失时返回 `specialization_unavailable`，设置页显示未保存提示。
- 目标 Retail 客户端的专精切换和实机派发仍需人工验证。
