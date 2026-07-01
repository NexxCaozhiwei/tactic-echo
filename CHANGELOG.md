# Tactic Echo 0.9.51 — P5.6.1 冷却事件注册热修

- **修复启动阻断**：移除 `CooldownResolver.lua` 对不存在的 `ITEM_COOLDOWN_CHANGED` 事件的订阅；该事件会使当前客户端在加载阶段报错并中止 AddOn 初始化。
- **保留冷却刷新覆盖**：物品、药水和饰品仍由 `BAG_UPDATE_COOLDOWN`、`ACTIONBAR_UPDATE_COOLDOWN`、`UNIT_SPELLCAST_SUCCEEDED`、装备变化与既有 0.10 秒有界饰品重读共同驱动；不改动冷却显示、TEAP、TEK、推荐或输入路径。
- **回归约束**：新增合同断言，禁止重新引入无效的物品专用冷却事件。

# Tactic Echo 0.9.51 — P5.6 TEAP v3 自动定位与客户区锚点

- 保持 TEAP v3 全部 20 个字段和校验语义不变；定位仅使用固定 `T / E / 3` 头部，完整帧仍是唯一授权来源。
- 自动定位限制在 WoW 客户区左上 `360×96 → 640×160 → 最大 960×240 px` 的有界区域；不再扫描完整客户区或桌面。
- 新增零间隙兼容、3×3/5×5 中位数采样、两帧 freshness 前进验证、缓存布局的重新证明与明确的 `SignalSearching` 失败状态。
- 自动模式删除 `(12,12)` 绝对坐标回退；布局失效时 fail-closed。
- AddOn 信号框改为客户区左上 8px 物理边距与最小 8px 方格自适应布局。


- **原生倒计时数字扩展**：HUD 现在会显示所有可用 Blizzard `DurationObject` 的原生数字：直接动作条技能、SpellID 回退技能、药水与其他物品类别冷却。公共冷却仍只显示转盘、不显示数字。
- **动作条仍为最高优先级**：直接映射到 Blizzard 默认动作条的技能，优先读取该动作条槽位的 `DurationObject`；HUD 不再以本地计时覆盖它。
- **事件驱动本地兜底**：参考 `CooldownTracking.lua` 增加脱战预缓存、施法成功启动、`0.01 / 0.05 / 0.15 / 0.35` 秒 API 复核、`SPELL_UPDATE_COOLDOWN` 早期清理，以及多充能恢复追踪。当原生对象/API 数值不可渲染时，才输出本地倒计时。
- **药水与物品路径**：`item_duration` 的原生数字不再被隐藏；绑定药水优先走动作条槽位，未绑定物品仍可走 `C_Item` 的原生 DurationObject。
- **安全边界**：冷却数据仍只用于 HUD 展示；没有修改官方主推荐、BindingToken、TEAP、TEK 或任何输入路径。

实机重点：复仇之怒、灰烬觉醒、常用打断/防御、爆发药水、13/14 饰品，以及至少一个双充能技能。

# Tactic Echo 0.9.49 — P5.3 动作条权威技能 CD 修正

- **动作条优先**：直接映射到 Blizzard 默认动作条的技能卡，HUD 转盘与数字均改用该动作条槽位的原生 `DurationObject`；HUD 不再以自建秒数覆盖它，因此数字与动作条保持一致。
- **撤回基础 CD 估算**：`CooldownTracker` 不再以 `GetSpellBaseCooldown`、离战缓存或施法时间戳合成中央倒计时。天赋减 CD、冷却速率、覆写技能、重置效果和充能均不会再被基础数值误覆盖。
- **确认只作状态提示**：施法后的 `0.01 / 0.05 / 0.15 / 0.35` 秒确认仍保留，但只标记“CD 校验中”；在权威 API/动作条尚未确认时，HUD 宁可不显示自定义数字，也不显示错误秒数。
- **充能同规则**：本地充能估算不再进入 HUD 数字模型，仅使用当前公开 API 数据或原生动作条显示。
- **范围**：仅修技能 CD 数字权威性；饰品 P5.1、药水、HUD 标签分层、TEAP 与 TEK 派发均未改变。

