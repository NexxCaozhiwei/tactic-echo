# TEF 1.0.0基线验证

运行语义冻结0.14.3。300项Lua5.1模拟（196原功能+104APL）、30个TOC入口与独立Bindings文件检查，88个Lua语法检查；Python791通过/7跳过/17subtests，TEK234/AddOn244 unittest，基线/compileall/diff检查。首个Release的TEK从同提交构建，隔离禁自动启动冒烟不代表Hook或真实输入验证。真实历史正样本和限制见S76报告，1.0.0的固定5019×2交接仍待游戏内验收。

# 0.14.3

300项Lua5.1模拟通过（196原功能+104APL）；新增4项覆盖可选冷却默认关闭/显式未知阻断/配置清洗、禁用时不查询及派发即时复核、5019最后有效成功在公开5019读条下交接、其他施法/引导/未知拒绝与暂停/重置/相邻5019失效。TOC30入口，Bindings.xml作为独立安装文件验证6命令及唯一分组头。88个Lua语法通过。

Python回归791通过、7跳过、17subtests；TEK234与AddOn244 unittest，baseline、compileall和diff检查通过。客户端文件1.60.1.70338，Interface16001。部署35文件逐文件SHA256及TOC加载列表由deliver.py核对。以上为模拟/文件验证，新版加载、战斗APL与射击交接未实机验收；按PRODUCTION_0.14.3.md短测。TE/TEK与WTF不改。

# 0.14.2 CDM帧身份隔离验证

296项Lua5.1模拟通过（194原功能+102APL），新增5项覆盖未知ID帧在精确匹配前后、Secret ID/失败getter/公开getter、多个请求独立UNKNOWN、冲突/Secret状态/容量阻断与有界诊断清洗。派发即时复核用未知帧夹住匹配帧验证，匹配活动变化仍撤销请求。TOC31入口及88个Lua语法检查通过。

Python回归791通过、7跳过、17subtests；TEK234及AddOn244 unittest，基线契约、compileall和diff检查通过。客户端文件版本重新核对1.60.1.70338，Interface16001。部署35文件逐文件SHA256、TOC版本和加载列表由交付脚本核对；记录见dist/tef/TEF-0.14.2-delivery.json。以上是模拟及文件验证，CDM修复尚未游戏内验收，按PRODUCTION_0.14.2.md测试。TE/TEK源码和WTF未改。

# 0.14.1验证

291项Lua5.1模拟（194原功能+97APL）。新增7项待命测试：自定义只读候选与TEAP paused/Token0；范围丢失/恢复；无目标自身技能；移动优先级及进战重核；蓝量阈值与Secret；战斗未知仍拒绝派发；手动APL不绕过战斗门禁。模板待命HUD主卡显示、直接Request拒绝、查询中途脱战撤销同样验证。

88个Lua语法、TOC31入口、来源检查通过。Python回归791通过、7跳过、17subtests；TEK234、AddOn244 unittest，baseline、compileall与diff检查通过。Wow.exe仍1.60.1.70338、Interface16001。新版待命预览尚未游戏内验证，按PRODUCTION_0.14.1.md实测；部署35文件核对见dist/tef/TEF-0.14.1-delivery.json。

推荐不再强制战斗；Allowed和最终Packet仍强制公开战斗true，其他条件UNKNOWN不放宽。下文战斗属于推荐必需条件的旧条目仅保留历史，以0.14.1为准。

## 0.14.0验证记录

284项Lua5.1模拟（194原功能、60模板、18自定义、12新条件）；TOC31入口，88个Lua语法检查。六比较边界、公开/Secret蓝量、零max、checked距离、CDM公开false/true与目录独立ID、可选nil SpellID物品条目、缺帧/linked/冲突/超限、用户四条例子、5019、拖放与拿技能点击/动作栏直放/拒绝宏，以及距离/蓝量/CDM即时变化撤销均通过。

Python回归791通过、7跳过、17subtests；TEK234与AddOn244 unittest通过；baseline/compileall/diff检查通过。客户端Wow.exe 1.60.1.70338、Interface16001。模拟不证明本版拖入实机成功或敌对距离公开，新版按PRODUCTION_0.14.0.md逐项验收。

本机UnitDocumentation说明UnitPower/Max可能受Secret限制；UnitDistanceSquared有checkedDistance返回。CooldownViewerDocumentation.spellID可为空，公开无spellID的条目不作直接匹配；Constants分类0/1/2/3对应Essential/Utility/TrackedBuff/TrackedBar。帧状态只取公开isActive，不以可见性恢复Secret。用户授权新条件，未读其他SavedVariables。部署核对见dist/tef/TEF-0.14.0-delivery.json。

