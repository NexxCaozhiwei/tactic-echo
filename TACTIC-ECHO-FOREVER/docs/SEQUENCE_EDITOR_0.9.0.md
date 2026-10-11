# TEF 0.9.0 推荐序列编辑与计数

单体与多目标各保留一套人工配置，按职业/专精隔离，每套最多16个技能步骤，每步次数1–99。不是16套序列，也不展开次数来占用步骤。旧17–32步配置保留在TEF数据库的对应职业/场景，高级文本完整显示；缩减至16步后保存才能运行。删除最后一行可保存空配置，无推荐与派发。

`/tefui` → 推荐配置：选场景与人工序列。拖入上方区域追加，拖到行空白区域插入该行之前；手输数字SpellID点“ID新增”，“射击5019”复用同一路径。每行上/下调整顺序、删除，次数输入后回车或移开焦点应用草稿。保存才生效并暂停回首步；代码来源不会隐式改成人工。草稿按职业/场景隔离，事件刷新不覆盖输入。

高级文本格式 `205:205*3`、`143`或`?技能名*2`，默认次数1。拖入/手输只产生一个精确匹配ID，不自动等价116与205，不扫描法术库或宏。信息/图标失败显示未解析/占位，保留显式ID，不跳步；7268拒绝。保存只用TEF_DB。

公开player、合法SpellID、公开castGUID，以及当前运行代次/步骤/成功收据代次一致的SENT/START关联，随后精确SUCCEEDED才增加次数。重复GUID、旧关联、顺序外、START/STOP/失败/取消/Secret不计数。次数未满仍推荐同一步，满后前进一步；每次成功递增receiptSerial，索引相同也使旧请求失效。循环末步次数满回首步；暂停保留次数，重置/保存/切场景/reload清零，不恢复落盘活动次数。128条日志新增castCount/requiredCasts，不落盘GUID。5143成功开始引导计一次，提前取消可能已计；CHANNEL_STOP不确认完整引导，推进不清读条。

5019精确绑定后查询当前动作激活状态，公开false才允许发起候选；true或UNKNOWN撤回Token，保留练习等待真实成功。活动状态只防止再次按键关闭射击，绝不作计数证据。70338是否每发都有独立公开SENT/START+SUCCEEDED尚待实机；只收到启动成功就不推算后续次数，可手动停射再重新开始以取得另一身份。可靠活动查询缺失保持零Token。若射击仍被API报告为读条，后续技能继续受读条保护，需要实际停射复测。`/tef stop`停止TEF输入，不代替游戏停止射击操作。

仅5019的C_Spell范围返回公开nil时可由当前精确验证动作槽读取C_ActionBar.IsActionInRange，仍须公开true；false、Secret、失败不覆盖。既有target/usable/绑定门禁保持。

本机70338核对：gamecursordocumentation.lua定义GetCursorInfo/ClearCursor，但未定义游标返回字段；actionbarframedocumentation.lua定义IsCurrentAction/IsActionInRange；spelldocumentation.lua定义信息与范围。第四字段用法参考[Blizzard ClickBindingUI源码镜像](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ClickBindingUI/Blizzard_ClickBindingUI.lua)和[SharedTalent源码镜像](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedTalentUI/Blizzard_SharedTalentSelectionTemplates.lua)，不是70338实机证明。仅接纳官方检测后的公开第四字段，不将第二字段法术书槽位猜为ID。成功加入草稿后才清游标；满额、无效类型、异常保留游标，不保存原值。

不新增APL、自动场景切换或输入通道；TEAP v3、TEK前台/Hook/手动让权/新鲜度/重放/限频保持，本轮不改TE/TEK源码。
