当前0.12.1：用户明确授权取消APL GCD条件与61304查询；其他条件不变。失败身份采用原4096共享预算，取消重复128失败上限。以下旧版本GCD限制作为历史记录，按本条覆盖。详见docs/PRODUCTION_0.12.1.md。

当前优先级已于0.12.0按用户五份WotLK文件重设；以下原v0规则说明作为历史背景。当前以WOTLK_MIGRATION_0.12.0.md及Rules.lua为准。

# 法师60职业APL v0

无限服不是现代互斥专精：本包为MAGE_FOREVER_60，火/冰/奥是能力分类和实际天赋分支，混合加点按同一套条件求值。不猜流派，不依赖专精ID。

## 来源

- 用户指定G:/CODES/TEProbe/TEFSim/data/forever_catalog/mage_spells.json：272条法师记录，来源[Kovarel无限服法术目录](https://kovarel.com/cn/wow-forever/spells)，资料状态unverified。SHA256 `C1F887145A21F1C109F7A8B3A12EA4741A6AC4C3C32D097F1E72ED00D53F0E00`。
- 同目录data/talents_forever_book_0_37_1/mage_talents.json：TalentsForeverBook0.37.1静态提取，声明1.60.1.70170，54天赋（奥18、火17、冰19）。SHA256 `AC025E6430F1EB7D33F9FB3351C9011CAE714B00F6DA09080C4657DB3FCDAB48`。节点、SpellID、最高点数是候选元数据，当前每级效果/rankSpellIDs/entryID/definitionID未知。
- 运行API签名核对本机70338生成的spellbookdocumentation、spellshareddocumentation、traitdocumentation和class talents定义。S55–S61状态契约沿用TEProbe只读说明；不读取其SavedVariables。
- 资料中的Classic旧说明、系数候选、Rune/Legacy规划规则不转换成当前效果；目录条目数不等于客户端完整覆盖或玩家已学数量。静态rank仅展示来源，不按静态最高等级自动认定成功ID等价。

生成的Talents.lua保留每个候选ID和名称（272记录）及全部54天赋。Registry为每个来源中的技能建立语义条目，无映射名称保留catalog_<ID>并标UNSUPPORTED，不静默丢弃Infinite新增能力。原有主动技能按school/type/target分类；关键被动统一注册但不成为主动技能。导入脚本scripts/import_apl_catalog.py可重复只读生成，运行插件不依赖Python。

## 能力及规则范围

| 分类 | 注册能力 | 本版规则 |
| --- | --- | --- |
| 奥术输出/增益 | 魔爆术、奥术飞弹、奥术强化、气定神闲、奥术冲击、Missile Barrage等 | 飞弹可选填充；奥强/气定独立开关且要求实际天赋；魔爆要求多目标场景及可见敌方阈值。奥术冲击层数/proc尚未支持 |
| 火焰输出 | 火球术、火焰冲击、灼烧、炎爆术、烈焰风暴、冲击波、燃烧、Heating Up等 | 火球/灼烧填充；火冲可选；炎爆要求实际已学、天赋及当前全部公开资格。灼烧Debuff维护、燃烧策略、地面/AoE命中条件未支持 |
| 冰霜输出 | 寒冰箭、冰锥术、暴风雪、冰霜新星、冰枪术、Fingers of Frost等 | 寒冰箭可选填充；锥形/地面/proc/控制条件未支持，不自动开启 |
| 资源 | 唤醒、法力宝石及制造技能、法力护盾 | 注册，mana_band/物品身份与资源策略未实现，不纳入DPS优先级 |
| 防御/通用 | 寒冰护体、寒冰屏障、急速冷却、反制、变形、闪现、护甲、结界、解除诅咒、奥术智慧/光辉、增效/抑制、侦测、缓落、造水/食、传送/门、魔杖射击等 | 注册并与DPS分开，保持UNSUPPORTED/OUTSIDE_DPS_V0；固定序列原5019功能仍保留 |
| 被动天赋 | 强化火球/寒冰箭、强化引导、奥术集中/专注/心智/增效、点燃、火焰强化/重击、强化灼烧、深冬之寒、碎冰等，完整54节点 | rank可查询；没有效果数值就不编造权重、触发机制或最优填充 |
| 其他Infinite新增记录 | 272来源内剩余技能、符文学习记录等 | 候选目录全保留，语义待验，不因目录存在而可派发 |

各能力都有SUPPORTED_V0或UNSUPPORTED状态；后者不因查询成功自动变成规则。static Ability Registry不等于每帧全量动态读取，v0动态只采9个动作。

规则顺序：可选奥强 → 可选气定 → 单体可选炎爆 → 单体可选火冲 → 用户填充；多目标为可选魔爆 → 用户填充。五个可选规则初始关闭。所有动作要求战斗内、GCD/自身CD公开就绪、实际known=true、usable=true、power_ok=true和必要范围。自增益无需敌方技能范围；连续派发仍遵守原有效敌方目标/文本焦点门禁。

气定、奥强和炎爆不是一个原子连招：本版不观察气定buff或爆发窗口，不保证下一个动作消耗气定。炎爆开关是明确的示范优先规则，不代表最高DPS。没有对应实际天赋或者rank未知时不参与。rank0不得用catalog SpellID存在替代学习。

填充偏好：自动/火球/寒冰箭/灼烧/奥术飞弹。自动权重尚未实现，若没有其他有效可选规则将显示APL_FILLER_SELECTION_REQUIRED；用户指定未学或未解析等级时不改推其他技能。多个已学且已绑定等级歧义时，可填写当前填充的精确ID；只有确认为该技能、已学的实际ID才接受为候选。默认固定序列已实测205/143/2136/5143、118/5019样本不自动成为全等级匹配映射。

当前并非最优DPS循环。尚未证明70338战斗内冷却/GCD、完整天赋节点、范围、资源布尔都可公开；UNKNOWN时不推荐可派发动作。测试步骤与这些限制见PRODUCTION_0.11.0.md。
