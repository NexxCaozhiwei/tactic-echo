# 1.4.4 — HUD 冷却与充能真实性修复

- **冷却单位明确化**：`GetSpellBaseCooldown()` 的毫秒值只在 API 边界转换为秒；`C_Spell`、动作条、Tooltip 与 tracker 的秒制数值不再按大小猜测单位，修复奥术弹幕 `500ms` 被显示为 `500s`，并避免合法长 CD 被错误缩短。
- **全局冷却重同步**：`SPELL_UPDATE_COOLDOWN` 不再假定携带 SpellID；事件到达时只遍历当前活跃 tracker 计时，优先用可读实时快照替换静态/事件兜底，并在明确就绪且非 GCD 时清除错误计时。
- **真实充能限定**：只有 `maxCharges > 1` 才进入 IconState、HUD 标签、Tooltip 和充能边框；普通 CD 技能的 `1/1` 不再显示为充能，物品数量仍沿用独立 `itemCount`。
- **陈旧充能清理**：tracker 在当前等效技能身份明确返回非充能时清除旧多充能状态；受保护或未知返回继续保持未知，不会误清。该收紧同时阻止陈旧 `0/2`、`1/2` 进入 AutoBurst 可用性与确认判断。
- **行为回归**：新增毫秒/秒边界、无 CD 技能、全局实时校正、`1/1` 过滤、真实 `1/2` 保留和陈旧充能清理的 Lua 行为测试；未修改 BindingToken、TEAP v3、TEK、宏资格或自动注入顺序。
- **当前文档收口**：README、架构、测试、交接、任务和项目管理文档统一到 1.4.4；退役的 P4/P5 反应链测试及战术/环境专题移入 `docs/archive/`，历史内容保留但不再作为当前实现授权。

# 1.4.3 — 多组 HUD 投影与设置页紧凑布局

- **全部启用组可见**：HUD 不再只选择活动、命中或当前编辑组；现在按 `autoInjectionGroups.order` 展开全部已启用组，组内严格保持各自步骤顺序。
- **组序列分开展示**：HUD 预创建容量由单组九张扩展为三组共 27 张；横向爆发方向按组分行，纵向方向按组分列，组名继续显示在卡片标签与 Tooltip 中。
- **活动状态隔离**：全部组都可见，但只有当前唯一活动组获得 `ACTIVE` 投影；Coordinator、OrderedPlan、BindingToken、TEAP v3 与 TEK 派发路径均未改变。
- **组开关前置**：当前组启用/停用入口移动到“当前组基本设置”上方，配置不完整时仍由既有 readiness 校验拒绝启用。
- **压缩尾部空白**：自动注入页的饰品设置和滚动子页高度跟随当前组实际序列行数，移除固定九行之后的大段无效空白与 3200 像素滚动尾巴。

# 1.4.2 — 窗口 SpellID 输入与设置引导修复

- **修复无法输入**：设置页的 0.25 秒状态刷新不再反复用已保存值覆盖当前组的名称和窗口输入框；输入内容会一直保留到用户保存或切换技能组。
- **四步设置流程**：页面明确显示“设置窗口技能 → 添加注入技能 → 调整九步顺序 → 启用当前组”，启用入口移动到最后。
- **窗口字段说明**：窗口栏更名为“窗口技能 SpellID”，明确只填写数字而不是技能名称或按键，并说明只有官方推荐精确命中该技能才启动本组；支持 Enter 或“保存窗口技能”提交。
- **运行语义不变**：仍由唯一 Coordinator 与 AutoBurst OrderedPlan 执行；活动链期间其他窗口不会建立嵌套链，TEAP v3/TEK 协议不变。

# 1.4.1 — 自动注入组配置流程修正

- **先配置、后启用**：新增组默认关闭，可先填写任意窗口 SpellID、添加/启用注入或饰品并调整顺序；配置完整后再启用，不再用原始 `group_window_missing` 让用户猜测操作顺序。
- **明确中文校验**：设置页持续显示当前组是否缺少窗口、缺少可选步骤或存在跨组冲突，失败状态不会阻止继续编辑关闭中的组。
- **窗口身份收紧**：本组窗口不得再次作为本组注入；不同启用组仍禁止重复窗口和窗口进入对方注入链，普通注入技能仍可跨组复用。
- **运行架构不变**：各组平级，活动链期间出现其他组窗口只记录并忽略，不建立嵌套链；继续共享唯一 AutoBurst OrderedPlan、BindingToken → TEAP v3 → TEK 输入路径。

# 1.4.0 — 多技能组自动注入

- **AutoBurst 泛化为自动注入**：每个专精最多保存三个稳定 `groupId` 技能组；每组拥有独立名称、开关、`simple/focused` 模式、普通或爆发窗口、最多六个注入和饰品 13/14 九步顺序。
- **单一计划协调器**：新增 `AutoInjectionGroups` 与 `AutoInjectionCoordinator`；空闲时以 `windowSpellID → groupId` 索引精确匹配，活动时只把唯一组规则交给现有 OrderedPlan 执行器，没有复制状态机、事件、轮询或输入路径。
- **跨组隔离**：活动组锁定 `groupId`、窗口和组签名；其他组窗口只记录 `group_window_ignored_while_owner_active`，不抢占、不排队、不补发，必须经过新的离开/进入边沿才可启动。
- **迁移与冲突保护**：旧 `autoBurstEnabled`、`autoBurstMode` 和每专精 `autoBurstSequence` 幂等迁移到组 1；重复窗口、跨组窗口/注入级联、缺失窗口和无可选步骤均确定性 fail-closed。
- **设置页与 HUD 修复**：设置页可完整编辑九步和最多三个组；HUD 只显示活动、命中或当前选中组，并在首个有效快照立即显示，不再因初始 debounce 或短暂运行快照缺失隐藏整个注入序列。
- **输入协议不变**：继续复用 BindingToken → TEAP v3 20 字节 → TEK；`dispatchOrigin="burst"` 与 flags `0x20` 保持不变，没有增加 groupId 协议字段或第二派发器。

# 1.3.0 — AutoBurst 稳定基线

- **P1–P3 正式验收**：冻结已实机通过的爆发链锁定、GCD/队列窗口派发、失败回执隔离与安全重试、HUD 真实“派发/阻止”展示，以及当前主键 + AutoBurst 加载链路结构收口。
- **奥法爆发链稳定性**：后续步骤不会在 `GCD_LOCKED` 建立新逻辑尝试；进入公开 `QUEUE_WINDOW` 后才派发，精确失败后经过 observation-only 隔离并等待 `READY_NOW` 重试，避免奥术涌动在错误相位被跳过或提前释放锁链。
- **HUD 只展示执行结果**：内部校验、等待、确认与重试过程不再投影到 HUD；只有真实 Burst TEAP 帧携带有效 BindingToken 且允许派发时显示“派发”，硬阻止继续显示“阻止”。
- **序列与结构统一**：HUD 支持窗口 + 六注入 + 两饰品共九张卡；当前已加载的 Advisor/设置链删除退役规划器、Reaction/打断诊断、重复 `window/followups` 投影与孤儿 helper。
- **测试基线健康**：完整套件为 `654 passed, 7 skipped, 17 subtests passed`；七项跳过均为明确退役的自动打断候选派发历史契约，当前运行链无失败。

