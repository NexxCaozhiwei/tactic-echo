# Project Context

Current version: `1.0.07`

Tactic Echo is a World of Warcraft AddOn plus the Windows TEK companion. The current development baseline is `1.0.07`; its source state derives from `0.9.51`.

Use these current entry points first:

- `README.md` for the current architecture and safety contract.
- `HANDOFF.md` for the current implementation handoff.
- `TASKS.md` for active validation and known gaps.
- `DECISIONS.md` for current technical decisions.
- `CHANGELOG.md` and `docs/archive/` for historical notes.

Current dispatch path:

```text
official primary recommendation
-> visible Blizzard default action-bar binding
-> BindingToken
-> TEAP v3
-> TEK safety gates
-> SendInput
```

Macro behavior is intentionally unchanged in the current cleanup: complex conditional macros are diagnostic-only unless Blizzard APIs expose their current spell association.

## 1.0.07 AutoBurst Field Corrections

The active baseline distinguishes explicit own cooldown from protected/ambiguous state, keeps strict front-plan window ownership through unknown/revalidation and timeout, persists one Burst candidate through confirmation, and uses `UNIT_SPELLCAST_SUCCEEDED` only as an already-dispatched-step receipt. See `BASELINE_1.0.07.md` and `docs/AUTOBURST_PHASE1.md` for the exact contract.