# Tactic Echo 0.9.48 — P5.2 技能冷却可靠显示

- **施法即刻本地计时**：`UNIT_SPELLCAST_SUCCEEDED` 后，已登记技能先以离战缓存或基础冷却启动仅 HUD 使用的本地计时，避免 C_Spell 在事件瞬间仍返回“就绪”而丢失 CD 数字。
- **多阶段 API 确认**：技能冷却采用 `0.01 / 0.05 / 0.15 / 0.35` 秒事件驱动确认；一旦 API 返回可解释的活动冷却，即用权威 `start/duration` 校正本地计时。
- **覆写技能统一**：无法从事件直接取得动作条槽位时，优先复用既有 SpellID→槽位别名，不再创建竞争的 spell-only timer，修复基础/覆写技能同一可见按钮出现不同 CD 的风险。
- **短暂 ready 不清空计时**：确认窗口内 API 暂时返回就绪时，本地计时继续有效直至自然结束或被后续 API 冷却确认覆盖。
- **HUD 诊断**：Tooltip 可显示“技能 API（施法后确认）”和“CD 校验中”；该状态纯展示，不进入推荐、TEAP 或 TEK 派发。

# Tactic Echo 0.9.47 — P5.1 饰品冷却显示热修

- **饰品槽位不再无限缓存**：`inventory:13`、`inventory:14` 使用 0.10 秒有界重读，仅覆盖两件已展示饰品，不对全部法术或背包物品增加 OnUpdate 轮询。
- **槽位与 ItemID 交叉校验**：优先读取 `GetInventoryItemCooldown("player", 13/14)`；若其在使用后短暂返回 `0/0`，则对当前装备的 ItemID 依次查询 `C_Item.GetItemCooldown`、`C_Container.GetItemCooldown` 与旧 API。任一来源确认冷却，即显示数字和转盘。
- **多阶段确认**：玩家施法、动作条冷却、法术冷却、背包冷却与装备变化后，以 `0.01 / 0.05 / 0.15 / 0.35` 秒的合并确认序列重新读取已展示饰品。
- **诊断可见性**：HUD Tooltip 会区分“装备槽位 API”与“当前装备 ItemID 回退”，用于确认客户端瞬态 API 读数。
- **范围控制**：本版只修饰品 CD 生命周期；技能、药水、HUD 样式及 TEK 派发路径未改变。

# Tactic Echo 0.9.46 — P5 统一冷却快照与 HUD 状态标签分层

- **统一冷却数据层**：新增 `Tactics/CooldownResolver.lua`。技能以 `C_Spell.GetSpellCooldown`（旧 API 回退）为来源；饰品以 `GetInventoryItemCooldown("player", 13/14)` 为来源；药水及其他主动使用物品以 `C_Item.GetItemCooldown(itemID)`（旧 API 回退）为来源。三类来源统一输出 `identity / source / known / start / duration / remaining / active` 快照。
- **事件驱动刷新**：冷却变化、施法成功、装备切换、背包、天赋/专精和法术表变更只标记缓存为脏，并以 `C_Timer.After(0.01)` 合并读取；HUD 倒计时仅按已缓存 `start + duration` 递减，不在 `OnUpdate` 高频查询冷却 API。
- **物品卡片不再依赖动作条冷却**：饰品/药水的动作条绑定现在只决定现实按键和“未绑定”提示；即使未放在动作条，仍可显示来自装备槽位或 ItemID 的 CD。药水耗尽后，只要类别冷却仍在，卡片仍保留 CD 显示。
- **HUD 三层文字**：来源标签（左上）、CD 数字（中央）、状态标签（左下）分离。`施法 / 引导 / 蓄力 / 暂停 / 阻止 / 未绑定` 不再覆盖 CD 数字；每个模块新增独立“状态标签”字体、字号、缩放、位置与偏移配置。
- **原生转盘边界**：公开数值不可解释时，HUD 不伪造 CD 数字；仍尝试在渲染边界使用 Blizzard DurationObject 转盘。原始 DurationObject 不进入 HUD 模型、战术建议、TEAP 或 TEK 派发路径。
- **回归覆盖**：新增 P5 冷却来源、未绑定物品卡片、三层 HUD 文本、事件合并与 DurationObject 边界合同测试。