# 1.2.11 — P3 当前链路结构收口

- **删除已退役运行分支**：从已加载的 `TacticalAdvisors.lua` 移除无消费者的旧打断、控制、Reaction P3、候选预测与旧动作条展示 helper；周期刷新现在只保留主推荐与 AutoBurst 投影。
- **删除无入口设置诊断**：设置中心移除不会被四页导航调用的 ReactionBindings、自动打断和 P3 观察文本组装代码；历史页面参数仍只重定向到当前页面，不恢复退役功能。
- **爆发 HUD 单一数据形态**：`AutoBurst:BuildHudSnapshot()` 只输出按保存顺序排列的 `items`，不再重复维护无人读取的 `window/followups` 副视图。
- **移除孤儿 helper**：清除 AutoBurst、设置中心内没有调用者的历史函数；新增结构契约，持续阻止当前加载链重新引入退役规划器、重复爆发视图或仅定义不使用的局部 helper。
- **运行行为不变**：P1 锁链/GCD/队列窗口派发与 P2 HUD“真实派发/硬阻止”语义不变；未修改 BindingToken、TEAP、TEK、宏资格或脱战门控。

# 1.2.10 — AutoBurst HUD 派发态与测试契约收口

- **HUD 只呈现真实派发**：移除 AutoBurst 内部校验、等待、重试等过程态的 HUD 投影；只有当前 TEAP 帧确实携带 Burst 来源、有效 BindingToken 且允许派发时，对应爆发卡才显示“派发”。硬阻止状态继续沿用既有阻止语义。
- **展示层不获得派发权限**：`TacticalState` 只透传当前派发动作类型、技能、饰品槽位与 ItemID；爆发 HUD 卡仍固定 `bindingToken=0`、`displayOnly=true`，不会反向改变 AutoBurst、TEAP 或 TEK。
- **序列容量统一为 9**：HUD 与数据模型统一支持一个窗口、最多六个注入和两个饰品，消除运行投影仍截断为五张卡的旧限制。
- **当前范围测试债清零**：将 40 个检查退役独立爆发、打断、控制、防御、生存、候选历史等旧结构的失败契约改写为当前“主键 + AutoBurst”边界；宏运行测试可使用本机 `lua`，Windows SimC 启动脚本恢复 ASCII/CRLF。
- **完整回归结果**：`652 passed, 7 skipped, 17 subtests passed`；七项跳过均为明确退役的自动打断候选派发历史契约，不是当前运行链失败。未修改 `AGENTS.md`。

# 1.2.9 — AutoBurst Retail upvalue 热修

- **修复 P1 实机加载失败**：`1.2.8` 新增的两个派发阶段 helper 不再作为 `Evaluate()` 的局部 upvalue，改由 `AutoBurst` 方法提供，消除 Retail 报告的 `function ... has more than 60 upvalues`。
- **P1 行为保持不变**：首步骤仍等待 `READY_NOW`，后续步骤仍在 `GCD_LOCKED` 输出无 Token hold、于 `QUEUE_WINDOW` 首次派发，精确失败后仍只在 `READY_NOW` 创建新逻辑重试。
- **回归契约补强**：测试明确要求新增派发阶段 helper 使用模块方法，避免未来再次把大型 `Evaluate()` 推过 Retail upvalue 上限。

# 1.2.8 — AutoBurst 队列窗口派发稳定性

- **禁止 GCD 锁定期建立新尝试**：锁定爆发链后，首个实际步骤等待 `READY_NOW`；后续受 GCD 影响的步骤在 `GCD_LOCKED` 只保留当前步骤所有权并输出无 Token hold，进入 `QUEUE_WINDOW` 或 `READY_NOW` 后才创建新的逻辑派发。
- **失败重试收紧到完整就绪**：队列窗口派发收到精确失败后，继续执行两帧 observation-only 回执隔离；隔离结束后不在同一 `QUEUE_WINDOW` 重试，只在 `READY_NOW` 创建第二次逻辑尝试。
- **尝试身份与确认保持稳定**：GCD 等待、队列等待、确认等待和隔离帧均不增加 `dispatchAttempt`；`WAIT_CONFIRM` 下的 `GCD_LOCKED` 不再重复发布 BindingToken，步骤仍只由精确成功事件、稳定自身非 GCD 冷却或充能减少推进。
- **奥法专项回归**：新增 `镜像 → 奥术涌动` 行为测试，覆盖 GCD 锁定保持、队列窗口首次派发、精确失败去重与 `READY_NOW` 安全重试。

# 1.2.7 — AutoBurst 失败重试队列窗口同步

- **保留 1.2.0 锁链语义**：计划建立后继续由 `plan.stepIndex` / `WAIT_CONFIRM` 锁定当前步骤；官方推荐旋转、单个失败事件和 GCD 状态均不会越过当前技能或重排爆发链。
- **失败回执按逻辑尝试去重**：同一次逻辑派发产生的多个 `UNIT_SPELLCAST_FAILED`、`UNIT_SPELLCAST_FAILED_QUIET` 或 `UNIT_SPELLCAST_INTERRUPTED` 只计为一次拒绝；第二次拒绝必须来自经过 observation-only 隔离后的新 `dispatchAttempt`。
- **重试等待公开队列窗口**：首次候选仍沿用共享 `GCD_LOCKED` 连续投递策略；若客户端已经精确拒绝该逻辑尝试，两帧回执隔离后继续输出 `BindingToken=0`，直到 `GCDGate` 进入 `QUEUE_WINDOW` 或 `READY_NOW` 才创建第二次逻辑尝试，避免奥术涌动等技能在 GCD 锁定期连续失败后被错误跳过。
- **诊断补强**：新增失败重试屏障、GCD 等待与安全重试阶段日志，并导出失败观察阶段和重试阶段纯标量；不改变 BindingToken、TEAP、TEK、宏资格、脱战硬门控或成功确认边界。

# 1.2.6 — AutoBurst 稳定确认与六注入序列

