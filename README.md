# Tactic Echo

Last updated: 2026-07-01 22:35:00 +08:00

Tactic Echo is a World of Warcraft AddOn plus Windows TEK companion. The current source release is `0.9.51`.

## Current Contract

The only Windows input path is:

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3
-> TEK safety gates
-> SendInput
```

HUD, burst, defense, interrupt/control, tooltip, queue and visual systems are read-only presentation/advisory layers. They must not change the official primary recommendation, create BindingToken values, write TEAP payloads or request TEK input.

## Version State

- `VERSION`: `0.9.51`
- AddOn TOC: `addon/!TacticEcho/!TacticEcho.toc`
- AddOn bootstrap version: `addon/!TacticEcho/Core/Bootstrap.lua`
- TEK one-click Windows build entry: `TEKEXEBUILD.CMD`

The feature baseline is still the frozen `0.9.0` maintenance line, whose functional base is the verified `0.8.11-trace-retention` tree. Do not copy, cherry-pick or overlay historical higher-version source trees into this baseline.

## Current Architecture

### AddOn

- Reads the official assisted-combat recommendation.
- Resolves that SpellID against the current visible Blizzard default action buttons.
- Uses existing player key bindings only; it does not create hidden buttons, write bindings, edit macros or switch action bars.
- Emits TEAP v3 as 20 visual fields with `T / E / 3 / State`, CRC16, commit byte, catalog fingerprint and BindingToken.
- Keeps tactical HUD and cooldown rendering separate from dispatch.

### TEK

- Locates the TEAP v3 strip inside the current WoW client area.
- Requires complete v3 CRC/commit/freshness validation before dispatch.
- Decodes BindingToken directly in v3; action catalog metadata is trace-only for dispatch.
- Requires WoW foreground, fresh session/frame data, valid protocol/catalog/token, local run state, physical input hook health, manual-input cooperation and rate limits.
- Treats `paused`, `waiting`, `manual_hold`, `channeling` and `empowering` as non-dispatch states.

## Macro Policy

Macro handling is intentionally conservative and is not being changed in this pass.

- A macro button may dispatch only by pressing the player's existing visible action-bar binding.
- The AddOn never evaluates macro branches or target conditions.
- Text fallback only associates one unconditioned, single-line `/cast <spell>` macro.
- Complex mouseover/target/fallback macros remain diagnostic-only unless Blizzard APIs report the macro's current spell association.

## Auto Location

TEK auto mode searches only bounded top-left regions of the current WoW client area for the v3 `T / E / 3` header. It supports zero visual gap between blocks and validates a candidate through complete v3 frames with advancing freshness before dispatch is allowed. Auto mode does not fall back to fixed desktop coordinates.

## Validation

For changes affecting AddOn, TEK, docs, build, status model or tests, run at least:

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python -m pytest -q tek/tests tests/unit
python -m unittest discover -s tek/tests -q
python -m unittest discover -s tests/unit -q
python -m compileall -q tek/src tek/app tek/runtime
```

If `luac` or `texluac` is available, also syntax-check every AddOn Lua file.

Windows GUI, tray, hook, multi-monitor/DPI, WoW foreground, real SendInput and packaged EXE behavior remain live-machine acceptance items unless backed by user-provided test evidence.

## Important Paths

- AddOn source: `addon/!TacticEcho`
- TEK source: `tek/src`, `tek/app`, `tek/runtime`
- TEK tests: `tek/tests`
- AddOn/static contract tests: `tests/unit`
- Current handoff: `HANDOFF.md`
- Current tasks: `TASKS.md`
- Current decisions: `DECISIONS.md`
- Historical notes: `CHANGELOG.md`, `docs/archive`
