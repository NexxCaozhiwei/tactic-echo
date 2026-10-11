# TEF 0.8.0 审计落实

依据用户提供的 TEF_070_AUDIT_AND_CODEX_PROMPT.md 修改，保留现有未提交工作。TE AddOn 1.5.12 和 TEK 源码不变；本轮只交付源码，不替换客户端插件。

## 状态机与输入边界

Runtime.intent 是唯一用户派发意图。运行、待命、阻断是派生状态，暂停、完成、异常关闭意图。设置打开、目标变化、焦点、移动、范围、usable 或检测 UNKNOWN 临时阻断保持意图，Token 为 0，并撤销旧 pending；条件恢复后由唯一传输心跳重新核对当前步骤、代次及真实绑定。低层 StopContinuous 不反向关闭意图。

读条阻断保留本步已建立的起始关联与成功收据，不强制写 castPresent=false；存在性未知也不派发。设置/目标变更则失效旧关联，迟到成功不得推进。当前步明确失败或中断、手动停止、重置、配置修改、切图、关闭许可或输出，以及异常，关闭意图；恢复高级开关不会复活旧意图。完成默认停机，循环一次成功只消费一步。

无 CD/GCD/充能侧信道、宏放宽、动态 APL 或额外输入通道。协议仍 TEAP v3；TEK 的前台、Hook、手动让权、新鲜度、重放及限频不变。真实直接默认动作条身份在请求和编码时复核。缺绑定缓存阻断，动作条/技能更新事件清缓存，避免每心跳重新扫描。

## 入口与界面

正式按键组仅 TEF_TOGGLE_DISPATCH，执行 TEF_ToggleDispatchIntent。旧命令身份和 Lua 别名保留，旧练习/连续键明确归入“旧版兼容（迁移用途）”；许可/单步/停止归入开发测试组。不依赖未经本机验证的 Binding hidden 属性。自定义热键、主卡左键和设置 Toggle 共享 Runtime。

HUD 主卡为普通 Button，左键只启停意图，右键设置；不直接请求、施法、调用 UseAction 或建立 secure 代理。六状态为暂停灰、待命青、运行绿、阻断黄、完成金、异常红。Hover、Pressed、Tooltip 属于控制按钮反馈，不表示技能成功；拖动遵守锁定与战斗限制。移除主 HUD 的重置/单步/许可工具行，保留独立测试面板。

UIComponents 提供 ActionButton、SectionCard、HintText、Divider、ToggleRow、SegmentedControl、SelectRow、SliderRow、StatusBadge、HotkeyRow，统一回调错误归 Runtime.Fault。总览显示意图和派生状态、三个模式、自动启动与热键；高级页保留独立许可/协议设置；诊断页保留重置、单步和采样。设置打开时单步仍被原门禁拒绝，关闭设置后使用 /tef dispatch，不借测试按钮绕过门禁。

刷新以事件为主；HUD 0.25 秒 fallback 仅更新已有公开冷却数值，不查询技能信息、绑定、施法或输入资格。客户端 DurationObject 仅即时渲染，不持久化或回写输入。

## 验证边界

124 项 Lua5.1 模拟保留原 99 项并新增 25 项，覆盖唯一意图、旧别名、设置 Token0/新代次、临时阻断、硬停止、视觉 hide、回调异常、主卡不派发、界面/热键同步、三模式、六状态与拖动、fallback 不扫描、读条收据、目标迟到收据、API 重入、绑定负缓存恢复。另有 XML 静态检查：6 个绑定中正式组只有 1 个。

仓库 pytest 789 通过、7 跳过、17 subtests 通过；TEK unittest 234、AddOn 244、验收脚本 mock 2。baseline contract、compileall、Lua 语法及 diff whitespace 检查通过。mock 中 input sent 是模拟，不是真实 Windows 输入。

0.7.0/S39 的 116→205→205→143 成功收据与循环是历史实机证据，不能证明本版设置恢复、新 HUD、热键或连续派发。0.8.0 尚未实机验证。