- **阻止瞬发技能预测性误跳过**：可选步骤进入 `WAIT_CONFIRM` 后，单帧自身冷却、冷却来源不确定或 UNKNOWN 不再清空确认上下文；自身 CD/充能变化继续走稳定确认，公开 GCD 可派发时保持同一步候选。
- **资源判断改为稳定证据**：资源不足必须跨两个不同共享业务快照持续成立才可跳过；普通读条、引导、蓄力、`GCD_LOCKED` 与 `QUEUE_WINDOW` 期间延后资源结论，噬灭虚空变形的 `usable=false/false` 兼容不再把普通施法不可用误判为资源不足。
- **连续失败有界释放**：当前等待步骤收到两个精确匹配的 `UNIT_SPELLCAST_FAILED`、`UNIT_SPELLCAST_FAILED_QUIET` 或 `UNIT_SPELLCAST_INTERRUPTED` 后，简易模式跳过当前可选步骤并继续，窗口步骤释放给普通官方路径，避免永久卡链；单个失败仍不会推进序列。
- **注入技能扩展到 6 个**：每专精取已启用的前六项注入技能，默认排序、稳定身份存储、设置页和 AutoBurst 执行链同步扩展；HUD 爆发队列上限调整为窗口 + 六注入 + 两饰品，共 9 张卡。

# 1.2.5 — AutoBurst 已确认窗口冷却重入隔离

- **修复冰 DK 重复窗口卡爆发**：窗口步骤完成可信确认后，在同一战斗内保留精确 SpellID、计划与窗口代次收据；官方推荐短暂离开又返回同一窗口、且实时采样仍为自身冷却时，不再创建第二轮爆发计划。
- **阻止前置注入重放与无效连按**：重复冷却窗口会锁定当前代次并输出 observation-only hold，避免重新执行前置注入，也避免对仍在冷却的窗口技能持续发布 Burst BindingToken。
- **正常下一轮不受影响**：抑制仅要求同一战斗、同一已确认窗口 SpellID 与实时自身冷却同时成立；窗口真正离开且后续采样恢复可派发后，仍可正常建立下一轮计划。
- **诊断补强**：新增 `confirmed_window_reentry_suppressed`、`confirmed_window_reentry_on_cooldown` 及最近已确认窗口的 SpellID、planId、generation、confirmation 摘要；不保存原始冷却值或其他受保护数据。

# 1.2.4 — AutoBurst 预测性充能回滚隔离

- **修复圣洁鸣钟伪成功卡住**：spell 步骤的充能下降或自身 CD 开始不再以单帧采样立即完成；必须跨越短稳定窗口并至少再次观察到相同证据，避免 Retail 在 GCD 队列失败前预测性扣除充能、随后回滚时误进入 `await_window_departure`。
- **失败事件参与确认隔离**：当前 `WAIT_CONFIRM` 步骤的精确 `UNIT_SPELLCAST_FAILED` / `UNIT_SPELLCAST_FAILED_QUIET` 会清除暂定充能/CD 证据并立即请求重评，同一步骤继续经原有 TEAP/TEK 节奏重试，不把失败当成功或计划中止。
- **既有边界保持**：精确 `UNIT_SPELLCAST_SUCCEEDED` 仍立即确认；饰品锁定槽位/ItemID 的自身 CD 确认、GCD 队列派发、BindingToken、TEAP v3、TEK 门禁与宏资格均未改变。

# 1.2.3 — AutoBurst 迟到确认隔离

- **修复奥法大法师之触卡住**：可选前置注入在等待确认阶段因资源不足被跳过时，原子清除该步骤的 `WAIT_CONFIRM`、冻结绑定和候选上下文；迟到的奥术涌动成功事件不再误确认下一步大法师之触。
- **确认身份加固**：接收 `UNIT_SPELLCAST_SUCCEEDED` 前复核 `plan.wait.expectedSpellID` 与当前步骤 SpellID；上下文不一致时拒绝事件并记录安全诊断，不改变等效/覆盖 SpellID 的既有确认能力。
- **跨专精竞态收口**：修复适用于所有“可选步骤运行期跳过后进入下一步骤”的序列，并新增奥法 `奥术涌动 → 大法师之触` 迟到事件行为回归。

# 1.2.2 — HUD 设置中心打开修复

- **修复设置中心创建失败**：补回标签颜色选择器所需的 `createColorChoice` 控件；1.2.1 中打开 HUD 设置页会调用未定义函数并中断，现已恢复可打开和颜色选择。

# 1.2.1 — HUD 标签样式设置恢复

- **HUD 标签样式恢复**：HUD 页重新提供主键与自动爆发卡的快捷键、充能/可用次数、CD 秒数与状态文字样式编辑；每类文字均可独立设置显示、字体、字号、缩放、锚点、颜色和横/纵偏移。
- **仅视觉层**：样式设置只写入既有 HUD module text-style 字段；不改变官方推荐、AutoBurst、动作条绑定、BindingToken、TEAP 或 TEK。

# 1.2.0 — TEUI 精简与 AutoBurst 稳定基线

- **正式基线晋升**：将已完成实机回归的 TEUI 四页精简、HUD 真实 AutoBurst 序列、自动爆发独立快捷键与 `HAD` / `LCC` 状态码统一冻结为 1.2.0。
- **噬灭 DH 行为冻结**：保留 `根除（1225826）→ 虚空变形（1217605）` 默认顺序，以及根除确认后的资源重新采样、GCD 等待和跨周期不足/UNKNOWN 释放规则。
- **安全边界不变**：官方推荐、BindingToken、TEAP v3、TEK 门禁、脱战硬门控、共享宏资格、HUD 战斗保护和自动打断硬暂停继续沿用 1.1.7 已验证行为。
- **交付基线更新**：新增 `docs/baselines/BASELINE_1.2.0.md`，并同步根版本、TOC、Bootstrap、文档索引与仓库开发基线声明。

# 1.1.7 — HUD 容器可见性战斗保护收口
- **TEUI 四页精简**：设置中心只保留“常规、HUD、自动爆发、配置文件”四个入口；独立主键页并入 HUD，退役功能页、调试监控内容、旧爆发子页与冗长运行诊断不再展示。旧 `/teui` 页面参数仍安全重定向到现有页面，不恢复退役功能。
- **HUD 显示设置单一化**：以“主键 + 自动爆发 / 仅主键”作为唯一内容选择，规范化时清除旧 compact、候选历史、来源标签及互相冲突的模块显隐状态；尺寸、排列、透明度、按键/状态标签、纯秒冷却与布局重置等实用选项继续保留。
- **HUD 展示真实爆发序列**：爆发栏直接读取当前专精保存的 `autoBurstSequence`，按启用后的实际顺序展示窗口、最多三个注入和饰品步骤，最多五张卡；删除只服务旧窗口辅助/候选提示的 `BurstStateMachine` 和职业冷却、药水、种族技能等候选拼装，不改变 AutoBurst 计划创建、BindingToken、TEAP 或 TEK 派发链路。
- **配置自动切换折叠**：配置文件的保存、载入、复制、重命名、删除和重置继续直接可用；全局、角色、职业、专精范围映射完整保留，并默认折叠到“高级设置”。
- **自动爆发独立快捷键**：在整体启停快捷键下方新增独立的“自动爆发开关快捷键”，沿用 ControlPanel 的覆盖绑定与战斗中延迟应用机制；快捷键只切换 `tactics.autoBurstEnabled`，与整体启停快捷键冲突时拒绝保存，不改变官方推荐、BindingToken、TEAP 或 TEK。
- **可派发状态区分**：自动派发处于可派发状态时，自动爆发关闭显示 `LCC`，自动爆发开启显示 `HAD`；暂停、待命、阻断、施法/引导等既有状态保持不变，HUD 主键按钮仍显示原有“可用”语义。
- **根除后的虚空变形资源复核**：噬灭默认 `根除 → 虚空变形` 序列不再用根除释放前的资源布尔值排除后置注入；初始预检在绑定、BindingToken 与自身 CD 合格时记录 `resourceCheckDeferred` 并保留该步骤。根除获得精确确认后进入 `POST_WINDOW_RESOURCE_SETTLING`：共享 GCD 锁定期间只观察，新的公开可用性布尔值明确可用时立即在同一轮爆发派发；持续不可用或 UNKNOWN 必须由两个不同 `RuntimeSnapshot.cycleId` 的非 GCD 锁定样本确认后才跳过，重复评估同一快照不得重复计数。该规则仅限 `DEMONHUNTER_3` 的后置 `1217605`，前置注入、其他技能与其他专精保持原预检规则，不读取具体资源数值，也不改变 BindingToken、TEAP 或 TEK。