# Tactic Echo 0.9.45 — P4 性能链路、重定位与异步诊断

- **P4-A**：WoW 客户区快速几何读取与前台标题缓存降低 50 ms 热路径 WinAPI 压力；插件端 TEAP 色块改为差量绘制，`TacticalState` 改为状态变化或 500 ms 心跳发布。
- **P4-B**：重定位采用左上角 900×220 → 1600×400 → 当前 WoW 客户区的渐进扫描；扫描在后台执行，变化期间 TEK 保持 fail-closed。已验证条带的相对客户区布局会跨启动保存为提示，仍须通过新的 TEAP CRC/Commit/颜色校验才可派发。
- **P4-C**：新增可选 `auto` / `gdi_blt` 条带后端。默认仍为 Pillow；选择 Auto 后，连续三次有效 Pillow 读取才提升为 GDI BitBlt，读取失败自动会话回退 Pillow。新增 `python -m tek.src.sampler_benchmark` 本地只读基准工具。
- **P4-D**：Trace 写入移至有界后台队列，诊断/序列化/写盘错误不会终止 worker；隐藏状态窗口停止 Tk 控件刷新，恢复时立即刷新；条带边界、采样点和 `ScreenFrameSource` 热路径对象使用缓存。
- 回归覆盖：渐进区域、后台重定位、跨启动布局缓存、Auto→GDI BitBlt 提升与回退、基准工具、异步 Trace、隐藏窗口刷新和热路径对象缓存。

# Tactic Echo 0.9.44 — P2-B 窗口模式恢复与状态窗口位置记忆

- P2-B：TEAP 读取现在持续记录已验证 WoW 客户区的 HWND、尺寸、DPI、窗口模式和显示器边界。窗口仅移动时，直接按相对客户区比例投影条带；不触发客户区重扫。
- 客户区缩放、全屏/无边框切换、分辨率、DPI、显示器或 HWND 变化时，先读取预测的窄 TEAP 条带；校验失败则立即且仅在当前 WoW 客户区内重新定位。重定位期间不产生有效帧，TEK 不会派发。
- 重新定位失败保留最后验证的相对布局并采用有界退避；不会退回默认固定桌面坐标，也不会扫描整个虚拟桌面。
- 新增状态窗口几何持久化：TEK 启动、托盘恢复和重新打开窗口时，恢复上次保存的大小与位置；已移除显示器导致的离屏位置会自动居中到当前虚拟桌面。
- 窗口大小与坐标写入现有设置 JSON，采用 350 ms 防抖，并在隐藏、关闭和退出时强制保存；保存失败不会影响 TEK 运行。
- 新增 P2-B 回归覆盖：纯窗口移动不重定位、尺寸/DPI/模式/显示器变化后的当前客户区重定位，以及状态窗口几何持久化与离屏回退。

# Tactic Echo 0.9.43 — P2-A locator compatibility hotfix

- 修复 P2-A 自动定位优先级回归：已提供前台 WoW HWND 时，运行期继续只扫描 WoW 客户区；未提供该 HWND 的显式 CLI、测试或兼容定位器则继续调用其 `locate_function`。
- 修复该兼容路径被通用校准矩形误劫持后退回固定布局的问题，恢复首次定位缓存、连续失败后的重新定位与指数退避回归契约。
- 本版仅修复 0.9.42 的构建阻断；不改变 P2-A 的条带截取、相对客户区布局、采样降频、状态写盘或 Trace 聚合策略。

# Tactic Echo 0.9.42 — P2-A 采样性能与写盘收敛

