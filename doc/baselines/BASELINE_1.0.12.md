# Tactic Echo 1.0.12 Baseline

## Scope

This release follows the validated 1.0.11 source baseline. It expands only the existing visible Blizzard default-action-bar macro association layer. TEAP v3, BindingToken protocol, TEK safety gates, official recommendation handling and the single SendInput path are unchanged.

## Changes

1. **Dynamic macro association**: `MacroSemantics` now describes `/cast`, `/use`, conditional/semicolon branches, target modifiers including `@cursor`, helper lines and `/castsequence`. The resolver first trusts Blizzard macro spell APIs, then uses broad text association for the requested SpellID.
2. **Existing-button only**: No macro body is edited, created or replayed. Resolver output remains a real BindingToken for the player’s already-visible default action button.
3. **AutoBurst eligibility**: Resolver-associated macro buttons can be window or injection steps. A macro step is still accepted only after the expected configured SpellID receives a current-step `UNIT_SPELLCAST_SUCCEEDED`, non-GCD own-CD or charge proof.
4. **Macro-aware CD identity**: A resolver-associated macro button’s visible action slot is trusted for cooldown tracker identity and strict front/simple two-sample own-CD evidence.
5. **Diagnostics**: Mapping exports add safe association/shape/trust booleans; no macro body or raw macro content is exported.

## Required field validation

- Place `260243` on an existing `#showtooltip /cast [@cursor] 乱射` macro with a real default-action-bar key.
- Configure `/teab set 260243 288613`, arm auto running, and verify that `official=260243` builds the `288613 -> 260243` pre plan rather than reporting `macro_not_single_use`.
- Test a helper-line macro, a conditional multi-spell macro and a `/castsequence`; only the actually configured step may confirm/advance.
- Confirm `/temapping` contains `macroAssociation`, `macroAutoBurstEligible`, `macroShape` and no `macroBody`.
