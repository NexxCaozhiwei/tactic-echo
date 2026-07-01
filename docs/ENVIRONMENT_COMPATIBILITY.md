# 环境兼容信号

环境建议没有内置“识别地板技能”的能力。外部兼容来源可向 `TacticEchoDB.environmentSignals` 写入短时布尔状态：

```lua
TacticEchoDB.environmentSignals = {
  available = true,
  observedAt = GetTime(),
  ttlSeconds = 1.5,
  source = "provider_name",
  dangerZone = false,
  knockbackRisk = false,
  highPressure = false,
}
```

规则：

- `observedAt` 缺失：状态为 `unstamped`，全部风险位为 `false`。
- 超过 TTL：状态为 `stale`，全部风险位为 `false`。
- TTL 默认 1.5 秒，限制为 0.25–10 秒。
- 环境信号仅影响只读防御/位移提示，不修改 TEAP 或 TEK 输入。