- **噬灭资源不足不再卡校验**：用户明确授权对已验证动作栏来源且具有真实 BindingToken 的可选注入步骤读取公开可用性布尔值。共享快照优先按精确 SpellID 调用 `C_Spell.IsSpellUsable()`，并保留 `IsUsableAction` 动作槽兼容回退；资源判定提前到冷却 UNKNOWN 继续派发分支之前。普通注入仍只在明确 `usable=false` 且 `notEnoughResource=true` 时跳过；针对 `DEMONHUNTER_3` 的 `1217605`（虚空变形），兼容 Retail 对光环型噬灭特殊资源只返回 `usable=false`、却不设置通用 `insufficientPower` 的实机形态。该精确专精/技能例外同样只作用于可选注入：`simple` 在首次派发前或等待确认时跳过并继续，`focused` 不创建或释放计划；窗口步骤、其他专精/技能、UNKNOWN、具体资源数值、BindingToken、TEAP 与 TEK 均不受影响。
- **噬灭恶魔猎手爆发默认值**：新增 `DEMONHUNTER_3` / SpecID `1480` 显式爆发资料，以 `1225826`（根除）作为默认窗口技能、`1217605`（虚空变形）作为默认第一注入技能，默认执行顺序固定为 `根除 → 虚空变形`，并继续允许添加当前专精已学会的自定义触发与注入 SpellID；已有用户自定义排序不被覆盖。
- **纯自定义爆发资料解锁**：`noSeedNotice` 改为检查合并后的有效专精列表，而非只检查内置参考种子；神圣骑、治疗牧等无内置种子的已注册专精，在添加自定义技能后可正常生成 AutoBurst sequence。
- **全专精覆盖审计**：契约测试逐项校验 13 个职业共 40 个现行战斗专精的 class、specIndex 与 specID，并新增噬灭默认序列、额外自定义技能和既有空种子治疗专精的行为回归。
- **HUD 拖动保护补回**：主卡和 HUD 抓手统一经 `beginContainerMove()` / `finishContainerMove()`；战斗锁定期间只记录阻断状态，不再直接调用容器 `StartMoving()` / `StopMovingOrSizing()`。
- **退役 HUD 对象收口**：HUD 初始化不再创建候选历史、打断、控制、位移与防御图标按钮，只保留主键和最多 5 个 AutoBurst 卡；布局指纹也只跟踪当前产品范围内的节点。
- **Signal 诊断降频**：TEAP 20Hz 新鲜度、sequence 和像素绘制保持不变；SavedVariables 历史改为语义变化即时记录、稳定派发状态每 0.5 秒记录一次，避免逐帧分配和队列头移除。
- **AutoBurst 日志合并**：`window_queue_delivery_continues` 与 `gcd_locked_delivery_continues` 每个计划步骤最多每 0.5 秒记录一次，并退出关键生命周期环；计划创建、预检、派发、确认、中止和完成事件仍完整保留。
- **HUD 配置读取去重**：`TacticalAdvisors` 每次刷新只调用一次 `Config.Normalize:All()`，同时取得 tactical 与 HUD 设置，避免永久 watcher 对同一配置重复规范化。
- **AutoBurst 窗口确认防卡死**：当前窗口步骤已派发、官方推荐已离开且确认宽限期结束后，若客户端仍未提供匹配的成功事件或可信自身 CD/充能变化，则以 `window_confirmation_unobserved_released` 安全释放计划；该路径不把超时记为成功，也不推进后续步骤。
- **覆盖技能事件确认补强**：`UNIT_SPELLCAST_SUCCEEDED` 除冻结绑定中的等效 SpellID 外，还会对当前等待步骤重新读取 Resolver 的有界基础/覆盖等效集合，兼容派发后才发生的 Retail replacement/override 身份变化。
- **HUD CD 时间一致性**：HUD 数字优先锚定安全的 `cooldownStart + cooldownDuration`；只有 remaining 的业务快照重复绘制时不再用新的 `GetTime` 延后到期点，避免 HUD 倒计时慢于 Blizzard 动作条。
- **主键/窗口纯 GCD 隐藏**：恢复 1.0.45 冷却展示边界，主键、Burst-window 与物品卡不绘制 `61304`/纯共享 GCD 转盘或数字；已确认的自身 CD 仍正常显示。

- **容器可见性保护**：`TacticalBoard` 在战斗中不再对 `TacticEchoTacticalBoard`、`TacticEchoDefenseBoard` 或状态文本调用 `SetShown`、`Show`、`Hide`，避免 `ADDON_ACTION_BLOCKED TacticEchoDefenseBoard:SetShown()`。
- **延迟可见性语义固化**：战斗中的 HUD 容器可见性变化只记录 `tacticEchoCombatShownPending`；脱战后再真实显示或隐藏。
- **输入边界不变**：不新增输入通道，不修改 TEK 派发逻辑；自动打断继续硬暂停，AutoBurst 脱战硬门控、共享宏资格和 HUD `manual_hold` 规则保持不变。

# 1.1.6 — HUD 容器缩放与布局战斗保护收口

- **容器缩放保护**：`TacticalBoard` 在战斗中不再对 `TacticEchoTacticalBoard` 或 defense 容器调用 `SetScale` / `SetAlpha`，避免 HUD 容器进入保护链后触发 `ADDON_ACTION_BLOCKED TacticEchoTacticalBoard:SetScale()`。
- **布局变更延迟**：`TacticalHudLayout` 在战斗中发现布局指纹变化时只记录 `tacticEchoLayoutDirty` / `tacticEchoPendingLayoutFingerprint`，不执行 `SetScale`、`SetPoint`、`SetSize`、`SetShown` 等布局变更；脱战后再应用。
- **输入边界不变**：不新增输入通道，不修改 TEK 派发逻辑；自动打断继续硬暂停，AutoBurst 脱战硬门控、共享宏资格和 HUD `manual_hold` 规则保持不变。

