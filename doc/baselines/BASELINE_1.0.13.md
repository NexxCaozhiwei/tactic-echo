# Tactic Echo 1.0.13 Baseline

## Scope

This release extends the validated 1.0.12 source baseline in two bounded areas only:

1. AutoBurst Phase 1.5 adds one explicitly configured equipped trinket action (`13` or `14`) as the single injection step before or after an official SpellID window.
2. TEUI adds direct HUD-context navigation, burst settings/style subpages, navigation selection emphasis, layout-spacing repair, and `/te` command buttons.

TEAP v3, BindingToken protocol, TEK safety gates, official recommendation handling, and the single SendInput path remain unchanged.

## AutoBurst Phase 1.5 trinket contract

- The official trigger remains a manually configured SpellID window. An item can never be an official-window trigger.
- The injected action may be a configured SpellID or a single equipped trinket slot, `13` or `14`. Potions, backpack items, multiple trinket actions and inferred gear strategies remain excluded.
- Direct visible trinket buttons and existing visible default-action-bar macros that reference exactly one `/use 13` or `/use 14` are accepted. Existing macros are not created, edited, split, evaluated or replayed.
- A macro that references both trinket slots is rejected as `macro_multiple_trinket_slots`; users must model the two slots as separate future actions rather than hiding them in one macro.
- Plan creation locks the current `slot + ItemID`. A missing item, changed equipment, missing binding, unknown state, or confirmation timeout is fail-closed.
- In pre/simple mode, a trinket may be skipped only after two independent live samples confirm the same locked slot and ItemID are on their own non-GCD cooldown. Any other unavailable/unknown condition aborts and locks the official window until departure.
- Trinkets follow GCDGate by default. `off_gcd_explicit` is disabled by default and can only be enabled intentionally for a tested item.
- Trinket success confirmation accepts only a current locked-slot + locked-ItemID own non-GCD cooldown transition. Buffs, icon grayness, general item cooldowns and generic GCD are not accepted proof.

## TEUI changes

- Right-click a HUD card to open its corresponding settings page: primary/candidates → 主键; burst → 爆发; interrupt/control/mobility → 打断与控制; defense → 防御与生存; HUD background → 常规.
- The selected navigation rectangle now retains a high-contrast border and background.
- 爆发 page is split into 爆发设置 and 样式设置. AutoBurst and display policy remain in the first subpage; burst card styling is in the second.
- The master 光效与动画 control now has a vertical gap before its effect matrix; the same layout helper is used across module style pages.
- 监控与调试 includes buttons for each `/te` subcommand, with a textual explanation beside each button.

## Required field validation

1. Put one trinket or one macro such as `/use 13` on a visible Blizzard default action bar with a real binding.
2. Configure `/teab trinket <official-window-spellID> 13`, choose `pre` or `post`, and keep `offgcd` disabled unless the exact trinket has been verified off-GCD.
3. In an official window edge, verify a trinket candidate is `dispatch_origin=burst`, then the window candidate is only offered after the exact trinket cooldown proof.
4. Test a macro containing both `/use 13` and `/use 14`; it must fail with `macro_multiple_trinket_slots` and must not create a plan.
5. Change the equipped trinket after a plan is created. The plan must stop and retain the window departure lock.
6. Right-click each HUD region and verify its TEUI route and left navigation highlight.