- UI 联动运行期首次定位、重定位和手动校准现在只扫描已验证 WoW 窗口的客户区；不再由运行链路扫描整个虚拟桌面。
- 首次获得有效 TEAP 条带后，TEK 保存其相对 WoW 客户区的比例坐标；正常运行按当前客户区投影条带位置，并仅截取 20 个色块所在的窄条带。
- `armed`、`manual_hold` 和 `blocked` 维持 50 ms 采样；插件 `paused / waiting` 或 WoW 非前台自动降至 200 ms。
- 前台校验分为读屏前完整进程验证，以及派发前 HWND/PID 轻量复核。
- `tek-status.json` 仅在生命周期、安全/插件状态、前台、错误变化时即时写盘；稳定运行使用 1 秒心跳。内存状态窗口仍按既有高频快照刷新。
- 默认 Trace 将成功 `input_sent` 聚合为 500 ms 桶，记录次数与最后动作/绑定；“完整 Trace 调试”选项可恢复逐条成功派发记录。
- 新增 P2-A 回归覆盖：条带截图边界、客户区相对布局投影、客户区定位路径、闲置降频、前台轻量复核、Trace 聚合/完整调试。

# Tactic Echo 0.9.41 — P1 派发状态机与安全门禁收敛

- 有效 paused / waiting / manual_hold / channeling / empowering 帧保持原始非派发语义，不被 catalog / binding 元数据异常误标为 blocked。
- 手动接管暂停查询去副作用；replay guard 仅由明确状态机推进清理。
- 限速器支持预占与回滚；未实际尝试 SendInput 的晚到门禁阻断不会消耗额度。
- sent=False 区分映射 blocked 与 SendInput 系统故障升级。
- 校准与采样布局原子交接。

# Tactic Echo 0.9.40 — P0 本地白名单收敛与运行可靠性

- 删除 TEK 运行期的 WoW `WTF`、`bindings-cache.wtf`、角色目录扫描和动态移动绑定依赖；本地“连发介入白名单”成为唯一人工接管豁免来源。
- 白名单禁止单独保存 `CTRL`、`ALT`、`SHIFT`、`WIN`；编辑页移除这些快捷添加项，录入修饰键时保持录入状态并等待实际主键。
- 设置导入可规范化旧版白名单元组/列表；无法可靠解析时保留当前有效白名单并提示，不再静默清空。
- 键盘 Hook 停止超时时保留 `Stopping` 状态并阻止重启，避免旧 Hook 尚存时创建第二个监听线程。
- `ErrorLocked` 恢复会重置故障计数、限速账本和接管恢复门禁；错误诊断记录不删除。
- 验证：359 项 Python 回归、两组 unittest、Python 编译、全部 AddOn Lua 语法和基线合同检查通过；Windows Hook / SendInput 仍待实机验收。

# Tactic Echo 0.9.39

- TEAP 常规刷新周期改为 **50 ms**，与 TEK 默认采样同步；人工接管释放后的两帧 freshness 等待约为 100 ms。
- UI 联动首次读取到满足协议、前台、Hook、绑定与 freshness 门禁的 `armed` 帧即可派发，不再要求人为执行“暂停→运行”，也不进入启动 replay guard。
- 本地白名单键的按下/松开不进入人工接管恢复状态机；非白名单键的 balanced 恢复策略调整为 **30 ms + 2 帧 freshness + 150 ms 同技能/同动作 replay guard**。
- TEAP `waiting` 不再隐藏 20 个色块；它持续输出可读的 waiting/disarmed 帧，TEK 将其识别为“插件未运行”而非信号丢失。
- 脱战策略明确为：手动启停（脱战保持 armed）、脱战暂停（脱战 paused、进战自动 armed）、脱战停止（脱战 paused、进战仍 paused，需手动 armed）。三种策略均保留可读 TEAP 色块。
- WoW 不在前台时状态明确显示“等待前台：WoW 未处于前台”。
- `tek-status.json` 使用唯一临时文件、有限重试与后台异常隔离；状态镜像写入失败不再允许退出 TEK worker。
- 验证：357 项 Python 回归测试通过。

# 0.9.38

- 修复 WoW 移动绑定自动发现：标准 Battle.net 安装的 WTF 数据位于 Windows 文档目录，TEK 现同时检查 Documents/OneDrive Documents 下的 World of Warcraft 产品目录，并仍只使用当前角色 TacticEcho.lua 同目录的 bindings-cache.wtf。

# Tactic Echo 0.9.38

