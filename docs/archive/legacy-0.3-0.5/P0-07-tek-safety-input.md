# P0-07 TEK Safety Gate and Input Plan（历史 POC 归档）

> **状态：历史 v1 / v2 POC 归档，不描述当前默认产品路径。**
>
> 当前规则以 [`../AGENTS.md`](../AGENTS.md)、[`../HANDOFF.md`](../HANDOFF.md) 和 [`DYNAMIC_ACTIONBAR_IMPLEMENTATION_SPEC.md`](DYNAMIC_ACTIONBAR_IMPLEMENTATION_SPEC.md) 为准：默认测试路径是 **TEAP v3 + BindingToken16**；TEAP v2 / Profile / 隐藏安全按钮为显式 Legacy 兼容。

## 历史价值

本文件记录早期 P0 阶段为何建立 SafetyGate、ProfileResolver、InputPlanner、TraceRecord、前台检测和 Windows SendInput 后端。模块边界仍有效：

```text
TEAP frame
→ SafetyGate
→ v3 BindingToken 或 v2 ProfileResolver
→ InputPlanner
→ InputDispatcher
→ TraceRecord
```

## 当前不可改变的 Core 原则

- 协议、前台、freshness、CRC/commit、非 Armed、无效 Token、Profile（仅 v2）、部分发送与 ErrorLocked 必须 fail-closed；
- `input_sent` 不等于游戏施法成功；
- Tray App 不能绕过 SafetyGate；
- UI 联动持续运行不等于关闭协议、前台、trace、限速或 ErrorLocked 保护；
- 停止和退出必须释放 dispatcher 状态与修饰键。

## 当前测试入口

```powershell
python -m unittest discover -s tek/tests -v
```

历史证据仅供回溯，不可据此恢复 v1 代码、旧键位或把 v2 当作默认路径。