## 0.13.0验证记录

272项Lua5.1模拟（194原功能、60模板APL、18自定义APL），TOC30入口；自定义排序、全部规则解释、即时条件复核、Secret/非法配置、16条上限、跨场景保存与reload、API重入、成功重新求值、拖入ID及数字框刷新/保存保护均通过。86个Lua语法检查通过。

pytest合并运行791通过、7跳过、17subtests通过（含验收脚本2项mock）；TEK unittest234、AddOn unittest244通过。baseline contract、compileall、git diff检查通过。实际Wow.exe仍1.60.1.70338，TOC Interface16001。TEK异常日志为测试故意注入的boom/locked，不是实机日志。

新版自定义APL UI和真实派发尚未实机验证；安装逐文件SHA256见dist/tef/TEF-0.13.0-delivery.json。具体使用、受限条件与实测见PRODUCTION_0.13.0.md。下文为历史版本验证记录。

## 0.12.1验证记录

254 Lua模拟（194+60），TOC加载、5来源hash与84规则顺序/条件核对。验证150次失败仍可恢复，失败GUID跨重置不复用，4096总容量保守停止，GCD检测不执行，自身CD未知仍阻断。新版未实机验证。

# 0.12.0验证

253项Lua5.1模拟（193原功能+60 APL）与TOC加载通过；TEK/TE回归789通过、7跳过、17子测试。模板默认填充、移动布尔、AoE父调用、条件阻断、落盘清洗、配置保存、原始条件展示均有模拟覆盖。新版界面与实际派发尚未游戏验证，GCD未知继续阻断。

# 0.11.0验证

245项Lua5.1模拟通过（原193+APL52），28项TOC加载入口/XML及TEK互操作通过。新增职业包、混合天赋、实际已学/等级、三值rank、经典与traits provider、GCD/自身CD未知、精确成功后再求值、当前SENT锁定、取消重试、时钟缺失与API重入失效、APL UI草稿和无序列预览等。

pytest789通过、7跳过、17subtests；TEK234/AddOn244/验收mock2；83Lua语法、baseline、compileall及diff检查通过。实际Wow.exe 1.60.1.70338。TEFSim来源272技能/54天赋为unverified候选，源文件SHA256见APL_MAGE_60_V0.md；没有读写TEProbe、TE、TEK或其他插件SavedVariables。

尚未游戏验证APL状态能力、天赋完整覆盖、动态推荐或真实派发。GCD61304 NO_DATA和冷却Secret仍不派发；原固定序列行为不变。首轮按PRODUCTION_0.11.0.md验收，落盘仅读TEF_DB。

# 0.10.1验证

193项Lua5.1模拟与18项TOC入口/TEK互操作通过；新增选项鼠标移开与切页保持、页面底层纹理及HUD右键入口回归。pytest789通过/7跳过/17subtests；TEK234/AddOn244/验收mock2；72Lua语法、baseline、compileall及diff检查通过。界面效果待游戏内视觉验收。

# 0.10.0验证

190项Lua5.1模拟通过：新增F5显式覆盖、原生绑定保留/reload重建、UNKNOWN仍拒绝；控制键及战斗延迟期间旧键从技能派发排除、第二绑定可选；四循环模式迁移/重复/次数、目标与脱战事件、意图保留、旧START/SUCCEEDED失效及4096身份上限；标签白名单/Secret/边界/reload隔离、隐藏保持、战斗延迟和单个显示API失败。18TOC入口、6Bindings检查，原TEK互操作6项decoder/dry-run、3编码/1预算/2手动恢复通过。仓库pytest789通过、7跳过、17subtests；TEK234/AddOn244/mock2；72Lua语法、baseline、compileall通过。

TEF S53(0.9.1)保存F6，三次HOTKEY_CONFLICT；205→143→2136有精确成功收据，到5019×3但未保留5019成功计数。不能据此确认F5原生用途或新版覆盖/循环/HUD实机成立。新版按PRODUCTION_0.10.0.md验收。

# 0.9.1验证

178项Lua5.1/TOC17入口/XML与原TEK互操作通过；新增UI录入提交、reload重建、生命周期晚加载重试、同步事件重入、刷新幂等、错误/Secret/冲突/战斗延迟及取消。真实快捷键仍待游戏内确认，见HOTKEY_FIX_0.9.1.md。