# 1.1.5 — HUD 点击路由战斗保护收口

- **点击层保护调用收口**：`HudClickRouter` 在战斗中不再对 secure proxy 或 blocker 调用 `SetAlpha`、`Show`、`Hide`，避免 `ADDON_ACTION_BLOCKED UNKNOWN()` 从 HUD 点击路由栈触发。
- **延迟刷新语义固化**：战斗中的 proxy/blocker 可见性变化只记录 `tacticEchoCombatVisibilityPending` 与 `dirty`；脱战后再真实隐藏、显示或重建。
- **输入边界不变**：不新增输入通道，不修改 TEK 派发逻辑；自动打断继续硬暂停，AutoBurst 脱战硬门控、共享宏资格和 HUD `manual_hold` 规则保持不变。

# 1.1.4 — HUD Button 战斗保护收口

- **保护调用再收口**：战斗中 HUD 卡片可见性变更不再调用卡片 Button 的 `SetAlpha`、`EnableMouse`、`Show` 或 `Hide`，只记录待处理状态，避免 `ADDON_ACTION_BLOCKED UNKNOWN()`。
- **点击层边界不变**：HUD secure proxy 仍由 blocker fail-closed 覆盖；脱战后再真实隐藏或重建。

# 1.1.3 — HUD 战斗中安全隐藏

- **保护调用修复**：HUD 卡片隐藏路径不再在战斗中直接调用 `Button:Hide()`，改为透明化并禁用卡片鼠标输入，避免 `ADDON_ACTION_BLOCKED`。
- **secure proxy fail-closed**：HUD 手动点击路由在战斗中不隐藏 `SecureActionButtonTemplate`，而是用非 secure blocker 覆盖旧 proxy，防止旧映射被误点。
- **输入边界不变**：TEK 白名单与修饰键手动接管规则保持 1.1.2 行为；自动打断继续硬暂停，AutoBurst 脱战硬门控不变。

# 1.1.2 — TEK 修饰键手动接管

- **白名单边界保持**：TEK 本地连发介入白名单继续只豁免配置中的主键，默认 `W/A/S/D/SPACE` 不进入手动让步。
- **修饰键持续让步**：`Ctrl`、`Alt`、`Shift` 等不能单独加入白名单的真实修饰键，现在按下即进入 `manual_input_held`，直到抬起后再进入既有 release delay、freshness 与 replay guard。
- **组合键误触收口**：避免玩家按住 `Alt/Ctrl/Shift` 时，TEK 在修饰键仍按下期间派发主键并被客户端解释成组合键。

# 1.1.1 — 自动启停待命状态

- **策略命名收口**：默认 `pause_out_of_combat` 策略对外从“脱战暂停”改为“自动启停”，设置页、策略说明与命令入口同步更新。
- **待命状态展示**：自动启停下因未进战斗或脱战产生的底层 `paused` 安全帧使用 `out_of_combat_auto_standby` 原因码，并在 HUD/紧凑条/设置中心显示为“待命”，区别于手动暂停和脱战停止。
- **协议边界不变**：TEAP/TEK 仍使用既有 `paused` 非派发状态，不新增输入通道；AutoBurst 脱战硬门控与自动打断硬暂停不变。

# 1.1.0 — 审计基线、自动打断硬暂停与共享宏资格冻结

- **基线升级**：将当前开发基线提升为 `1.1.0`，同步 `VERSION`、TOC、`Core/Bootstrap.lua`、`AGENTS.md`、`README.md` 与 `docs/baselines/BASELINE_1.1.0.md`。
- **代码审计结论固化**：`AutoReaction`、Defaults 与 Normalize 均保持 `auto_interrupt_suspended`，生产运行时不会生成 reaction candidate、BindingToken、TEAP reaction 帧或 TEK 自动打断请求。
- **共享宏资格继续冻结**：AutoBurst、Reaction、控制、防御与生存继续统一经 `ActionBarBindingResolver:IsVerifiedCurrentMacroSource()`；AutoBurst 额外经 `IsAutoBurstMacroEligible()`。宏名、图标、宏列表存在和未知正文仍不得授权当前动作栏身份。
- **交付文档归档收口**：所有 `PATCH_MANIFEST*` 统一归档到 `docs/patch-manifests/`，根目录和 `docs/` 根层不再保留重复清单；验证脚本同步阻止新的错位 patch manifest。
- **运行边界不变**：AutoBurst 脱战硬门控、HUD/原生动作条 `manual_hold` 人工优先、DurationObject 仅视觉转盘、HUD 徽标纯秒数、P4 target-only action-info 例外隔离均保持不变。

# 1.0.56 P5.11 — 宏资格统一、控制诊断收口与 HUD 手动来源一致性

- **统一宏资格入口**：`ActionBarBindingResolver` 新增并作为唯一判定口使用 `IsVerifiedCurrentMacroSource()` 与 `IsAutoBurstMacroEligible()`。AutoBurst、P4 Reaction 常规解析、控制、防御与生存 HUD 展示均不再各自复制或放宽 macro identity 逻辑。
- **保持宽松语义、先证明当前身份**：当前可见默认动作条上已经验证身份的 `/cast`、`/use`、条件分支、`@focus`、`@mouseover`、`@cursor`、目标管理辅助命令和 `/castsequence` 继续允许作为既有宏语义；控制、防御、生存仅作 `bindingToken=0` 的 HUD 手动复用，不进入 TEAP/TEK、自动控制、防御或生存。`/use item:ID`、ItemID 和本地化物品名仍由正文语义精确关联。
- **P4 例外仍隔离**：`action_info_represented_spell` / `action_info_macro_spell` 正文不可读兼容只保留 target-only reaction transport，仍要求当前真实 BindingToken；不能成为 HUD 手动来源，也不能获得 AutoBurst 资格。
- **修复控制诊断污染**：`ResolveSpell()` 只显示与请求 SpellID 有明确 action-info / macro-spell 证据的宏诊断；同一有效 numeric macro index 的当前按钮在其动作条文本可见命名请求技能时，可保留同槽位“正文暂不可读”诊断，但绝不恢复、扫描或替代其它 index。`BUTTON3` 的“坐骑”等无关宏不会再出现在胁迫、冰冻陷阱等控制卡的未匹配候选中。
- **回归覆盖**：新增共享宏资格、`[@cursor] 冰冻陷阱`、`/use item:5512`、P4 opaque 排除与无关坐骑宏过滤测试。
- **不变边界**：不改宏、不改目标、不新建按键、不程序化点击；自动打断继续硬暂停，AutoBurst 继续战斗内硬门控，HUD CD/转盘/标签/排序与 `manual_hold` 人工优先不变。

