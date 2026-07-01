# P0-04 Signal Frame POC

状态：TEAP v2 发送端与 TEK 解码/双采样/安全门自动测试已完成；真实 WoW 画面读取仍待人工验证。

## 当前范围

本阶段只验证惩戒骑官方推荐能否被编码为固定位置、可校验、可 fail-closed 的视觉帧。固定坐标仍是 POC，不宣称支持所有 DPI、全屏和多显示器组合。

## 已实现

- `SignalEncoder`：生成 TEAP v2 20 字节字段，包含 session、动作序列、新鲜度、目录/Profile 指纹、inCombat、CRC16 和 commit。
- `SignalFrame`：在屏幕左上角渲染 20 个固定小色块，commit 最后写入。
- `/tesignal`：提供 armed、pause、off、once、status。
- `/tesignal once`：输出 observation-only paused 帧，默认不可执行。
- SavedVariables：记录 v2 字段到 `TacticEchoDB.signal.frames` 与 `bySequence`。
- TEK：使用 Pillow 最小 bbox 双采样，要求两次样本一致、commit 正确、CRC 正确。
- TEK：旧 v1 帧、撕裂帧、CRC 错误、目录/Profile 指纹不匹配均 fail-closed。

## 手工验证步骤

1. 同步插件到 AddOns 后进入惩戒骑角色，执行 `/reload`。
2. 执行 `/tecontext`，确认职业为 `PALADIN`、专精为 `3`。
3. 执行 `/tebindings`，非战斗状态建立隐藏按钮绑定。
4. 执行 `/tebindings check`，确认 10 个动作 ready；如有冲突，记录被覆盖的原 Binding Action。
5. 执行 `/tesignal once`，确认聊天框显示协议、会话、新鲜度、目录/Profile 指纹和字段。
6. 执行 `/tesignal armed`，观察左上角是否出现 20 个小色块。
7. Windows 侧执行 `.\scripts\tek-live-dry-run.ps1`，确认第一帧因 bootstrap 阻断，后续新鲜 armed 动作 dry-run 规划 `SHIFT+字母`。
8. 执行 `/tesignal off`，确认 TEK 后续阻断而不发送。

## TEK dry-run 采样命令

```text
python -m tek.src.cli --live --trace logs/p0-04-v2-dry-run.jsonl
```

或：

```text
.\scripts\tek-live-dry-run.ps1
```

当前仍为 dry-run，不发送真实按键。

## 待验证

- 20 色块在目标 WoW 客户端中的真实采样稳定性。
- 不同 DPI、UI 缩放、窗口模式、全屏模式下的位置与颜色采样。
- `/tesignal off` 的 waiting/disarmed 状态是否能被 TEK 可观测地记录。
- TEK v2 trace 与 `/reload` 后 SavedVariables 的 session/actionSequence/catalogFingerprint 关联。
