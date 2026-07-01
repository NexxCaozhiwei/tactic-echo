# Tactic Echo Handoff

Current source release: `0.9.51`

## Current State

The repository is on the 0.9.0 maintenance baseline with current source release `0.9.51`. The dispatch architecture is TEAP v3 dynamic action-bar binding:

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3 visual frame
-> TEK safety gates
-> SendInput
```

The current pass intentionally does not change macro behavior.

## Recent Functional State

- TEAP v3 still uses a 20-field frame with `T / E / 3 / State`, CRC16 and commit byte.
- AddOn resolves recommendations through `ActionBarBindingResolver.lua` against visible Blizzard default action buttons.
- TEK decodes v3 BindingToken directly; v2/profile/hidden-button dispatch is not the default path.
- TEK auto-location searches bounded top-left WoW client regions for the v3 header and requires complete-frame proof before dispatch.
- Non-dispatch states retain their meaning: `waiting`, `paused`, `manual_hold`, `channeling`, `empowering`.
- `ProtocolMonitor` target-cast values are secret-safe; protected interruptibility falls back to unknown instead of raising a taint/protected-value error.

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