# 1.0.55 P5.10 — 当前动作栏宏身份收口与冰冻陷阱 HUD 精确锚定

- **修复 `CTRL+1` 冰冻陷阱宏未识别**：当当前可见动作条宏的 `GetActionInfo(...).id` 是代表 SpellID、`GetActionText()` 仅显示“冰冻陷阱”、而 action-info handle 可只读提供实际宏名时，Resolver 现在将两种允许的标签作为同一次受限 join 的候选。只有当前宏列表中唯一一枚、正文语义明确引用 `冰冻陷阱` 的宏才可恢复；HUD 固定复用该当前 `CTRL+1` 原按钮。
- **严格宏身份规则落地**：有效 numeric macro index 仅允许对同一 index 有界读取；该读取失败时不再扫描其他宏。非 index 的 Retail 形态只允许使用 `GetActionText` 或 action-info handle 的只读名称、代表 SpellID 和唯一正文语义共同确认。`GetMacroSpell`/代表 SpellID 只能辅助诊断，不能单独让正文恢复通过。
- **歧义与失配 fail-closed**：多个不同标签或同名同技能候选同时存活时返回 `macro_semantic_identity_ambiguous`；宏正文不引用请求技能时返回 `macro_semantic_identity_no_spell_match`。不调用 `GetMacroInfo(name)`，不按名称取第一枚，不将宏正文持久化。
- **HUD 点击精确来源进一步收紧**：HUD 卡除 `buttonName + actionSlot` 外，还复核当前来源类型、macroID 与只读语义身份；原栏位被同技能直放、另一枚同技能宏或不同语义宏替换时一律 `manual_actionbar_source_changed`，不会跳转到 `CTRL+2` 或其他同技能槽位。
- **P4 例外保持孤立**：`action_info_represented_spell` / `action_info_macro_spell` 的正文不可读兼容只保留给 P4 reaction 的 target-only transport，且必须已有真实 BindingToken。它不能成为控制、防御、生存 HUD 的宏来源，不能推断 focus/mouseover/cursor 分支，也不能授权 AutoBurst。
- **不变边界**：自动打断继续硬暂停；脱战 AutoBurst 硬门控、主键启停、CD/DurationObject、标签、排序、TEAP/TEK 和用户已有宏文本/目标语义均不改变。

# 1.0.54 P5.9 — 控制、防御与生存宏兼容统一

- **控制/防御宏不再被上层降级**：控制与防御卡现在保留 Resolver 已确认的 `actionBarStateTrusted`、当前动作条槽位与宏语义身份；`@focus`、`@mouseover`、`@cursor`、条件分支、辅助命令、目标管理和 `/castsequence` 等既有宽松关联形态，均继续由现有宏解析器识别为当前可见玩家宏的来源。无键位或不受 TEK 支持的既有宏仍可显示并由 HUD 真实鼠标点击复用，但 BindingToken 固定为 0，绝不进入 TEAP/TEK 派发。
- **生存消耗品支持已有 `/use` 宏**：`ResolveItem` 新增与 `ResolveSpell` 同级的语义关联，可识别 `/use <ItemID>`、`/use item:<ItemID>`、本地化物品名、条件分支、多物品分支及 `/castsequence` 中的既有物品引用；仍仅接受当前可见 Blizzard 默认动作条上的唯一已解析宏按钮，不按宏名/图标/宏列表猜测来源。
- **HUD 兼容**：无标准快捷键但动作条来源可靠的控制、防御、生存卡可继续显示，并允许 secure proxy 复用同一真实按钮；宏的目标、条件、分支和原本行为完全由玩家既有宏执行。找不到可靠来源时保持卡片显示并 fail-closed。
- **不变边界**：不创建按键、不改写或替换宏、不切换目标、不新增输入通道；控制、防御、生存仍是只读/手动 HUD 入口，自动打断继续硬暂停，TEAP/TEK、爆发排序、CD 数字和 DurationObject 转盘不变。

# 1.0.53 P5.8 — HUD 点击修复、脱战爆发硬门控与基线归档规范

- **修复脱战爆发派发**：删除 `pre-combat bridge` 的运行时授权。`AutoBurst` 在任何脱战帧先清除旧 plan/capture 并返回空结果；不会创建 Burst candidate、写入 Burst TEAP 帧或交给 TEK。`Run` 重新启动和切图后均不能恢复脱战起手派发。
- **修复 HUD 非主键点击**：secure proxy 同时接收 `LeftButtonDown` / `LeftButtonUp`，兼容 `ActionButtonUseKeyDown`；代理和 fail-closed blocker 提升到 `HIGH` 输入层，确保真实 HUD 左键能先取得 `manual_hold`，再由既有动作条按钮执行原始动作。
- **精确复用饰品来源**：13/14 槽 HUD 卡先解析对应装备槽位的现有动作条按钮或已识别 `/use 13|14` 宏，避免同物品/共享效果的错误来源。
- **保持边界**：不新建快捷键、不改写宏、不替换目标、不创建 spell/item 动作；主键启停、CD/转盘、标签、技能排序和既有宏兼容策略不变。
- **文档规范**：所有版本基线移入 `docs/baselines/`；新增交付规则，版本化源码改动必须同步更新 baseline 与 `CHANGELOG.md`。

# 1.0.52 P5.7 — HUD 手动点击与自动打断暂停

- 自动打断改为全局暂停：默认、SavedVariables 规范化与运行时均强制 `auto_interrupt_suspended`；保留只读打断观察/高亮。
- 主 HUD 左键复用原 `ToggleRun()`；爆发、打断、控制、防御/生存 HUD 卡片可安全代理现有可见默认动作条按钮或已识别宏。
- 无可靠来源、特殊动作条、按钮不可见及战斗中映射变化均 fail-closed；HUD 保持显示并给出原因。
- HUD/原生动作条鼠标左键触发既有 `manual_hold`，清空派发动作码与 BindingToken，人工点击优先于 TEAP/TEK 派发。
- 不改写 AutoBurst 顺序、CD/转盘/标签/排序、现有宏或 TEK。

# 1.0.51 P5.6 — API/事件确认打断资格，修复 `false` 证据丢失

- **修复直接 API false 丢失**：`ReactionObservation` 不再用 Lua `and/or` 处理 `notInterruptible`，避免合法 `false` 被折成 `nil`。当前 API `notInterruptible=false` 会正确产出 `directInterruptibilityKnown=true` 与 `interruptible=true`。
- **收紧自动派发资格**：P4.3 transport 只在 `unit_api_confirmed` 或 `unit_event_interruptible_confirmed` 后派发；`interruptibility_unknown` 仅观察，不再生成 `compat_interrupt_candidate`。
- **钢条硬阻断**：`notInterruptible=true`、`UNIT_SPELLCAST_NOT_INTERRUPTIBLE` 和真实可见盾继续零 Token 阻断。
- **CD 门控保持**：实际打断动作条按钮存在已知非 GCD 自身 CD 时，返回 `interrupt_action_cooldown`，不占主键。
- **宏兼容未改动**：P5.5 的当前动作栏 `action_info_represented_spell` / `action_info_macro_spell` target-only transport 保持。

