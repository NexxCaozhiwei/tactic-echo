# Tactic Echo 1.0.11 Baseline

## Scope

This release follows the validated 1.0.10 source baseline. It changes only HUD cooldown/state presentation and AutoBurst confirmation/retry handling. TEAP v3, BindingToken resolution, TEK gates and the single SendInput path are unchanged.

## Changes

1. **HUD CD ownership**: default and migrated legacy `auto` profiles use the configurable HUD countdown text. Blizzard DurationObjects remain timer/swipe authority; their digits display only in explicit `duration` mode.
2. **One cooldown visual**: confirmed self-CD leaves the icon saturated and uses only the cooldown swipe plus countdown. Resource/range/target states use labels/borders, while blocked/error/unbound retain hard-state grey semantics.
3. **Burst-only verification label**: generic `CooldownTracker.confirmationPending` stays internal. “校验” appears only on the current AutoBurst injection/window step while it waits for proof or is confirming a strict front own-CD skip.
4. **Window confirmation hardening**: `UNIT_SPELLCAST_SUCCEEDED` accepts the declared ID and current resolver requested/matched/equivalent IDs. A matching event triggers an immediate SignalFrame refresh. A window sent in `QUEUE_WINDOW` can receive one controlled retry only after GCDGate proves the queue opportunity passed and no confirmation arrived.

## Required field validation

- Change CD text colour, size, scale and anchor in each module; verify the HUD countdown changes immediately.
- Cast a normal interrupt or defense skill; it must not show “校验”.
- Run pre/post AutoBurst; only the active injection/window may show “校验”.
- Verify a real cooldown shows one radial swipe and one countdown without a full icon greyscale mask.
- Test a delayed/missed window delivery; `/temapping` should show either `step_confirmed` or `window_queue_delivery_unconfirmed` followed by one new dispatch attempt.
