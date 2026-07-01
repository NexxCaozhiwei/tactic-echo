# P0-08 Trace Schema

状态：TEK JSONL trace schema v1 已开始实现；TE signal SavedVariables 已补基础对照字段。

## 目标

同一条动作链路必须能用 sequence 串起：

```text
TE official SpellID
TE ActionID
TE signal frame
TEK decode result
TEK Profile binding
TEK input plan / dispatch result
```

## TEK Trace v1

当前 TEK JSONL 每行是一个 JSON object，核心字段：

```json
{
  "schemaVersion": 1,
  "component": "TEK",
  "eventType": "input_dispatch",
  "observedAt": "2026-06-26T00:00:00+00:00",
  "accepted": true,
  "reason": "dry_run_planned",
  "sequence": 42,
  "state": "armed",
  "action_code": 1,
  "dispatcher_backend": "dry_run",
  "protocol_version": 1,
  "checksum": 230,
  "raw_fields": [84, 69, 1, 1, 1, 42, 0, 230],
  "action_id": "PALADIN_RETRIBUTION_JUDGMENT",
  "binding": "SHIFT+Z",
  "input_plan": {
    "binding": "SHIFT+Z",
    "events": [
      { "key": "CTRL", "event": "down" }
    ]
  },
  "dispatch_result": {
    "sent": false,
    "backend": "dry_run",
    "reason": "dry_run_planned",
    "events_sent": 6
  }
}
```

Blocked events use:

```text
eventType = input_blocked
accepted = false
reason = wow_not_foreground | duplicate_or_old_sequence | frame_state_paused | frame_read_error:...
```

## 待补齐

- TE SavedVariables 中的 signal record 已包含 `schemaVersion/component/eventType`。
- TE signal record 已包含 `sequence/actionCode/actionId/spellID/checksum/fields`。
- TEK trace correlator 已可按 `sequence/actionCode/actionId` 对照 TE 和 TEK 记录。
- TE SavedVariables extractor 可读取最近的 TE signal frame，并为旧记录补默认 `schemaVersion/component/eventType`。
- TE SavedVariables extractor 可按 TEK trace sequence 查询 `TacticEchoDB.signal.bySequence`。
- 已用真实 SavedVariables 中的 TE signal record 和 TEK dry-run trace 验证 correlator 可匹配。
- TEK trace 后续需要在真实 SendInput 后区分 `input_sent`、`input_error`。