- UI 联动启动不再要求人工执行一次“暂停→运行”状态转换；仍保留首次有效帧 bootstrap、freshness、前台、键盘 Hook、手动接管等门禁。
- 自动定位连续解码失败后不再降级覆盖为默认固定坐标；改为立即重新定位，并保留最后验证布局用于诊断。
- 从已选择的 TacticEcho.lua 自动定位移动键缓存时，优先当前角色目录的 bindings-cache.wtf，避免选择其他角色的较新缓存。

# 0.9.33 — Keyboard-hook reliability repair

- Fixed the Windows low-level keyboard-hook ABI: `GetModuleHandleW`, `SetWindowsHookExW`, `CallNextHookEx`, message-loop APIs and hook handles now use explicit pointer-safe ctypes signatures.
- Removed the unused low-level mouse hook from the SendInput readiness requirement. The approved policy ignores every mouse input, so only the keyboard hook is required; real SendInput remains fail-closed when that keyboard hook is unhealthy.
- Keyboard-hook installation now retries with a NULL-module low-level-hook fallback and records the native WinError in diagnostics when Windows refuses both attempts.
- Status diagnostics now distinguish keyboard-hook health from intentionally disabled mouse monitoring.
- Added regression coverage for keyboard-only hook health and pointer-width-safe module-handle fallback.

# 0.9.32 — Manual ownership gate and dynamic movement exemptions

- Rebased manual-input cooperation on the 0.9.28 full source baseline; no 0.9.30/0.9.31 fixed-WASD or short-window behavior is retained.
- Added a held-input ownership state machine: non-exempt physical keyboard keys block SendInput while held; only the final release begins recovery.
- Added recovery policies: aggressive (50 ms + 1 freshness frame + 300 ms replay guard), balanced (80 ms + 2 + 1000 ms), manual_first (250 ms + 2 + 1200 ms), and bounded custom settings.
- Added manualEpoch re-check immediately before dispatch and a same-token/action-sequence replay guard.
- Added fail-closed Windows SendInput behavior whenever either low-level Hook is unavailable, unhealthy, stopped, or failed to install.
- Added dynamic movement exemptions loaded from bindings-cache.wtf, including modifier combinations; absent/invalid binding metadata uses conservative keyboard takeover with no WASD fallback.
- Mouse buttons, wheels, drag, and movement are intentionally ignored by the manual-takeover policy.
- Added TEAP State code 7 `manual_hold` for AddOn-detectable in-game input/UI blocking; it is a hard TEK dispatch inhibit, not a replacement for physical keyboard tracking.
- Added read-only AddOn movement-binding diagnostics, a manual cache-file picker, detailed Hook/held-key/recovery status, and a resizable TEK window (450–900 px wide, 900–2000 px high).

# 0.9.28 — Cross-role cooldown identity consistency

- Unified primary, burst, interrupt, control, defense and mobility cards on the same canonical action-bar cooldown identity.
- Preserved action-slot, direct-slot and spell-equivalence metadata through AdvisoryPlanner, TacticalAdvisors and TacticalState.
- Eliminated spell-ID fallback divergence for transformed/override skills represented by the same visible action-bar button.

# 0.9.27 - Burst cooldown identity unification

- Canonicalise HUD cooldown tracking by direct action-bar slot when a base/override spell pair resolves to the same visible button.
- Share local cooldown and charge timers across equivalent SpellIDs, including burst window and injected follower cards.
- Keep cooldown swipe rendering independent from the numeric label source; diagnostics now label them separately.
- Preserve all changes as HUD presentation only.

## 0.9.38

- Redesigned the local dispatch-intervention page with a compact four-column layout.
- Added direct keyboard capture for adding whitelist keys and selected-key deletion.
- Added Tk key-symbol normalization for the record-key workflow.

## 0.9.51 P5.6.2 — ProtocolMonitor secret boolean hotfix

- Fixed `ProtocolMonitor` comparing the `notInterruptible` value returned by `UnitCastingInfo` / `UnitChannelInfo` directly. On current Retail clients this value can be secret, causing a taint error during the monitor poll.
- Target cast name, spell ID and interruptibility now pass through secret-safe scalar probes. Any protected value becomes unknown; tactical telemetry remains advisory-only and does not alter recommendation, TEAP or TEK input eligibility.
- Added a regression contract that rejects direct raw comparison of `notInterruptible`.

