# TEAP v2 — Tactic Echo Action Protocol 草案（Legacy 历史）

> 本文描述 v2 Profile/隐藏按钮兼容路径。当前默认测试路径为 TEAP v3 + BindingToken16；以 `../AGENTS.md`、`../HANDOFF.md` 为准。


> 状态：代码与自动测试已实现；真实 WoW 画面读取、DPI/窗口模式/多显示器稳定性仍待人工验证。

## 1. 目标

TEAP 用于把 TE 中的“当前应执行动作”以可校验、可去重、可暂停、可关联的形式交给 TEK。

当前 v2 解决 v1 的问题：

- TEK 启动时不能直接执行屏幕上已有 armed 旧帧；
- 不能只依赖 16 位 sequence 和单字节 checksum；
- 目录版本、目录指纹和 Profile 指纹必须进入帧校验；
- 需要区分动作序列和帧新鲜度，避免 heartbeat 重复触发同一动作；
- 需要降低逐色块更新导致的撕裂帧风险。

## 2. 视觉帧字段

TEAP v2 使用 20 个固定色块，每个色块承载一个字节：

```text
0  MagicT = 84
1  MagicE = 69
2  protocolVersion = 2
3  state
4  sessionEpoch low
5  sessionEpoch high
6  actionSequence low
7  actionSequence high
8  frameFreshnessCounter low
9  frameFreshnessCounter high
10 ActionCode
11 catalogVersion
12 catalogFingerprint low
13 catalogFingerprint high
14 profileFingerprint low
15 profileFingerprint high
16 flags: bit0=inCombat, bit1=observationOnly
17 CRC16 low
18 CRC16 high
19 commit = 0xA5
```

颜色编码仍为 POC 方案：

```text
R = value
G = 255 - value
B = 17
```

## 3. 状态编码

```text
0 = waiting
1 = armed
2 = paused
3 = blocked
4 = error
```

TEK 只允许在 `armed` 且非 observation-only、Profile/catalog 匹配、前台检查通过、动作未重复、真实输入路径处于 inCombat 时考虑分发。

## 4. 新鲜度、回绕和启动

- `sessionEpoch` 在插件加载、`/reload` 或信号状态重置时变化。
- `actionSequence` 只表达动作输出变化；同一动作的 heartbeat 不得重复执行。
- `frameFreshnessCounter` 表达视觉帧刷新，TEK 用它区分旧画面和新采样。
- TEK live 启动后先进入 Bootstrap，第一帧只建立当前 session 观察基线，不分发。
- 序列比较使用模 65536 差值，不能用简单 `sequence <= lastSequence` 永久阻断回绕后的有效帧。

## 5. 撕裂帧处理

TE 写入色块时 commit 字节最后写入。TEK live 读取时执行双采样：

```text
采样 payload + commit
立即再次采样 payload + commit
两次完全一致
验证 commit
验证 CRC16
通过后才交给安全门
```

任一条件失败均 fail-closed，不发送输入。

## 6. 当前目录与 Profile

当前目录为惩戒骑 10 个 ActionID：

```text
catalogVersion = 2
catalogFingerprint = 55799402f13427c4
catalogFingerprint16 = 21881
```

当前唯一可运行 Profile：

```text
profileId = laptop
profileFingerprint = fa6f775d78e31239
profileFingerprint16 = 64111
```

`desktop-numpad` 仍保留为不可运行示例，因为 TE 侧尚未实现 Profile 切换和对应隐藏按钮建绑。

## 7. 命令语义

- `/tesignal armed`：持续输出 armed 或 blocked 帧。
- `/tesignal pause`：输出 paused 帧。
- `/tesignal off`：先记录 waiting/disarmed 帧，再隐藏视觉帧。
- `/tesignal once`：输出 observation-only paused 帧，仅用于观察，不得触发 live SendInput。

## 8. 测试要求

自动测试已覆盖：

- v2 解码、CRC、commit；
- 旧 v1 帧 fail-closed；
- 双采样不一致 fail-closed；
- catalog/profile 指纹不匹配 fail-closed；
- live bootstrap 不执行第一帧；
- 同一动作 heartbeat 不重复分发；
- 非战斗真实 SendInput 路径阻断。

仍待人工验证：

- WoW 12.0.7 zhCN 中 20 色块真实画面采样；
- `/reload` 后 SavedVariables 与 TEK v2 trace 关联；
- DPI、窗口模式、全屏和多显示器组合。