# 0.9.0验证

166项Lua5.1模拟通过，新增拖拽第四字段/Secret/失败/满额保留游标、精确ID排序删除/次数、16/17边界、旧配置保留、空配置关闭、草稿隔离/刷新、重复收据与同索引重入、暂停/循环/保存/reload、5019激活与未知零Token、精确动作槽nil范围回退。17TOC入口与6Bindings检查，6decoder/dry-run、3编码/1预算/2手动恢复互操作通过。pytest789通过/7跳过/17subtests；TEK234、AddOn244、验收脚本mock2。baseline/compileall/71Lua语法通过，实际Wow.exe 1.60.1.70338。

0.8.2/S49已有前三步116→205→205成功，末步143与循环未保留。新编辑器和5019逐次收据尚未游戏验证；模拟与文件部署不能替代实机。按PRODUCTION_0.9.0.md验证。

# 0.7.0验证

追加实机S39（14:41:25落盘）：同一generation10的连续请求1–4对应116→205→205→143，各自公开SENT关联与SUCCEEDED成功，末步LOOP_COMPLETED回首步。TEK保留7条windows_sendinput成功记录（不是全部物理输入计数）；第二轮116失败后停止，未误计步。只将上述固定序列/相邻计数/循环与输入链标记实机成立，未测功能仍待验收。详见FIELD_REPORT_2026-10-11_TEF_070_S39.md。0.7.0交付时的“尚未实机”收据是部署时历史状态，不改写原包/哈希。

99项Lua5.1模拟、TOC 15个入口及6个Bindings动作通过；新增职业/专精/Secret隔离、来源缺失、三模式、自动启动、单步幂等、连续四步、旧任务失效和快捷键冲突/延迟/组合键。未调用真实输入器，新功能未游戏验收。

# 0.6.1修复验证

87项Lua5.1模拟通过：新增冷却/GCD/充能接口不被固定尝试读取、无关动作栏刷新保留、进战保留及目标变化停止；保留文本焦点/目标/范围/usable UNKNOWN拒绝、施法保护与失败停止。新修复未实机验收，S34只证明旧版连续阻塞和手动成功。

# 验证与证据范围（2026-10-11）

## 0.5.0

70项Lua5.1模拟，新增公开施法/引导文字不改变输入，以及CD/充能独立文字层清理。TEK颜色7项测试含256字节、TE/TEF双颜色、有/无间隔定位、两份真实屏幕像素CRC、量化64组合上限、损坏/未知颜色拒绝。仓库789项通过、7项跳过、17子测试；TEK unittest234项、AddOn244项；TOC、Lua语法、基线及compileall通过。

已有实时画面只读定位及Token0完整帧解码通过；生产TEK已持续报告signal_found=true、protocol_version3、Token0及observation_frame，无输入。HUD/TEUI已在当前游戏中只读检查排版和加载，未声称用户主观满意。新TEK非零请求及游戏成功仍须另验。PyInstaller构建与包内新模块核验不代替真实输入。

追加13:28实机证据：用户主动派发测试后，桌面生产TEK trace记录TEAP v3、BindingToken5/6/7对应键1/2/3，gatePassed、dispatchAttempted、inputSent均true，backend=windows_sendinput、events_sent=2。这证明真实Windows发送接口返回成功；不替代游戏精确成功收据。部分请求重复发送，不能承诺单次输入。测试已按用户回复停止，游戏成功推进仍需落盘另验。

## 0.4.0

65项Lua5.1模拟，包括许可门控和持久分类、共用快捷键、CD事件分类、GCD排除、Secret/缺API/调用失败、单一视觉对象和显示ticker不推进/派发。2项验收脚本mock检查等待前台和暂缺信号后恢复，保留真实模式Hook/预算/退出清理。6 TEK互操作、3人工帧编码、预算耗尽和暂停handoff检查通过；12个TOC入口含Bindings.xml（XML解析通过）。本机实际dry-run两帧启动成功，门禁window_process_mismatch，无输入；不等于游戏内定位/真实发送成功。新快捷键/HUD标签与API公开性仍待实机。

## 0.3.0（历史）

59项Lua5.1模拟覆盖交付HUD、保留测试面板、118迁移、绑定codec、人工请求及撤回；10个TOC入口。新UI和真实输入未实机验收。TEK验收脚本只装配已有组件，固定成功发送预算1，缺Hook拒绝输入。

