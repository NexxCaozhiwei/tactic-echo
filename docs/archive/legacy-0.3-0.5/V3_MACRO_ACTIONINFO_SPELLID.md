# v3 Macro Association via Action Slot API

This build changes macro association to follow the action-bar evidence path used by established rotation-helper addons:

1. For a macro action slot, call `GetActionInfo(slot)` and preserve all four return values:
   - `actionType`
   - `id`
   - `subType`
   - `macroSpellID`
2. If `subType == "spell"` or `macroSpellID` equals the current recommendation SpellID, the macro button is accepted as associated with the recommendation.
3. If the fourth return value does not match, resolve the macro body through the action slot:
   - `GetActionText(slot)`
   - `GetMacroInfo(actionText)`
   - fallback enumeration through global and character macros by macro name
4. If the body contains the localized spell name or numeric SpellID, the macro button is accepted.

TE still only sends the action-bar binding token. TE does not rewrite macros, parse branches for execution, or call `SetBinding`/`SaveBindings`.

## Expected Holy Shock macro case

For:

```lua
#showtooltip 神圣震击
/cast [@mouseover,help] 神圣震击
/cast [@target,help] 神圣震击
/cast 神圣震击
```

When the official recommendation is `SpellID=20473`, the resolver should accept the macro button if either:

- `GetActionInfo(slot)` returns a macro spell ID of `20473`, or
- the macro body can be found through `GetActionText(slot)` and contains `神圣震击` or `20473`.

The output should show:

```text
source=macro
binding=<the button binding, e.g. E>
bindingToken=<non-zero token>
macroAssociation=action_info_macro_spell | GetMacroSpell | macro_body_reference
```

If the macro still cannot be associated, `/tecurrent` should print macro diagnostics including slot, binding command, raw binding, `actionInfoId`, `actionText`, `macroSpellID`, lookup source, macro index/body length, and failure reason.
