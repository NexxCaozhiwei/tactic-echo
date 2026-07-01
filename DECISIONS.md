# Tactic Echo Decisions

Current version: `0.9.51`

## D1. Dispatch Path

The only allowed input path is:

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3
-> TEK safety gates
-> SendInput
```

All tactical, defensive, burst, interrupt/control, mobility, HUD, tooltip and visual systems are advisory or presentation-only.

## D2. Action-Bar Scope

Only Blizzard default visible action buttons are dispatch sources. Vehicle, possession, override and pet-battle contexts fail closed. ExtraActionBar may be observed for diagnostics but does not replace player action-bar resolution.

Custom action-bar addons are out of scope until explicitly designed and verified.

## D3. Macro Scope

Macros are never evaluated by Tactic Echo. A macro can only be dispatched by pressing the player's existing visible bound button.

Text fallback is limited to one unconditioned single-line `/cast <spell>` macro. Conditional, mouseover, target, semicolon branch, `/use`, `/castsequence` and multi-action macros remain diagnostics unless Blizzard APIs report their current spell association.

## D4. TEAP v3 Auto Location

TEK auto mode locates only inside bounded top-left regions of the current WoW client area. The `T / E / 3` header is a geometry candidate only; dispatch requires complete v3 frame validation with CRC/commit/session/freshness proof.

Auto mode must not fall back to fixed desktop coordinates.

## D5. Secret Values

Protected or secret values must not cross from WoW APIs into model, strategy, tooltip, TEAP or TEK payloads. If a value cannot be proven to be a normal Lua scalar inside a protected probe, it degrades to unknown.

## D6. Cooldowns

Cooldown data is HUD presentation only. Native DurationObject rendering is preferred where public APIs provide it. Raw protected cooldown values must not enter recommendation, TEAP or TEK input paths.

## D7. Validation Claims

Offline unit tests, Python compile checks and PyInstaller/build success do not prove Windows live behavior. Tray, hook, foreground, DPI/multi-monitor, WoW capture and actual SendInput remain live-machine acceptance items unless user evidence exists.
