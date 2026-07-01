# Tactic Echo Tasks

Current version: `0.9.51`

## Active Scope

- Keep the 0.9.0 maintenance baseline intact.
- Preserve the v3 dispatch path: official primary recommendation -> visible default action-bar binding -> BindingToken -> TEAP -> TEK gates -> SendInput.
- Do not change macro behavior in this pass.
- Keep tactical HUD, burst, defense, interrupt/control and cooldown work presentation-only.

## Current Validation Queue

- Sync `addon/!TacticEcho` into the WoW AddOns directory before live AddOn checks.
- Verify WoW Retail loads without Lua errors after `/reload`.
- Verify TEAP v3 signal remains visible in `waiting`, `paused`, `armed`, `manual_hold`, `channeling` and `empowering`.
- Verify TEK auto-location in windowed, borderless/fullscreen, moved window and changed DPI/resolution cases.
- Verify TEK real SendInput only after foreground, hook, freshness, BindingToken and rate-limit gates pass.
- Verify the ProtocolMonitor secret-boolean hotfix against target casts that previously produced protected-value errors.

## Known Open Items

- Complex healing macros are still conservative: conditional mouseover/target/fallback macro bodies are not parsed as dispatch associations unless Blizzard APIs report the current macro spell.
- Custom action-bar addons are diagnostic-only; only Blizzard default visible action buttons are supported.
- Windows GUI/tray/hook/SendInput behavior must be treated as live-machine validation unless the user provides test evidence.
- This workspace was not a git repository before the current cleanup, so remote configuration must be confirmed before pushing.

## Next Engineering Candidates

- Add clearer in-game diagnostics for "visible default action button missing" versus "custom action-bar addon ownership".
- Expand specialization-aware defensive profiles beyond Paladin using live-client verification.
- Keep documenting live test evidence in `HANDOFF.md` or `CHANGELOG.md` instead of adding duplicate "current version" blocks to README/TASKS.

## Completed Current Checks

- Baseline contract passes for the current tree.
- Python unit and pytest suites pass.
- Python compile check for TEK source passes.
- Lua syntax check should be run whenever `luac` or `texluac` is available.