6项既有TEK解码/dry-run、3项新人工帧逐字节编码、预算耗尽和暂停→请求handoff检查通过；2项脚本mock装配测试核对Hook/前台/预算/退出清理与明确真实输入授权。没有调用真实发送器。仓库pytest 782通过、7跳过、17 subtests通过；TEK unittest227、AddOn unittest244通过，baseline、Lua语法、compileall通过。实机客户端文件版本重新核对1.60.1.70338，Interface16001由本机同build快照及插件加载查询核对。

## 0.2.0 大更新第一阶段（历史）

53项Lua5.1模拟通过，覆盖双场景、配置草稿/保存/reload净化、未核验变形术与显式公开成功ID确认、旧代次/相邻去重、自动建议滞回/重复轮/未知/过期、逐字段及整轮失效、目标存在不替代有效性、动态规则门槛、128条饱和、菜单和协议失败。新API只显式旁路采样，自身ready/gcdClear固定UNKNOWN，不开放自动切换/动态输入。

现有未修改TEK的3项观察帧CRC/Commit解码及拒绝输入、3项ActionCode0/真实BindingToken dry-run路径通过（1、SHIFT-1、CTRL-Q）。实际Windows发送器未调用，这些不是Hook、定位、SendInput或游戏施法验收。进一步源码核对修正初始草案：已有未收录技能的ActionCode0路径，当前无需修改TEK或新增目录适配。

客户端Wow.exe FileVersion1.60.1.70338/ProductVersion同build当前重新核对；Interface16001沿用同build本地官方快照并在加载后GetBuildInfo再核对。8个TOC入口文件、版本、独立命名空间/数据库及源码ZIP检查通过。部署收据dist/tef/TEF-0.2.0-delivery.json列逐文件SHA256及备份。

仓库要求回归：baseline contract通过；pytest 782通过、7跳过、17 subtests通过；TEK unittest227、AddOn unittest244通过；全部TE/TEF Lua的luac语法及Python compileall通过。TEK测试中的boom/locked等为预期故障注入，最终测试成功。TE代码与版本1.5.12、TEK源码保持不变。

本版新HUD、变形术实际成功ID、姓名板公开性与屏幕信号定位均待MAJOR_UPDATE_TEST_0.2.0.md实测。模拟中118仅为人工构造的测试ID，不是本机变形术ID结论。

## 0.1.3 用户指定精确ID序列

当前配置116→205→205→143，保留StandardConfig原四步及AdjacentConfig两步205。Engine及门禁无改动，未扩展等级等价。新增跨ID误匹配、相邻205两次独立成功、后续143选择与成功测试，共28项Lua5.1模拟及TOC/基线检查通过。0.1.2两步205已在session10实机完整完成，首发STOP无额外推进；本次新四步仍待RANK_SEQUENCE_TEST_0.1.3.md独立实测。

交付为dist/tef/TACTIC-ECHO-FOREVER-0.1.3.zip与TEF-0.1.3-delivery.json，部署备份现有TEF目录并核对9安装文件SHA256；TE回归、Lua语法与compileall按下述既有命令运行。未修改WTF及TE运行逻辑。

## 0.8.2 原TE普通派发/手动让权恢复 — 2026-10-11

用户明确覆盖失败停机与全局移动门禁。141项Lua5.1通过：新增9项顺序外开怪、未发起候选等待释放、当前关联保护、移动尝试、重复失败恢复及停止粘性；原132项保留，移动/静止失败断言按新授权行为更新。追加2项TEF实际编码→原TEKEngine/PhysicalInputPause dry-run互操作，Q/SHIFT按住让权、松开delay及freshness恢复通过，无实际Windows输入。

pytest789通过、7跳过、17 subtests通过，TEK unittest234、AddOn244、验收mock2；baseline、compileall、所有Lua语法及diff检查通过。协议/TEK源码无改动。当前落盘0.8.0/S46，只能证明旧失败关意图及5019顺序外现象；0.8.2新行为需实机。部署20文件SHA256、TOC版本与16入口/Interface16001核对，完整备份、保留未知文件，不改WTF。学习原代码与具体差异见TE_DISPATCH_PARITY_0.8.2.md。

## 0.8.1 移动失败与相邻ID收据 — 2026-10-11

