当前0.12.1：用户明确授权取消APL GCD条件与61304查询；其他条件不变。失败身份采用原4096共享预算，取消重复128失败上限。以下旧版本GCD限制作为历史记录，按本条覆盖。详见docs/PRODUCTION_0.12.1.md。

当前规则版本0.12.0，来源与逐行清单见WOTLK_MIGRATION_0.12.0.md。以下State/生命周期契约继续有效。

# APL v0 架构（TEF 0.11.0）

Infinite APL的基本单位是 **Class Pack，不是Spec Pack**。当前只有MAGE_FOREVER_60；其他职业不回退法师包。不依赖“天赋点最多的一系”或build标签选择规则，奥火冰混合加点在同一包里参与条件求值。

## 模块与证据边界

加载顺序为Abilities → Talents → TalentState → Registry → State → Conditions → Trace → Mage60 → Rules → APL Engine，再进入原Sequence/Recommendation及Runtime链路。Lua5.1，无字符串eval、C_Timer、宏生成或新的输入路径。唯一TEAP心跳调用Runtime；APL合并dirty事件，通常最多每0.5秒采一次动态状态。期间只采12个当前规则/填充技能；不会每帧扫描全部目录或天赋。

能力目录参考用户指定TEFSim，导入272个技能候选、54个天赋候选。见APL_MAGE_60_V0.md。导入脚本只读外部JSON，复制ID、名称、等级、节点及最高rank事实，保留unverified；不执行资料里的Lua，不导入旧Classic效果或法强系数。运行不读取TEFSim文件、TEProbe/其他插件数据库。

State把API返回立即经官方issecretvalue检查、独立pcall和类型/范围检查归一化。缓存只保存普通bool/number/string/table，不保存API对象、原始Secret或异常全文。行为条件为true/false/nil（UNKNOWN）：All中任何false否决，存在UNKNOWN不能通过。条件是声明式Lua数据，支持combat、gcd、action.known/usable/power_ok/in_range/ready、talent.known、talent.rank>=N、可见enemy_count>=N、配置开关和填充偏好。

已学技能来自公开玩家法术书：最多16个skill line、256个slot，使用官方Enum和ItemInfo，忽略被动及7268，独立IsSpellKnown确认实际ID。若同名多个等级，优先唯一真实直接绑定的等级；仍不唯一时不猜最高数值ID，显示等级未解析，用户可填写已学精确ID。静态目录ID不构成等级成功别名；每次候选的成功匹配表只有当前实际ID。完整扫描才可把缺少的能力标未学；不完整或检测未知保持UNKNOWN。

TalentState先检查真实legacy树/rank API是否存在；它不使用现代row/column专精接口代替。签名参考Blizzard历史UI源码的[GetTalentInfo调用](https://github.com/Ennie/wow-ui-source/blob/master/FrameXML/TalentFrameBase.lua#L157)。目标build未确认legacy可用，因此还提供本机70338生成定义的C_ClassTalents/C_Traits provider：当前config、最多3棵树、128个节点；节点须在当前树返回列表内，公开ID与查询一致，单entry的定义SpellID及名称与目录节点相符，实际activeRank/maxRanks合法。多选节点的整体rank不冒充某一entry rank；配置在采样中改变则全部UNKNOWN。无API、Secret、节点失配、未覆盖都不当作rank0。rank0明确NOT_KNOWN，rank>0 KNOWN。每棵树的所有已登记节点rank都确认才合计BuildSignature，否则显示?，不拿它做规则选择。

冷却只接受公开、合法、isEnabled=true且startTime=duration=0的即时证据；非零为未就绪，受限/缺失为UNKNOWN。不用isActive=false、DurationObject、估算GCD、钟表推演过期或读条长度代替ready；isOnGCD不用于本版准入。GCD独立查询61304，NO_DATA不是ready。资源只读IsSpellUsable的公开usable/insufficientPower，power_ok来自insufficientPower=false，不读UnitPower、mana_pct或具体数值。mana_band预留UNKNOWN。自身施法范围标“不需要”，敌方技能要求公开inRange=true；可见敌方数不声称实际AoE命中数。

## 推荐、生命周期与输入

默认仍为人工/代码固定序列；APL在推荐配置里按**职业+场景**显式启用（aplByClass），不会覆盖classProfiles的序列。APL配置独立保存在TEF_DB.apl；没有现代专精选择菜单。APL实际候选在运行期用原Engine的一步槽承载，不持久化候选、快照或活动状态。reload后重新采样；旧autoStart偏好只创建新意图。

优先级按手选WotLK构筑模板的default及受门控子列表原顺序；保留每条原始条件/开关/迁移状态。奥术/火焰/冰霜属于统一Class Pack，非现代专精，不自动猜天赋。依模板使用源末尾填充，显式覆盖只作用末尾填充；复杂条件未支持即BLOCKED。

APL Refresh须处于唯一用户意图内且设置关闭；施法/引导存在或UNKNOWN时不换候选，已收到当前SENT/START的精确公开关联也锁定候选并零Token等待收据，防止SENT先于读条显示的间隙丢失身份。SUCCEEDED只确认该关联，receiptSerial递增、旧快照失效；不强制写castPresent=false。奥术飞弹按成功发动语义，7268子事件忽略。取消/失败不消费，按原重试路径保持意图；无成功/失败收据时不凭时间解锁，需停止/重置。

候选ID改变通过原Runtime内部Reset失效旧关联与请求，保留意图；设置/目标变化/生命周期仍沿用原门禁。Packet检查generation/receiptSerial/revision、时钟有效与≤1秒快照，再独立实时复核当前实际技能known/usable/power/range/自身CD/GCD/战斗。天赋/学技能/动作条/战斗/目标事件使对应缓存dirty，旧快照立即不能编码。TTL与0.5秒合并只管理证据新鲜度，不估算技能/GCD/施法时间。TEK的前台、Hook、手动让权、限频和重放守卫不变。

最近128条原诊断共用容量；状态或规则结果变化时记录APL_SELECTED/APL_NO_CANDIDATE，包含最多48条规则及12个技能的公开bool/ID和4个关键天赋rank。淘汰不妨碍新状态更新，reload白名单清洗记录，不恢复派发资格。HUD显示来源、规则和BuildSignature；原CD/充能转盘仍只用于视觉，不回写APL。

本版本提供机制骨架和保守可验证规则，不是最优DPS或实机ready路径已经闭合的结论。70338既有证据中GCD61304可能NO_DATA、冷却数值战斗中可能Secret，这时APL正常显示等待并保持零Token。固定序列不受这些新准入依赖影响。
