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