# 1.0.50 P5.5 — 双 action-info 宏身份兼容，恢复 P4.3 target transport

- **修复 P5.4 的实际 API 形态遗漏**：P5.4 只接受 `action_info_represented_spell`，但现场当前可见反制射击宏被 Resolver 匹配为 `action_info_macro_spell`。P5.5 将两种精确 action-info 身份同等作为正文不可读时的 target-only compatibility transport。
- **以当前动作栏按钮为唯一事实**：路由仍要求当前可见宏按钮、当前请求的打断 SpellID、真实 BindingToken 和正文不可读状态；不读取其他宏、不会按宏名恢复正文、不会把宏列表存在的任何宏推断为当前绑定。
- **钢条/CD 门控不变**：3 次共享观察、0.40 秒钢条稳定、硬钢条否决和实际 action slot 的非 GCD 自身 CD 门控均保留。CD 中仍为 `interrupt_action_cooldown`，不得占 reaction 主键。
- **宏兼容性**：本版只恢复 P4.3 已验证的当前 target transport，未收紧、删除或改写任何现有宏；不会通过该 opaque 路由猜测 focus/mouseover。

# 1.0.49 P5.4 — P4.3 当前动作栏路由恢复、钢条稳定与冷却门控收口

- **恢复 P4.3 已验证动作链的实际动作栏路由**：当当前可见默认动作栏按钮是宏、`GetActionInfo` 返回所请求打断技能的代表 SpellID、且按钮已有真实绑定，但 Retail 不提供宏正文/有效宏索引时，P2 以“实际按钮 + 代表 SpellID + BindingToken”建立 `target` 专用 `action_info_represented_spell_compat` 路由。不会按宏名查找、不会从宏列表存在某种形态推断当前绑定，也不会推断 focus/mouseover 分支。
- **钢条稳定窗口**：兼容未确认读条继续要求同一 `castKey` 的 3 次不同观察；额外要求至少 0.40 秒稳定等待，并在候选前再次检查事件缓存。API 明确不可打断、真实可见盾、`NOT_INTERRUPTIBLE`、原生明确不可打断和 native scalar/method 钢条嫌疑继续零 Token 硬拦截。
- **冷却不占主键**：对 TEK 将实际按下的 action slot 保留精确只读 CD 门控。已知非 GCD 自身 CD 且无可用 charges 时记录 `interrupt_action_cooldown`，不写 reaction candidate、不覆盖官方正常序列。
- **宏兼容性边界**：未修改玩家宏文本、宏发现、宏绑定、TEK、TEAP 或输入门禁。正文可见的现有宏沿原有解析/分支守卫走；正文不可见的当前按钮仅恢复 target transport，不以它的名字或其他宏猜测路由。

# 1.0.48 P5.3.1 — legacy 目标管理打断宏兼容恢复

- **恢复已验证 legacy target 路由**：P5.3 不再一律阻断当前目标的目标管理宏。仅对解析为严格 `focus → target` 回退链的旧宏，在不存在活敌焦点抢占首分支时，允许继续使用 P4.3 reaction 交付链，诊断为 `macro_managed_target_target_compat`。
- **保留关键边界**：敌对焦点存在时，target 候选记录 `macro_managed_target_target_preempted_by_focus`；不具有精确 fallback metadata 的目标管理宏和 mouseover 目标管理路由仍 fail-closed。普通 direct target 动作条按钮保持优先。
- **修复代表 SpellID 宏名空窗**：当 `GetActionText` 为空、`GetActionInfo` 返回代表 SpellID（例如 147362）且 action-info probe 只能得到宏名时，该宏名可作为唯一语义回收的 join key。仍要求真实宏 index 正文与 SpellID 语义唯一一致；不按名称盲取正文。
- **不变项**：P5.3 的 3 次兼容稳定、钢条硬否决、native scalar 嫌疑、打断自身 CD 门控、TEK/TEAP/BindingToken 均不变；无需重建 `TEK.exe`。

# 1.0.47 P5.3 — 钢条稳定证据、打断冷却门控与目标管理宏收紧

