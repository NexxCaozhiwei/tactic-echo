# AGENTS.md — Tactic Echo 0.9.0 基线维护约束

## 1. 基线、范围与交付

- 当前唯一基线为 `0.9.0` 工作树；其功能基础是已验证的 `0.8.11-trace-retention`。
- 禁止复制、迁移、Cherry-pick、覆盖、对比或叠加任何历史高版本源码、补丁、测试或构建产物。
- 每次默认只解决一个明确问题；允许在同一模块内清理直接相关的重复职责。跨模块重构、UI 结构调整、线程模型变更、事件模型变更必须先提交审计与设计，得到明确确认后才实施。
- 发现旧代码与新代码职责重叠时，先报告路径、调用点、风险与删除方案；未经确认不得删除仍可能被调用的旧实现。
- 小型、明确、可独立覆盖的改动可交付补丁；跨模块、基线、构建或配置改动默认交付完整源码包。
- 不得将 `dist/`、`build/`、`release/`、缓存、日志、本机配置、SavedVariables、EXE 或历史补丁压入源码包。
- 每个源码包必须在空目录解压，验证只有一个顶层根目录，并重复执行当前测试入口。

## 2. 主派发安全边界

唯一允许产生 Windows 输入的路径：

```text
官方主推荐 → 默认动作条现有绑定 → BindingToken → TEAP → TEK 安全门禁 → SendInput
```

禁止：

- 让候选、防御、爆发、打断、控制、位移或 HUD 建立 Token、改变官方主推荐、修改 TEAP 或调用输入。
- HUD、Burst、队列、Tooltip 或视觉效果修改 `RecommendationResult`、BindingToken、TEAP payload 或 TEK 输入请求。
- AddOn 创建隐藏动作按钮、写绑定、保存绑定、编辑宏或切换动作条。
- 通过宏正文推断条件分支、目标修饰、`/castsequence` 或多行 `/use` 的真实执行结果。
- 绕过 WoW 前台、文本输入、玩家引导、物理输入让权、会话、新鲜度、CRC、协议和限频门禁。

## 3. 动作条、宏与职业数据

- 仅保证 Blizzard 默认动作条；载具、控制单位、覆盖动作条、宠物战斗硬阻断，ExtraActionBar 仅观察。
- `ActionBarBindingResolver.lua` 与 TEK `binding_tokens.py` 的现实键位白名单必须同步；主、次绑定须显式分别检查。
- 宏正文仅允许单行、无条件、无目标修饰、无分支的 `/cast` 用于文本关联回退；复杂宏仅诊断。
- 防御与爆发资料必须按 `CLASS_SPECINDEX → empty` 解析；禁止职业级回退、跨专精注入和单职业/单技能/单键位特例。

## 4. HUD、secret value 与事件边界

- HUD、战术建议与视觉层均为只读展示；只消费现有快照，不得写推荐、绑定、Token、TEAP 或 TEK。视觉层仅用于呈现，不得改变推荐或派发条件。
- 潜在 secret 值不得进入策略比较、字符串拼接、Tooltip 格式化、模型指纹、TEAP 或 TEK。无法验证为普通 Lua 值时必须降级为未知。
- 原生 CD/GCD 仅可停留在 `TacticalIconButton.lua` 的 `CooldownFrameTemplate` 展示层；原始数值不得泄漏到模型、策略或传输层。
- 图标纹理缺失时必须使用安全问号占位；单卡失败不得隐藏整个 HUD。
- 除 `Core/Bootstrap.lua` 外，AddOn 模块不得直接 `:RegisterEvent()`；必须使用既有 Bootstrap 安全注册入口，且只允许加载期一次性订阅。

## 5. 性能与刷新约束

- `ProtocolMonitor` 的轮询快照、环境状态与 GCD 上下文必须在同一轮建议刷新中共享；不得对同一事实重复采样。
- `BurstPlanner` 已生成的 `iconState` 必须复用；`TacticalBoard` 仅订阅 `TacticalAdvisors` 快照，不得恢复第二条全量 `OnUpdate` 刷新。
- 模型层只构造真实卡片；物理空槽由 Board 隐藏。相同布局、尺寸与视觉效果必须使用现有签名缓存，避免重复锚定、缩放或重启动画。

## 6. TEK 与 Windows 验收

- Windows GUI、托盘、Hook、多屏/DPI、WoW 前台、实际 SendInput 和 EXE 行为只能标记为“待人工实机验收”，除非已有用户提供的实测证据。
- 不得将离线单元测试、PyInstaller 成功或进程存活 smoke test 表述为 Windows 实机功能已验证。
- `TEKEXEBUILD.CMD` 是唯一的 Windows 一键构建入口。

## 7. 必需验证

影响构建、文档版本、AddOn、TEK、状态模型或测试入口的修改，至少运行：

```bash
python scripts/verify-baseline-contract.py --repo-root .
PYTHONPATH="$PWD" python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

系统存在 `texluac` 或 `luac` 时，还必须对全部 AddOn Lua 执行语法检查。交付前核对：版本三处一致、TOC 路径存在、Bootstrap 之外无直接事件注册、ZIP 结构和内容干净。
