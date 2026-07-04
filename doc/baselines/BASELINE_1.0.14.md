# Tactic Echo 1.0.14 Baseline

## Scope

This release extends the validated 1.0.13 source baseline in one bounded area: AutoBurst delivery cadence and pre-window trinket recovery.

TEAP v3, BindingToken, official recommendation handling, macro ownership, default action-bar restrictions, and the single TEK SendInput path remain unchanged.

## Unified delivery contract

All dispatchable candidates use one scheduler contract:

```text
fresh armed TEAP frame
→ ordinary TEK protocol / foreground / Hook / manual ownership / freshness gates
→ shared global dispatch-rate limiter
→ one physical SendInput attempt for that frame
```

- Ordinary official recommendations and AutoBurst candidates can both remain visible across multiple fresh `armed` frames. The configured TEK global rate is the only physical-input frequency limit; Burst no longer has a sequence-specific one/two-attempt limiter.
- A logical Burst step keeps its action sequence and candidate identity while waiting for confirmation. Repeated physical attempts do **not** advance the plan. Only exact current-step evidence may advance it.
- A normal player cast keeps the existing `armed` cadence, therefore follows the same fresh-frame scheduler as ordinary official recommendations and Burst candidates.
- Channeling and empowering remain explicit non-dispatch TEAP states for both ordinary and Burst paths. Text input, manual takeover, death, vehicle, focus loss, observation-only frames and other existing hard gates remain non-dispatch.
- When an action is own-ready but the public GCD is active, AutoBurst now keeps publishing the current candidate through `GCD_LOCKED`, `QUEUE_WINDOW` and `READY_NOW`. The game can accept/queue it at its normal queue boundary; TEK still limits input at the configured global rate.
- A GCD-aligned cooldown is never confirmation or skip evidence. The plan advances only after exact spell event / own cooldown / charge proof, or exact locked trinket cooldown proof.

## Pre-window trinket recovery contract

Phase 1.5 still permits exactly one explicit `13` or `14` trinket injection before or after an official SpellID window.

- Plan creation locks `inventory slot + ItemID + existing BindingToken`.
- Soft pauses freeze plan, confirmation, revalidation and recovery clocks. On resume, the same current step is revalidated instead of losing its time budget.
- A pre-window trinket whose initial confirmation window expires enters one bounded recovery period. During recovery the same candidate remains publishable at the shared global rate and the AddOn continuously samples only the locked slot + ItemID's non-GCD own cooldown.
- A player may manually supplement the trinket press. When that exact locked trinket enters its own non-GCD cooldown, AutoBurst confirms the injection and proceeds to the official window.
- Unknown data, generic GCD, HUD grayness, Buffs, slot mismatch, item replacement, binding failure and recovery expiry never count as success or a skip. The plan then aborts and retains the window-departure lock.

## Required field validation

1. Configure a pre/simple spell injection and verify repeated fresh Burst frames produce repeated TEK `dispatch_origin=burst` attempts only at the configured global rate; after exact confirmation, the next plan step begins.
2. Configure a window that first appears during ordinary GCD. Verify the current injection/window candidate stays dispatchable during `GCD_LOCKED`, transitions through `QUEUE_WINDOW`, and is still confirmed only by exact evidence.
3. Use one visible direct trinket button or an existing single-slot `/use 13` / `/use 14` macro. Interrupt, pause or manually supplement the first trinket action. Verify that the recovery path accepts only the locked slot + ItemID own cooldown and then offers the window.
4. Test chat input, manual takeover, channeling and empowering. Verify no BindingToken is output while the matching ordinary path is non-dispatchable.
5. Test recovery expiry, item replacement, missing binding and generic GCD. Verify no automatic window fallback occurs and the official window remains locked until departure.
