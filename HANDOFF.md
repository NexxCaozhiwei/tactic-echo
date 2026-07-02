# Tactic Echo Handoff

Current source release: `1.0.08`

## Current State

The repository is on the `1.0.08` development baseline. Its historical code ancestry is `0.9.51`; the current source release is `1.0.08`. The dispatch architecture is TEAP v3 dynamic action-bar binding:

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3 visual frame
-> TEK safety gates
-> SendInput
```

当前版本新增了 AutoBurst Phase 1；复杂宏策略仍保持保守，不在本阶段扩展。

## Recent Functional State

- TEAP v3 still uses a 20-field frame with `T / E / 3 / State`, CRC16 and commit byte.
- AddOn resolves recommendations through `ActionBarBindingResolver.lua` against visible Blizzard default action buttons.
- TEK decodes v3 BindingToken directly; v2/profile/hidden-button dispatch is not the default path.
- TEK auto-location searches bounded top-left WoW client regions for the v3 header and requires complete-frame proof before dispatch.
- Non-dispatch states retain their meaning: `waiting`, `paused`, `manual_hold`, `channeling`, `empowering`.
- `ProtocolMonitor` target-cast values are secret-safe; protected interruptibility falls back to unknown instead of raising a taint/protected-value error.

## AutoBurst Phase 1

- 代码入口：`Tactics/AutoBurst.lua`；默认 `autoBurstEnabled=false`。
- 仅一条 Profile 声明的窗口 + 注入规则，支持 pre/post、simple/focused。
- 只读取 CD、充能和 `GCDGate` 标签；不使用 Buff、资源、目标或范围。
- TEAP flags bit 5 标记 `dispatchOrigin=burst`；TEK 对同一 burst sequence 去重。
- AutoBurst 内部 hold 使用 `armed + observationOnly`，不再错误转写成全局 `paused`；这避免 GCD/确认等待将计划自锁。
- 真正输入仍需 Windows 实机验收；AddOn 没有 SendInput 回执。

## Boundaries

- No hidden action buttons.
- No AddOn binding writes.
- No macro editing.
- No macro branch execution or target-condition inference.
- No tactical/HUD path may create BindingToken, change the official recommendation or request TEK input.
- Vehicle, possession, override and pet-battle action bars fail closed; ExtraActionBar is observation-only.

## Known Gaps

- Complex conditional macros, including common healing mouseover/target/fallback macros, are not associated by text fallback. They only work when Blizzard APIs expose the current macro spell association.
- Custom action-bar addons are not dispatch sources.
- Live Windows validation is still required for tray, hook, foreground, multi-monitor/DPI and actual SendInput behavior.
- Remote GitHub configuration must be confirmed before push.

## Validation Commands

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

If available:

```powershell
luac -p <each addon lua file>
```

or:

```powershell
texluac -p <each addon lua file>
```

## Live Test Notes To Preserve

- User has previously validated Retribution Paladin key dispatch after TE/TEK updates.
- Holy Paladin dynamic v3 binding required later code updates and should be rechecked after AddOn sync.
- Macro behavior is intentionally deferred; do not "fix" it unless the user reopens that scope.

## 1.0.07 Field Fixes

- `active=true` without reliable own-CD/GCD provenance is `UNKNOWN`, never a skip-eligible cooldown. Front injection holds/revalidates for a bounded interval.
- Every created Phase 1 plan retains its window departure lock when it aborts or times out; ordinary official dispatch cannot bypass an unconfirmed front injection.
- A Burst candidate remains visible with one stable TEAP sequence until success, explicit invalidation or deadline. TEK attempts that sequence at most once.
- `UNIT_SPELLCAST_SUCCEEDED` can confirm only the current dispatched step; it is not a timing/trigger input.
- Observation-only Burst frames retain `BindingToken=0` for TEK safety but carry a separate official display binding for HUD/diagnostics.

## 1.0.08 Field Fixes

- AutoBurst trigger ownership now uses `armedEpoch` and window generation counters, not only `previousOfficial != window`.
- `paused -> armed` can claim an already visible, not-yet-consumed `343527` window and start the expected `31884 -> 343527` plan.
- Completion, skip, timeout and abort all consume the current window generation and keep a departure lock until official recommendation leaves.
- `/temapping` exports generation, plan, step, candidate, confirmation, abort and official/dispatch binding fields for post-fight diagnosis.
- Tactical HUD observation frames display the official binding while preserving dispatch `BindingToken=0`.