新增8项Lua5.1模拟，共132项通过：移动失败保留意图并原步重试；旧失败/START/SUCCEEDED隔离；heartbeat先阻断的事件顺序；静止精确失败停机；相邻205旧失败不关闭当前请求；Secret/nil身份与移动API未知/失败零Token；API重入；128身份容量与reload清空。旧124项保留。

仓库pytest789通过、7跳过、17 subtests通过，TEK unittest234、AddOn244、验收mock2通过。baseline、compileall、Lua语法及diff检查通过。0.8.0/S45落盘确认失败路径误停风险，未持久化移动值/GUID，不推断具体失败原因；0.8.1移动恢复仍待实机。部署20文件逐文件SHA256核对、TOC0.8.1/Interface16001/16加载入口，既有TEF备份并保留未知文件，不改WTF。

## 0.8.0 审计落实验证 — 2026-10-11

保留99项既有Lua5.1测试，新增25项，共124项通过；6项TEK decoder/dry-run、3种精确编码、1项模拟预算通过。XML验证六绑定只有一个正式启停，旧入口明确兼容/开发分组。状态机、主卡、设置同步及事件刷新覆盖详见UI_RUNTIME_UNIFICATION_0.8.0.md。

baseline contract通过；pytest789通过、7跳过、17 subtests通过；TEK unittest234、AddOn244、验收脚本mock2通过；compileall、全部AddOn/TEF Lua语法和diff检查通过。测试中的模拟inputSent和故障注入不能作为实机证据。

完整源码ZIP逐成员SHA256复核，单层插件根目录；本轮不部署、不提交推送。0.8.0新HUD/设置/热键/自动恢复尚未实机验证，0.7.0/S39仅历史参考。下一轮按PRODUCTION_0.8.0.md验收。

## 0.1.2 临时相邻同技能配置

运行配置205→205，保留StandardConfig原四步供恢复；无Engine推进/去重/生命周期改动，不修改WTF或原循环偏好。新增当前部署配置必须两次独立成功的模拟测试，共27项Lua5.1测试及TOC检查通过。原四步回归使用保留配置，不与当前两步配置混淆。相邻同技能实机仍待ADJACENT_TEST_0.1.2.md验收，不能用模拟代替。

交付为dist/tef/TACTIC-ECHO-FOREVER-0.1.2.zip与TEF-0.1.2-delivery.json，部署前完整备份已有TEF目录；9个安装文件逐文件SHA256与TOC/Interface核对。TE全量回归及语法验证结果沿用以下相同命令，本次仍运行，不改TE源码。

## 0.1.1 诊断升级

新增事件白名单持久化、重复成功/同标识后续事件分类、旧历史兼容四项回归，共26项Lua5.1模拟。0.1.1新event身份尚未实机验收；0.1.0实机已记录完整四步、循环、取消/失败、偏离和暂停/继续，原始分析保存在仓库dist/tef/FIELD_REPORT_2026-10-11_TEF_0.1.0.md，不随安装包复制私人日志。飞弹IDENTITY_NO_DATA旧记录不能归因，本版仅为取得可定位的新证据。

0.1.1本地验证：Lua5.1共26项模拟与TOC检查通过；基线契约通过；TE全量pytest 782通过、7跳过、17 subtests通过，TEK unittest227与AddOn unittest244通过；全部TE/TEF Lua语法及Python compileall通过。基线检查最初指出TEF子目录归档不符合全仓库路径约束，已移至docs/baselines/tef并在ZIP映射回独立插件的docs/baselines；未更改TE检查器。未将旧版本实机证据扩大为本次新诊断的实机验收。

0.1.1源码包和部署收据为dist/tef/TACTIC-ECHO-FOREVER-0.1.1.zip及TEF-0.1.1-delivery.json。部署前完整备份现有TEF目录，不改WTF或其他插件。短测见UPGRADE_TEST_0.1.1.md。

## 0.1.0 初始交付验证（归档）

本轮仅代码与模拟验证、部署完整性核对，没有游戏内操作或实机事件公开性验收。

已核对本机 `E:/World of Warcraft/_cn_beta_/Wow.exe` FileVersion/ProductVersion：1.60.1.70338。Interface16001依据同版本CASC官方快照及既有S55–S61实测记录；TEF加载时再独立GetBuildInfo记录实际Interface，不从Windows文件版本推测接口。

