# 0.7.5 HUD Icon Visibility Hotfix

## Field symptom

The queue HUD retained active card hitboxes and Tooltips, while card images were invisible and only the parent backdrop could be seen.

## Fix

- Replaced the mandatory rounded-mask / decorative atlas / animation-dependent card surface with a visibility-first icon surface.
- Every visible card explicitly shows a spell texture; unavailable or unsafe textures fall back to `Interface\\Icons\\INV_Misc_QuestionMark`.
- Removed mask creation and alpha-animation gating from the icon visibility path.
- Retained card layout, tooltip data, cooldown frames, charge rim, overlay, border, and read-only dispatch boundary.

## Guardrails

- Rounded masks are disabled in the current baseline. They are presentation-only and must be reintroduced only as an optional client-validated enhancement.
- The HUD does not read official recommendations directly, mutate recommendations, write Tokens, encode TEAP, or trigger TEK input.

## Automated checks

- `pytest tests/unit tek/tests`: 199 passed.
- `unittest discover -s tests/unit`: 68 passed.
- `unittest discover -s tek/tests`: 124 passed.
- `compileall tek`: passed.
- Lua syntax parse: 36/36.
- TOC paths: 36/36.

The `RuntimeError("boom")` message emitted during TEK tests is the expected worker-recovery fixture; that test suite passed.