- **兼容读条先稳定**：P4.3 兼容派发不再在首张 `unit_event_pending` 帧立即放行；同一 `castKey` 必须经过 3 次不同共享观察样本。这样为 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` 和动态原生盾组件提供有限稳定窗口。
- **扩展真实盾组件探测**：除直接字段和既有全局命名外，原生施法条现在只读扫描名称、atlas 或 texture 明确包含 shield/uninterruptible/notinterruptible 的当前子组件与 region。`showShield`/`barType` 仍仅是诊断。
- **native scalar 嫌疑阻断兼容派发**：scalar-only / method-only 不可打断 `true` 仍不会被 P3 当作可见钢条结论，但 P5.3 不会再将其视为“无钢条”；兼容路径记录 `compat_native_steel_suspected` 并 fail-closed。
- **打断冷却门控**：候选路由建立后，对 TEK 将实际按下的 action slot 进行只读 CD/charges/GCD 采样。已知非 GCD 自身 CD 且无可用 charges 时返回 `interrupt_action_cooldown`，不产生 reaction candidate，不覆盖正常主推荐。宏按钮仅能提供 CD 否决证据，不能用“ready”反向授权派发。
- **目标管理宏收紧**：现场日志显示某些解析形态未标出 exact fallback 元数据，仍让当前目标使用 `/targetenemy` 宏。P5.3 以 `macroManagedTarget` 为整体安全边界：带目标管理命令的宏仅可用于已验证的焦点分支；target/mouseover 均不自动使用。
- **不变项**：未修改 TEK、TEAP 字段、BindingToken、宏正文、宏执行顺序、AutoBurst 或 HUD CD 渲染；无需重建 `TEK.exe`。

# 1.0.46 P5.2 — P4.3 兼容打断派发与宏命中守卫

- **恢复已验证动作链**：当真实活跃读条因 Retail 证据不透明而停在 `interruptibility_unconfirmed` 时，默认启用 `compatibilityActiveCast`，生成稳定 `compat_interrupt_candidate`，继续使用既有 BindingToken → TEAP reaction → TEK 链。
- **硬钢条仍不可绕过**：直接 API 明确不可打断、真实可见盾、有效 `UNIT_SPELLCAST_NOT_INTERRUPTIBLE`、原生明确不可打断仍一律零 Token；`showShield`/`barType`/未知值不单独作为判定。
- **可切换策略**：打断设置新增“兼容未确认读条派发”；关闭后恢复 P4.4 严格正向确认模式。
- **宏命中守卫**：P5.1 的宏身份语义回收保留。严格 mouseover→focus→target 宏继续检查上游宏分支。焦点优先 `/targetenemy` 回退宏仅允许焦点读条路径自动派发；当前目标 fallback 在按键前无法验证最终目标，记录 `macro_managed_target_fallback_target_unverifiable`。
- **路由优先级**：同一技能同时存在普通当前目标按钮和目标管理宏时，优先普通当前目标按钮。
- **不变项**：不改宏、不切换目标、不新增输入路径，不修改 TEK、AutoBurst 或 HUD 冷却；无需重建 TEK.exe。

# 1.0.45 P5.1 — 宏动作身份与唯一语义回收

- **修复 P5 实机错误假设**：部分 Retail 宏动作的 `GetActionInfo(actionSlot).id` 为代表技能 SpellID，而不是宏列表 index；反制射击宏现场返回 `147362`，P5 误把它用于 `GetMacroInfo(147362)`，导致宏正文必然不可用。
- **双路径身份模型**：动作信息值处于当前账号/角色宏索引范围时，继续以同一 numeric index 读取正文；动作信息值不属于有效宏索引时，进入受限的“动作条宏名 + 代表 SpellID + 宏正文语义”唯一匹配。
- **同名不再盲取第一枚**：仅名称相同不会授权；候选宏必须引用动作条代表技能，且仅有一枚候选时才恢复正文。多个同名且同技能候选记录 `macro_semantic_identity_ambiguous` 并 fail-closed。
- **诊断扩展**：记录 `actionInfoLooksLikeMacroIndex`、`representedSpellID`、`actionTextCandidateCount`、`semanticCandidateCount`、`semanticCandidateIndexes` 与身份来源；仍不保存宏正文。
- **不变项**：没有修改宏文本、目标处理、BindingToken、TEAP、TEK 或任何输入门禁；无需重建 TEK.exe。

# 1.0.44 P5 — 宏身份锚定与同名宏防错配

- **取消宏名正文回收**：宏正文只允许通过当前动作条 `GetActionInfo` 返回的数值 `macroIndex` 回收；不再按 `GetMacroInfo(name)` 或账号/角色宏列表中的同名条目取正文。
- **有界同索引重读**：`GetMacroInfo(macroIndex)` 首读名称存在而正文为空时，仅对相同 numeric index 最多重读两次，覆盖客户端短暂正文空窗而不引入同名错配。
- **同名宏 fail-closed**：当前 index 无正文时，即使另一枚账号/角色同名宏引用 `反制射击`，也不能提供派发资格；诊断为 `macro_body_unavailable_action_info_id`。
- **诊断增强**：映射导出、面板与 `/temapping` 增加 macro identity source、动作条 macro index、读取次数、身份确认结果；不保存宏正文。
- **不变项**：P4.4 严格钢条、P4.5 宏分支守卫、P4.6 SpellID 令牌关联、BindingToken → TEAP → TEK 链均未修改；无需重建 TEK.exe。

# 1.0.43 P4.6 — 多行打断宏发现与 SpellID 关联韧性

- **修复宏正文回收后备**：当 `GetMacroInfo(actionInfoID)` 首读只给出宏名称而正文缺失时，解析器会继续使用动作条文本与该索引返回名称，从已有账号/角色宏列表回收同一宏正文；不再仅依赖 `GetActionText`。
- **新增 `/cast` 令牌 SpellID 关联**：宏内技能名称可只读查询为普通 SpellID。请求技能名称在当次 API 调用中不可材料化时，仍可安全关联已知的 `反制射击`（147362）等同技能多行宏；不依赖宏名称或图标猜测。
- **避免负缓存锁死**：名称/SpellID 临时读取失败不会写入会话级负缓存；下一次既有动作条失效/重建后可重新确认。
- **诊断增强**：P2 映射与 `/temapping` 增加宏正文回收来源、查找次数、动作条宏名与已解析 `/cast` SpellID 令牌数量；仍不保存宏正文。
- **不变项**：P4.4 严格钢条资格、P4.5 宏分支守卫、现有 BindingToken → TEAP → TEK 输入链与全部 Windows 门禁均未修改；无需重建 TEK.exe。

# 1.0.42 P4.5 — 受守卫的整合打断宏

- **修正整合宏解析**：`/cast [@mouseover,harm,nodead][@focus,harm,nodead][harm,nodead] 技能` 不再被误判为单一 `@mouseover` 宏；解析器保留全部条件块，并仅接受严格 `mouseover → focus → target` 单技能链。
- **新增 `macro_priority_chain` 路由元数据**：P2 对同一已有宏键位登记 mouseover、focus、target 三个来源及固定优先级；不创建 BindingToken、不编辑宏、不增加输入路径。
- **新增 P4 分支兼容性守卫**：focus/target 读条候选前，检查是否存在会先被宏命中的上游活敌单位；若存在，则记录 `macro_priority_preempted_by_mouseover/focus` 并 fail-closed。
- **未知链保持手动**：部分链、修饰键、战斗状态、混合条件、目标管理或多技能宏统一标记为 `macro_conditional_chain_opaque` / 既有不透明原因，不再把首个条件分支误升格为自动路由。
- **保留 P4.4 与 P4.3 所有动作链保障**：严格钢条证据、稳定 candidate、stable sequence 与 TEK reaction dedupe 均未改变。

# 1.0.41 P4.4 — 严格钢条判定与原生视觉复核

- **取消 P4.3 探测例外**：删除 `probe_active_cast_ignore_steel`。读条存在但不具备可打断证据时，恢复为 `interruptibility_unconfirmed`，只高亮、不派发。
- **修正 `showShield` 误用**：该字段及 `barType` 仅保留为诊断，不再作为当前读条的钢条或可打断结论。
- **真实盾组件判定**：读取 `BorderShield` / 等价子组件的实际 `IsShown()` / `IsVisible()` 状态；可见盾为硬否决，明确无盾可作为视觉证据。
- **视觉防抖**：原生无盾或原生 explicit-false 路径必须在同一读条连续两次 P3 样本中一致，才可派发；直接 API 与单位施法事件不受此等待影响。
- **事件身份保留**：`ReactionInterruptEvents` 的 status 事件不再以 nil 覆盖 START 事件中已取得的 spellID/castGUID，避免削弱 stale-event mismatch 防线。
- **保留 P4.3 可靠性交付修复**：reaction candidate 仍稳定保留到读条结束；SignalFrame 保持同 sequence；TEK 继续按稳定 reaction sequence 成功后去重。
- **诊断增强**：面板显示真实盾组件来源、原生证据以及视觉采样 `1/2`、`2/2`。

# 1.0.40 P4.3 — 自动打断动作链探测与稳定投递（历史）

- P4.3 已确认现有 BindingToken → TEAP reaction → TEK → 游戏内打断动作链可达。
- P4.4 已替代其临时“忽略钢条”探测资格；P4.3 不再作为正式判定策略。