只读参考：TEProbe的KNOWN_CAPABILITIES、FIELD_REPORT_2026-10-10_FOREVER_INVENTORY第29–32节及相关样本、TEF_STATE_INTERFACE_70338、TEF_STATE_CONSUMPTION_70338、TEF_PREPARATION_AND_VALIDATION_PLAN、NEXT_STEP_PLAN_2026-10-10_70338、API_SOURCE_70338；Client/Probe/Events/Probes/CDM的官方检测与事件方法。未修改其源文件或文档，也未读取其数据库。早期暂停动态ready MVP不阻止本次人工固定顺序授权。

一手声明目录：`G:/CODES/TEProbe/dist/client-api/wow_cn_beta-1.60.1.70338/Blizzard_APIDocumentationGenerated/`。

| 文件 | 核对内容 | SHA256 |
| --- | --- | --- |
| UnitDocumentation.lua | SUCCEEDED/START/STOP/CHANNEL_START/CHANNEL_STOP/FAILED/INTERRUPTED均unitTarget,castGUID,spellID；SENT为unitTarget,target,castGUID,spellID。忽略第四参数及SENT目标参数 | E62816D9F8EDC63AC3B80C5A50540A62CABA77586FCC4827F684FD74E0257C1E |
| SpellDocumentation.lua | C_Spell.GetSpellInfo返回可无数据SpellInfo；GetSpellTexture返回可无数据iconID及额外图标字段，本版仅检测使用第一图标 | 86583940D9A2C4594092EB248A1396A93A285084872AF1F3F4875169796E7D2B |
| FrameScriptDocumentation.lua | issecretvalue官方检测函数；缺失、失败或非布尔返回保守UNKNOWN | 945C09648A60FE90271ED5FC092608AF85774FD24DAA615D1410263593DE7C2C |

Unit事件声明SecretWhenUnitSpellCastRestricted，因此定义不能替代事件unit/spellID/castGUID各自的实际检测。205、143、2136、5143及7268是报告观察样本，不补造全部等级映射或公开GUID验收。尤其SENT/START和成功事件的公开GUID一致性尚待实机，标识受限或未观察到起始关联时TEF会不推进。

TEF：22项纯Lua模拟用例；系统Lua5.4模拟通过；Lupa Lua5.1加载/语法及同组模拟另核对。覆盖正常四步、非成功事件、失败后迟到成功、偏离、重复/相邻同技能、飞弹/7268、循环、Secret三字段、检测缺失/错误/UNKNOWN、nil/非法类型/ID/GUID、无起始关联、暂停/继续/重置/旧代次、reload与历史净化、128条饱和、关联/去重容量、非法配置、元数据/图标失效、独立namespace/DB与真实SENT参数顺序、UI异常、slash/退出。

TE仓库第9节回归：baseline contract通过；pytest 782 passed、7 skipped、17 subtests passed；TEK unittest 227通过；AddOn unittest 244通过；compileall及TE AddOn全部Lua luac语法检查通过。TE未作源码修改或版本升级。测试中预期的故障注入stderr（boom、locked等）不作为实机运行错误。

部署脚本逐文件比较源/安装SHA256并验证TOC加载顺序、版本和Interface；ZIP复读逐成员哈希并确认仅一个顶层目录。机器可读最终收据为仓库 `dist/tef/TEF-0.1.0-delivery.json`，独立ZIP为 `dist/tef/TACTIC-ECHO-FOREVER-0.1.0.zip`。目录已有文件会先备份并保留未知文件；本次目标初始不存在。部署不能证明游戏内已枚举加载或成功推进，按FIRST_TEST.md验收。
# 0.4.1 验证增补

增加三项Lua5.1模拟：无关动作更新保留锁定请求；技能/键位/按钮对象变更及Secret/API异常立即撤回；生产dispatch入口与游戏成功计步分离、失败不自动重请求。总计68项。复用实际TEK协议/门禁互操作验证，不执行真实Windows输入。新版本物理派发需实机另验。
# 0.6.0 连续派发实验 — 2026-10-11

84项Lua5.1模拟通过，包括固定四步、相邻同技能、单步循环、5143/7268、等待成功、失败停止、公开证据UNKNOWN/缺失/调用失败、采样重入生命周期失效、128条日志及重复等待去噪。TOC加载列表及五个原生绑定检查通过。

仓库789 passed、7 skipped、17 subtests passed；TEK unittest234、AddOn244、验收脚本mock2通过。baseline、compileall及全部Lua语法通过。TEK源码和EXE本次不变。连续功能及新增HUD控件尚未游戏内验收；0.5.0/S29和S30成功证据不能代替0.6.0实机结论。
