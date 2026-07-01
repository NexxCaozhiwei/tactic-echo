# Project Context

Current version: `0.9.51`

Tactic Echo is a World of Warcraft AddOn plus the Windows TEK companion. The current baseline remains `0.9.0`; the current source release is `0.9.51`.

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
