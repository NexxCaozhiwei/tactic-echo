# Audit Report 0.7.1

## Scope

- Fixed TEUI nil callback errors reported at `ControlPanel.lua:313` and `ControlPanel.lua:319`.
- Added dedicated burst settings page and connected settings defaults across ControlPanel and TacticalAdvisors.
- Reviewed BurstPlanner and TacticalBoard integration for advisory-only boundaries.

## Verification

- `pytest tests/unit tek/tests`: 185 passed.
- `unittest tek/tests`: 124 passed.
- `unittest tests/unit`: 54 passed.
- Python compilation check passed.

## Not verified in sandbox

- WoW runtime UI behavior.
- Aura confirmation in live combat.
- HUD visual layout with real icons.
